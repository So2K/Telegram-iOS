// SuperGram: translation features (stream W2-TRANSLATE).
//
// - Chat translation without Premium (F1 / chat-13): the client-side Premium gate is removed behind
//   `sgTranslateChatsWithoutPremium`. Translation still goes through Telegram's own
//   `messages.translateText`, or through on-device Apple Translation (iOS 18+) when the user picks
//   the "On-Device" service. There is NO Google / third-party fallback (SGM-F18): Swiftgram's
//   SGGTranslate and its silent `sgWrappedTranslate*` fallback are intentionally not ported.
// - When a translation request fails (for example the server refuses to translate a whole chat for an
//   account without Premium), the failure is published here and the translate bar shows a clear
//   message instead of silently doing nothing.
// - Quick translate button (Swiftgram `quickTranslateButton`), non-destructive: the stored message
//   text is never rewritten; the translation lives in the regular TranslationMessageAttribute and the
//   renderer asks `sgQuickTranslationLanguage(messageId:)` whether to show it.
// - Outgoing message translation (Swiftgram `outgoingLanguageTranslation`) helpers.
import Foundation
import NaturalLanguage
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import SGSimpleSettings
import SGStrings

// MARK: - Settings

/// "Translate Entire Chats" is available without Telegram Premium.
public func sgCanTranslateChatsWithoutPremium() -> Bool {
    return SGSimpleSettings.shared.sgTranslateChatsWithoutPremium
}

/// On-device Apple Translation can be used (iOS 18+).
public func sgIsOnDeviceTranslationAvailable() -> Bool {
    #if targetEnvironment(simulator)
    // The Translation framework is present in the SDK but cannot run in the simulator.
    return false
    #else
    if #available(iOS 18.0, *) {
        return true
    } else {
        return false
    }
    #endif
}

/// The user picked the on-device translation service and it is available.
public func sgPrefersOnDeviceChatTranslation() -> Bool {
    return sgIsOnDeviceTranslationAvailable() && SGSimpleSettings.shared.sgPrefersOnDeviceTranslation
}

/// The explicit local selection persists even when this OS cannot run the service.
/// Request routing uses this to fail locally instead of silently choosing a server.
func sgRequestsOnDeviceChatTranslation() -> Bool {
    return SGSimpleSettings.shared.sgPrefersOnDeviceTranslation
}

/// Switches the translation service between Telegram (server) and on-device Apple Translation.
public func sgSetPrefersOnDeviceChatTranslation(_ value: Bool) {
    SGSimpleSettings.shared.translationBackend = value ? SGSimpleSettings.TranslationBackend.system.rawValue : SGSimpleSettings.TranslationBackend.default.rawValue
}

// MARK: - Failures

public enum SGChatTranslationFailureReason: Equatable {
    /// Telegram's server refused the request (e.g. entire-chat translation for an account without Premium).
    case serverRejected
    /// Telegram translation is disabled for this account or region (TRANSLATIONS_DISABLED_ALT). Upstream would
    /// switch to Google here; SuperGram only offers on-device translation.
    case serverUnavailable
    /// FLOOD_WAIT from the server.
    case limitExceeded
    /// On-device translation failed (unsupported language pair, model download cancelled, ...).
    case onDeviceFailed
}

/// A chat-wide failure belongs to the account and target language of its request.
/// Account identity is the exact AccountRecordId.int64 value, never a peer identity.
public struct SGChatTranslationFailureEvent: Equatable {
    public let accountId: Int64
    public let peerId: EnginePeer.Id
    public let toLang: String
    public let reason: SGChatTranslationFailureReason

    public init(accountId: Int64, peerId: EnginePeer.Id, toLang: String, reason: SGChatTranslationFailureReason) {
        self.accountId = accountId
        self.peerId = peerId
        self.toLang = normalizeTranslationLanguage(toLang)
        self.reason = reason
    }
}

private final class SGChatTranslationFailureReporter {
    let pipe = ValuePipe<SGChatTranslationFailureEvent>()
}

