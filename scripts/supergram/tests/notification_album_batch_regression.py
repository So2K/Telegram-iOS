#!/usr/bin/env python3
"""Exercise the production fallback album coalescer and its scheduling loop.

PeerId is production code. Message/account/notification delivery are deterministic
doubles; this test does not contact an account or schedule an OS notification.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
application = (ROOT / "submodules/TelegramUI/Sources/ApplicationContext.swift").read_text()
peer_source = (ROOT / "submodules/Postbox/Sources/Peer.swift").read_text()


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end] + "\n"


peer_fixture = block(peer_source, "public struct PeerId:")
for marker in ["public static func encodeArrayToBuffer(", "public static func decodeArrayFromBuffer(", "public func encodeToBuffer("]:
    peer_fixture = peer_fixture.replace(block(peer_fixture, marker).rstrip(), "")

swift = "import Foundation\n" + peer_fixture + r'''
struct MessageId { let peerId: PeerId; let namespace: Int32; let id: Int32 }
struct MessageFlags: OptionSet {
    let rawValue: Int
    static let WasScheduled = Self(rawValue: 128)
}
final class Message {
    let id: MessageId
    let groupingKey: Int64?
    let flags: MessageFlags
    init(_ id: Int32, peer: Int64 = 55, namespace: Int32 = 0, group: Int64? = nil, scheduled: Bool = false) {
        self.id = MessageId(peerId: PeerId(peer), namespace: namespace, id: id)
        self.groupingKey = group
        self.flags = scheduled ? [.WasScheduled] : []
    }
}
typealias PeerGroupId = Int32
final class MessageHistoryThreadData { let value: Int; init(_ value: Int) { self.value = value } }
typealias Batch = [([Message], PeerGroupId, Bool, MessageHistoryThreadData?)]
final class ScheduleRecorder {
    var messages: [[Message]] = []
    var notify: [Bool] = []
    func scheduleBackgroundMessageNotification(messages: [Message], notify: Bool) {
        self.messages.append(messages)
        self.notify.append(notify)
    }
}
'''
swift += block(application, "private struct BackgroundMessageNotificationAlbumKey:")
swift += block(application, "private func coalescedBackgroundMessageNotificationBatch(")
swift += "func scheduledBatch(_ messageList: Batch) -> ScheduleRecorder {\nlet strongSelf = ScheduleRecorder()\n"
swift += block(application, "for (backgroundMessages, _, backgroundNotify, _) in coalescedBackgroundMessageNotificationBatch(messageList)")
swift += "return strongSelf\n}\n"
swift += r'''
var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ description: String) {
    assertions += 1
    precondition(value(), description)
}
func anchors(_ result: Batch) -> [Int32] { result.compactMap { $0.0.first?.id.id } }
func ids(_ messages: [Message]) -> [Int32] { messages.map { $0.id.id } }
func entry(_ messages: [Message], notify: Bool = true, peerGroup: Int32 = 0, thread: MessageHistoryThreadData? = nil) -> ([Message], PeerGroupId, Bool, MessageHistoryThreadData?) {
    (messages, peerGroup, notify, thread)
}
let a = Message(1, group: 100)
let b = Message(2, group: 100)
let c = Message(3, group: 200)
let d = Message(4, group: 200)
let plain = Message(5)
let plain2 = Message(6)
let threadA = MessageHistoryThreadData(10)
let threadB = MessageHistoryThreadData(20)

// Real state-manager album shape: each newly added member is first in its own group result.
let repeated: Batch = [entry([a, b], peerGroup: 7, thread: threadA), entry([b, a], peerGroup: 8, thread: threadB)]
let coalesced = coalescedBackgroundMessageNotificationBatch(repeated)
check(coalesced.count == 1, "one notification per album within one event batch")
check(ids(coalesced[0].0) == [1, 2], "first actual message order is preserved")
check(coalesced[0].0[0] === a && coalesced[0].0[1] === b, "original message objects are retained")
check(coalesced[0].1 == 7 && coalesced[0].2 && coalesced[0].3 === threadA, "first peer-group/notification/topic policy context is retained")
let scheduled = scheduledBatch(repeated)
check(scheduled.messages.count == 1 && ids(scheduled.messages[0]) == [1, 2], "production background loop schedules coalesced array once")
check(scheduled.notify == [true], "production loop retains first eligible notification decision")
let reversed = coalescedBackgroundMessageNotificationBatch([entry([b, a]), entry([a, b])])
check(ids(reversed[0].0) == [2, 1], "coalescer does not invent a sorted anchor or request ID")

// Empty and ineligible entries cannot hide the following eligible album.
let falseThenTrue: Batch = [entry([a, b], notify: false), entry([], notify: true), entry([b, a], thread: threadB)]
let firstEligible = coalescedBackgroundMessageNotificationBatch(falseThenTrue)
check(firstEligible.count == 1 && anchors(firstEligible) == [2], "false/empty entries do not consume album key")
check(firstEligible[0].3 === threadB, "first eligible topic data is retained")
check(scheduledBatch(falseThenTrue).messages.count == 1, "only eligible array reaches scheduling")
check(coalescedBackgroundMessageNotificationBatch([entry([a], notify: false), entry([])]).isEmpty, "ineligible-only event emits no notification")
check(coalescedBackgroundMessageNotificationBatch([]).isEmpty, "empty event emits no notification")

// Numeric group IDs are scoped to the peer and message namespace, not globally.
let otherPeer = Message(7, peer: 56, group: 100)
let otherNamespace = Message(8, namespace: 1, group: 100)
let scoped = coalescedBackgroundMessageNotificationBatch([entry([a]), entry([otherPeer]), entry([otherNamespace]), entry([b])])
check(anchors(scoped) == [1, 7, 8], "same group number in another peer/namespace remains independent")
check(scoped[1].0[0].id.peerId == otherPeer.id.peerId, "other peer identity remains unchanged")
check(scoped[2].0[0].id.namespace == 1, "other namespace identity remains unchanged")
let signedGroup = Message(9, group: -100)
check(anchors(coalescedBackgroundMessageNotificationBatch([entry([a]), entry([signedGroup])])) == [1, 9], "different signed group numbers remain independent")

// Preserve order of distinct albums and ordinary notifications. Nongrouped entries are not coalesced.
let mixed: Batch = [entry([a, b]), entry([plain]), entry([d, c]), entry([b, a]), entry([plain2])]
let ordered = coalescedBackgroundMessageNotificationBatch(mixed)
check(anchors(ordered) == [1, 5, 4, 6], "first group representatives and unrelated messages retain event order")
check(ids(ordered[2].0) == [4, 3], "second album's original order is retained")
let ordinary = coalescedBackgroundMessageNotificationBatch([entry([plain]), entry([plain]), entry([plain2])])
check(anchors(ordinary) == [5, 5, 6], "nongrouped entries retain prior scheduling semantics")
check(scheduledBatch(mixed).messages.map(ids) == [[1, 2], [5], [4, 3], [6]], "production loop retains exact coalesced arrays and order")

// Scheduled reminders remain outside incoming-album coalescing and never consume its key.
let reminder = Message(10, group: 100, scheduled: true)
let reminder2 = Message(11, group: 100, scheduled: true)
let reminders: Batch = [entry([reminder, reminder2]), entry([a, b]), entry([reminder2, reminder]), entry([b, a])]
let retainedReminders = coalescedBackgroundMessageNotificationBatch(reminders)
check(anchors(retainedReminders) == [10, 1, 11], "reminders before/after album retain their existing notifications")
check(ids(retainedReminders[0].0) == [10, 11] && ids(retainedReminders[2].0) == [11, 10], "reminder arrays retain original message order")
check(scheduledBatch(reminders).messages.map(ids) == [[10, 11], [1, 2], [11, 10]], "production loop keeps reminders and coalesces only incoming album entries")

// There is no persisted history: later event batches and another account context remain independent.
let nextEvent = coalescedBackgroundMessageNotificationBatch([entry([b, a])])
check(nextEvent.count == 1 && anchors(nextEvent) == [2], "next event's album notification is not suppressed by prior batch")
check(scheduledBatch(repeated).messages.count == 1 && scheduledBatch(repeated).messages.count == 1, "independent account-context/event invocations do not share keys")
print("PASS: \(assertions) actual-source background album coalescing and scheduling assertions")
'''

with tempfile.TemporaryDirectory(prefix="supergram-notification-album-") as temporary:
    swift_source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    swift_source.write_text(swift)
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(swift_source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
