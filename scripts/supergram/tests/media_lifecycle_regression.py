#!/usr/bin/env python3
"""Run the production sticker/display-link code with deterministic macOS test doubles.

The harness controls queue delivery and timers, so cancellation races and accidental
decode loops can be reproduced without an iOS device. It does not measure UIKit,
FFmpeg, GPU performance, or device energy use. Run with Python 3 and Xcode installed.
"""

import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]


def source(relative_path):
    return "\n".join(
        line
        for line in (ROOT / relative_path).read_text().splitlines()
        if not line.startswith("import ")
    )


STUBS = r'''
import Foundation

final class Scheduler {
    static var pending: [(Queue, () -> Void)] = []
    static var current: Queue?
    static func drain(limit: Int = 50) {
        var count = 0
        while !pending.isEmpty {
            precondition(count < limit, "Asynchronous work failed to quiesce (decode busy loop)")
            let (queue, task) = pending.removeFirst()
            let previous = current
            current = queue
            task()
            current = previous
            count += 1
        }
    }
    static func runOneWorker() {
        guard let index = pending.firstIndex(where: { $0.0 !== Queue.main }) else {
            preconditionFailure("Expected a pending frame decode")
        }
        let (queue, task) = pending.remove(at: index)
        let previous = current
        current = queue
        task()
        current = previous
    }
}

public final class Queue {
    static let main = Queue(name: "main")
    public init(name: String = "worker", qos: DispatchQoS.QoSClass = .default) {}
    public static func mainQueue() -> Queue { return main }
    public func isCurrent() -> Bool { return Scheduler.current === self }
    public func async(_ f: @escaping () -> Void) { Scheduler.pending.append((self, f)) }
    public func sync(_ f: () -> Void) {
        let previous = Scheduler.current
        Scheduler.current = self
        f()
        Scheduler.current = previous
    }
}

public protocol Disposable { func dispose() }
public final class MockDisposable: Disposable {
    var cancelled = false
    public func dispose() { cancelled = true }
    public func strict() -> MockDisposable { return self }
}
public enum NoError: Error {}
public final class Subscriber<T, E: Error> {}
let EmptyDisposable = MockDisposable()
public final class Signal<T, E: Error> {
    let value: T?
    init(_ value: T) { self.value = value }
    init(_ generator: @escaping (Subscriber<T, E>) -> Disposable) { self.value = nil }
    public static func single(_ value: T) -> Signal<T, E> { return Signal(value) }
    func startStrict(next: (T) -> Void) -> MockDisposable {
        next(self.value!)
        return MockDisposable()
    }
}
public final class Promise<T> {
    public init() {}
    public func get() -> Signal<T, NoError> { fatalError("Status is outside this harness") }
}
infix operator |> : AdditionPrecedence
func |> <T, R>(lhs: T, rhs: (T) -> R) -> R { return rhs(lhs) }
func filter<T, E>(_ predicate: @escaping (T) -> Bool) -> (Signal<T, E>) -> Signal<T, E> { return { $0 } }
func take<T, E>(_ count: Int) -> (Signal<T, E>) -> Signal<T, E> { return { $0 } }
func deliverOnMainQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { return signal }
func runOn<T, E>(_ queue: Queue) -> (Signal<T, E>) -> Signal<T, E> { return { $0 } }

enum SwiftSignalKit {
    final class Timer {
        static var active: [Timer] = []
        let completion: () -> Void
        var valid = true
        init(timeout: Double, repeat: Bool, completion: @escaping () -> Void, queue: Queue) {
            precondition(timeout.isFinite && timeout > 0)
            self.completion = completion
        }
        func start() { Self.active.append(self) }
        func invalidate() { valid = false; Self.active.removeAll { $0 === self } }
        static func fireNext() {
            guard let timer = active.first else { preconditionFailure("Expected a playback timer") }
            timer.invalidate()
            timer.completion()
        }
    }
}

public final class MockImage: NSObject {}
public typealias CGImage = MockImage
extension CGSize {
    init(width: Int, height: Int) { self.init(width: CGFloat(width), height: CGFloat(height)) }
}
public final class UIImage {
    public let cgImage: MockImage?
    public init(cgImage: MockImage = MockImage()) { self.cgImage = cgImage }
}
public final class UIColor {}
public final class MockLayer { public var contents: Any? }
open class ASDisplayNode: NSObject {
    public let layer = MockLayer()
    public override init() { super.init() }
}
public protocol AnimatedStickerNode: AnyObject {}
public enum AnimatedStickerMode { case cached; case direct(cachePathPrefix: String?) }
public enum AnimatedStickerPlaybackPosition { case start; case end; case timestamp(Double); case frameIndex(Int) }
public enum AnimatedStickerPlaybackMode { case once; case count(Int); case loop; case still(AnimatedStickerPlaybackPosition) }
public struct AnimatedStickerStatus {}
public enum LottieFitzModifier { case none }
public enum EmojiFitzModifier {
    case none
    var lottieFitzModifier: LottieFitzModifier { return .none }
}
public protocol AnimatedStickerNodeSource {
    var isVideo: Bool { get }
    var fitzModifier: EmojiFitzModifier? { get }
    func directDataPath(attemptSynchronously: Bool) -> Signal<String?, NoError>
}
struct TestSource: AnimatedStickerNodeSource {
    let path: String
    let isVideo: Bool
    var fitzModifier: EmojiFitzModifier? { return nil }
    func directDataPath(attemptSynchronously: Bool) -> Signal<String?, NoError> { return .single(path) }
}
public final class LottieInstance {
    static var rendered: [Int32] = []
    public let frameRate: Int32 = 30
    public let frameCount: Int32
    init?(data: Data, fitzModifier: LottieFitzModifier, colorReplacements: Any?, cacheKey: String) {
        guard let text = String(data: data, encoding: .utf8), let count = Int32(text) else { return nil }
        self.frameCount = count
    }
    func renderFrame(with index: Int32, into: UnsafeMutablePointer<UInt8>, width: Int32, height: Int32, bytesPerRow: Int32) {
        precondition(index >= 0 && index < self.frameCount)
        Self.rendered.append(index)
    }
}
func TGGUnzipData(_ data: Data, _ limit: Int) -> Data? { return data }
public final class DrawingContext {
    let scaledSize: CGSize
    let bytesPerRow: Int
    let length: Int
    let bytes: UnsafeMutableRawPointer
    init?(size: CGSize, scale: Double, opaque: Bool, clear: Bool, bytesPerRow: Int? = nil) {
        self.scaledSize = size
        self.bytesPerRow = bytesPerRow ?? Int(size.width) * 4
        self.length = self.bytesPerRow * Int(size.height)
        self.bytes = .allocate(byteCount: max(1, self.length), alignment: 8)
    }
    deinit { bytes.deallocate() }
    func generateImage() -> UIImage? { return UIImage() }
}
public final class AnimatedStickerFrame {
    let width = 8
    let height = 8
    let bytesPerRow = 32
    let data = Data(count: 256)
}
public protocol AnimatedStickerFrameSource: AnyObject {
    var frameCount: Int { get }
    var frameRate: Int { get }
    func takeFrame(draw: Bool) -> AnimatedStickerFrame?
}
final class AnimatedStickerFrameSourceWrapper {
    let value: AnimatedStickerFrameSource
    init(_ value: AnimatedStickerFrameSource) { self.value = value }
}
final class TestVideoSource: AnimatedStickerFrameSource {
    let queue: Queue
    let count: Int
    var index = 0
    var frameCount = 0
    let frameRate = 30
    static var decoded = 0
    static var released = 0
    init(queue: Queue, count: Int) { self.queue = queue; self.count = count }
    deinit { precondition(queue.isCurrent(), "Video source released off its owner queue"); Self.released += 1 }
    func takeFrame(draw: Bool) -> AnimatedStickerFrame? {
        precondition(queue.isCurrent())
        Self.decoded += 1
        if index == count { frameCount = count; index = 0; return nil }
        index += 1
        return AnimatedStickerFrame()
    }
}
func makeVideoStickerDirectFrameSource(queue: Queue, path: String, hintVP9: Bool, width: Int, height: Int, cachePathPrefix: String?, unpremultiplyAlpha: Bool) -> AnimatedStickerFrameSource? {
    return TestVideoSource(queue: queue, count: Int((try! String(contentsOfFile: path, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines))!)
}

struct CAFrameRateRange: Equatable {
    var minimum: Float
    var maximum: Float
    var preferred: Float
    static let `default` = CAFrameRateRange(minimum: 0, maximum: 0, preferred: 0)
}
final class UIScreen {
    static let main = UIScreen()
    let maximumFramesPerSecond = 120
}
final class UIApplication {
    enum State { case active; case inactive; case background }
    static let shared = UIApplication()
    static let willEnterForegroundNotification = Notification.Name("willEnterForeground")
    static let didEnterBackgroundNotification = Notification.Name("didEnterBackground")
    var applicationState = State.active
}
var testMediaTime = 0.0
func CACurrentMediaTime() -> Double { return testMediaTime }
public final class CADisplayLink: NSObject {
    static var created: [CADisplayLink] = []
    let target: AnyObject
    let selector: Selector
    var timestamp = 0.0
    var targetTimestamp = 1.0 / 60.0
    var preferredFrameRateRange = CAFrameRateRange.default
    var isPaused = false
    var invalidated = false
    init(target: Any, selector: Selector) {
        self.target = target as AnyObject
        self.selector = selector
        super.init()
        Self.created.append(self)
    }
    func add(to: RunLoop, forMode: RunLoop.Mode) {}
    func invalidate() { invalidated = true }
    func fire() { (target as! SharedDisplayLinkDriver).displayLinkEvent(displayLink: self) }
}
'''