private let sgChatTranslationFailureReporter = SGChatTranslationFailureReporter()

func sgChatTranslationFailureReason(error: TranslationError, onDevice: Bool) -> SGChatTranslationFailureReason? {
    switch error {
    case .limitExceeded:
        return .limitExceeded
    case .tryAlternative:
        return onDevice ? .onDeviceFailed : .serverUnavailable
    case .generic, .invalidLanguage:
        return onDevice ? .onDeviceFailed : .serverRejected
    case .invalidMessageId, .textIsEmpty, .textTooLong:
        // Problems of individual messages, not of chat translation as a whole.
        return nil
    }
}

func sgReportChatTranslationFailure(accountId: Int64, peerIds: Set<EnginePeer.Id>, toLang: String, error: TranslationError, onDevice: Bool) {
    guard let reason = sgChatTranslationFailureReason(error: error, onDevice: onDevice) else {
        return
    }
    for peerId in peerIds {
        sgChatTranslationFailureReporter.pipe.putNext(SGChatTranslationFailureEvent(accountId: accountId, peerId: peerId, toLang: toLang, reason: reason))
    }
}

/// Failed translation requests for this exact account/peer (any queue).
/// The consumer checks the current language and active state again after delivery.
public func sgChatTranslationFailures(accountId: Int64, peerId: EnginePeer.Id) -> Signal<SGChatTranslationFailureEvent, NoError> {
    return sgChatTranslationFailureReporter.pipe.signal()
    |> filter { value in
        return value.accountId == accountId && value.peerId == peerId
    }
}

/// User-facing explanation of a translation failure.
public func sgChatTranslationFailureText(reason: SGChatTranslationFailureReason, isPremium: Bool, offerOnDevice: Bool, strings: PresentationStrings) -> String {
    let lang = strings.baseLanguageCode
    switch reason {
    case .serverRejected:
        if isPremium {
            return i18n("SuperGram.Translate.Failure.Server", lang)
        } else if offerOnDevice {
            return i18n("SuperGram.Translate.Failure.ServerNonPremium.OnDevice", lang)
        } else {
            return i18n("SuperGram.Translate.Failure.ServerNonPremium", lang)
        }
    case .serverUnavailable:
        if offerOnDevice {
            return i18n("SuperGram.Translate.Failure.Unavailable.OnDevice", lang)
        } else {
            return i18n("SuperGram.Translate.Failure.Unavailable", lang)
        }
    case .limitExceeded:
        return i18n("SuperGram.Translate.Failure.LimitExceeded", lang)
    case .onDeviceFailed:
        return i18n("SuperGram.Translate.Failure.OnDevice", lang)
    }
}

/// Title of the toast action that switches translation to the on-device service.
public func sgUseOnDeviceTranslationActionTitle(strings: PresentationStrings) -> String {
    return i18n("SuperGram.Translate.Failure.UseOnDevice", strings.baseLanguageCode)
}

/// Title of the translate bar menu item that toggles on-device translation.
public func sgOnDeviceTranslationMenuTitle(strings: PresentationStrings) -> String {
    return i18n("SuperGram.Translate.OnDeviceMenuItem", strings.baseLanguageCode)
}

// MARK: - Quick translate button

/// Insertion-ordered cache with a hard size limit. On overflow the oldest quarter is dropped instead of the whole
/// table, so one screenful of messages is never re-recognised at once (W2A-15).
private struct SGBoundedCache<Key: Hashable, Value> {
    private let limit: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(limit: Int) {
        self.limit = max(4, limit)
    }

    subscript(key: Key) -> Value? {
        get {
            return self.values[key]
        }
        set {
            if let newValue = newValue {
                if self.values.updateValue(newValue, forKey: key) == nil {
                    self.order.append(key)
                    self.trimIfNeeded()
                }
            } else if self.values.removeValue(forKey: key) != nil, let index = self.order.firstIndex(of: key) {
                self.order.remove(at: index)
            }
        }
    }

