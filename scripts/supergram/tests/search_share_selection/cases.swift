let a=MessageId(peerId:PeerId(namespace:0),raw:1)
let b=MessageId(peerId:PeerId(namespace:0),raw:2)
let secret=MessageId(peerId:PeerId(namespace:0),raw:3)
var checks=0
func check(_ value:Bool,_ text:String) { checks += 1; if !value { fputs("FAIL: \(text)\n",stderr);exit(42) } }
let expectedBug=CommandLine.arguments.contains("--expect-bug")
func scenario(_ change:String) {
    let context=Context();let container=SearchContainer(context:context);let panel=Panel(context:context,getSelectedMessageIds:container.selectedIdsAction())
    container.selectionPanelNode=panel;panel.shareMessages=container.shareAction()
    context.engine.data.messages[a]=EngineMessage(raw:RawMessage(id:a,secret:false))
    context.engine.data.messages[b]=EngineMessage(raw:RawMessage(id:b,secret:false))
    context.engine.data.messages[secret]=EngineMessage(raw:RawMessage(id:secret,secret:true))
    SuperGramContentProtection.allowSaveProtectedContent=true
    container.select([a]);panel.press()
    check(context.engine.data.requests.count==1,"first lookup snapshots A")
    var map:[MessageId:EngineMessage?]?=nil
    if change=="selection" { container.select([b]) }
    if change=="secret" { container.select([secret]);panel.shareButton.isImplicitlyDisabled=true }
    if change=="empty" { container.select([]);panel.shareButton.isImplicitlyDisabled=true }
    if change=="allow" { SuperGramContentProtection.allowSaveProtectedContent=false }
    if change=="disabled" { panel.shareButton.isImplicitlyDisabled=true }
    if change=="missing" { map=[a:nil] }
    if change=="partial" { map=[:] }
    if change=="wrongId" { map=[a:context.engine.data.messages[b]] }
    if change=="extra" { map=[a:context.engine.data.messages[a],b:context.engine.data.messages[b]] }
    context.engine.data.deliverFirst(map)
    while !context.engine.data.requests.isEmpty { context.engine.data.deliverFirst() }
    let expected:[[MessageId]]
    if change=="stable" { expected=[[a]] }
    else if expectedBug && change=="selection" { expected=[[b]] }
    else if expectedBug && change=="secret" { expected=[[secret]] }
    else if expectedBug && change != "empty" { expected=[[a]] }
    else { expected=[] }
    check(context.sharedContext.shares==expected,"selected-ID admission must be stable, received \(context.sharedContext.shares.map{$0.map{$0.raw}})")
    check(panel.selectedMessages == (container.stateValue.selectedMessageIds ?? []),"actual state update keeps panel current")
    SuperGramContentProtection.allowSaveProtectedContent=true
}
scenario("stable")
scenario("selection")
scenario("secret")
for kind in ["empty","allow","disabled","missing","partial","wrongId","extra"] { scenario(kind) }


