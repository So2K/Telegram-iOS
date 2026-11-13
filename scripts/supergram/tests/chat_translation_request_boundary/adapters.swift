import Foundation
import CoreFoundation
import SwiftSignalKit

enum EnginePeer { struct Id: Hashable { let value: Int64 } }
enum EngineMessage { struct Id: Hashable { let peerId: EnginePeer.Id; let id: Int32 } }
struct MessageAndThreadId: Hashable { let messageId: EngineMessage.Id }
enum TranslationError: Error { case limitExceeded, tryAlternative, generic, invalidLanguage, invalidMessageId, textIsEmpty, textTooLong }
struct AccountRecordId: Hashable { let value: Int64; var int64: Int64 { value } }
struct Account { let id: AccountRecordId }
struct Strings { var baseLanguageCode = "de" }
struct PresentationData { let strings = Strings() }
final class SharedContext { let currentPresentationData = Atomic(value: PresentationData()) }
final class AccountContext { let account: Account; let sharedContext = SharedContext(); let engine = SyntheticEngine(); init(_ id: Int64) { account = Account(id: AccountRecordId(value: id)) } }
final class SyntheticRequest {
    var subscriber: Subscriber<Never, TranslationError>?
    var disposals = 0
    func fail(_ error: TranslationError = .generic) { subscriber?.putError(error) }
}
final class SyntheticEngine {
    var requests: [SyntheticRequest] = []
    var synchronousError: TranslationError?
    func request() -> Signal<Never, TranslationError> {
        let request = SyntheticRequest(); requests.append(request)
        let immediate = synchronousError; synchronousError = nil
        return Signal { subscriber in
            request.subscriber = subscriber
            if let immediate { subscriber.putError(immediate) }
            return ActionDisposable { request.disposals += 1 }
        }
    }
}
struct Peer { let id: EnginePeer.Id }
struct Info { var isPremium = false; var isActive = true; var fromLang = "en"; var toLang: String? = "de"; var peer: Peer? }
struct ChatTranslationState { var fromLang: String = "en"; var toLang: String? = "de"; var isEnabled = true }
struct ChatPresentationTranslationState { var isEnabled = true; var fromLang = "en"; var toLang = "de" }
final class TranslationMessageAttribute { let toLang: String; init(_ value: String) { toLang = value } }
final class PinnedMessageValue { let id: EngineMessage.Id; var attributes: [Any]; init(_ id: EngineMessage.Id, cached: String? = nil) { self.id = id; self.attributes = cached.map { [TranslationMessageAttribute($0)] } ?? [] } }
struct PinnedValue { let message: PinnedMessageValue }
struct PinnedInterfaceState { var translationState: ChatPresentationTranslationState?; var pinnedMessage: PinnedValue? }
enum Source { case `default`, other }
final class ProcessingManager { var process: ((Set<MessageAndThreadId>) -> Void)? }
struct UIColor { static let white = UIColor() }
struct UIImage { init?(bundleImageName: String) {} }
func generateTintedImage(image: UIImage?, color: UIColor) -> UIImage? { nil }
func sgIsOnDeviceTranslationAvailable() -> Bool { true }
var prefersOnDevice = false
var backendChoices = 0
func sgPrefersOnDeviceChatTranslation() -> Bool { prefersOnDevice }
func sgSetPrefersOnDeviceChatTranslation(_ value: Bool) { prefersOnDevice = value; backendChoices += 1 }
func sgChatTranslationFailureText(reason: SGChatTranslationFailureReason, isPremium: Bool, offerOnDevice: Bool, strings: Strings) -> String { "Synthetic reason" }
func sgUseOnDeviceTranslationActionTitle(strings: Strings) -> String { "Synthetic action" }
enum UndoOverlayContent { case image(image: UIImage, title: String?, text: String, round: Bool, undoText: String?); case info(title: String?, text: String, timeout: Double?, customUndoText: String?) }
enum Action { case undo, dismiss }
final class UndoOverlayController { let action: (Action) -> Bool; init(presentationData: PresentationData, content: UndoOverlayContent, elevatedLayout: Bool, animateInAsReplacement: Bool, action: @escaping (Action) -> Bool) { self.action = action } }
enum PresentationLocation { case current }
final class ViewController { var presented = 0; var overlay: UndoOverlayController?; func present(_ value: UndoOverlayController, in location: PresentationLocation) { presented += 1; overlay = value } }

var checks = 0
var failures: [String] = []
func check(_ value: Bool, _ label: String) { checks += 1; if !value { failures.append(label); print("FAIL: \(label)") } }
func pump() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08)) }
func raw(_ language: String? = "de", enabled: Bool = true, from: String = "en") -> ChatTranslationState { ChatTranslationState(fromLang: from, toLang: language, isEnabled: enabled) }