    private mutating func trimIfNeeded() {
        guard self.order.count > self.limit else {
            return
        }
        let removeCount = max(1, self.limit / 4)
        for key in self.order.prefix(removeCount) {
            self.values.removeValue(forKey: key)
        }
        self.order.removeFirst(removeCount)
    }
}

private let sgLanguageRecognizerThreadKey = "SGQuickTranslationLanguageRecognizer"

/// Detects the language of `text` on a recognizer that belongs to the calling thread. The store used to hold one
/// process-wide `NLLanguageRecognizer` under its lock, which serialised every concurrent message-layout thread
/// through `processString` (PERF-P2-4).
private func sgRecognizeLanguage(text: String) -> String? {
    let threadDictionary = Thread.current.threadDictionary
    let recognizer: NLLanguageRecognizer
    if let existing = threadDictionary[sgLanguageRecognizerThreadKey] as? NLLanguageRecognizer {
        recognizer = existing
    } else {
        recognizer = NLLanguageRecognizer()
        threadDictionary[sgLanguageRecognizerThreadKey] = recognizer
    }
    recognizer.processString(text)
    let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
    recognizer.reset()
    let filteredLanguages = hypotheses.filter { supportedTranslationLanguages.contains(normalizeTranslationLanguage($0.key.rawValue)) }.sorted(by: { $0.value > $1.value })
    return filteredLanguages.first.map { normalizeTranslationLanguage($0.key.rawValue) }
}

private final class SGQuickTranslationStore {
    final class Request {
        enum Phase {
            case pending
            case completed
            case cancelled
            case failed
        }

        let language: String
        let disposable = MetaDisposable()
        // Read and written only while SGQuickTranslationStore.lock is held.
        var phase: Phase = .pending

        init(language: String) {
            self.language = language
        }
    }

    enum Toggle {
        case original(Request)
        case translation(Request)
    }

    /// Messages the user explicitly quick-translated. Only grows on a tap, but still bounded: an evicted entry just
    /// means the message shows its original text again.
    private static let languageLimit = 512
    /// Recognition results, keyed by message. Bounded because `recognizedLanguage` is called from message layout.
    private static let recognizedLanguageLimit = 2000

    private let lock = NSLock()
    private var languages = SGBoundedCache<EngineMessage.Id, Request>(limit: SGQuickTranslationStore.languageLimit)
    private var recognizedLanguages = SGBoundedCache<EngineMessage.Id, (text: String, language: String?)>(limit: SGQuickTranslationStore.recognizedLanguageLimit)

    private let targetLanguageLock = NSLock()
    private var targetLanguage: String?
    private var isObservingTargetLanguage = false
    private var targetLanguageDisposable: Disposable?

    private let ignoredLanguagesLock = NSLock()
    private var ignoredLanguages: [String]?
    private var isObservingIgnoredLanguages = false
    private var ignoredLanguagesDisposable: Disposable?

