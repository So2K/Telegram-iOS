import Foundation
import NaturalLanguage
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramUIPreferences

public struct ChatTranslationState: Codable {
    enum CodingKeys: String, CodingKey {
        case baseLang
        case fromLang
        case timestamp
        case toLang
        case isEnabled
    }
    
    public let baseLang: String
    public let fromLang: String
    public let timestamp: Int32?
    public let toLang: String?
    public let isEnabled: Bool
    
    public init(
        baseLang: String,
        fromLang: String,
        timestamp: Int32?,
        toLang: String?,
        isEnabled: Bool
    ) {
        self.baseLang = baseLang
        self.fromLang = fromLang
        self.timestamp = timestamp
        self.toLang = toLang
        self.isEnabled = isEnabled
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.baseLang = try container.decode(String.self, forKey: .baseLang)
        self.fromLang = try container.decode(String.self, forKey: .fromLang)
        self.timestamp = try container.decodeIfPresent(Int32.self, forKey: .timestamp)
        self.toLang = try container.decodeIfPresent(String.self, forKey: .toLang)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.baseLang, forKey: .baseLang)
        try container.encode(self.fromLang, forKey: .fromLang)
        try container.encodeIfPresent(self.timestamp, forKey: .timestamp)
        try container.encodeIfPresent(self.toLang, forKey: .toLang)
        try container.encode(self.isEnabled, forKey: .isEnabled)
    }

    public func withToLang(_ toLang: String?) -> ChatTranslationState {
        return ChatTranslationState(
            baseLang: self.baseLang,
            fromLang: self.fromLang,
            timestamp: self.timestamp,
            toLang: toLang,
            isEnabled: self.isEnabled
        )
    }
    
    public func withIsEnabled(_ isEnabled: Bool) -> ChatTranslationState {
        return ChatTranslationState(
            baseLang: self.baseLang,
            fromLang: self.fromLang,
            timestamp: self.timestamp,
            toLang: self.toLang,
            isEnabled: isEnabled
        )
    }
}

private func cachedChatTranslationState(engine: TelegramEngine, peerId: EnginePeer.Id, threadId: Int64?) -> Signal<ChatTranslationState?, NoError> {
    let key: EngineDataBuffer
    if let threadId {
        key = EngineDataBuffer(length: 16)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
        key.setInt64(8, value: threadId)
    } else {
        key = EngineDataBuffer(length: 8)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
    }
    
    return engine.data.subscribe(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key))
    |> map { entry -> ChatTranslationState? in
        return entry?.get(ChatTranslationState.self)
    }
}

private func updateChatTranslationState(engine: TelegramEngine, peerId: EnginePeer.Id, threadId: Int64?, state: ChatTranslationState?) -> Signal<Never, NoError> {
    let key: EngineDataBuffer
    if let threadId {
        key = EngineDataBuffer(length: 16)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
        key.setInt64(8, value: threadId)
    } else {
        key = EngineDataBuffer(length: 8)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
    }
    
    if let state {
        return engine.itemCache.put(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key, item: state)
    } else {
        return engine.itemCache.remove(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key)
    }
}

public func updateChatTranslationStateInteractively(engine: TelegramEngine, peerId: EnginePeer.Id, threadId: Int64?, _ f: @escaping (ChatTranslationState?) -> ChatTranslationState?) -> Signal<Never, NoError> {
    let key: EngineDataBuffer
    if let threadId {
        key = EngineDataBuffer(length: 16)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
        key.setInt64(8, value: threadId)
    } else {
        key = EngineDataBuffer(length: 8)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
    }
    
    return engine.data.get(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key))
    |> map { entry -> ChatTranslationState? in
        return entry?.get(ChatTranslationState.self)
    }
    |> mapToSignal { current -> Signal<Never, NoError> in
        if let current {
            return updateChatTranslationState(engine: engine, peerId: peerId, threadId: threadId, state: f(current))
        } else {
            return .never()
        }
    }
}


