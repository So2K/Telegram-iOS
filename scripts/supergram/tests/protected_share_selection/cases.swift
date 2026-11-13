
let normal = MessageId(peerId:PeerId(namespace:0),raw:1)
let other = MessageId(peerId:PeerId(namespace:0),raw:2)
let secretMedia = MessageId(peerId:PeerId(namespace:0),raw:3)
let secretChat = MessageId(peerId:PeerId(namespace:3),raw:4)
var checks = 0
func check(_ value:Bool,_ text:String) { checks += 1; guard value else { fputs("FAIL: \(text)\n",stderr);exit(42) } }
func setSelection(_ ids:Set<MessageId>,_ panel:Panel,_ controller:Controller) {
    let state = PresentationState(interfaceState:InterfaceState(selectionState:SelectionState(selectedIds:ids)))
    panel.presentationInterfaceState = state
    panel.selectedMessages = ids
    controller.presentationInterfaceState = state
}
func runCase(initial:Set<MessageId>,later:Set<MessageId>?,expect:[MessageId]?,tip:Bool=false,panelLag:Bool=false,hosted:Bool=true,exited:Bool=false,panelStateNil:Bool=false) {
    let context=Context();let panel=Panel(context:context);let controller=Controller(context:context);let interaction=Interaction()
    panel.interfaceInteraction=interaction;interaction.share=controller.shareAction();interaction.hostController=hosted ? controller:nil
    for id in [normal,other,secretMedia,secretChat] { context.engine.data.messages[id]=EngineMessage(raw:RawMessage(id:id,containsSecretMedia:id==secretMedia)) }
    setSelection(initial,panel,controller)
    if panelStateNil { panel.presentationInterfaceState = nil }
    panel.press()
    check(context.engine.data.requests.count == (initial.isEmpty ? 0:1),"initial request retains snapshot")
    if let later { if panelLag { controller.presentationInterfaceState = PresentationState(interfaceState:InterfaceState(selectionState:SelectionState(selectedIds:later))) } else { setSelection(later,panel,controller) } }
    if exited { controller.presentationInterfaceState.interfaceState.selectionState = nil }
    if !context.engine.data.requests.isEmpty { context.engine.data.deliverFirst() }
    // real deliverOnMainQueue executes inline on the main thread; no UI event is synthesized between the guard and delegation.
    if !context.engine.data.requests.isEmpty { context.engine.data.deliverFirst() }
    check(context.sharedContext.shares == expect.map { [$0] } ?? [], "share must use admitted selection, received \(context.sharedContext.shares.map { $0.map { $0.raw } })")
    check((interaction.tips>0)==tip,"secret admission result")
}
let expectedBug=CommandLine.arguments.contains("--expect-bug")
SGSimpleSettings.shared.sgAllowSaveProtectedContent=true
runCase(initial:[normal],later:nil,expect:[normal])
runCase(initial:[secretMedia],later:nil,expect:nil,tip:true)
runCase(initial:[secretChat],later:nil,expect:nil,tip:true)
runCase(initial:[],later:nil,expect:nil)
runCase(initial:[normal],later:[normal],expect:[normal])
if expectedBug {
    runCase(initial:[normal],later:[other],expect:[other])
    runCase(initial:[normal],later:[secretMedia],expect:[secretMedia])
    print("PASS expected original bug: selected message1 admission exports changed message2 or secret3; \(checks) controls")
} else {
    runCase(initial:[normal],later:[other],expect:nil)
    runCase(initial:[normal],later:[secretMedia],expect:nil)
    runCase(initial:[normal],later:[],expect:nil)
    runCase(initial:[normal,other],later:[normal],expect:nil)
    runCase(initial:[normal,other],later:nil,expect:[normal,other])
    runCase(initial:[normal],later:[other],expect:nil,panelLag:true)
    runCase(initial:[normal],later:[secretMedia],expect:nil,panelLag:true)
    runCase(initial:[normal],later:[],expect:nil,panelLag:true)
    runCase(initial:[normal],later:nil,expect:[normal],panelStateNil:true)
    runCase(initial:[normal],later:nil,expect:nil,exited:true)
    runCase(initial:[normal],later:nil,expect:[normal],hosted:false)
    runCase(initial:[normal],later:[other],expect:nil,hosted:false)
    print("PASS candidate \(checks) exact-source controls")
}

