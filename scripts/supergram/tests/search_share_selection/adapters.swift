import Foundation
import SwiftSignalKit
struct PeerId: Hashable { let namespace: Int }
struct MessageId: Hashable { let peerId: PeerId; let namespace:Int;let raw: Int;init(peerId:PeerId,namespace:Int=0,raw:Int){self.peerId=peerId;self.namespace=namespace;self.raw=raw} }
enum Namespaces { enum Peer { static let SecretChat=3 } }
// ACTUAL_VIEW_ONCE_CONSTANT
struct RawMessage {
    let id:MessageId;let secret:Bool;let timeout:Int32?
    init(id:MessageId,secret:Bool,timeout:Int32?=nil){self.id=id;self.secret=secret;self.timeout=timeout}
    var index:Int {id.raw}
    var containsSecretMedia:Bool {secret}
    var minAutoremoveOrClearTimeout:Int32? {timeout}
    // ACTUAL_RAW_SECRET
}
struct EngineMessage {
    typealias Id=MessageId
    let raw:RawMessage
    var id:Id { raw.id }; var index:Int { raw.index }
    // ACTUAL_ENGINE_SECRET
    func _asMessage()->RawMessage { raw }
}
struct RequestItem { let id:MessageId; init(id:MessageId) { self.id=id } }
enum TelegramEngine { enum EngineData { enum Item { enum Messages { typealias Message=RequestItem } } } }
struct EngineDataMap { let ids:[MessageId]; init(_ items:[RequestItem]) { ids=items.map { $0.id } } }
final class DataEngine {
    var messages:[MessageId:EngineMessage]=[:]
    var requests:[([MessageId],Subscriber<[MessageId:EngineMessage?],NoError>)]=[]
    var issuedRequests:[[MessageId]]=[]
    var immediate=false
    func get(_ map:EngineDataMap)->Signal<[MessageId:EngineMessage?],NoError> {
        Signal { subscriber in
            self.issuedRequests.append(map.ids)
            if self.immediate {
                subscriber.putNext(Dictionary(uniqueKeysWithValues:map.ids.map { ($0,self.messages[$0]) }))
                subscriber.putCompletion()
            } else {
                self.requests.append((map.ids,subscriber))
            }
            return EmptyDisposable
        }
    }
    func deliverFirst(_ override:[MessageId:EngineMessage?]?=nil) {
        let (ids,s)=requests.removeFirst()
        s.putNext(override ?? Dictionary(uniqueKeysWithValues:ids.map { ($0,messages[$0]) }))
        s.putCompletion()
    }
}
final class Engine { let data=DataEngine() }
struct ShareControllerParams {
    enum Subject { case messages([RawMessage]) }
    let subject:Subject;let externalShare:Bool;let immediateExternalShare:Bool
}
struct SharedController { let ids:[MessageId];let secrets:[Bool] }
final class SharedContext {
    var shares:[[MessageId]]=[]
    var secrets:[[Bool]]=[]
    func makeShareController(context:Context,params:ShareControllerParams)->SharedController {
        guard case let .messages(messages)=params.subject else { fatalError() }
        return SharedController(ids:messages.map{$0.id},secrets:messages.map{$0.secret})
    }
}
protocol AccountContext:AnyObject { var engine:Engine {get};var sharedContext:SharedContext {get} }
final class Context:AccountContext { let engine=Engine();let sharedContext=SharedContext() }
struct ChatAvailableMessageActions {
    struct Options:OptionSet {
        let rawValue:Int
        static let externalShare=Options(rawValue:1)
    }
    let isCopyProtected:Bool;let options:Options
}
enum SuperGramContentProtection { static var allowSaveProtectedContent=true }
final class Button { var isImplicitlyDisabled=false;var view:Int { 0 } }
struct SearchState:Equatable {
    var selectedMessageIds:Set<MessageId>?
}
final class StatePromise {
    func set(_ state:SearchState) {}
}
final class PaneNode { func updateSelectedMessages(animated:Bool) {} }
struct Pane { let node=PaneNode() }
final class PaneContainer { var currentPanes:[Int:Pane]=[:] }
final class SearchContainer {
    let context:Context
    var stateValue=SearchState()
    let statePromise=StatePromise()
    let paneContainerNode=PaneContainer()
    var selectionPanelNode:Panel?
    var present:((SharedController,Int?)->Void)?
    init(context:Context) {
        self.context=context
        self.present={ [weak context] controller,_ in
            context?.sharedContext.shares.append(controller.ids)
            context?.sharedContext.secrets.append(controller.secrets)
        }
    }
    func dismissInput() {}
    // ACTUAL_STATE_UPDATE
    func select(_ ids:Set<MessageId>?) { updateState { _ in SearchState(selectedMessageIds:ids) } }
    // ACTUAL_SELECTED_IDS_GETTER
    // ACTUAL_SHARE_CLOSURE
}
final class Panel:NSObject {
    let context:AccountContext
    let shareButton=Button()
    var actions:ChatAvailableMessageActions?=ChatAvailableMessageActions(isCopyProtected:true,options:[.externalShare])
    var selectedMessages=Set<MessageId>()
    var shareMessages:()->Void={}
    let getSelectedMessageIds:()->Set<MessageId>?
    var tips=0
    init(context:Context,getSelectedMessageIds:@escaping()->Set<MessageId>?) { self.context=context;self.getSelectedMessageIds=getSelectedMessageIds }
    func displayCopyProtectionTip(_ view:Int,_ save:Bool) { tips += 1 }
    func press() { shareButtonPressed() }
    // ACTUAL_PANEL_METHOD
}