private func sgLanguageRecognitionSample(text: String, entities: [MessageTextEntity]) -> String {
    let sample = NSMutableString(string: String(text.prefix(256)))
    var ranges: [Range<Int>] = []
    for entity in entities {
        switch entity.type {
        case .Pre, .Code, .Url, .Email, .Mention, .Hashtag, .BotCommand:
            // Telegram's entity offsets are UTF-16, not Swift Character offsets. Clip to
            // the sample and merge overlaps before deleting so every range remains valid.
            let lower = entity.range.lowerBound
            let upper = min(entity.range.upperBound, sample.length)
            if lower >= 0, lower < upper {
                ranges.append(lower ..< upper)
            }
        default:
            break
        }
    }
    ranges.sort { $0.lowerBound < $1.lowerBound }
    var merged: [Range<Int>] = []
    for range in ranges {
        if let last = merged.last, range.lowerBound <= last.upperBound {
            merged[merged.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
        } else {
            merged.append(range)
        }
    }
    for range in merged.reversed() {
        sample.deleteCharacters(in: NSRange(location: range.lowerBound, length: range.count))
    }
    return sample as String
}

public func translateMessageIds(context: AccountContext, messageIds: [EngineMessage.Id], fromLang: String?, toLang: String, isCurrent: (() -> Bool)? = nil) -> Signal<Never, NoError> {
    let accountId = context.account.id.int64
    return context.account.postbox.transaction { transaction -> Signal<Never, NoError> in
        var messageIdsToTranslate: [EngineMessage.Id] = []
        var messageIdsSet = Set<EngineMessage.Id>()
        for messageId in messageIds {
            if let message = transaction.getMessage(messageId) {
                if let replyAttribute = message.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute, let replyMessage = message.associatedMessages[replyAttribute.messageId] {
                    if !replyMessage.text.isEmpty {
                        if let translation = replyMessage.attributes.first(where: { $0 is TranslationMessageAttribute }) as? TranslationMessageAttribute, translation.toLang == toLang {
                        } else {
                            if !messageIdsSet.contains(replyMessage.id) {
                                messageIdsToTranslate.append(replyMessage.id)
                                messageIdsSet.insert(replyMessage.id)
                            }
                        }
                    }
                }
                guard message.author?.id != context.account.peerId else {
                    continue
                }
                if let translation = message.attributes.first(where: { $0 is TranslationMessageAttribute }) as? TranslationMessageAttribute, translation.toLang == toLang {
                    continue
                }
                
                if !message.text.isEmpty {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                    }
                } else if let _ = message.media.first(where: { $0 is TelegramMediaPoll }) {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                    }
                } else if let audioTranscription = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, !audioTranscription.text.isEmpty && !audioTranscription.isPending {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                    }
                }
            } else {
                if !messageIdsSet.contains(messageId) {
                    messageIdsToTranslate.append(messageId)
                    messageIdsSet.insert(messageId)
                }
            }
        }
        
        let translationConfiguration = TranslationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
        var enableLocalIfPossible = false
        switch translationConfiguration.auto {
        case .system:
            if #available(iOS 18.0, *) {
                enableLocalIfPossible = true
            }
        default:
            break
        }
        // SuperGram: the user can pick on-device Apple Translation (iOS 18+) instead of Telegram's server.
        // A missing local model or source language is an error, never permission for a server fallback.
        if sgRequestsOnDeviceChatTranslation() {
            enableLocalIfPossible = true
        }
        let effectiveFromLang: String? = (fromLang?.isEmpty ?? true) ? nil : fromLang
        let isOnDevice = enableLocalIfPossible
        let peerIds = Set(messageIdsToTranslate.map(\.peerId))
        return context.engine.messages.translateMessages(messageIds: messageIdsToTranslate, fromLang: effectiveFromLang, toLang: toLang, enableLocalIfPossible: enableLocalIfPossible)
        |> deliverOnMainQueue
        |> `catch` { error -> Signal<Never, NoError> in
            // Caller state is main-owned. A retained old RPC must not publish into a new translation episode.
            if let isCurrent, !isCurrent() {
                return .complete()
            }
            // SuperGram: no silent failure and no third-party fallback (SGM-F18); the translate bar explains what happened.
            sgReportChatTranslationFailure(accountId: accountId, peerIds: peerIds, toLang: toLang, error: error, onDevice: isOnDevice)
            return .complete()
        }
    } |> switchToLatest
}

