var checks=0
func check(_ value:Bool,_ text:String) { checks += 1;if !value { fputs("FAIL: \(text)\n",stderr);exit(42) } }
let expectedBug=CommandLine.arguments.contains("--expect-bug")
func input(_ text:String,_ attr:Int=0,_ caret:Int?=nil)->ChatTextInputState {
    let value=NSAttributedString(string:text,attributes:[NSAttributedString.Key("owned-format"):attr])
    let end=caret ?? value.length
    return ChatTextInputState(inputText:value,selectionRange:end..<end)
}
func scenario(_ kind:String,error:Bool=false) {
    let controller=Controller();controller.presentationInterfaceState.interfaceState.composeInputState=input("A")
    if kind=="editSwitch" || kind=="editToCompose" { controller.presentationInterfaceState.interfaceState.editMessage=ChatEditMessageState(messageId:MessageId(value:1),inputState:input("A")) }
    if kind=="samePeerThread" { controller.chatLocation = .replyThread(1,10) }
    Globals.enabled=true
    let view=MenuView();view.component=Component(sgTranslationContext:makeTranslationContext(selfController:controller,peer:Peer(id:PeerId(namespace:0))))
    view.action()(0,0)
    check(view.environment!.parent.dismissed==1 && view.animateOutToEmpty,"actual menu dismisses after starting translation")
    check(controller.context.engine.messages.requests.count==1 && controller.context.engine.messages.requests[0].text=="A","original draft sent once before response")
    if kind=="draft" { controller.presentationInterfaceState.interfaceState.composeInputState=input("B") }
    if kind=="cleared" { controller.presentationInterfaceState.interfaceState.composeInputState=input("") }
    if kind=="attributes" { controller.presentationInterfaceState.interfaceState.composeInputState=input("A",1) }
    if kind=="caret" { controller.presentationInterfaceState.interfaceState.composeInputState=input("A",0,0) }
    if kind=="composeToEdit" { controller.presentationInterfaceState.interfaceState.editMessage=ChatEditMessageState(messageId:MessageId(value:1),inputState:input("A")) }
    if kind=="editSwitch" { controller.presentationInterfaceState.interfaceState.editMessage=ChatEditMessageState(messageId:MessageId(value:2),inputState:input("A")) }
    if kind=="thread" { controller.chatLocation = .replyThread(1,10) }
    if kind=="samePeerThread" { controller.chatLocation = .replyThread(1,11) }
    if kind=="editToCompose" { controller.presentationInterfaceState.interfaceState.editMessage=nil }
    if kind=="setting" { Globals.enabled=false }
    let current=controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText.copy() as! NSAttributedString
    if error { controller.context.engine.messages.fail() } else { controller.context.engine.messages.deliver("T(A)") }
    let mayApply=kind=="stable" || kind=="caret" || expectedBug
    if error {
        check(controller.overlays==(mayApply ? 1:0),"stale error must not affect current draft")
        check(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText.isEqual(to:current),"error preserves current draft")
    } else {
        let expected=mayApply ? "T(A)":current.string
        check(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText.string==expected,"late translation must preserve newer draft, received \(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText.string)")
        if !mayApply { check(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText.isEqual(to:current),"stale translation preserves attributes") }
        check(controller.updates==(mayApply ? 1:0),"stale success has no UI state update")
    }
    check(controller.sends==0,"translation never sends a message")
    Globals.enabled=true
}
scenario("stable")
scenario("draft")
for kind in ["cleared","attributes","caret","composeToEdit","editSwitch","thread","setting"] { scenario(kind) }
for kind in ["stable","draft","attributes","composeToEdit","editSwitch","thread","setting"] { scenario(kind,error:true) }
print("PASS \(checks) exact outgoing translation controls")

scenario("caret",error:true)
for kind in ["editToCompose","samePeerThread"] { scenario(kind);scenario(kind,error:true) }