func buttonControl(allow:Bool,disabled:Bool,renderedSecret:Bool,protected:Bool) {
    let context=Context();let panel=Panel(context:context);let controller=Controller(context:context);let interaction=Interaction()
    panel.interfaceInteraction=interaction;interaction.share=controller.shareAction();interaction.hostController=controller
    context.engine.data.messages[normal]=EngineMessage(raw:RawMessage(id:normal,containsSecretMedia:false))
    setSelection([normal],panel,controller)
    panel.shareButton.isImplicitlyDisabled=disabled;panel.actions=ChatAvailableMessageActions(isCopyProtected:protected)
    SGSimpleSettings.shared.sgAllowSaveProtectedContent=allow
    if renderedSecret { panel.presentationInterfaceState?.renderedPeer=RenderedPeer(peer:TelegramSecretChat()) }
    panel.press()
    let shouldShare = !disabled && !renderedSecret && (!protected || allow)
    check(context.engine.data.requests.count==(shouldShare ? 1:0),"actual button eligibility")
    while !context.engine.data.requests.isEmpty { context.engine.data.deliverFirst() }
    check(context.sharedContext.shares == (shouldShare ? [[normal]]:[]),"stock unprotected and protected route")
    check(interaction.tips == (protected && !renderedSecret && (!allow || disabled) ? 1:0),"actual copy-protection tip control")
}
buttonControl(allow:false,disabled:false,renderedSecret:false,protected:true)
buttonControl(allow:true,disabled:true,renderedSecret:false,protected:true)
buttonControl(allow:true,disabled:false,renderedSecret:true,protected:true)
buttonControl(allow:false,disabled:false,renderedSecret:false,protected:false)
buttonControl(allow:true,disabled:false,renderedSecret:false,protected:true)
print("FINAL \(checks) checks")

func metadataControl(_ kind:String,expectedBug:Bool=false) {
    let context=Context();let panel=Panel(context:context);let controller=Controller(context:context);let interaction=Interaction()
    panel.interfaceInteraction=interaction;interaction.share=controller.shareAction();interaction.hostController=controller
    setSelection(kind=="partial" ? [normal,other]:[normal],panel,controller)
    context.engine.data.messages[normal]=EngineMessage(raw:RawMessage(id:normal,containsSecretMedia:false))
    context.engine.data.messages[other]=EngineMessage(raw:RawMessage(id:other,containsSecretMedia:false))
    panel.press();check(context.engine.data.requests.count==1,"metadata read begins")
    let snapshot:[MessageId:EngineMessage?]
    switch kind {
    case "missing": snapshot=[normal:nil]
    case "partial": snapshot=[normal:context.engine.data.messages[normal],other:nil]
    case "wrongId": snapshot=[normal:context.engine.data.messages[other]]
    case "extra": snapshot=[normal:context.engine.data.messages[normal],other:context.engine.data.messages[other]]
    default: fatalError()
    }
    context.engine.data.deliverFirst(snapshot)
    if kind=="missing" { context.engine.data.messages[normal]=EngineMessage(raw:RawMessage(id:normal,containsSecretMedia:true)) }
    while !context.engine.data.requests.isEmpty { context.engine.data.deliverFirst() }
    if expectedBug {
        check(context.sharedContext.shares == [[normal]],"old missing metadata still starts share")
        check(context.sharedContext.sharedSecretFlags == [[true]],"old second lookup passes later secret same-ID to external share")
    } else {
        check(context.sharedContext.shares.isEmpty,"incomplete or inconsistent admission must not start share")
        check(context.sharedContext.sharedSecretFlags.isEmpty,"no secret material enters shared params")
    }
}
if expectedBug { metadataControl("missing",expectedBug:true) } else {
    for kind in ["missing","partial","wrongId","extra"] { metadataControl(kind) }
}
print("FINAL WITH METADATA \(checks) checks")

