#!/usr/bin/env python3
"""Exercise extracted NSE error, completion/reuse and privacy branches with SDK doubles.

This does not compile the extension against the iOS SDK or deliver a real push.
Crypto/account loading and Apple attributed-body presentation are out of scope.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / "Telegram/NotificationService/Sources/NotificationService.swift").read_text()


def block(marker, start=0):
    beginning = source.index(marker, start)
    opening = source.index("{", beginning)
    depth, ending = 1, opening + 1
    while depth:
        depth += (source[ending] == "{") - (source[ending] == "}")
        ending += 1
    return source[beginning:ending]


def body(marker, start=0):
    value = block(marker, start)
    return value[value.index("{") + 1:-1]


failure_markers = [
    "guard let strongSelf = self, let recordId = recordId else",
    "guard let stateManager = stateManager else",
    "guard let strongSelf = self else",
    "guard let notificationsKey = notificationsKey else",
    "guard let decryptedPayload = decryptedNotificationPayload(key: notificationsKey, data: payloadData) else",
    "guard let payloadJson = try? JSONSerialization.jsonObject(with: decryptedPayload, options: []) as? [String: Any] else",
]
key_failure_start = source.index(failure_markers[0])
swift = r'''
import Foundation
'''
swift += (ROOT / "submodules/SSignalKit/SwiftSignalKit/Source/Atomic.swift").read_text()
swift += r'''
var generationHook: (() -> Void)?
final class Queue {
    private let lock = NSLock()
    private var work: [() -> Void] = []
    func async(_ f: @escaping () -> Void) {
        if Thread.current.threadDictionary["NotificationFixtureQueue"] as? Bool == true { f() } else { justDispatch(f) }
    }
    func justDispatch(_ f: @escaping () -> Void) { lock.lock(); work.append(f); lock.unlock() }
    func drain() {
        Thread.current.threadDictionary["NotificationFixtureQueue"] = true
        defer { Thread.current.threadDictionary.removeObject(forKey: "NotificationFixtureQueue") }
        while true {
            lock.lock()
            let next = work.isEmpty ? nil : work.removeFirst()
            lock.unlock()
            guard let next else { return }; next()
        }
    }
}
final class Logger {
    static let shared = Logger()
    func log(_ category: String, _ message: String) {}
}
let queue = Queue()
final class QueueLocalObject<T> {
    private var value: T?
    init(queue: Queue, generate: @escaping () -> T) { queue.async { self.value = generate() } }
}
class UNNotificationContent {
    var title = ""
    var subtitle = ""
    var body = ""
    var badge: NSNumber?
    var userInfo: [AnyHashable: Any] = [:]
    var attributedBody: NSAttributedString?
    func setValue(_ value: NSAttributedString, forKey key: String) { precondition(key == "attributedBody"); attributedBody = value }
}
final class UNNotificationRequest {
    let content: UNNotificationContent
    init(_ content: UNNotificationContent) { self.content = content }
}
class UNNotificationServiceExtension: NSObject {
    func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {}
    func serviceExtensionTimeWillExpire() {}
}
struct NotificationContent {
    var title: String?
    var body: String?
    var badge: Int?
    var retainedProbe: NSObject?
    let isLockedMessage: String?
    init(isLockedMessage: String?) { self.isLockedMessage = isLockedMessage }
    func generate() -> UNNotificationContent {
        generationHook?()
        let value = UNNotificationContent(); value.title = title ?? ""; value.body = body ?? ""; value.badge = badge.map { NSNumber(value: $0) }; return value
    }
}
private final class BoxedNotificationServiceHandler {
    let value: NotificationServiceHandler?
    init(value: NotificationServiceHandler?) { self.value = value }
}
private final class NotificationServiceHandler {
    static var started = 0
    static var stopped = 0
    static weak var last: NotificationServiceHandler?
    static var delayedUpdate: ((NotificationContent) -> Void)?
    static var delayedComplete: (() -> Void)?
    init?(queue: Queue, episode: String, updateCurrentContent: @escaping (NotificationContent) -> Void, completed: @escaping () -> Void, payload: [AnyHashable: Any]) {
        Self.started += 1
        Self.last = self
        switch payload["mode"] as? String {
        case "unavailable": return nil
        case "render":
            var value = NotificationContent(isLockedMessage: nil); value.title = "Resolved sender"; value.body = "Resolved full text"
            updateCurrentContent(value); completed()
        case "suppress":
            var content = NotificationContent(isLockedMessage: nil)
            content.body = "Already displayed private text"
            let wasDisplayed = true
'''
swift += block("if wasDisplayed {", source.index("content.resolvedEmojiFiles = resolvedEmojiFiles"))
swift += r'''
            updateCurrentContent(content); completed()
        case "readStories":
'''
swift += body("let completeRemoval: () -> Void =", source.index("case let .readStories(peerId, maxId):"))
swift += r'''
        case "delete":
            let isCurrentAccount = true
            let value = (3, 0)
'''
deletion_start = source.index("var content = NotificationContent(isLockedMessage: nil)", source.index("case let .deleteMessage(ids):"))
deletion_end = source.index("completed()", deletion_start) + len("completed()")
swift += source[deletion_start:deletion_end]
swift += r'''
        case "timeout":
            Self.delayedUpdate = updateCurrentContent; Self.delayedComplete = completed
        default:
            switch payload["failure"] as? Int {
'''
for index, marker in enumerate(failure_markers):
    start = source.index("strongSelf.notificationKeyDisposable.set", key_failure_start) if index == 2 else key_failure_start
    swift += f"case {index}: do {{\n{body(marker, start)}\n}}\n"
swift += r'''
            default: completed()
            }
        }
    }
    deinit { Self.stopped += 1 }
}
'''
swift += block("private final class NotificationServiceRequestState {") + "\n"
swift += block("final class NotificationService: UNNotificationServiceExtension {")
swift += r'''
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
func request(_ mode: String, failure: Int? = nil) -> UNNotificationRequest {
    let content = UNNotificationContent()
    content.title = "Server sender"; content.body = "Original server full text"
    content.userInfo["mode"] = mode
    content.userInfo["failure"] = failure
    return UNNotificationRequest(content)
}
let service = NotificationService()
var deliveries: [UNNotificationContent] = []
service.didReceive(request("render")) { deliveries.append($0) }
queue.drain()
check(deliveries.count == 1 && deliveries[0].body == "Resolved full text", "successful processing keeps generated content")
check(NotificationServiceHandler.stopped == 1, "inline-when-current completion disposes worker after QueueLocalObject assignment")
for failure in 0..<6 {
    let previousCount = deliveries.count
    service.didReceive(request("failure", failure: failure)) { deliveries.append($0) }
    queue.drain()
    check(deliveries.count == previousCount + 1 && deliveries.last!.title == "Server sender" && deliveries.last!.body == "Original server full text", "processing failure preserves original server content and clears previous request " + String(failure))
}
service.didReceive(request("suppress")) { deliveries.append($0) }
queue.drain()
check(deliveries.last!.title.isEmpty && deliveries.last!.body.isEmpty, "intentional already-displayed suppression stays empty")
service.didReceive(request("readStories")) { deliveries.append($0) }; queue.drain()
check(deliveries.last!.title.isEmpty && deliveries.last!.body.isEmpty, "intentional read-stories suppression stays empty")
service.didReceive(request("delete")) { deliveries.append($0) }; queue.drain()
check(deliveries.last!.title.isEmpty && deliveries.last!.body.isEmpty && deliveries.last!.badge?.intValue == 3, "intentional deletion suppression stays empty while updating badge")
let beforeTimeout = deliveries.count
service.didReceive(request("timeout")) { deliveries.append($0) }
queue.drain()
check(deliveries.count == beforeTimeout, "timeout request stays pending until expiration")
service.serviceExtensionTimeWillExpire()
queue.drain()
check(deliveries.count == beforeTimeout + 1 && deliveries.last!.body == "Original server full text", "expiration without generated content preserves original")
NotificationServiceHandler.delayedComplete?()
service.serviceExtensionTimeWillExpire()
queue.drain()
check(deliveries.count == beforeTimeout + 1, "sequential completion after expiration does not redeliver")
service.didReceive(request("timeout")) { deliveries.append($0) }
queue.drain()
var partial = NotificationContent(isLockedMessage: nil); partial.body = "Latest partial text"
NotificationServiceHandler.delayedUpdate?(partial)
service.serviceExtensionTimeWillExpire()
queue.drain()
check(deliveries.last!.body == "Latest partial text", "expiration retains latest generated partial content")

service.didReceive(request("unavailable")) { deliveries.append($0) }; queue.drain()
check(deliveries.last!.body == "Original server full text", "unavailable initializer falls back immediately")

// A stale worker cannot overwrite content or take the completion handler of a replacement request.
let overlap = NotificationService()
var first: [UNNotificationContent] = []
var second: [UNNotificationContent] = []
overlap.didReceive(request("timeout")) { first.append($0) }; queue.drain()
let staleUpdate = NotificationServiceHandler.delayedUpdate!
let staleComplete = NotificationServiceHandler.delayedComplete!
overlap.didReceive(request("timeout")) { second.append($0) }; queue.drain()
let liveUpdate = NotificationServiceHandler.delayedUpdate!
let liveComplete = NotificationServiceHandler.delayedComplete!
private weak var currentWorker = NotificationServiceHandler.last
check(first.count == 1 && first[0].body == "Original server full text" && second.isEmpty, "replacement completes original pending handler once")
var staleContent = NotificationContent(isLockedMessage: nil); staleContent.body = "STALE first request"
staleUpdate(staleContent); staleComplete(); queue.drain()
check(first.count == 1 && second.isEmpty, "stale callback cannot complete replacement")
check(currentWorker != nil, "stale queued cleanup cannot dispose replacement worker")
var liveContent = NotificationContent(isLockedMessage: nil); liveContent.body = "CURRENT second request"
liveUpdate(liveContent)
overlap.serviceExtensionTimeWillExpire(); liveComplete(); queue.drain()
check(second.count == 1 && second[0].body == "CURRENT second request", "expiry reads replacement's own content and completes once")
check(currentWorker == nil, "expired replacement worker is released")

// Expiry before the queued initializer does not start account/network work.
let earlyExpiry = NotificationService()
var early: [UNNotificationContent] = []
let startedBefore = NotificationServiceHandler.started
earlyExpiry.didReceive(request("timeout")) { early.append($0) }
earlyExpiry.serviceExtensionTimeWillExpire(); queue.drain()
check(early.count == 1 && NotificationServiceHandler.started == startedBefore, "already expired queued request skips worker initialization")

// Real concurrent expiry/worker completion races exercise production Atomic handler ownership.
let concurrent = NotificationService()
let concurrentCount = Atomic(value: 0)
concurrent.didReceive(request("timeout")) { _ in
    let _ = concurrentCount.modify { $0 + 1 }
}; queue.drain()
let competingComplete = NotificationServiceHandler.delayedComplete!
DispatchQueue.concurrentPerform(iterations: 200) { index in
    if index % 2 == 0 { concurrent.serviceExtensionTimeWillExpire() } else { competingComplete() }
}
queue.drain()
check(concurrentCount.with { $0 } == 1, "concurrent expiration and completion deliver handler exactly once")

// Completion freezes content atomically even if generation blocks while a late worker update arrives.
let frozenBody = Atomic(value: "")
private let frozenRequest = NotificationServiceRequestState(episode: "freeze", initialContent: request("timeout").content) { content in
    let _ = frozenBody.swap(content.body)
}
var beforeClaim = NotificationContent(isLockedMessage: nil); beforeClaim.body = "Chosen before completion"
frozenRequest.updateContent(beforeClaim)
let beganGenerating = DispatchSemaphore(value: 0)
let finishGenerating = DispatchSemaphore(value: 0)
let finishedFrozen = DispatchSemaphore(value: 0)
generationHook = { beganGenerating.signal(); finishGenerating.wait() }
DispatchQueue.global().async { frozenRequest.complete(); finishedFrozen.signal() }
check(beganGenerating.wait(timeout: .now() + 5.0) == .success, "content generation began after claim")
weak var lateProbe: NSObject?
do {
    let probe = NSObject(); lateProbe = probe
    var afterClaim = NotificationContent(isLockedMessage: nil); afterClaim.body = "Late stale update"; afterClaim.retainedProbe = probe
    frozenRequest.updateContent(afterClaim)
}
check(lateProbe == nil, "finished request cannot retain media from a late update")
frozenRequest.complete()
finishGenerating.signal()
check(finishedFrozen.wait(timeout: .now() + 5.0) == .success, "frozen content completion finished")
generationHook = nil
check(frozenBody.with { $0 } == "Chosen before completion" && frozenRequest.isCompleted, "late update cannot alter frozen delivered content")

final class UIImage {}
func convertLottieImage(data: Data, size: CGSize, forceSquare: Bool) -> UIImage? { nil }
enum WebP { static func convert(fromWebP: Data) -> UIImage? { nil } }
enum Customoji { static func makeGlyph(from image: UIImage, description: String, tileSizes: [Int], cropToSquare: Bool) throws -> String { description } }
extension NSAttributedString {
    convenience init(adaptiveImageGlyph: String, attributes: [NSAttributedString.Key: Any]) { self.init(string: adaptiveImageGlyph, attributes: attributes) }
}
struct BodyFixture {
    struct CustomEmoji { var range: Range<Int>; var fileId: Int64 }
    var body: String?
    var isLockedMessage: String?
    var customEmoji: [CustomEmoji] = []
    var resolvedEmojiFiles: [Int64: String] = [:]
    func render() -> UNNotificationContent {
        let content = UNNotificationContent()
'''
swift += block("if let body = self.body {", source.index("func generate()")) + "\n"
swift += block("if !content.title.isEmpty || !content.subtitle.isEmpty || !content.body.isEmpty {", source.index("func generate()"))
swift += r'''
        return content
    }
}
let secret = "Very private full message text"
let locked = BodyFixture(body: secret, isLockedMessage: "Generic locked message", resolvedEmojiFiles: [1: "/unavailable/glyph"]).render()
check(locked.body == "Generic locked message" && locked.attributedBody == nil, "locked rich emoji text never reaches attributedBody")
let plainLocked = BodyFixture(body: secret, isLockedMessage: "Generic locked message").render()
check(plainLocked.body == "Generic locked message" && plainLocked.attributedBody == nil, "locked plain body stays generic")
let unlocked = BodyFixture(body: secret, isLockedMessage: nil).render()
check(unlocked.body == secret && unlocked.attributedBody == nil, "unlocked plain body retains full text")
let unlockedRich = BodyFixture(body: secret, isLockedMessage: nil, resolvedEmojiFiles: [1: "/unavailable/glyph"]).render()
check(unlockedRich.attributedBody?.string == secret, "unlocked rich body retains full text")
let empty = BodyFixture(body: nil, isLockedMessage: nil).render()
check(empty.body.isEmpty && empty.attributedBody == nil, "intentional no-content render stays empty")
print("PASS: actual-source NSE failure fallback, sequential reuse/expiration, intentional suppression and locked attributed-body privacy regressions")
'''

with tempfile.TemporaryDirectory(prefix="supergram-notification-service-") as temporary:
    swift_source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    swift_source.write_text(swift)
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(swift_source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