    func language(messageId: EngineMessage.Id) -> String? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.languages[messageId]?.language
    }

    func toggle(messageId: EngineMessage.Id, language: String) -> Toggle {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if let request = self.languages[messageId] {
            request.phase = .cancelled
            self.languages[messageId] = nil
            return .original(request)
        }
        let request = Request(language: language)
        self.languages[messageId] = request
        return .translation(request)
    }

    func isSelected(_ request: Request, messageId: EngineMessage.Id) -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.languages[messageId] === request && (request.phase == .pending || request.phase == .completed)
    }

    func isShowingOriginal(_ request: Request, messageId: EngineMessage.Id) -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.languages[messageId] == nil && request.phase == .cancelled
    }

    @discardableResult
    func complete(_ request: Request, messageId: EngineMessage.Id) -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard self.languages[messageId] === request, request.phase == .pending else {
            return false
        }
        request.phase = .completed
        return true
    }

    func fail(_ request: Request, messageId: EngineMessage.Id) -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard request.phase == .pending else {
            return false
        }
        request.phase = .failed
        guard self.languages[messageId] === request else {
            return false
        }
        self.languages[messageId] = nil
        return true
    }

    func cancel(_ request: Request, messageId: EngineMessage.Id) {
        self.lock.lock()
        if request.phase == .pending {
            request.phase = .cancelled
            if self.languages[messageId] === request {
                self.languages[messageId] = nil
            }
        }
        self.lock.unlock()
    }

    func recognizedLanguage(messageId: EngineMessage.Id, text: String) -> String? {
        let text = String(text.prefix(64))
        self.lock.lock()
        let cached = self.recognizedLanguages[messageId]
        self.lock.unlock()
        if let cached = cached, cached.text == text {
            return cached.language
        }
        // Recognition runs outside the lock, on a recognizer owned by this thread.
        let language = sgRecognizeLanguage(text: text)
        self.lock.lock()
        self.recognizedLanguages[messageId] = (text: text, language: language)
        self.lock.unlock()
        return language
    }

    /// Target language of quick translations (the app language), cached from the presentation-data signal instead of
    /// copying the whole `PresentationData` struct under its lock once per message (PERF-P2-4).
    func currentTargetLanguage(context: AccountContext) -> String {
        self.targetLanguageLock.lock()
        let shouldObserve = !self.isObservingTargetLanguage
        self.isObservingTargetLanguage = true
        var language = self.targetLanguage
        self.targetLanguageLock.unlock()

        if shouldObserve {
            // Subscribed outside of the lock: the signal delivers the current value synchronously.
            let disposable = (context.sharedContext.presentationData
            |> map { presentationData -> String in
                return sgNormalizedTranslationTargetLanguage(presentationData.strings.baseLanguageCode)
            }
            |> distinctUntilChanged).start(next: { [weak self] value in
                guard let self else {
                    return
                }
                self.targetLanguageLock.lock()
                self.targetLanguage = value
                self.targetLanguageLock.unlock()
            })
            self.targetLanguageLock.lock()
            self.targetLanguageDisposable = disposable
            language = self.targetLanguage
            self.targetLanguageLock.unlock()
        }

        if let language = language {
            return language
        }
        return sgNormalizedTranslationTargetLanguage(context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode)
    }

    /// Cached "Do Not Translate" languages (nil until the shared data arrives, which means the defaults).
    func currentIgnoredLanguages(context: AccountContext) -> [String]? {
        self.ignoredLanguagesLock.lock()
        let shouldObserve = !self.isObservingIgnoredLanguages
        self.isObservingIgnoredLanguages = true
        let ignoredLanguages = self.ignoredLanguages
        self.ignoredLanguagesLock.unlock()

        if shouldObserve {
            // Subscribed outside of the lock: the signal may deliver synchronously.
            let disposable = (context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.translationSettings])
            |> map { sharedData -> [String]? in
                return (sharedData.entries[ApplicationSpecificSharedDataKeys.translationSettings]?.get(TranslationSettings.self) ?? TranslationSettings.defaultSettings).ignoredLanguages
            }).start(next: { [weak self] ignoredLanguages in
                guard let self else {
                    return
                }
                self.ignoredLanguagesLock.lock()
                self.ignoredLanguages = ignoredLanguages
                self.ignoredLanguagesLock.unlock()
            })
            self.ignoredLanguagesLock.lock()
            self.ignoredLanguagesDisposable = disposable
            self.ignoredLanguagesLock.unlock()
        }
        return ignoredLanguages
    }
}

private let sgQuickTranslationStore = SGQuickTranslationStore()

/// The quick translate button setting (Swiftgram `quickTranslateButton`, default off).
public func sgQuickTranslateButtonEnabled() -> Bool {
    return SGSimpleSettings.shared.quickTranslateButton
}