func lateAdmissionControl(_ kind:String,expectedBug:Bool=false) {
    let a=Context();let b=Context();let panel=Panel(context:a);let ca=Controller(context:a);let cb=Controller(context:b);let interaction=Interaction()
    panel.interfaceInteraction=interaction;interaction.share=ca.shareAction();interaction.hostController=ca
    setSelection([normal],panel,ca);setSelection([normal],panel,cb)
    a.engine.data.messages[normal]=EngineMessage(raw:RawMessage(id:normal,containsSecretMedia:false))
    b.engine.data.messages[normal]=EngineMessage(raw:RawMessage(id:normal,containsSecretMedia:true))
    SGSimpleSettings.shared.sgAllowSaveProtectedContent=true
    panel.press();check(a.engine.data.requests.count==1,"original account lookup queued")
    if kind=="context" { panel.context=b;interaction.share=cb.shareAction();interaction.hostController=cb }
    else if kind=="disabled" { panel.shareButton.isImplicitlyDisabled=true }
    else if kind=="setting" { SGSimpleSettings.shared.sgAllowSaveProtectedContent=false }
    a.engine.data.deliverFirst()
    while !a.engine.data.requests.isEmpty { a.engine.data.deliverFirst() }
    while !b.engine.data.requests.isEmpty { b.engine.data.deliverFirst() }
    if expectedBug {
        check(b.sharedContext.shares == [[normal]],"old context rebound delegates to new account")
        check(b.sharedContext.sharedSecretFlags == [[true]],"new account's secret same-ID is passed to share params")
    } else {
        check(a.sharedContext.shares.isEmpty && b.sharedContext.shares.isEmpty,"late admission invalidation cancels callback")
        check(a.sharedContext.sharedSecretFlags.isEmpty && b.sharedContext.sharedSecretFlags.isEmpty,"no late account material enters external share")
    }
    SGSimpleSettings.shared.sgAllowSaveProtectedContent=true
}
if expectedBug { lateAdmissionControl("context",expectedBug:true) } else {
    for kind in ["context","disabled","setting"] { lateAdmissionControl(kind) }
}
print("FINAL ALL \(checks) checks")

func peerInfoControl(changed:Bool,expectedBug:Bool=false) {
    let context=Context();let panel=Panel(context:context);let peer=PeerInfo(context:context)
    let interaction=peerInfoInteraction(shareMessages:peer.shareAction());panel.interfaceInteraction=interaction
    // Actual PeerInfo wiring has nil chatController() and synchronously updates its selectedMessages field.
    panel.presentationInterfaceState=nil;panel.selectedMessages=[normal];peer.state.selectedMessageIds=[normal]
    context.engine.data.messages[normal]=EngineMessage(raw:RawMessage(id:normal,containsSecretMedia:false))
    context.engine.data.messages[other]=EngineMessage(raw:RawMessage(id:other,containsSecretMedia:false))
    SGSimpleSettings.shared.sgAllowSaveProtectedContent=true
    panel.press();check(context.engine.data.requests.count==1,"supported PeerInfo first read")
    if changed { peer.state.selectedMessageIds=[other];panel.selectedMessages=[other] }
    while !context.engine.data.requests.isEmpty { context.engine.data.deliverFirst() }
    let result:[[MessageId]]=changed ? (expectedBug ? [[other]]:[]):[[normal]]
    check(context.sharedContext.shares==result,"supported PeerInfo stable/fallback race admission")
    check(interaction.chatController()==nil,"PeerInfo host stays nil")
}
peerInfoControl(changed:false)
peerInfoControl(changed:true,expectedBug:expectedBug)
print("FINAL INCLUDING REAL PEERINFO \(checks) checks")


// Keep only the engine's pending subscriber registry alive. Do not flush a response
// during ARC observation: queued Postbox work may outlive a closed panel.
func pendingContextLifetimeControl(rebound: Bool) {
    var context: Context? = Context()
    let engine = context!.engine
    weak var observedContext = context
    var panel: Panel? = Panel(context:context!)
    weak var observedPanel = panel
    let interaction = Interaction()
    panel!.interfaceInteraction = interaction
    panel!.selectedMessages = [normal]
    panel!.presentationInterfaceState = PresentationState(interfaceState:InterfaceState(selectionState:SelectionState(selectedIds:[normal])))
    SGSimpleSettings.shared.sgAllowSaveProtectedContent = true
    panel!.press()
    check(engine.data.requests.count == 1, "context lifetime retains pending request")
    if rebound {
        panel!.context = Context()
    } else {
        panel = nil
    }
    context = nil
    check((observedPanel != nil) == rebound, "panel lifetime is independent of pending callback")
    check(engine.data.requests.count == 1, "context lifetime observation must not flush pending work")
    let expectedRetention = CommandLine.arguments.contains("--expect-context-retention")
    check((observedContext != nil) == expectedRetention, "pending lookup must not retain departed AccountContext")
    // Remove only the owned pending registry after the observation, with no delivery.
    engine.data.requests.removeAll()
    check(observedContext == nil, "pending registry cleanup releases context")
    panel = nil
    check(observedPanel == nil, "rebound panel teardown releases panel")
}
pendingContextLifetimeControl(rebound:false)
pendingContextLifetimeControl(rebound:true)
print("FINAL INCLUDING PENDING CONTEXT LIFETIME \(checks) checks")