func entityControl(isEdit:Bool,emptyCompose:Bool) {
    let controller=Controller()
    let compose=NSAttributedString(string:emptyCompose ? "":"COMPOSE",attributes:[ChatTextInputAttributes.italic:true])
    let edit=NSAttributedString(string:"EDIT",attributes:[ChatTextInputAttributes.bold:true])
    controller.presentationInterfaceState.interfaceState.composeInputState=ChatTextInputState(inputText:compose,selectionRange:0..<0)
    if isEdit { controller.presentationInterfaceState.interfaceState.editMessage=ChatEditMessageState(messageId:MessageId(value:7),inputState:ChatTextInputState(inputText:edit,selectionRange:0..<0)) }
    let translation=makeTranslationContext(selfController:controller,peer:Peer(id:PeerId(namespace:0)))
    translation.translate?()
    check(controller.context.engine.messages.requests.count==1,"entity control starts one request")
    let request=controller.context.engine.messages.requests[0]
    let actualText=isEdit ? edit:compose
    check(request.text==actualText.string,"request text uses effective edit/compose input")
    let correct=generateChatInputTextEntities(actualText)
    let expected=expectedBug && isEdit ? generateChatInputTextEntities(compose):correct
    check(request.entities==expected,"request entities belong to matching input snapshot")
    check((request.entities==correct) == !(expectedBug && isEdit),"before edit mismatch versus snapshot-derived entities")
}
entityControl(isEdit:false,emptyCompose:false)
entityControl(isEdit:true,emptyCompose:false)
entityControl(isEdit:true,emptyCompose:true)

func mutableSnapshotControl(attributesOnly:Bool) {
    let controller=Controller()
    let mutable=NSMutableAttributedString(string:"A")
    controller.presentationInterfaceState.interfaceState.composeInputState=ChatTextInputState(inputText:mutable,selectionRange:1..<1)
    let translation=makeTranslationContext(selfController:controller,peer:Peer(id:PeerId(namespace:0)))
    translation.translate?()
    check(controller.context.engine.messages.requests.count==1,"mutable input request queued")
    if attributesOnly { mutable.addAttribute(ChatTextInputAttributes.bold,value:true,range:NSRange(location:0,length:1)) }
    else { mutable.replaceCharacters(in:NSRange(location:0,length:1),with:"B") }
    let current=NSAttributedString(attributedString:mutable)
    controller.context.engine.messages.deliver("T(A)")
    if expectedBug {
        check(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText.string=="T(A)","old callback overwrites in-place changed input")
    } else {
        check(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText.isEqual(to:current),"immutable snapshot catches in-place text/attribute mutation")
    }
    check(controller.updates==(expectedBug ? 1:0),"changed mutable input must have no stale state update")
}
mutableSnapshotControl(attributesOnly:false)
mutableSnapshotControl(attributesOnly:true)

func nilResultControl() {
    let controller=Controller()
    makeTranslationContext(selfController:controller,peer:Peer(id:PeerId(namespace:0))).translate?()
    check(controller.context.engine.messages.requests.count==1,"nil response request started")
    controller.context.engine.messages.deliver(nil)
    check(controller.updates==0 && controller.overlays==0 && controller.sends==0,"nil translation has no UI/send side effect")
}
nilResultControl()

func eligibilityControl(secret:Bool) {
    let controller=Controller()
    Globals.enabled=secret
    let translation=makeTranslationContext(selfController:controller,peer:Peer(id:PeerId(namespace:secret ? 3:0)))
    translation.translate?()
    check(controller.context.engine.messages.requests.isEmpty,"disabled feature/secret chat never starts request")
    check(controller.updates==0 && controller.sends==0,"eligibility preserves draft and sends nothing")
    Globals.enabled=true
}
eligibilityControl(secret:false)
eligibilityControl(secret:true)

func weakLifetimeControl(error:Bool) {
    var controller:Controller?=Controller()
    let engine=controller!.context.engine.messages
    weak var observedController=controller
    weak var observedContext=controller!.context
    let translation=makeTranslationContext(selfController:controller!,peer:Peer(id:PeerId(namespace:0)))
    translation.translate?()
    check(engine.requests.count==1,"weak lifetime request pending")
    controller=nil
    check(observedController==nil && observedContext==nil,"pending translation must not retain UI/controller context")
    check(engine.requests.count==1,"observe pending callback without flushing")
    if error { engine.fail() } else { engine.deliver("T(A)") }
    check(engine.requests.isEmpty,"late callback after teardown terminates owned request")
}
weakLifetimeControl(error:false)
weakLifetimeControl(error:true)
print("FINAL \(checks) outgoing translation/entity/lifecycle checks")