/// Strips the `-raw` suffix of untranslated app languages and normalizes the rest.
private func sgNormalizedTranslationTargetLanguage(_ languageCode: String) -> String {
    var languageCode = languageCode
    let rawSuffix = "-raw"
    if languageCode.hasSuffix(rawSuffix) {
        languageCode = String(languageCode.dropLast(rawSuffix.count))
    }
    return normalizeTranslationLanguage(languageCode)
}

/// Target language of quick translations (the app language). Cached, so it is cheap to call per message.
public func sgQuickTranslationTargetLanguage(context: AccountContext) -> String {
    return sgQuickTranslationStore.currentTargetLanguage(context: context)
}

/// Language a message is currently shown translated into by the quick translate button, or nil.
/// Renderers use `item.associatedData.translateToLanguage ?? sgQuickTranslationLanguage(messageId:)`. Thread-safe.
public func sgQuickTranslationLanguage(messageId: EngineMessage.Id) -> String? {
    return sgQuickTranslationStore.language(messageId: messageId)
}

/// Whether the quick translate button should be shown next to a message. Thread-safe (called from async layout).
/// - chatTranslateToLanguage: `associatedData.translateToLanguage`; the button is hidden while the whole chat is translated.
public func sgShouldShowQuickTranslateButton(context: AccountContext, messageId: EngineMessage.Id, text: String, isIncoming: Bool, chatTranslateToLanguage: String?) -> Bool {
    guard sgQuickTranslateButtonEnabled() else {
        return false
    }
    if sgQuickTranslationStore.language(messageId: messageId) != nil {
        // Keep the button so the translation can be undone.
        return true
    }
    guard isIncoming, chatTranslateToLanguage == nil, !text.isEmpty else {
        return false
    }
    // Secret chats are end-to-end encrypted: their text is never sent anywhere for translation.
    guard messageId.peerId.namespace != Namespaces.Peer.SecretChat, messageId.namespace == Namespaces.Message.Cloud else {
        return false
    }
    guard let language = sgQuickTranslationStore.recognizedLanguage(messageId: messageId, text: text) else {
        return false
    }
    if language == sgQuickTranslationTargetLanguage(context: context) {
        return false
    }
    let ignoredLanguages = effectiveIgnoredTranslationLanguages(context: context, ignoredLanguages: sgQuickTranslationStore.currentIgnoredLanguages(context: context))
    return !ignoredLanguages.contains(language)
}