public func chatTranslationState(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?) -> Signal<ChatTranslationState?, NoError> {
    if peerId.id == EnginePeer.Id.Id._internalFromInt64Value(777000) {
        return .single(nil)
    }
    
    guard canTranslateChats(context: context) else {
        return .single(nil)
    }
    
    let loggingEnabled = context.sharedContext.immediateExperimentalUISettings.logLanguageRecognition
    
    if #available(iOS 12.0, *) {
        var baseLang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        let rawSuffix = "-raw"
        if baseLang.hasSuffix(rawSuffix) {
            baseLang = String(baseLang.dropLast(rawSuffix.count))
        }

        return combineLatest(
            context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.translationSettings])
            |> map { sharedData -> TranslationSettings in
                return sharedData.entries[ApplicationSpecificSharedDataKeys.translationSettings]?.get(TranslationSettings.self) ?? TranslationSettings.defaultSettings
            },
            context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.AutoTranslateEnabled(id: peerId))
        )
        |> mapToSignal { settings, autoTranslateEnabled in
            if !settings.translateChats && !autoTranslateEnabled {
                return .single(nil)
            }
            
            var dontTranslateLanguages = Set<String>()
            if let ignoredLanguages = settings.ignoredLanguages {
                dontTranslateLanguages = Set(ignoredLanguages)
            } else {
                dontTranslateLanguages.insert(baseLang)
                for language in systemLanguageCodes() {
                    dontTranslateLanguages.insert(language)
                }
            }
            
            return cachedChatTranslationState(engine: context.engine, peerId: peerId, threadId: threadId)
            |> mapToSignal { cached in
                let currentTime = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
                if let cached, let timestamp = cached.timestamp, cached.baseLang == baseLang && currentTime - timestamp < 60 * 60 {
                    if !dontTranslateLanguages.contains(cached.fromLang) {
                        return .single(cached)
                    } else {
                        return .single(nil)
                    }
                } else {
                    return .single(nil)
                    |> then(
                        context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: threadId), index: .upperBound, anchorIndex: .upperBound, count: 32, fixedCombinedReadStates: nil)
                        |> filter { messageHistoryView -> Bool in
                            return messageHistoryView.0.entries.count > 1
                        }
                        |> take(1)
                        |> map { messageHistoryView, _, _ -> ChatTranslationState? in
                            let messages = messageHistoryView.entries.map(\.message)
                            
                            if loggingEnabled {
                                Logger.shared.log("ChatTranslation", "Start language recognizing for \(peerId)")
                            }
                            var fromLangs: [String: Int] = [:]
                            var count = 0
                            for message in messages {
                                if message.effectivelyIncoming(context.account.peerId), message.text.count >= 10 {
                                    if let summaryAttribute = message.attributes.first(where: { $0 is SummarizationMessageAttribute }) as? SummarizationMessageAttribute, !summaryAttribute.fromLang.isEmpty {
                                        let fromLang = normalizeTranslationLanguage(summaryAttribute.fromLang)
                                        if supportedTranslationLanguages.contains(fromLang) {
                                            fromLangs[fromLang] = (fromLangs[fromLang] ?? 0) + message.text.count
                                            count += 1
                                        }
                                    } else {
                                        let text = sgLanguageRecognitionSample(text: message.text, entities: message.textEntitiesAttribute?.entities ?? [])
                                        
                                        if text.count < 10 {
                                            continue
                                        }
                                        
                                        let languageRecognizer = sgTranslationLanguageRecognizer()
                                        languageRecognizer.processString(text)
                                        let hypotheses = languageRecognizer.languageHypotheses(withMaximum: 4)
                                        languageRecognizer.reset()
                                        
                                        let filteredLanguages = hypotheses.filter { supportedTranslationLanguages.contains(normalizeTranslationLanguage($0.key.rawValue)) }.sorted(by: { $0.value > $1.value })
                                        if let language = filteredLanguages.first {
                                            let fromLang = normalizeTranslationLanguage(language.key.rawValue)
                                            if loggingEnabled && !["en", "ru"].contains(fromLang) && !dontTranslateLanguages.contains(fromLang) {
                                                Logger.shared.log("ChatTranslation", "\(text)")
                                                Logger.shared.log("ChatTranslation", "Recognized as: \(fromLang), other hypotheses: \(hypotheses.map { $0.key.rawValue }.joined(separator: ",")) ")
                                            }
                                            fromLangs[fromLang] = (fromLangs[fromLang] ?? 0) + message.text.count
                                            count += 1
                                        }
                                    }
                                }
                                if count >= 16 {
                                    break
                                }
                            }
                                                        
                            var mostFrequent: (String, Int)?
                            for (lang, count) in fromLangs {
                                if let current = mostFrequent {
                                    if count > current.1 {
                                        mostFrequent = (lang, count)
                                    }
                                } else {
                                    mostFrequent = (lang, count)
                                }
                            }
                            let fromLang = mostFrequent?.0 ?? ""
                            if loggingEnabled {
                                Logger.shared.log("ChatTranslation", "Ended with: \(fromLang)")
                            }
                            
                            let isEnabled: Bool
                            if let currentIsEnabled = cached?.isEnabled {
                                isEnabled = currentIsEnabled
                            } else if autoTranslateEnabled {
                                isEnabled = true
                            } else {
                                isEnabled = false
                            }
                            
                            let state = ChatTranslationState(
                                baseLang: baseLang,
                                fromLang: fromLang,
                                timestamp: currentTime,
                                toLang: cached?.toLang,
                                isEnabled: isEnabled
                            )
                            let _ = updateChatTranslationState(engine: context.engine, peerId: peerId, threadId: threadId, state: state).start()
                            if !dontTranslateLanguages.contains(fromLang) {
                                return state
                            } else {
                                return nil
                            }
                        }
                    )
                }
            }
        }
    } else {
        return .single(nil)
    }
}
