// MARK: Swiftgram
// SuperGram (W2-GHOST, SGUI-05): extra profile rows ported from Swiftgram without the Swiftgram API.
// - "id: …" (showProfileId), copyable by tap / long tap;
// - "dc: N" + phone country (showDC) from the avatar's datacenter and peerStatusSettings.phoneCountry;
// - chat creation date (showCreationDate): legacy groups use the local creation date, channels and supergroups the
//   date of message #1 (Swiftgram `getFirstMessage`, one `channels.getMessages` request when it is not cached);
// - "Joined <chat>" (sgShowJoinedDate): the date the user joined the group the profile was opened from
//   (Swiftgram `fetchNearestChatParticipant`, one `channels.getParticipant` request);
// - "Registered" (showRegDate): only the local peerStatusSettings.registrationDate branch (no Swiftgram regdate API).
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import TelegramStringFormatting
import UndoUI
import SGSimpleSettings
import SGStrings

// MARK: Swiftgram
/// SuperGram (W2A-04 / PERF-P2-7): memo for the two lookups these rows make, so reopening the same profile does
/// not reissue the same request.
///
/// Without this, `showCreationDate` (default ON) costs one `channels.getMessages` per channel/supergroup profile
/// open and `sgShowJoinedDate` costs one `channels.getParticipant` per user profile opened from a channel — the
/// latter completely uncached, so tapping the same person's avatar ten times issued ten requests.
///
/// Bounded by an insertion-ordered eviction list rather than growing for the lifetime of the process. Values are
/// small and change rarely (a chat's creation date never changes; a join date changes only if the person leaves
/// and rejoins), so no TTL: the memo is per-process and is gone on the next launch.
private final class SuperGramProfileExtrasCache {
    static let shared = SuperGramProfileExtrasCache()

    private struct JoinedKey: Hashable {
        let chatPeerId: EnginePeer.Id
        let participantId: EnginePeer.Id
    }

    private let limit = 128
    private let lock = NSLock()
    private var creationTimestamps: [EnginePeer.Id: Int32?] = [:]
    private var creationTimestampOrder: [EnginePeer.Id] = []
    private var joined: [JoinedKey: (String?, Int32?)] = [:]
    private var joinedOrder: [JoinedKey] = []

    func cachedCreationTimestamp(peerId: EnginePeer.Id) -> Int32?? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.creationTimestamps[peerId]
    }

    func setCreationTimestamp(_ value: Int32?, peerId: EnginePeer.Id) {
        self.lock.lock()
        defer { self.lock.unlock() }
        let isNewKey = self.creationTimestamps.index(forKey: peerId) == nil
        self.creationTimestamps[peerId] = .some(value)
        if isNewKey {
            self.creationTimestampOrder.append(peerId)
            while self.creationTimestampOrder.count > self.limit {
                self.creationTimestamps.removeValue(forKey: self.creationTimestampOrder.removeFirst())
            }
        }
    }

    func cachedJoined(chatPeerId: EnginePeer.Id, participantId: EnginePeer.Id) -> (String?, Int32?)? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.joined[JoinedKey(chatPeerId: chatPeerId, participantId: participantId)]
    }

    func setJoined(_ value: (String?, Int32?), chatPeerId: EnginePeer.Id, participantId: EnginePeer.Id) {
        let key = JoinedKey(chatPeerId: chatPeerId, participantId: participantId)
        self.lock.lock()
        defer { self.lock.unlock() }
        let isNewKey = self.joined.index(forKey: key) == nil
        self.joined[key] = value
        if isNewKey {
            self.joinedOrder.append(key)
            while self.joinedOrder.count > self.limit {
                self.joined.removeValue(forKey: self.joinedOrder.removeFirst())
            }
        }
    }
}

/// Asynchronously loaded data for the SuperGram profile rows (kept on PeerInfoScreenNode).
struct PeerInfoSuperGramExtras: Equatable {
    var creationTimestamp: Int32?
    var joinedChatTitle: String?
    var joinedAt: Int32?

    init(creationTimestamp: Int32? = nil, joinedChatTitle: String? = nil, joinedAt: Int32? = nil) {
        self.creationTimestamp = creationTimestamp
        self.joinedChatTitle = joinedChatTitle
        self.joinedAt = joinedAt
    }
}

