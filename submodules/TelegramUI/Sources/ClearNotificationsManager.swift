import Foundation
import CoreFoundation
import SwiftSignalKit
import TelegramCore

private let messageNotificationKeyExpr = try? NSRegularExpression(pattern: "^m(-?[0-9]+):(-?[0-9]+):(-?[0-9]+)(?:_.*)?$", options: [])
private let accountMessageNotificationKeyExpr = try? NSRegularExpression(pattern: "^a(-?[0-9]+):m(-?[0-9]+):(-?[0-9]+):(-?[0-9]+)$", options: [])

func managedNotificationPayloadInt64(_ value: Any?) -> Int64? {
    if let value = value as? String {
        return Int64(value)
    } else if let value = value as? NSNumber {
        // Boolean and fractional values cannot identify an account or message.
        guard CFGetTypeID(value) != CFBooleanGetTypeID() else {
            return nil
        }
        return Int64(value.stringValue)
    }
    return nil
}

private func managedNotificationPayloadInt32(_ value: Any?) -> Int32? {
    guard let value = managedNotificationPayloadInt64(value), value >= Int64(Int32.min), value <= Int64(Int32.max) else {
        return nil
    }
    return Int32(value)
}

func managedNotificationPackedPeerId(_ value: Int64) -> EnginePeer.Id? {
    // PeerId's packed representation has three namespace bits and at most 56 scalar ID bits.
    // Namespace 7 / ID 0 uses a special sentinel, so its ordinary packed spelling is noncanonical.
    guard value >= 0, value <= 0x07ffffffffffffff, value != 0x0000000700000000 else {
        return nil
    }
    return EnginePeer.Id(value)
}

public enum NotificationManagedNotificationRequestId: Hashable {
    case messageId(EngineMessage.Id, accountId: Int64? = nil)
    case globallyUniqueId(Int64, EnginePeer.Id?, accountId: Int64? = nil)
    case accountOnly(Int64)

    public var accountId: Int64? {
        switch self {
        case let .messageId(_, accountId), let .globallyUniqueId(_, _, accountId):
            return accountId
        case let .accountOnly(accountId):
            return accountId
        }
    }
    
    public init?(string: String, userInfo: [AnyHashable: Any] = [:]) {
        var accountId: Int64?
        var messageId: EngineMessage.Id?
        let scopedIdentifier = string.hasPrefix("a") && string.contains(":m")
        let legacyIdentifier = string.hasPrefix("m") && string.contains(":")
        if scopedIdentifier || legacyIdentifier {
            let expression = scopedIdentifier ? accountMessageNotificationKeyExpr : messageNotificationKeyExpr
            let range = NSRange(location: 0, length: (string as NSString).length)
            guard let match = expression?.firstMatch(in: string, options: [], range: range), match.range == range else {
                return nil
            }
            let nsString = string as NSString
            let offset = scopedIdentifier ? 1 : 0
            if scopedIdentifier {
                guard let value = Int64(nsString.substring(with: match.range(at: 1))) else {
                    return nil
                }
                accountId = value
            }
            guard let rawPeerId = Int64(nsString.substring(with: match.range(at: offset + 1))),
                  let peerId = managedNotificationPackedPeerId(rawPeerId),
                  let namespace = Int32(nsString.substring(with: match.range(at: offset + 2))),
                  let id = Int32(nsString.substring(with: match.range(at: offset + 3))) else {
                return nil
            }
            messageId = EngineMessage.Id(peerId: peerId, namespace: namespace, id: id)
        }

        if let rawAccountId = userInfo["accountId"] {
            guard let value = managedNotificationPayloadInt64(rawAccountId), accountId == nil || accountId == value else {
                return nil
            }
            accountId = value
        }

        var payloadPeerId: EnginePeer.Id?
        if let rawPeerId = userInfo["peerId"] {
            guard let value = managedNotificationPayloadInt64(rawPeerId), let peerId = managedNotificationPackedPeerId(value) else { return nil }
            payloadPeerId = peerId
        } else {
            for (key, namespace) in [("from_id", Namespaces.Peer.CloudUser), ("chat_id", Namespaces.Peer.CloudGroup), ("channel_id", Namespaces.Peer.CloudChannel)] {
                if let rawPeerId = userInfo[key] {
                    guard let value = managedNotificationPayloadInt64(rawPeerId), value > 0, value <= 0x00ffffffffffffff else { return nil }
                    payloadPeerId = EnginePeer.Id(namespace: namespace, id: EnginePeer.Id.Id._internalFromInt64Value(value))
                    break
                }
            }
        }
        if let payloadPeerId, let messageId, payloadPeerId != messageId.peerId {
            return nil
        }
        var payloadMessageId: EngineMessage.Id?
        let resolvedPeerId = payloadPeerId ?? messageId?.peerId
        if userInfo["messageId.namespace"] != nil || userInfo["messageId.id"] != nil {
            guard let resolvedPeerId, let namespace = managedNotificationPayloadInt32(userInfo["messageId.namespace"]),
                  let id = managedNotificationPayloadInt32(userInfo["messageId.id"]) else { return nil }
            payloadMessageId = EngineMessage.Id(peerId: resolvedPeerId, namespace: namespace, id: id)
        }
        if let rawId = userInfo["msg_id"] {
            guard let resolvedPeerId, let id = managedNotificationPayloadInt32(rawId), payloadMessageId == nil || payloadMessageId?.id == id else { return nil }
            if payloadMessageId == nil {
                payloadMessageId = EngineMessage.Id(peerId: resolvedPeerId, namespace: Namespaces.Message.Cloud, id: id)
            }
        }
        if let messageId, let payloadMessageId, messageId != payloadMessageId { return nil }
        if let messageId {
            self = .messageId(messageId, accountId: accountId)
        } else if let payloadMessageId {
            self = .messageId(payloadMessageId, accountId: accountId)
        } else if let accountId {
            // Calls, stories and other opaque APNs identifiers still belong to an account on logout.
            self = .accountOnly(accountId)
        } else {
            return nil
        }
    }
}