TESTS = r'''
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}
let testDirectory = CommandLine.arguments[1]
func sticker(_ count: Int) -> TestSource {
    let path = testDirectory + "/sticker-\(count)"
    try! String(count).write(toFile: path, atomically: true, encoding: .utf8)
    return TestSource(path: path, isVideo: false)
}
func video(_ count: Int) -> TestSource {
    let path = testDirectory + "/video-\(count)"
    try! String(count).write(toFile: path, atomically: true, encoding: .utf8)
    return TestSource(path: path, isVideo: true)
}
func setup(_ node: DirectAnimatedStickerNode, _ source: TestSource, _ mode: AnimatedStickerPlaybackMode = .loop) {
    node.setup(source: source, width: 8, height: 8, playbackMode: mode, mode: .direct(cachePathPrefix: nil))
}
Scheduler.current = Queue.main

do {
    let node = DirectAnimatedStickerNode()
    node.visibility = true
    LottieInstance.rendered = []
    setup(node, sticker(4))
    Scheduler.drain()
    expect(LottieInstance.rendered == [0, 1], "The current and next frame must each decode once")
    expect(SwiftSignalKit.Timer.active.count == 1, "Expected one playback timer")
    SwiftSignalKit.Timer.fireNext()
    Scheduler.runOneWorker()
    node.visibility = false
    Scheduler.drain()
    expect(SwiftSignalKit.Timer.active.isEmpty, "A late render must not restart hidden animation")
    expect(!node.isPlaying, "A hidden sticker must be stopped")
}
Scheduler.drain()
print("PASS: bounded prefetch and hide during an in-flight render")

do {
    let node = DirectAnimatedStickerNode()
    node.visibility = true
    setup(node, sticker(5))
    Scheduler.runOneWorker()
    setup(node, sticker(1), .once)
    Scheduler.drain()
    expect(node.currentFrameCount == 1 && node.currentFrameIndex == 0, "Reused node accepted stale resource state")
    var completions = 0
    node.completed = { stopped in if stopped { completions += 1 } }
    SwiftSignalKit.Timer.fireNext()
    Scheduler.drain()
    expect(completions == 1 && !node.isPlaying, "One-shot playback must complete exactly once")
    expect(SwiftSignalKit.Timer.active.isEmpty, "Completed playback must not retain a timer")
}
Scheduler.drain()
print("PASS: source replacement rejects stale frames and one-shot completion stops playback")

do {
    let node = DirectAnimatedStickerNode()
    node.visibility = true
    setup(node, sticker(4), .still(.start))
    LottieInstance.rendered = []
    Scheduler.drain()
    expect(LottieInstance.rendered == [0], "A still sticker must decode only its still frame")
    expect(!node.isPlaying && SwiftSignalKit.Timer.active.isEmpty, "Still mode must not animate")
    setup(node, sticker(0))
    Scheduler.drain()
    expect(SwiftSignalKit.Timer.active.isEmpty, "Invalid zero-frame Lottie data must not schedule playback")
}
Scheduler.drain()
print("PASS: still mode and zero-frame Lottie data")

do {
    let node = DirectAnimatedStickerNode()
    node.visibility = true
    setup(node, video(3), .once)
    Scheduler.drain()
    expect(node.currentFrameCount == 0, "A video's unknown frame count must remain unknown until EOF")
    SwiftSignalKit.Timer.fireNext()
    Scheduler.drain()
    SwiftSignalKit.Timer.fireNext()
    Scheduler.drain()
    expect(node.currentFrameCount == 3, "EOF must publish the discovered video frame count")
    SwiftSignalKit.Timer.fireNext()
    Scheduler.drain()
    expect(!node.isPlaying && SwiftSignalKit.Timer.active.isEmpty, "Video one-shot did not finish")
    node.reset()
    Scheduler.drain()
    expect(TestVideoSource.released == 1, "Video reader must release on its queue when reset")
}
Scheduler.drain()
print("PASS: unknown video count, EOF completion, and reader queue lifetime")

do {
    let node = DirectAnimatedStickerNode()
    node.visibility = true
    setup(node, sticker(4))
    Scheduler.runOneWorker()
    node.pause()
    Scheduler.drain()
    expect(!node.isPlaying && SwiftSignalKit.Timer.active.isEmpty, "Pause lost a race with frame completion")
    node.play(firstFrame: false, fromIndex: -20)
    Scheduler.drain()
    expect(node.currentFrameIndex == 0 && node.isPlaying, "Resume must clamp invalid frame indexes")
    node.stop()
    Scheduler.drain()
    expect(SwiftSignalKit.Timer.active.isEmpty, "Stop must invalidate playback")
}
Scheduler.drain()
print("PASS: pause/render race, resume, and stop")

func requestCount(_ driver: SharedDisplayLinkDriver) -> Int {
    let requests = Mirror(reflecting: driver).children.first { $0.label == "requests" }!.value
    return Mirror(reflecting: requests).children.count
}
do {
    let driver = SharedDisplayLinkDriver.shared
    let lower = driver.add(framesPerSecond: .fps(60)) { _ in }
    let higher = driver.add(framesPerSecond: .max) { _ in }
    let displayLink = CADisplayLink.created.last!
    expect(displayLink.preferredFrameRateRange.preferred == 120, "High frame-rate client was ignored")
    higher.invalidate()
    expect(displayLink.preferredFrameRateRange == .default, "Invalidating a high-FPS client must immediately lower the requested rate")
    lower.isPaused = true
    lower.invalidate()
    expect(displayLink.invalidated && requestCount(driver) == 0, "Stopping the last client must clean requests without another tick")

    var link: SharedDisplayLinkDriver.Link?
    var replacement: SharedDisplayLinkDriver.Link?
    link = driver.add { _ in
        link?.invalidate()
        replacement = driver.add { _ in }
    }
    CADisplayLink.created.last!.fire()
    expect(requestCount(driver) == 1, "Reentrant invalidation/addition corrupted request cleanup")
    replacement?.invalidate()
    expect(requestCount(driver) == 0, "Replacement display-link request leaked")
}
print("PASS: display-link rate downgrade, idle cleanup, and mutation during callbacks")
'''


def main():
    swift_sources = [
        STUBS,
        source("submodules/SSignalKit/SwiftSignalKit/Source/Atomic.swift"),
        source("submodules/SSignalKit/SwiftSignalKit/Source/QueueLocalObject.swift"),
        source("submodules/AnimatedStickerNode/Sources/DirectAnimatedStickerNode.swift"),
        source("submodules/Display/Source/DisplayLinkAnimator.swift").replace(
            "@objc private func displayLinkEvent(", "@objc func displayLinkEvent("
        ),
        TESTS,
    ]
    with tempfile.TemporaryDirectory(prefix="supergram-media-lifecycle-") as directory:
        swift_file = pathlib.Path(directory) / "main.swift"
        swift_file.write_text("\n\n".join(swift_sources))
        binary = pathlib.Path(directory) / "media-lifecycle-tests"
        subprocess.run(["xcrun", "swiftc", str(swift_file), "-o", str(binary)], check=True)
        subprocess.run([str(binary), directory], check=True)


if __name__ == "__main__":
    main()