func makeFixture()->(Context,SearchContainer,Panel) {
    let context=Context();let container=SearchContainer(context:context)
    let panel=Panel(context:context,getSelectedMessageIds:container.selectedIdsAction())
    container.selectionPanelNode=panel;panel.shareMessages=container.shareAction()
    for id in [a,b,secret] { context.engine.data.messages[id]=EngineMessage(raw:RawMessage(id:id,secret:id==secret)) }
    SuperGramContentProtection.allowSaveProtectedContent=true
    return (context,container,panel)
}
func drain(_ context:Context) { while !context.engine.data.requests.isEmpty { context.engine.data.deliverFirst() } }
for kind in ["multiStable","multiSecret","multiPartial","wrongNamespace"] {
    let (context,container,panel)=makeFixture()
    let ids:Set<MessageId> = kind=="multiSecret" ? [a,secret] : kind=="wrongNamespace" ? [a] : [a,b]
    container.select(ids);panel.press()
    check(context.engine.data.requests.count==1,"multi-ID helper has one lookup")
    var map:[MessageId:EngineMessage?]?=nil
    if kind=="multiPartial" { map=[a:context.engine.data.messages[a],b:nil] }
    if kind=="wrongNamespace" {
        let wrong=MessageId(peerId:a.peerId,namespace:1,raw:a.raw)
        map=[a:EngineMessage(raw:RawMessage(id:wrong,secret:false))]
    }
    context.engine.data.deliverFirst(map);drain(context)
    let allowed=kind=="multiStable" || expectedBug && (kind=="multiPartial" || kind=="wrongNamespace")
    check(context.sharedContext.shares.count==(allowed ? 1 : 0),"multi-ID metadata admission")
    if allowed { check(Set(context.sharedContext.shares[0])==ids,"share retains full original ID set") }
    check(panel.tips==(kind=="multiSecret" ? 1 : 0),"known secret metadata keeps privacy tip")
}
for kind in ["initialMismatch","initialParentNil"] {
    let (context,container,panel)=makeFixture()
    container.select(kind=="initialMismatch" ? [b] : nil)
    panel.selectedMessages=[a] // Controlled stale panel; not a claimed normal UI lag.
    panel.press()
    check(context.engine.data.requests.count==(expectedBug ? 1 : 0),"authoritative getter blocks stale panel before lookup")
    drain(context)
    check(context.sharedContext.shares==(expectedBug && kind=="initialMismatch" ? [[b]] : []),"authoritative admission preserves current parent selection")
}
for kind in ["stable","empty"] {
    let (context,container,panel)=makeFixture()
    container.select(kind=="stable" ? [a] : [])
    panel.actions=ChatAvailableMessageActions(isCopyProtected:false,options:[])
    panel.press();drain(context)
    check(context.sharedContext.shares==(kind=="stable" ? [[a]] : []),"ordinary nonprotected Share route unchanged")
    check(panel.tips==0,"ordinary Share never gains protection tip")
}
for kind in ["settingOff","buttonOff","noExternalOption"] {
    let (context,container,panel)=makeFixture();container.select([a])
    if kind=="settingOff" { SuperGramContentProtection.allowSaveProtectedContent=false }
    if kind=="buttonOff" { panel.shareButton.isImplicitlyDisabled=true }
    if kind=="noExternalOption" { panel.actions=ChatAvailableMessageActions(isCopyProtected:true,options:[]) }
    panel.press()
    check(context.engine.data.requests.isEmpty,"initial protected gate does not query when disabled")
    check(context.sharedContext.shares.isEmpty,"disabled protected action never delegates")
    check(panel.tips==1,"initial disabled protected gate keeps existing tip")
    SuperGramContentProtection.allowSaveProtectedContent=true
}
for id in [secret,MessageId(peerId:PeerId(namespace:3),raw:1),MessageId(peerId:a.peerId,raw:4)] {
    let (context,container,panel)=makeFixture();container.select([id])
    context.engine.data.messages[id]=EngineMessage(raw:RawMessage(id:id,secret:id==secret,timeout:id.raw==4 ? viewOnceTimeout : nil))
    panel.press();drain(context)
    check(context.sharedContext.shares.isEmpty,"secret/view-once model metadata never delegates")
    check(panel.tips==1,"secret metadata keeps protection tip")
}
do {
    let (context,container,panel)=makeFixture();container.select([a])
    context.engine.data.immediate=true;panel.press()
    check(context.engine.data.requests.isEmpty,"synchronous completion leaves no pending requests")
    check(context.engine.data.issuedRequests.count==2,"inline helper and unchanged Share lookup each run once")
    check(context.sharedContext.shares==[[a]],"synchronous valid result preserves legitimate Share")
    check(panel.tips==0,"inline valid result has no false privacy tip")
}
do {
    let context=Context();var container:SearchContainer?=SearchContainer(context:context)
    let panel=Panel(context:context,getSelectedMessageIds:container!.selectedIdsAction())
    container!.selectionPanelNode=panel;panel.shareMessages=container!.shareAction()
    context.engine.data.messages[a]=EngineMessage(raw:RawMessage(id:a,secret:false))
    container!.select([a]);panel.press();weak var weakContainer=container;container=nil
    check(weakContainer==nil,"weak getter and delegate do not retain departed parent")
    check(context.engine.data.requests.count==1,"parent teardown test retains pending metadata")
    context.engine.data.deliverFirst();drain(context)
    check(context.sharedContext.shares.isEmpty,"departed parent cannot be shared through cached panel")
}
do {
    let (context,container,initialPanel)=makeFixture();var panel:Panel?=initialPanel
    container.select([a]);panel!.press();weak var weakPanel=panel
    container.selectionPanelNode=nil;panel=nil
    // initialPanel intentionally holds the panel until the surrounding scope ends;
    // use the next no-flush scope for an actual complete panel teardown.
    check(weakPanel != nil,"controlled remaining owner keeps panel alive")
    container.select(nil);context.engine.data.deliverFirst();drain(context)
    check(context.sharedContext.shares.isEmpty,"cleared parent prevents departed-panel result")
}
do {
    var context:Context?=Context();let engine=context!.engine
    var container:SearchContainer?=SearchContainer(context:context!)
    var panel:Panel?=Panel(context:context!,getSelectedMessageIds:container!.selectedIdsAction())
    container!.selectionPanelNode=panel;panel!.shareMessages=container!.shareAction()
    engine.data.messages[a]=EngineMessage(raw:RawMessage(id:a,secret:false))
    container!.select([a]);panel!.press()
    weak var weakContext=context;weak var weakContainer=container;weak var weakPanel=panel
    panel=nil;container=nil;context=nil
    check(engine.data.requests.count==1,"no-flush lifetime fixture keeps engine lookup pending")
    check(weakPanel==nil,"pending callback never owns departed panel")
    check(weakContainer==nil,"pending callback never owns departed Search parent")
    check(weakContext==nil,"pending callback must not retain departed AccountContext")
    engine.data.deliverFirst()
    check(engine.data.requests.isEmpty,"late result after complete teardown starts no second lookup")
}
print("PASS \(checks) exact search source controls")
