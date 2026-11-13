#!/usr/bin/env python3
"""Execute native frame-preview Impl with real disposables/QueueLocalObject.

The deterministic queue preserves inline-when-current async and deferred
justDispatch. Signals, UIKit images and decoder results are doubles. No media,
device, network or account is touched. Use --source with the archived native
before snapshot to reproduce the pre-fix failures without changing production.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, default=ROOT / "submodules/MediaPlayer/Sources/MediaPlayerFramePreview.swift", help="Alternative source snapshot for reproducing a baseline")
source = parser.parse_args().source.read_text()
disposable_source = (ROOT / "submodules/SSignalKit/SwiftSignalKit/Source/Disposable.swift").read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end] + "\n"


swift = "import Foundation\n"
for marker in ["public protocol Disposable:", "public final class ActionDisposable", "public final class MetaDisposable", "final class _EmptyDisposable:"]:
    swift += block(disposable_source, marker)
swift += r'''
public let EmptyDisposable: Disposable = _EmptyDisposable()
public final class Queue {
    static var current: Queue?
    var tasks: [() -> Void] = []
    public func isCurrent() -> Bool { Self.current === self }
    public func async(_ task: @escaping () -> Void) { if isCurrent() { task() } else { tasks.append(task) } }
    public func justDispatch(_ task: @escaping () -> Void) { tasks.append(task) }
    public func sync(_ task: () -> Void) { let previous = Self.current; Self.current = self; task(); Self.current = previous }
    func drain() { var steps = 0; while !tasks.isEmpty { steps += 1; precondition(steps < 1000); let next = tasks.removeFirst(); sync(next) } }
}
public final class Subscriber<V, E> {
    var disposed = false
    let next: (V) -> Void
    init(_ next: @escaping (V) -> Void) { self.next = next }
    public func putNext(_ value: V) { if !disposed { next(value) } }
}
public struct Signal<V, E> {
    let generator: (Subscriber<V, E>) -> Disposable
    public init(_ generator: @escaping (Subscriber<V, E>) -> Disposable) { self.generator = generator }
    public func start(next: @escaping (V) -> Void) -> Disposable {
        let subscriber = Subscriber<V, E>(next)
        let upstream = generator(subscriber)
        return ActionDisposable { subscriber.disposed = true; upstream.dispose() }
    }
    static func single(_ value: V) -> Signal { Signal { subscriber in subscriber.putNext(value); return EmptyDisposable } }
}
infix operator |> : AdditionPrecedence
func |> <T, R>(_ value: T, _ f: (T) -> R) -> R { f(value) }
func runOn<V, E>(_ queue: Queue) -> (Signal<V, E>) -> Signal<V, E> { { $0 } }
func take<V, E>(_ count: Int) -> (Signal<V, E>) -> Signal<V, E> {
    { signal in Signal { subscriber in var remaining = count; return signal.start(next: { value in if remaining > 0 { remaining -= 1; subscriber.putNext(value) } }) } }
}
enum NoError: Error {}
final class Promise<V> {
    var value: Signal<V, NoError>?
    func set(_ value: Signal<V, NoError>) { self.value = value }
    func get() -> Signal<V, NoError> { value! }
}
final class ValuePipe<V> { var values: [V] = []; var onValue: ((V) -> Void)?; func putNext(_ value: V) { values.append(value); onValue?(value) } }
struct UIImage: Equatable { let value: Int }
enum FramePreviewResult { case image(UIImage); case waitingForData }
enum UniversalSoftwareVideoSourceTakeFrameResult { case waitingForData; case image(UIImage?) }
final class PreviewRequest {
    let timestamp: Double
    let subscriber: Subscriber<UniversalSoftwareVideoSourceTakeFrameResult, NoError>
    var disposed = false
    init(_ timestamp: Double, _ subscriber: Subscriber<UniversalSoftwareVideoSourceTakeFrameResult, NoError>) { self.timestamp = timestamp; self.subscriber = subscriber }
    func emit(_ result: UniversalSoftwareVideoSourceTakeFrameResult) { subscriber.putNext(result) }
}
final class UniversalSoftwareVideoSource {
    var requests: [PreviewRequest] = []
    var synchronousImage: UIImage?
    func takeFrame(at timestamp: Double) -> Signal<UniversalSoftwareVideoSourceTakeFrameResult, NoError> {
        Signal { subscriber in
            let request = PreviewRequest(timestamp, subscriber)
            self.requests.append(request)
            if let image = self.synchronousImage { subscriber.putNext(.image(image)) }
            return ActionDisposable { request.disposed = true }
        }
    }
}
final class Postbox { let source = UniversalSoftwareVideoSource() }
struct MediaResourceUserLocation {}
struct MediaResourceUserContentType {}
struct FileMediaReference {}
'''
swift += (ROOT / "submodules/SSignalKit/SwiftSignalKit/Source/QueueLocalObject.swift").read_text().replace("import Foundation", "")
swift += block(source, "private final class FramePreviewContext {")
swift += r'''
private func initializedPreviewContext(queue: Queue, postbox: Postbox, userLocation: MediaResourceUserLocation, userContentType: MediaResourceUserContentType, fileReference: FileMediaReference) -> Signal<QueueLocalObject<FramePreviewContext>, NoError> {
    .single(QueueLocalObject(queue: queue, generate: { FramePreviewContext(source: postbox.source) }))
}
'''
if "private final class FramePreviewRequest {" in source:
    swift += block(source, "private final class FramePreviewRequest {")
swift += block(source, "private final class MediaPlayerFramePreviewImpl {")
swift += r'''
var assertions = 0
var failures = 0
func check(_ value: @autoclosure () -> Bool, _ description: String) {
    assertions += 1
    if !value() { failures += 1; print("FAIL: " + description) }
}
private func fixture(_ body: (Queue, Postbox, MediaPlayerFramePreviewImpl) -> Void) {
    let queue = Queue()
    let postbox = Postbox()
    var impl: MediaPlayerFramePreviewImpl?
    queue.sync { impl = MediaPlayerFramePreviewImpl(queue: queue, postbox: postbox, userLocation: MediaResourceUserLocation(), userContentType: MediaResourceUserContentType(), fileReference: FileMediaReference()) }
    body(queue, postbox, impl!)
    queue.sync { impl = nil }
    queue.drain()
}
private func images(_ impl: MediaPlayerFramePreviewImpl) -> [Int] { impl.framePipe.values.compactMap { if case let .image(image) = $0 { return image.value }; return nil } }
fixture { queue, postbox, impl in
    queue.sync { impl.generateFrame(at: 1); impl.cancelPendingFrames() }
    queue.drain()
    check(postbox.source.requests.isEmpty, "cancel before deferred start must not launch discarded decode")
    check(impl.framePipe.values.isEmpty, "cancel before start cannot emit preview")
}
fixture { queue, postbox, impl in
    queue.sync { impl.generateFrame(at: 1) }
    queue.drain()
    check(postbox.source.requests.count == 1, "current preview starts once")
    postbox.source.requests[0].emit(.image(UIImage(value: 1))) // callback queued before cancellation
    queue.sync { impl.cancelPendingFrames(); impl.generateFrame(at: 2) }
    queue.drain()
    check(images(impl).isEmpty, "old queued image is rejected after cancel/new request")
    check(postbox.source.requests.count == 2 && postbox.source.requests[0].disposed, "cancel disposes old source and starts new one")
    queue.sync { impl.generateFrame(at: 3) }
    queue.drain()
    check(postbox.source.requests.count == 2, "old result cannot reset current request or allow overlapping decode")
    postbox.source.requests[1].emit(.image(UIImage(value: 2)))
    queue.drain()
    check(images(impl) == [2], "legitimate replacement preview is preserved")
    check(postbox.source.requests.count == 3 && postbox.source.requests[2].timestamp == 3, "latest queued timestamp starts after current result")
    postbox.source.requests[2].emit(.image(UIImage(value: 3)))
    queue.drain()
    check(images(impl) == [2, 3], "latest preview finishes normally")
}
fixture { queue, postbox, impl in
    queue.sync { impl.generateFrame(at: 10) }
    queue.drain()
    postbox.source.requests[0].emit(.waitingForData)
    postbox.source.requests[0].emit(.image(UIImage(value: 1)))
    queue.sync { impl.cancelPendingFrames(); impl.generateFrame(at: 10) }
    queue.drain()
    check(impl.framePipe.values.isEmpty, "same-timestamp replacement rejects old waiting/image callbacks")
    postbox.source.requests[1].emit(.waitingForData)
    queue.drain()
    check(impl.framePipe.values.count == 1, "current waiting status is preserved")
    postbox.source.requests[1].emit(.image(UIImage(value: 10)))
    queue.drain()
    check(images(impl) == [10], "same-timestamp replacement result is accepted")
}
fixture { queue, postbox, impl in
    queue.sync { impl.generateFrame(at: 1) }
    queue.drain()
    queue.sync { impl.generateFrame(at: 2); impl.generateFrame(at: 3) }
    queue.drain()
    check(postbox.source.requests.count == 1, "current decode coalesces rapidly requested timestamps")
    postbox.source.requests[0].emit(.image(nil))
    queue.drain()
    check(postbox.source.requests.count == 2 && postbox.source.requests[1].timestamp == 3, "nil image still advances to latest queued request")
    postbox.source.requests[1].emit(.image(UIImage(value: 3)))
    queue.drain()
    check(images(impl) == [3], "latest rapid request completes without stale pending timestamp")
}
fixture { queue, postbox, impl in
    postbox.source.synchronousImage = UIImage(value: 20)
    queue.sync { impl.generateFrame(at: 20) }
    queue.drain()
    check(images(impl) == [20] && postbox.source.requests.count == 1, "inline source completion is handled once")
    queue.sync { impl.generateFrame(at: 21) }
    queue.drain()
    check(images(impl) == [20, 20] && postbox.source.requests.count == 2, "next request can start after inline completion")
    check(postbox.source.requests[0].disposed, "replacement disposes completed old request")
}
fixture { queue, postbox, impl in
    queue.sync { impl.generateFrame(at: 1); impl.cancelPendingFrames(); impl.generateFrame(at: 2) }
    queue.drain()
    check(postbox.source.requests.count == 1 && postbox.source.requests[0].timestamp == 2, "cancel before start followed by replacement launches only current decode")
}
fixture { queue, postbox, impl in
    var replaced = false
    impl.framePipe.onValue = { _ in
        if !replaced { replaced = true; impl.cancelPendingFrames(); impl.generateFrame(at: 2) }
    }
    queue.sync { impl.generateFrame(at: 1) }
    queue.drain()
    postbox.source.requests[0].emit(.image(UIImage(value: 1)))
    queue.drain()
    check(images(impl) == [1] && postbox.source.requests.count == 2, "consumer can synchronously cancel/replace during current image emission")
    queue.sync { impl.generateFrame(at: 3) }
    queue.drain()
    check(postbox.source.requests.count == 2, "post-emission old cleanup cannot reset replacement state")
    postbox.source.requests[1].emit(.image(UIImage(value: 2)))
    queue.drain()
    check(postbox.source.requests.count == 3 && postbox.source.requests[2].timestamp == 3, "reentrant replacement preserves latest queued request")
    postbox.source.requests[2].emit(.image(UIImage(value: 3)))
    queue.drain()
    check(images(impl) == [1, 2, 3], "reentrant replacement completes all current images in order")
    impl.framePipe.onValue = nil
}
fixture { queue, postbox, impl in
    postbox.source.synchronousImage = UIImage(value: 1)
    var replaced = false
    impl.framePipe.onValue = { _ in
        if !replaced {
            replaced = true
            postbox.source.synchronousImage = nil
            impl.cancelPendingFrames()
            impl.generateFrame(at: 2)
        }
    }
    queue.sync { impl.generateFrame(at: 1) }
    queue.drain()
    check(images(impl) == [1] && postbox.source.requests.count == 2, "synchronous decoder can reentrantly start a pending replacement")
    check(postbox.source.requests[0].disposed && !postbox.source.requests[1].disposed, "inline old decoder handle cannot dispose pending replacement subscription")
    queue.sync { impl.generateFrame(at: 3) }
    queue.drain()
    check(postbox.source.requests.count == 2 && !postbox.source.requests[1].disposed, "pending reentrant replacement keeps its handle and coalesces next timestamp")
    postbox.source.requests[1].emit(.image(UIImage(value: 2)))
    queue.drain()
    check(images(impl) == [1, 2] && postbox.source.requests.count == 3 && postbox.source.requests[2].timestamp == 3, "inline replacement remains subscribed and advances to latest preview")
    impl.framePipe.onValue = nil
}
var releasedRequest: PreviewRequest?
fixture { queue, postbox, impl in
    queue.sync { impl.generateFrame(at: 1) }
    queue.drain()
    releasedRequest = postbox.source.requests[0]
    releasedRequest?.emit(.image(UIImage(value: 1))) // remains queued as the Impl is released
}
check(releasedRequest?.disposed == true, "preview teardown disposes an in-flight source despite queued result")
releasedRequest = nil
if failures > 0 { print("FAIL: \(failures) of \(assertions) actual-source preview assertions"); exit(1) }
print("PASS: \(assertions) actual-source preview cancellation/identity and inline/deferred queue assertions")
'''

with tempfile.TemporaryDirectory(prefix="supergram-media-preview-") as temporary:
    swift_source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    swift_source.write_text(swift)
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(swift_source), "-o", str(executable)], check=True)
    raise SystemExit(subprocess.run([str(executable)]).returncode)
