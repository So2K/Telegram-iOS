import Foundation
import SwiftSignalKit

// Only Telegram/UI/engine boundaries are synthetic. The complete sgToggleQuickTranslation,
// Bubble's property/method/deinit, and every SwiftSignalKit implementation are extracted.
enum TranslationError { case limitExceeded, tryAlternative, generic, invalidLanguage, invalidMessageId, textIsEmpty, textTooLong }
final class TranslationMessageAttribute {
    let toLang: String
    let text: String
    let entities: [Int] = []
    init(toLang: String, text: String) { self.toLang = toLang; self.text = text }
}
struct EngineMessage {
    typealias Id = Int64
    var id: Id
    var text: String = "synthetic text"
    var attributes: [AnyObject] = []
}
enum TelegramEngine {
    enum EngineData {
        enum Item {
            enum Messages {
                struct Message { let id: Int64 }
            }
        }
    }
}
final class EngineRegistry {
    struct Request {
        let messageIds: [Int64]
        let subscriber: Subscriber<Never, TranslationError>
    }
    private let requests = Atomic<[Int: Request]>(value: [:])
    private let ids = Atomic<Int>(value: 0)
    private let disposeCount = Atomic<Int>(value: 0)
    private let starts = Atomic<[[Int64]]>(value: [])
    var onDispose: (() -> Void)?
    var count: Int { requests.with { $0.count } }
    var disposalCount: Int { disposeCount.with { $0 } }
    var startedIds: [[Int64]] { starts.with { $0 } }
    func request(messageIds: [Int64]) -> Signal<Never, TranslationError> {
        return Signal { [self] subscriber in
            let id = ids.modify { $0 + 1 }
            _ = starts.modify { $0 + [messageIds] }
            _ = requests.modify { state in var state = state; state[id] = Request(messageIds: messageIds, subscriber: subscriber); return state }
            return ActionDisposable { [self] in
                _ = disposeCount.modify { $0 + 1 }
                _ = requests.modify { state in var state = state; state.removeValue(forKey: id); return state }
                onDispose?()
            }
        }
    }
    func heldSubscribers() -> [Subscriber<Never, TranslationError>] { requests.with { $0.sorted { $0.key < $1.key }.map { $0.value.subscriber } } }
    func fail() { heldSubscribers().forEach { $0.putError(.generic) } }
    func complete() { heldSubscribers().forEach { $0.putCompletion() } }
    func forceCleanup() { heldSubscribers().forEach { $0.putCompletion() } }
}
final class DataEngine {
    var values: [Int64: EngineMessage] = [:]
    var emitsValue = true
    func get(_ item: TelegramEngine.EngineData.Item.Messages.Message) -> Signal<EngineMessage?, NoError> {
        // Real EngineData fetch returns a signal; reading happens at subscription here too.
        return Signal { [self] subscriber in
            if emitsValue { subscriber.putNext(values[item.id]) }
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}
final class MessagesEngine {
    let registry: EngineRegistry
    init(_ registry: EngineRegistry) { self.registry = registry }
    func translateMessages(messageIds: [Int64], fromLang: String?, toLang: String, enableLocalIfPossible: Bool) -> Signal<Never, TranslationError> {
        return registry.request(messageIds: messageIds)
    }
}
final class Engine {
    let data = DataEngine()
    let messages: MessagesEngine
    init(_ registry: EngineRegistry) { self.messages = MessagesEngine(registry) }
}
struct Strings {}
struct PresentationData { let strings = Strings() }
final class SharedContext { let currentPresentationData = Atomic<PresentationData>(value: PresentationData()) }
final class AccountContext {
    let engine: Engine
    let sharedContext = SharedContext()
    var isPremium = false
    init(_ registry: EngineRegistry) { engine = Engine(registry) }
}
enum UndoContent { case info(title: String?, text: String, timeout: Double?, customUndoText: String?) }
final class ControllerInteraction {
    var updates: [Int64] = []
    var failures = 0
    var summarizedMessageIds = Set<Int64>()
    var onUpdate: ((Int64) -> Void)?
    func requestMessageUpdate(_ id: Int64, _ scroll: Bool, _ transition: Int?) { updates.append(id); onUpdate?(id) }
    func displayUndo(_ content: UndoContent) { failures += 1 }
}
enum Subject { case messageOptions }
struct AssociatedData { var translateToLanguage: String?; var subject: Subject? }
struct Summary { let text: String; let entities: [Int] }
final class SummarizationMessageAttribute { func summaryForLang(_ language: String?) -> Summary? { nil } }
struct ChatMessageItem {
    let context: AccountContext
    let message: EngineMessage
    let controllerInteraction: ControllerInteraction
    var associatedData = AssociatedData()
}
private var onDevice = false
func sgQuickTranslationTargetLanguage(context: AccountContext) -> String { "de" }
func sgRequestsOnDeviceChatTranslation() -> Bool { onDevice }
func sgChatTranslationFailureText(reason: SGChatTranslationFailureReason, isPremium: Bool, offerOnDevice: Bool, strings: Strings) -> String { "synthetic failure" }

// The extraction script appends actual enum/reason function/helper and the Bubble shell here.

func sgRecognizeLanguage(text: String) -> String? { "en" }