/// Translates one message in place (or shows the original again when it is already quick-translated).
/// `updated` is called on the main queue whenever the message node must be laid out again
/// (e.g. `item.controllerInteraction.requestMessageUpdate(messageId, false, nil)`); `failed` reports errors on the main queue.
public func sgToggleQuickTranslation(context: AccountContext, messageId: EngineMessage.Id, text: String, updated: @escaping () -> Void, failed: @escaping (SGChatTranslationFailureReason) -> Void) -> Disposable {
    let toLang = sgQuickTranslationTargetLanguage(context: context)
    let request: SGQuickTranslationStore.Request
    switch sgQuickTranslationStore.toggle(messageId: messageId, language: toLang) {
    case let .original(previousRequest):
        // Revoke selection under the store lock before disposing any producer or queuing UI work.
        previousRequest.disposable.dispose()
        Queue.mainQueue().async {
            if sgQuickTranslationStore.isShowingOriginal(previousRequest, messageId: messageId) {
                updated()
            }
        }
        return EmptyDisposable
    case let .translation(newRequest):
        request = newRequest
    }

    Queue.mainQueue().async {
        if sgQuickTranslationStore.isSelected(request, messageId: messageId) {
            updated()
        }
    }
    // The initial update may synchronously toggle the same message back to its original text.
    guard sgQuickTranslationStore.isSelected(request, messageId: messageId) else {
        return EmptyDisposable
    }

    let fromLang = sgQuickTranslationStore.recognizedLanguage(messageId: messageId, text: text)
    // Pass the selected backend through even if language detection or service setup failed.
    // The local route reports a failure; it must never silently upload the message instead.
    let onDevice = sgRequestsOnDeviceChatTranslation()

    let hasTranslation: (EngineMessage?) -> Bool = { message in
        guard let message else {
            return false
        }
        for attribute in message.attributes {
            if let attribute = attribute as? TranslationMessageAttribute, attribute.toLang == toLang, !attribute.text.isEmpty {
                return true
            }
        }
        return false
    }
    let currentMessage: Signal<Bool, TranslationError> = context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
    |> castError(TranslationError.self)
    |> map { message -> Bool in
        return hasTranslation(message)
    }

    let signal: Signal<Bool, TranslationError> = currentMessage
    |> mapToSignal { alreadyTranslated -> Signal<Bool, TranslationError> in
        if alreadyTranslated {
            return .single(true)
        }
        return context.engine.messages.translateMessages(messageIds: [messageId], fromLang: fromLang, toLang: toLang, enableLocalIfPossible: onDevice)
        |> map { _ -> Bool in }
        |> then(currentMessage)
    }

    let fail: (SGChatTranslationFailureReason) -> Void = { reason in
        guard sgQuickTranslationStore.fail(request, messageId: messageId) else {
            return
        }
        updated()
        failed(reason)
    }

    request.disposable.set((signal
    |> take(1)
    |> deliverOnMainQueue).start(next: { success in
        if success {
            sgQuickTranslationStore.complete(request, messageId: messageId)
        } else {
            fail(onDevice ? .onDeviceFailed : .serverRejected)
        }
    }, error: { error in
        fail(sgChatTranslationFailureReason(error: error, onDevice: onDevice) ?? (onDevice ? .onDeviceFailed : .serverRejected))
    }, completed: {
        // A completed stream without a result must not leave a selected, permanently pending translation.
        fail(onDevice ? .onDeviceFailed : .serverRejected)
    }))
    return ActionDisposable {
        // A cached/completed translation remains selected. Only this request's pending selector is removed.
        sgQuickTranslationStore.cancel(request, messageId: messageId)
        request.disposable.dispose()
    }
}

// MARK: - Outgoing message translation

/// "Translate to …" items in the long-press Send menu (default off).
public func sgOutgoingTranslationEnabled() -> Bool {
    return SGSimpleSettings.shared.sgOutgoingTranslation
}

private func sgOutgoingTranslationKey(context: AccountContext, peerId: EnginePeer.Id) -> String {
    return SGSimpleSettings.makeOutgoingLanguageTranslationKey(accountId: context.account.peerId.id._internalGetInt64Value(), peerId: peerId.id._internalGetInt64Value())
}

/// Language chosen for outgoing messages in this chat, if any.
public func sgOutgoingTranslationLanguage(context: AccountContext, peerId: EnginePeer.Id) -> String? {
    return SGSimpleSettings.shared.outgoingLanguageTranslation[sgOutgoingTranslationKey(context: context, peerId: peerId)]
}

/// User-facing explanation of a failed outgoing text translation.
public func sgOutgoingTranslationFailureText(error: TranslationError, strings: PresentationStrings) -> String {
    let lang = strings.baseLanguageCode
    switch error {
    case .limitExceeded:
        return i18n("SuperGram.Translate.Failure.LimitExceeded", lang)
    case .textTooLong:
        return i18n("SuperGram.Translate.Failure.TextTooLong", lang)
    case .generic, .invalidMessageId, .textIsEmpty, .invalidLanguage, .tryAlternative:
        return i18n("SuperGram.Translate.Failure.Outgoing", lang)
    }
}

/// Remembers the language for outgoing messages in this chat.
public func sgSetOutgoingTranslationLanguage(context: AccountContext, peerId: EnginePeer.Id, language: String) {
    // MARK: Swiftgram
    var langCode = language
    if langCode == "nb" {
        langCode = "no"
    } else if langCode.lowercased() == "pt-br" {
        langCode = "pt"
    }
    SGSimpleSettings.shared.outgoingLanguageTranslation[sgOutgoingTranslationKey(context: context, peerId: peerId)] = langCode
}
