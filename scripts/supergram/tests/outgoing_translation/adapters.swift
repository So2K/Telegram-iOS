import Foundation
import SwiftSignalKit
struct MessageId:Equatable { let value:Int }
struct PeerId { let namespace:Int }
struct Peer { let id:PeerId }
enum Namespaces { enum Peer { static let SecretChat=3 } }
enum ChatLocation:Equatable {
    case peer(Int),replyThread(Int,Int)
    var peerId:Int? { switch self { case let .peer(id),let .replyThread(id,_):return id } }
}
// ACTUAL_ENTITY_ADAPTERS
struct ChatTextInputState:Equatable {
    var inputText:NSAttributedString;var selectionRange:Range<Int>
    // ACTUAL_INPUT_EQUALITY
    init(inputText:NSAttributedString,selectionRange:Range<Int>) { self.inputText=inputText;self.selectionRange=selectionRange }
}
struct ChatEditMessageState {
    let messageId:MessageId;let inputState:ChatTextInputState
    func withUpdatedInputState(_ inputState:ChatTextInputState)->ChatEditMessageState { .init(messageId:messageId,inputState:inputState) }
}
struct ChatInterfaceState {
    var timestamp:Int32=0
    var composeInputState:ChatTextInputState
    var composeDisableUrlPreviews:[String]=[]
    var replyMessageSubject:ReplyMessageSubject?=nil
    var forwardMessageIds:[MessageId]?=nil
    var forwardOptionsState:Int?=nil
    var editMessage:ChatEditMessageState?=nil
    var selectionState:Int?=nil
    var messageActionsState:Int=0
    var historyScrollState:Int?=nil
    var mediaRecordingMode:Int=0
    var mediaDraftState:Int?=nil
    var silentPosting=false
    var inputLanguage:String?=nil
    var sendMessageEffect:Int64?=nil
    var postSuggestionState:PostSuggestionState?=nil
    // ACTUAL_SYNCHRONIZEABLE_GETTER
    // ACTUAL_EFFECTIVE_GETTER
    // ACTUAL_EFFECTIVE_UPDATE
}
struct TranslationState { let fromLang:String }
struct PresentationState {
    var interfaceState:ChatInterfaceState
    var translationState:TranslationState?=TranslationState(fromLang:"de")
    func updatedInterfaceState(_ f:(ChatInterfaceState)->ChatInterfaceState)->PresentationState { var result=self;result.interfaceState=f(interfaceState);return result }
}
enum TranslationError:Error { case generic }
final class EngineMessages {
    struct Request { let text:String;let entities:[MessageTextEntity];let subscriber:Subscriber<(String,[MessageTextEntity])?,TranslationError> }
    var requests:[Request]=[]
    func translate(text:String,toLang:String,entities:[MessageTextEntity])->Signal<(String,[MessageTextEntity])?,TranslationError> {
        Signal { subscriber in self.requests.append(Request(text:text,entities:entities,subscriber:subscriber));return EmptyDisposable }
    }
    func deliver(_ text:String?) {
        let request=requests.removeFirst();request.subscriber.putNext(text.map{($0,[])});request.subscriber.putCompletion()
    }
    func fail() { requests.removeFirst().subscriber.putError(.generic) }
}
final class Engine { let messages=EngineMessages() }
final class Context { let engine=Engine() }
enum Globals { static var enabled=true;static var language:String?="fr" }
func sgOutgoingTranslationEnabled()->Bool { Globals.enabled }
func sgOutgoingTranslationLanguage(context:Context,peerId:PeerId)->String? { Globals.language }
func sgSetOutgoingTranslationLanguage(context:Context,peerId:Int,language:String) {}
func chatInputStateStringWithAppliedEntities(_ text:String,entities:[MessageTextEntity])->NSAttributedString { NSAttributedString(string:text) }
struct PresentationData { let strings=0 }
enum Target { case current }
enum OverlayContent { case info(title:String?,text:String,timeout:Int?,customUndoText:String?) }
final class UndoOverlayController {
    init(presentationData:PresentationData,content:OverlayContent,elevatedLayout:Bool,animateInAsReplacement:Bool,action:(Int)->Bool) {}
}
func sgOutgoingTranslationFailureText(error:TranslationError,strings:Int)->String { "failure" }
final class LanguageController {}
func sgOutgoingTranslationLanguageSelectionController(context:Context,selectedLanguage:String?,completion:@escaping(String)->Void)->LanguageController { LanguageController() }
final class Controller {
    let context=Context()
    var chatLocation=ChatLocation.peer(1)
    var presentationInterfaceState=PresentationState(interfaceState:ChatInterfaceState(composeInputState:ChatTextInputState(inputText:NSAttributedString(string:"A"),selectionRange:1..<1)))
    let presentationData=PresentationData()
    var updates=0;var overlays=0;var sends=0
    func updateChatPresentationInterfaceState(interactive:Bool,_ f:(PresentationState)->PresentationState) { updates += 1;presentationInterfaceState=f(presentationInterfaceState) }
    func present(_ controller:UndoOverlayController,in target:Target) { overlays += 1 }
    func push(_ controller:LanguageController) {}
}
func chatMessageDisplaySendMessageOptions(selfController:Controller,node:Int,gesture:Int) {}
typealias TranslationContext=(outgoingMessageTranslateToLang:String?,translate:(()->Void)?,changeTranslationLanguage:(()->())?)
func makeTranslationContext(selfController:Controller,peer:Peer,node:Int=0,gesture:Int=0)->TranslationContext {
    // ACTUAL_TRANSLATION_BLOCK
    return sgTranslationContext
}
final class MenuController { var dismissed=0;func dismiss() { dismissed += 1 } }
final class Environment { let parent=MenuController();func controller()->MenuController? { parent } }
struct Component { let sgTranslationContext:TranslationContext }
final class MenuView {
    var component:Component?
    let environment:Environment?=Environment()
    var animateOutToEmpty=false
    // ACTUAL_MENU_ACTION
}