extension PeerInfoScreenNode {
    /// Starts loading `superGramExtras`; rows are re-laid out when the data arrives.
    func superGramStartLoadingExtras() {
        if self.isSettings {
            return
        }
        let context = self.context
        let peerId = self.peerId

        let creationTimestamp: Signal<Int32?, NoError>
        if SGSimpleSettings.shared.showCreationDate && (peerId.namespace == Namespaces.Peer.CloudChannel || peerId.namespace == Namespaces.Peer.CloudGroup) {
            // MARK: Swiftgram
            // SuperGram (W2A-04 / PERF-P2-7): serve a previously resolved date straight from the memo, so reopening
            // the same profile costs no request and shows the row immediately instead of after a round trip.
            if let cached = SuperGramProfileExtrasCache.shared.cachedCreationTimestamp(peerId: peerId) {
                creationTimestamp = .single(cached)
            } else {
                creationTimestamp = Signal<Int32?, NoError>.single(nil)
                |> then(
                    superGramChatCreationTimestamp(context: context, peerId: peerId)
                    |> beforeNext { value in
                        SuperGramProfileExtrasCache.shared.setCreationTimestamp(value, peerId: peerId)
                    }
                )
            }
        } else {
            creationTimestamp = .single(nil)
        }

        let joined: Signal<(String?, Int32?), NoError>
        if SGSimpleSettings.shared.sgShowJoinedDate && peerId.namespace == Namespaces.Peer.CloudUser && peerId != context.account.peerId {
            // The navigation stack is inspected after the push has completed.
            joined = Signal<(String?, Int32?), NoError>.single((nil, nil))
            |> then(
                Signal<Void, NoError>.single(Void())
                |> delay(0.2, queue: Queue.mainQueue())
                |> mapToSignal { [weak self] _ -> Signal<(String?, Int32?), NoError> in
                    guard let self else {
                        return .single((nil, nil))
                    }
                    return self.superGramFetchNearestChatParticipant()
                }
            )
        } else {
            joined = .single((nil, nil))
        }

        self.superGramExtrasDisposable.set((combineLatest(queue: Queue.mainQueue(), creationTimestamp, joined)
        |> map { creationTimestamp, joined -> PeerInfoSuperGramExtras in
            return PeerInfoSuperGramExtras(creationTimestamp: creationTimestamp, joinedChatTitle: joined.0, joinedAt: joined.1)
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).startStrict(next: { [weak self] extras in
            guard let self else {
                return
            }
            if self.superGramExtras == extras {
                return
            }
            self.superGramExtras = extras
            if let (layout, navigationHeight) = self.validLayout {
                self.containerLayoutUpdated(layout: layout, navigationHeight: navigationHeight, transition: .immediate)
            }
        }))
    }

    private func superGramFetchNearestChatParticipant() -> Signal<(String?, Int32?), NoError> {
        guard let navigationController = self.controller?.navigationController as? NavigationController else {
            return .single((nil, nil))
        }
        let context = self.context
        let participantId = self.peerId
        for controller in navigationController.viewControllers.reversed() {
            if let chatController = controller as? ChatController, let chatPeerId = chatController.chatLocation.peerId, chatPeerId.namespace == Namespaces.Peer.CloudChannel {
                // MARK: Swiftgram
                // SuperGram (W2A-04 / PERF-P2-7): `fetchChannelParticipant` had no cache at all, so every open of
                // the same person's profile from the same channel issued another `channels.getParticipant`.
                if let cached = SuperGramProfileExtrasCache.shared.cachedJoined(chatPeerId: chatPeerId, participantId: participantId) {
                    return .single(cached)
                }
                return combineLatest(
                    context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: chatPeerId)),
                    context.engine.peers.fetchChannelParticipant(peerId: chatPeerId, participantId: participantId)
                )
                |> map { chatPeer, participant -> (String?, Int32?) in
                    if let participant, case let .member(_, invitedAt, _, _, _, _) = participant {
                        return (chatPeer?.compactDisplayTitle, invitedAt)
                    } else {
                        return (nil, nil)
                    }
                }
                |> beforeNext { value in
                    SuperGramProfileExtrasCache.shared.setJoined(value, chatPeerId: chatPeerId, participantId: participantId)
                }
            }
        }
        return .single((nil, nil))
    }
}

private func superGramChatCreationTimestamp(context: AccountContext, peerId: EnginePeer.Id) -> Signal<Int32?, NoError> {
    if peerId.namespace == Namespaces.Peer.CloudGroup {
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> map { peer -> Int32? in
            if case let .legacyGroup(group)? = peer, group.creationDate != 0 {
                return group.creationDate
            }
            return nil
        }
    }
    return context.engine.messages.getMessagesLoadIfNecessary([EngineMessage.Id(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 1)])
    |> `catch` { _ -> Signal<GetMessagesResult, NoError> in
        return .single(.result([]))
    }
    |> mapToSignal { result -> Signal<Int32?, NoError> in
        guard case let .result(messages) = result else {
            return .complete()
        }
        guard let firstMessage = messages.first else {
            return .single(nil)
        }
        var timestamp = firstMessage.timestamp
        // A supergroup migrated from a legacy group: message #1 is the migration service message.
        for media in firstMessage.media {
            if let action = media as? TelegramMediaAction, case let .channelMigratedFromGroup(_, legacyGroupId) = action.action {
                if let legacyGroup = firstMessage.peers[legacyGroupId] as? TelegramGroup, legacyGroup.creationDate != 0 {
                    timestamp = legacyGroup.creationDate
                }
            }
        }
        return .single(timestamp)
    }
}