// V2 controls: Foundation-native collapsed quote payloads and exact source expander.
let expectedQuoteBug=CommandLine.arguments.contains("--expect-quote-bug")
let quoteControlGroup=CommandLine.arguments.first(where: { $0.hasPrefix("--quote-control-group=") })?.components(separatedBy:"=").last ?? "all"
func equivalentEntities(_ lhs:[MessageTextEntity],_ rhs:[MessageTextEntity])->Bool {
    func values(_ input:[MessageTextEntity])->[String] { input.map { "\($0.range.lowerBound):\($0.range.upperBound):\($0.type)" }.sorted() }
    return values(lhs)==values(rhs)
}
func collapsedRequestControl(isEdit:Bool,caretOnly:Bool=false) {
    let controller=Controller()
    let payload=NSMutableAttributedString(string:"Hidden quote",attributes:[ChatTextInputAttributes.bold:true])
    let raw=NSMutableAttributedString(string:"prefix ")
    raw.append(NSAttributedString(string:" ",attributes:[ChatTextInputAttributes.collapsedBlock:payload]))
    raw.append(NSAttributedString(string:" suffix"))
    controller.presentationInterfaceState.interfaceState.composeInputState=ChatTextInputState(inputText:isEdit ? NSAttributedString(string:"COMPOSE",attributes:[ChatTextInputAttributes.italic:true]):raw,selectionRange:0..<0)
    if isEdit { controller.presentationInterfaceState.interfaceState.editMessage=ChatEditMessageState(messageId:MessageId(value:5),inputState:ChatTextInputState(inputText:raw,selectionRange:0..<0)) }
    let expanded=NSAttributedString(attributedString:expandedInputStateAttributedString(raw))
    let expandedEntities=generateChatInputTextEntities(expanded)
    check(expanded.string=="prefix Hidden quote suffix","actual collapsed expander restores hidden text")
    check(expandedEntities.contains { if case .BlockQuote(isCollapsed:true)=$0.type { return $0.range==7..<19 };return false },"actual collapsed expander restores quote entity")
    makeTranslationContext(selfController:controller,peer:Peer(id:PeerId(namespace:0))).translate?()
    check(controller.context.engine.messages.requests.count==1,"collapsed request begins once")
    let request=controller.context.engine.messages.requests[0]
    let expectedText=expectedQuoteBug ? raw.string:expanded.string
    check(request.text==expectedText,"collapsed compose/edit request must include hidden quote text")
    let expectedEntities:[MessageTextEntity]
    if expectedQuoteBug {
        expectedEntities=expectedBug ? (controller.presentationInterfaceState.interfaceState.synchronizeableInputState?.entities ?? []):generateChatInputTextEntities(raw)
    } else { expectedEntities=expandedEntities }
    check(equivalentEntities(request.entities,expectedEntities),"collapsed request entities must use the same expanded snapshot")
    check((request.text==expanded.string && equivalentEntities(request.entities,expandedEntities)) == !expectedQuoteBug,"old/V1 omission versus desired expanded request")
    if !expectedQuoteBug { check(request.entities.allSatisfy { $0.range.lowerBound>=0 && $0.range.upperBound<=request.text.utf16.count },"expanded entity ranges fit expanded request text") }
    if caretOnly {
        let inputState=ChatTextInputState(inputText:raw,selectionRange:raw.length..<raw.length)
        controller.presentationInterfaceState.interfaceState=controller.presentationInterfaceState.interfaceState.withUpdatedEffectiveInputState(inputState)
    }
    controller.context.engine.messages.deliver("translated full draft")
    check(controller.updates==1,"stable/caret-only collapsed draft accepts response")
    check(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText.string=="translated full draft","stable collapsed draft adopts returned text")
    if isEdit { check(controller.presentationInterfaceState.interfaceState.composeInputState.inputText.string=="COMPOSE","edit translation preserves compose backup") }
    check(controller.sends==0,"collapsed translation does not send")
}
if quoteControlGroup=="all" || quoteControlGroup=="request" { for isEdit in [false,true] { collapsedRequestControl(isEdit:isEdit);collapsedRequestControl(isEdit:isEdit,caretOnly:true) } }
func mutableCollapsedPayloadControl(isEdit:Bool,attributesOnly:Bool,error:Bool) {
    let payload=NSMutableAttributedString(string:"Old hidden quote",attributes:[ChatTextInputAttributes.bold:true])
    let raw=NSMutableAttributedString(string:"prefix ")
    raw.append(NSAttributedString(string:" ",attributes:[ChatTextInputAttributes.collapsedBlock:payload]))
    raw.append(NSAttributedString(string:" suffix"))
    let controller=Controller()
    controller.presentationInterfaceState.interfaceState.composeInputState=ChatTextInputState(inputText:isEdit ? NSAttributedString(string:"COMPOSE"):raw,selectionRange:0..<0)
    if isEdit { controller.presentationInterfaceState.interfaceState.editMessage=ChatEditMessageState(messageId:MessageId(value:6),inputState:ChatTextInputState(inputText:raw,selectionRange:0..<0)) }
    let originalExpanded=NSAttributedString(attributedString:expandedInputStateAttributedString(raw))
    makeTranslationContext(selfController:controller,peer:Peer(id:PeerId(namespace:0))).translate?()
    check(controller.context.engine.messages.requests.count==1,"mutable collapsed request pending")
    let request=controller.context.engine.messages.requests[0]
    let capturedRequestText=request.text
    let capturedRequestEntities=request.entities
    if attributesOnly {
        payload.removeAttribute(ChatTextInputAttributes.bold,range:NSRange(location:0,length:payload.length))
        payload.addAttribute(ChatTextInputAttributes.italic,value:true,range:NSRange(location:0,length:payload.length))
    } else { payload.replaceCharacters(in:NSRange(location:0,length:payload.length),with:"New hidden quote") }
    let currentExpanded=NSAttributedString(attributedString:expandedInputStateAttributedString(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText))
    check(!currentExpanded.isEqual(to:originalExpanded),"nested mutable payload changed effective expanded draft")
    check(request.text==capturedRequestText && equivalentEntities(request.entities,capturedRequestEntities),"captured request text/entities remain unchanged after nested payload mutation")
    if error { controller.context.engine.messages.fail() } else { controller.context.engine.messages.deliver("translated old draft") }
    let mayApply=expectedQuoteBug
    if error {
        check(controller.overlays==(mayApply ? 1:0),"nested payload change suppresses stale failure overlay")
        check(controller.updates==0,"failure never replaces nested payload")
        check(expandedInputStateAttributedString(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText).isEqual(to:currentExpanded),"failure preserves nested text and attributes")
    } else {
        check(controller.updates==(mayApply ? 1:0),"nested payload change suppresses stale success")
        if mayApply { check(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText.string=="translated old draft","old/V1 shallow snapshot permits stale replacement") }
        else { check(expandedInputStateAttributedString(controller.presentationInterfaceState.interfaceState.effectiveInputState.inputText).isEqual(to:currentExpanded),"stale response preserves new nested text and formatting") }
    }
    if isEdit { check(controller.presentationInterfaceState.interfaceState.composeInputState.inputText.string=="COMPOSE","nested edit response preserves compose backup") }
    check(controller.sends==0,"nested payload callbacks do not send")
}
for isEdit in [false,true] { for attributesOnly in [false,true] { for error in [false,true] {
    let group="nested-" + (attributesOnly ? "attributes":"text") + (error ? "-error":"-success")
    if quoteControlGroup=="all" || quoteControlGroup==group { mutableCollapsedPayloadControl(isEdit:isEdit,attributesOnly:attributesOnly,error:error) }
} } }
print("FINAL V2 \(checks) outgoing translation/expanded quote/lifecycle checks")
