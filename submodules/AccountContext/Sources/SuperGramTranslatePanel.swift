import Foundation
import SwiftSignalKit
import TelegramCore

// SuperGram: the "Translate to …" bar at the top of a chat is opt-in. It is shown only in chats where the user
// turned it on from the profile menu ("Translate"), and hiding the bar turns it off again. Stored locally per peer.
public enum SuperGramTranslatePanel {
    private static let key = "sgTranslatePanelShownPeers"
    private static let lock = NSLock()
    private static let updatedPipe = ValuePipe<Int64>()

    private static func load() -> Set<Int64> {
        let values = UserDefaults.standard.array(forKey: key) as? [NSNumber] ?? []
        return Set(values.map { $0.int64Value })
    }

    public static func isShown(peerId: EnginePeer.Id) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return load().contains(peerId.toInt64())
    }

    public static func setShown(peerId: EnginePeer.Id, _ value: Bool) {
        let rawId = peerId.toInt64()
        lock.lock()
        var peers = load()
        if value {
            peers.insert(rawId)
        } else {
            peers.remove(rawId)
        }
        UserDefaults.standard.set(peers.map { NSNumber(value: $0) }, forKey: key)
        lock.unlock()
        updatedPipe.putNext(rawId)
    }

    /// Current value followed by every change.
    public static func shown(peerId: EnginePeer.Id) -> Signal<Bool, NoError> {
        let rawId = peerId.toInt64()
        return Signal<Bool, NoError>.single(isShown(peerId: peerId))
        |> then(
            updatedPipe.signal()
            |> filter { $0 == rawId }
            |> map { _ -> Bool in
                return isShown(peerId: peerId)
            }
        )
        |> distinctUntilChanged
    }
}