/// Copies `text` and shows the standard "Copied" toast over the profile.
func superGramCopyProfileText(_ text: String, context: AccountContext, interaction: PeerInfoInteraction) {
    UIPasteboard.general.string = text
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    interaction.getController()?.present(UndoOverlayController(presentationData: presentationData, content: .copy(text: presentationData.strings.Conversation_TextCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
}

/// Rows of `InfoSection.superGram` (profile of a user, channel, supergroup or legacy group).
func superGramProfileItems(
    data: PeerInfoScreenData,
    extras: PeerInfoSuperGramExtras,
    context: AccountContext,
    presentationData: PresentationData,
    interaction: PeerInfoInteraction
) -> [PeerInfoScreenItem] {
    var items: [PeerInfoScreenItem] = []
    guard let peer = data.peer else {
        return items
    }
    let lang = presentationData.strings.baseLanguageCode
    var itemId = 0

    if SGSimpleSettings.shared.showProfileId {
        let idText: String
        switch peer {
        case .channel:
            idText = "-100" + String(peer.id.id._internalGetInt64Value())
        case .legacyGroup:
            idText = "-" + String(peer.id.id._internalGetInt64Value())
        default:
            idText = String(peer.id.id._internalGetInt64Value())
        }
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: "id: \(idText)", text: "", textColor: .primary, action: { _, _ in
            superGramCopyProfileText(idText, context: context, interaction: interaction)
        }, longTapAction: { _ in
            superGramCopyProfileText(idText, context: context, interaction: interaction)
        }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
    }
    itemId += 1

    if SGSimpleSettings.shared.showDC {
        var dcId: Int?
        var phoneCountryText = ""
        if let cachedData = data.cachedData as? CachedUserData, let phoneCountry = cachedData.peerStatusSettings?.phoneCountry {
            var countryName = ""
            let countriesConfiguration = context.currentCountriesConfiguration.with { $0 }
            if let country = countriesConfiguration.countries.first(where: { $0.id == phoneCountry }) {
                countryName = country.localizedName ?? country.name
            } else if phoneCountry == "FT" {
                countryName = presentationData.strings.Chat_NonContactUser_AnonymousNumber
            } else if phoneCountry == "TS" {
                countryName = "Test"
            }
            let flag = phoneCountry.count == 2 ? flagEmoji(countryCode: phoneCountry) : ""
            phoneCountryText = flag.isEmpty ? countryName : (flag + " " + countryName)
        }
        if let smallProfileImage = peer.smallProfileImage, let cloudResource = smallProfileImage.resource as? CloudPeerPhotoSizeMediaResource {
            dcId = cloudResource.datacenterId
        }

        var dcLabel = ""
        var dcText = ""
        if let dcId {
            dcLabel = "dc: \(dcId)"
            dcText = phoneCountryText
        } else if !phoneCountryText.isEmpty {
            dcLabel = "dc: ?"
            dcText = phoneCountryText
        }
        if !dcLabel.isEmpty {
            items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: dcLabel, text: dcText, textColor: .primary, action: nil, requestLayout: { _ in
                interaction.requestLayout(false)
            }))
        }
    }
    itemId += 1

    if SGSimpleSettings.shared.showCreationDate, let creationTimestamp = extras.creationTimestamp {
        let creationDateString = stringForDate(timestamp: creationTimestamp, strings: presentationData.strings)
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: i18n("Chat.Created", lang, creationDateString), text: "", action: nil, longTapAction: { _ in
            superGramCopyProfileText(creationDateString, context: context, interaction: interaction)
        }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
    }
    itemId += 1

    if SGSimpleSettings.shared.sgShowJoinedDate, let joinedAt = extras.joinedAt {
        let joinedDateString = stringForDate(timestamp: joinedAt, strings: presentationData.strings)
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: i18n("Chat.JoinedDateTitle", lang, extras.joinedChatTitle ?? "chat"), text: joinedDateString, action: nil, longTapAction: { _ in
            superGramCopyProfileText(joinedDateString, context: context, interaction: interaction)
        }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
    }
    itemId += 1

    if SGSimpleSettings.shared.showRegDate, let cachedData = data.cachedData as? CachedUserData, let registrationDate = cachedData.peerStatusSettings?.registrationDate {
        var regDateString = ""
        let components = registrationDate.components(separatedBy: ".")
        if components.count == 2, let first = Int32(components[0]), let second = Int32(components[1]) {
            let month = first - 1
            let year = second - 1900
            regDateString = stringForMonth(strings: presentationData.strings, month: month, ofYear: year)
        }
        if !regDateString.isEmpty {
            let regDateValue = regDateString
            items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: i18n("Chat.RegDate", lang), text: regDateValue, action: nil, longTapAction: { _ in
                superGramCopyProfileText(regDateValue, context: context, interaction: interaction)
            }, requestLayout: { _ in
                interaction.requestLayout(false)
            }))
        }
    }

    return items
}
