import Foundation
import SwiftSignalKit
struct PeerId: Hashable { let namespace: Int }
struct MessageId: Hashable { let peerId: PeerId; let raw: Int }
enum Namespaces { enum Peer { static let SecretChat = 3 } }
struct RawMessage { let id: MessageId; let containsSecretMedia: Bool; var index: Int { id.raw } }
struct EngineMessage { typealias Id = MessageId; let raw: RawMessage; var id: Id { raw.id }; var index: Int { raw.index }; func _asMessage() -> RawMessage { raw } }
struct RequestItem { let id: MessageId; init(_ id: MessageId) { self.id = id } }
enum TelegramEngine { enum EngineData { enum Item { enum Messages { typealias Message = RequestItem } } } }
struct EngineDataMap { let ids: [MessageId]; init(_ items: [RequestItem]) { ids = items.map { $0.id } } }
final class DataEngine {
    var messages: [MessageId: EngineMessage] = [:]
    var requests: [([MessageId], Subscriber<[MessageId: EngineMessage?], NoError>)] = []
    func get(_ map: EngineDataMap) -> Signal<[MessageId: EngineMessage?], NoError> {
        return Signal { subscriber in self.requests.append((map.ids, subscriber)); return EmptyDisposable }
    }
    func deliverFirst(_ override: [MessageId: EngineMessage?]? = nil) {
        let (ids, subscriber) = requests.removeFirst()
        subscriber.putNext(override ?? Dictionary(uniqueKeysWithValues: ids.map { ($0, messages[$0]) }))
        subscriber.putCompletion()
    }
}
final class Engine { let data = DataEngine() }
struct SelectionState { var selectedIds: Set<MessageId> }
struct InterfaceState { var selectionState: SelectionState?; func withoutSelectionState() -> InterfaceState { InterfaceState(selectionState:nil) } }
final class TelegramSecretChat {}
struct RenderedPeer { let peer: AnyObject }
struct PresentationState {
    var renderedPeer: RenderedPeer? = nil
    var interfaceState: InterfaceState
    func updatedInterfaceState(_ f: (InterfaceState)->InterfaceState)->PresentationState { PresentationState(interfaceState:f(interfaceState)) }
}
struct ShareControllerParams {
    enum Subject { case messages([RawMessage]) }
    let subject: Subject
    let externalShare: Bool
    let immediateExternalShare: Bool
    let updatedPresentationData: Int?
}
struct SharedController { let messages: [RawMessage]; var ids: [MessageId] { messages.map { $0.id } } }
final class SharedContext {
    var shares: [[MessageId]] = []
    var sharedSecretFlags: [[Bool]] = []
    func makeShareController(context: Context, params: ShareControllerParams)->SharedController {
        guard case let .messages(messages) = params.subject else { fatalError() }
        return SharedController(messages:messages)
    }
}
protocol AccountContext: AnyObject { var engine: Engine { get }; var sharedContext: SharedContext { get } }
final class Context: AccountContext { let engine = Engine(); let sharedContext = SharedContext() }
final class DisplayNode { func dismissInput() {} }
enum Window { case root }; enum InTarget { case window(Window) }
protocol ChatController: AnyObject { var selectedMessageIds: Set<MessageId>? { get } }
struct ChatAvailableMessageActions { let isCopyProtected: Bool }
final class Button { var isImplicitlyDisabled = false }
final class SGSimpleSettings { static let shared = SGSimpleSettings(); var sgAllowSaveProtectedContent = true }
final class Interaction {
    weak var hostController: Controller?
    func chatController()->AnyObject? { hostController }
    var share: () -> Void = {}
    var tips = 0
    func displayCopyProtectionTip(_ button: Button, _ value: Bool) { tips += 1 }
    func shareSelectedMessages() { share() }
}
final class Controller: ChatController {
    // ACTUAL_SELECTED_ID_GETTER
    let context: Context
    let chatDisplayNode = DisplayNode()
    var presentationInterfaceState = PresentationState(interfaceState:InterfaceState(selectionState:nil))
    var updatedPresentationData = 0
    init(context:Context) { self.context=context }
    func commitPurposefulAction() {}
    func updateChatPresentationInterfaceState(animated: Bool, interactive: Bool, _ f: (PresentationState)->PresentationState) { presentationInterfaceState=f(presentationInterfaceState) }
    func present(_ controller:SharedController,in target:InTarget) { context.sharedContext.shares.append(controller.ids); context.sharedContext.sharedSecretFlags.append(controller.messages.map { $0.containsSecretMedia }) }
    // ACTUAL_CONTROLLER_CLOSURE
}
final class Panel: NSObject {
    var context: AccountContext?
    var presentationInterfaceState: PresentationState?
    var selectedMessages = Set<MessageId>()
    var interfaceInteraction: Interaction?
    let shareButton = Button()
    var actions: ChatAvailableMessageActions? = ChatAvailableMessageActions(isCopyProtected:true)
    init(context:Context) { self.context=context; super.init() }
    func press() { shareButtonPressed() }
    // ACTUAL_PANEL_METHOD
}

enum NavAction { case selectionDone }
final class NavigationButtons { var performAction: ((NavAction,Int?,Int?)->Void)? }
final class Header { let navigationButtonContainer=NavigationButtons() }
final class View { func endEditing(_ value:Bool) {} }
struct PeerInfoState { var selectedMessageIds:Set<MessageId>? }
final class PeerInfo {
    let context:Context
    let peerId=PeerId(namespace:0)
    var state=PeerInfoState(selectedMessageIds:nil)
    let headerNode=Header()
    let view=View()
    var controller:Controller?
    init(context:Context) { self.context=context;self.controller=Controller(context:context) }
    // ACTUAL_PEERINFO_CLOSURE
}
func peerInfoInteraction(shareMessages:@escaping()->Void)->Interaction {
    let value=Interaction();value.share = // ACTUAL_PEERINFO_BRIDGE
    return value
}