public final class ClearNotificationIdsCompletion {
    public let f: ([(String, NotificationManagedNotificationRequestId)]) -> Void
    
    public init(f: @escaping ([(String, NotificationManagedNotificationRequestId)]) -> Void) {
        self.f = f
    }
}

public final class ClearNotificationsManager {
    private struct ReadKey: Hashable {
        let accountId: Int64
        let peerId: EnginePeer.Id
        let namespace: Int32
    }

    private struct ExactKey: Hashable {
        let accountId: Int64
        let messageId: EngineMessage.Id
    }
    private let getNotificationIds: (ClearNotificationIdsCompletion) -> Void
    private let getPendingNotificationIds: (ClearNotificationIdsCompletion) -> Void
    private let removeNotificationIds: ([String]) -> Void
    private let removePendingNotificationIds: ([String]) -> Void
    
    private var ids: [ReadKey: Int32] = [:]
    private var exactIds = Set<ExactKey>()
    
    private var timer: SwiftSignalKit.Timer?
    
    public init(getNotificationIds: @escaping (ClearNotificationIdsCompletion) -> Void, removeNotificationIds: @escaping ([String]) -> Void, getPendingNotificationIds: @escaping (ClearNotificationIdsCompletion) -> Void, removePendingNotificationIds: @escaping ([String]) -> Void) {
        self.getNotificationIds = getNotificationIds
        self.removeNotificationIds = removeNotificationIds
        self.getPendingNotificationIds = getPendingNotificationIds
        self.removePendingNotificationIds = removePendingNotificationIds
    }
    
    deinit {
        self.timer?.invalidate()
    }
    
    public func clearAll(accountId: Int64? = nil) {
        self.getNotificationIds(ClearNotificationIdsCompletion { [weak self] result in
            Queue.mainQueue().async {
                var removeKeys: [String] = []
                for (identifier, requestId) in result {
                    if accountId == nil || requestId.accountId == accountId {
                        removeKeys.append(identifier)
                    }
                }
                
                if let strongSelf = self, !removeKeys.isEmpty {
                    strongSelf.removeNotificationIds(removeKeys)
                }
            }
        })
        
        self.getPendingNotificationIds(ClearNotificationIdsCompletion { [weak self] result in
            Queue.mainQueue().async {
                var removeKeys: [String] = []
                for (identifier, requestId) in result {
                    if accountId == nil || requestId.accountId == accountId {
                        removeKeys.append(identifier)
                    }
                }
                
                if let strongSelf = self, !removeKeys.isEmpty {
                    strongSelf.removePendingNotificationIds(removeKeys)
                }
            }
        })
    }
    
    public func append(_ id: EngineMessage.Id, accountId: Int64) {
        let key = ReadKey(accountId: accountId, peerId: id.peerId, namespace: id.namespace)
        self.ids[key] = max(self.ids[key] ?? id.id, id.id)
        self.scheduleCommit()
    }

    public func removeExact(_ id: EngineMessage.Id, accountId: Int64) {
        self.exactIds.insert(ExactKey(accountId: accountId, messageId: id))
        self.scheduleCommit()
    }

    private func scheduleCommit() {
        self.timer?.invalidate()
        let timer = SwiftSignalKit.Timer(timeout: 2.0, repeat: false, completion: { [weak self] in
            self?.commitNow()
        }, queue: Queue.mainQueue())
        self.timer = timer
        timer.start()
    }
    
    public func commitNow() {
        self.timer?.invalidate()
        self.timer = nil
        
        let ids = self.ids
        let exactIds = self.exactIds
        self.ids.removeAll()
        self.exactIds.removeAll()
        
        self.getNotificationIds(ClearNotificationIdsCompletion { [weak self] result in
            Queue.mainQueue().async {
                var removeKeys: [String] = []
                for (identifier, requestId) in result {
                    if case let .messageId(messageId, accountId?) = requestId {
                        let key = ReadKey(accountId: accountId, peerId: messageId.peerId, namespace: messageId.namespace)
                        if exactIds.contains(ExactKey(accountId: accountId, messageId: messageId)) || ids[key].map({ messageId.id <= $0 }) == true {
                            removeKeys.append(identifier)
                        }
                    }
                }
                
                if let strongSelf = self, !removeKeys.isEmpty {
                    strongSelf.removeNotificationIds(removeKeys)
                }
            }
        })
        
        self.getPendingNotificationIds(ClearNotificationIdsCompletion { [weak self] result in
            Queue.mainQueue().async {
                var removeKeys: [String] = []
                for (identifier, requestId) in result {
                    if case let .messageId(messageId, accountId?) = requestId {
                        let key = ReadKey(accountId: accountId, peerId: messageId.peerId, namespace: messageId.namespace)
                        if exactIds.contains(ExactKey(accountId: accountId, messageId: messageId)) || ids[key].map({ messageId.id <= $0 }) == true {
                            removeKeys.append(identifier)
                        }
                    }
                }
                
                if let strongSelf = self, !removeKeys.isEmpty {
                    strongSelf.removePendingNotificationIds(removeKeys)
                }
            }
        })
    }
}
