var checks = 0
func check(_ ok: @autoclosure () -> Bool, _ name: String) { checks += 1; if !ok() { print("FAIL: \(name)"); exit(42) } }
let selfPeer = PeerId(100)
func entry(_ local: Int32 = 1, _ merged: Int32 = 10) -> PeerMergedOperationLogEntry { PeerMergedOperationLogEntry(peerId: PeerId(0), tagLocalIndex: local, mergedIndex: merged, contents: SynchronizePinnedChatsOperation()) }
func setup(_ pins: [Int64] = [99]) -> (Postbox, Network, PeerMergedOperationLogEntry) {
    let p = Postbox(); let n = Network(); let e = entry()
    p.tx.pins = pins
    p.tx.log[e.tagLocalIndex] = OperationEntry(mergedIndex: e.mergedIndex, contents: e.contents, peerId: e.peerId, localIndex: e.tagLocalIndex)
    return (p, n, e)
}
func payload(_ ids: [Int64], includeMessages: Bool = true, includePeers: Bool = true) -> Api.messages.SavedDialogs {
    .savedDialogs(Api.SavedDialogsData(dialogs: ids.enumerated().map { .savedDialog(Api.SavedDialogData(flags: 1 << 2, peer: Api.Peer(peerId: PeerId($0.element)), topMessage: Int32($0.offset + 1))) }, messages: includeMessages ? ids.enumerated().map { ApiMessage(id: MessageId(peerId: selfPeer, namespace: 0, id: Int32($0.offset + 1)), threadId: $0.element) } : [], chats: [], users: includePeers ? ids.map { Peer(id: PeerId($0)) } : []))
}
let mode = CommandLine.arguments.dropFirst().first ?? "all"

if mode == "all" || mode == "cancel" {
    do {
        let (p,n,e) = setup(); p.holdNextTransaction = true
        let a = savedSetter(account:Account(peerId:selfPeer,postbox:p,network:n),id:selfPeer,threadIds:[5]).start()
        check(p.queued.count == 1 && p.tx.pins == [99] && n.setters == 0, "setter first transaction queued before cancellation")
        a.dispose(); n.replies = [.data(payload([7]))]
        let d = runSync(p,n,e).start(); check(p.tx.pins == [7], "canceled setter releases marker for reconciliation")
        p.drain()
        check(p.tx.pins == [7] && n.setters == 0, "canceled optimistic transaction cannot overwrite settled pin state without RPC")
        check(p.tx.pinWrites == 1, "only accepted remote transaction wrote pins")
        d.dispose()
    }
    do {
        let (p,n,_) = setup(); p.holdNextTransaction = true
        let a = savedSetter(account:Account(peerId:selfPeer,postbox:p,network:n),id:selfPeer,threadIds:[5]).start(); a.dispose(); p.drain()
        check(p.tx.pins == [99] && p.tx.pinWrites == 0 && n.setters == 0, "canceled setter queued before first write mutates nothing")
    }
    do {
        let p = Postbox(); let n = Network(); let account = Account(peerId:selfPeer,postbox:p,network:n)
        var scope: SavedPinnedThreadsSynchronizationState.Scope?
        let d = SavedPinnedThreadsSynchronizationState.withSynchronization(postbox:p,accountPeerId:selfPeer,{ current -> Signal<Void,NoError> in scope=current; return .never() }).start()
        d.dispose(); var completed = 0
        let rpc = capturedSetterNext(inputPeers:[],scope:scope!,account:account).start(completed:{completed+=1})
        check(n.setters == 0 && completed == 1, "already captured setter next checks inactive scope before starting RPC")
        rpc.dispose()
    }
    do {
        let p = Postbox(); var inactiveBeforeChild = false
        let d = SavedPinnedThreadsSynchronizationState.withSynchronization(postbox:p,accountPeerId:selfPeer,{ scope -> Signal<Void,NoError> in
            Signal { _ in ActionDisposable { inactiveBeforeChild = !scope.isActive } }
        }).start()
        d.dispose(); check(inactiveBeforeChild, "synchronization revokes scope before child disposal callout")
    }
    do {
        let p = Postbox(); var idleBeforeChild = false; var scope: SavedPinnedThreadsSynchronizationState.Scope?
        let reader = SavedPinnedThreadsSynchronizationState.withSynchronization(postbox:p,accountPeerId:selfPeer,{ current -> Signal<Void,NoError> in scope=current; return .never() }).start()
        let mutation = dispositionProbeMutation(postbox:p, { let wait = scope!.waitForIdle().start(next:{_ in idleBeforeChild=true}); wait.dispose() }).start()
        mutation.dispose(); check(idleBeforeChild, "mutation revokes/releases scope before child disposal callout")
        reader.dispose()
    }
}
if mode == "all" || mode == "success" {
    do {
        let (p,n,e) = setup(); let ids: [Int64] = [100,2666000,0x000000020000014d]
        n.replies = [.data(payload(ids))]; let d = runSync(p,n,e).start()
        check(p.tx.pins == ids, "self/MyNotes, anonymous-author and channel source identifiers retain exact order")
        check(ids.allSatisfy { p.tx.isRenderable($0) }, "all three valid saved source topologies bootstrap")
        d.dispose()
    }
    do {
        let (p,n,e) = setup(); p.tx.messages[MessageId(peerId:selfPeer,namespace:0,id:1)] = Message(threadId:nil)
        n.replies = [.data(payload([3]))]; let d = runSync(p,n,e).start()
        check(p.tx.pins == [3] && p.tx.messages[MessageId(peerId:selfPeer,namespace:0,id:1)]?.threadId == 3, "proper RPC top repairs older cached missing saved thread field")
        check(p.tx.isRenderable(3), "old cache bootstrap gains actual thread top")
        d.dispose()
    }
    do {
        let (p,n,e) = setup(); n.replies = [.data(payload([3,2,1]))]
        var finished = 0
        let d = runSync(p,n,e).start(completed: { finished += 1 })
        check(p.tx.pins == [3,2,1], "complete remote order applied")
        check(p.tx.removed == [1], "exact reconciliation retired")
        check(p.tx.log.isEmpty, "settled log removed")
        check(n.fetches == 1 && finished == 1, "successful fetch completes once")
        check(p.tx.isRenderable(3) && p.tx.isRenderable(2) && p.tx.isRenderable(1), "unknown pinned rows bootstrap with top and info")
        check(p.tx.combinedState == "unchanged-full-list-boundary", "pin-only fetch does not claim entire Saved list loaded")
        check(p.tx.messageWrites == 1 && p.tx.peerWrites == 1 && p.tx.pinWrites == 1, "single atomic admitted update")
        d.dispose()
    }
    do {
        let (p,n,e) = setup(); p.tx.messages[MessageId(peerId: selfPeer,namespace: 0,id: 50)] = Message(threadId: 99)
        n.replies = [.data(payload([]))]; var finished = false
        let d = runSync(p,n,e).start(completed: { finished = true })
        check(p.tx.pins.isEmpty && finished, "complete empty remote pins clear pins")
        check(p.tx.messages.count == 1, "clearing pins preserves messages")
        check(p.tx.removed == [1], "empty success retires owned entry")
        d.dispose()
    }
    do {
        let (p,n,e) = setup(); p.tx.infos[3] = StoredMessageHistoryThreadInfo(value: 9)
        p.tx.messages[MessageId(peerId:selfPeer,namespace:0,id:1)] = Message(threadId: 3)
        p.tx.peers[PeerId(3)] = Peer(id: PeerId(3)); n.replies = [.data(payload([3],includeMessages:false,includePeers:false))]
        let d = runSync(p,n,e).start()
        check(p.tx.pins == [3], "existing valid top/peer can be admitted")
        check(p.tx.infos[3]?.value == 9, "existing thread info preserved")
        d.dispose()
    }
}
if mode == "all" || mode == "error" || mode == "network" {
    if mode != "network" {
    do {
        let (p,n,e) = setup(); p.tx.messages[MessageId(peerId:selfPeer,namespace:0,id:1)] = Message(threadId:3)
        p.tx.infos[3] = StoredMessageHistoryThreadInfo(value:9)
        if case let .savedDialogs(data) = payload([3]) {
            n.replies = Array(repeating: .data(.savedDialogs(Api.SavedDialogsData(dialogs:data.dialogs,messages:[ApiMessage(id:data.messages[0].id,threadId:4)],chats:[],users:data.users))),count:3)
        }
        let d = runSync(p,n,e).start()
        check(n.fetches == 3 && p.tx.pins == [99] && p.tx.pinWrites == 0, "conflicting returned top cannot borrow matching cached topology")
        check(p.tx.messages[MessageId(peerId:selfPeer,namespace:0,id:1)]?.threadId == 3 && p.tx.infos[3]?.value == 9, "conflicting returned top leaves cached valid row intact")
        check(p.tx.messageWrites == 0 && p.tx.peerWrites == 0 && p.tx.removed == [1], "cached-conflict failure preserves contents and retires exact log")
        d.dispose()
    }
    var invalid: [Api.messages.SavedDialogs] = [.savedDialogsNotModified]
    if case let .savedDialogs(data) = payload([3]) { invalid.append(.savedDialogsSlice(data)) }
    invalid.append(payload([3,3]))
    invalid.append(payload([3], includeMessages: false))
    invalid.append(payload([3], includePeers: false))
    invalid.append(.savedDialogs(Api.SavedDialogsData(dialogs: [.monoForumDialog], messages: [], chats: [], users: [])))
    if case let .savedDialogs(data) = payload([3]) {
        invalid.append(.savedDialogs(Api.SavedDialogsData(dialogs: data.dialogs, messages: data.messages + [ApiMessage(id: data.messages[0].id, threadId: 4)], chats: [], users: data.users)))
        invalid.append(.savedDialogs(Api.SavedDialogsData(dialogs: data.dialogs, messages: data.messages + data.messages, chats: [], users: data.users)))
        invalid.append(.savedDialogs(Api.SavedDialogsData(dialogs: data.dialogs, messages: [ApiMessage(id: data.messages[0].id, threadId: 4)], chats: [], users: data.users)))
        invalid.append(.savedDialogs(Api.SavedDialogsData(dialogs: data.dialogs, messages: [ApiMessage(id: MessageId(peerId: selfPeer,namespace:1,id:1), threadId: 3)], chats: [], users: data.users)))
        invalid.append(.savedDialogs(Api.SavedDialogsData(dialogs: data.dialogs, messages: [ApiMessage(id: MessageId(peerId: PeerId(101),namespace:0,id:1), threadId: 3)], chats: [], users: data.users)))
        invalid.append(.savedDialogs(Api.SavedDialogsData(dialogs: [.savedDialog(Api.SavedDialogData(flags:4,peer:Api.Peer(peerId:PeerId(3)),topMessage:0))],messages:data.messages,chats:[],users:data.users)))
    }
    for response in invalid {
        let (p,n,e) = setup(); n.replies = Array(repeating: .data(response), count: 4)
        var finished = 0; let d = runSync(p,n,e).start(completed: { finished += 1 })
        check(n.fetches == 3, "invalid admission bounded to three requests")
        check(finished == 1, "invalid admission finitely completes")
        check(p.tx.pins == [99] && p.tx.pinWrites == 0, "invalid admission preserves pins")
        check(p.tx.messageWrites == 0 && p.tx.peerWrites == 0 && p.tx.infos.isEmpty, "invalid admission writes no peer/message/thread metadata")
        check(p.tx.removed == [1], "invalid admission retires only owned reconciliation")
        d.dispose()
    }
    }
    do {
        let (p,n,e) = setup(); n.replies = [.error,.error,.error,.data(payload([3]))]
        var finished = 0; let d = runSync(p,n,e).start(completed: { finished += 1 })
        check(n.fetches == 3 && finished == 1, "network failures three total attempts then completion")
        check(p.tx.pins == [99] && p.tx.messageWrites == 0 && p.tx.peerWrites == 0, "network failure preserves local contents")
        check(p.tx.removed == [1] && n.replies.count == 1, "no hot retry or guaranteed later recovery claimed")
        d.dispose()
    }
    do {
        let (p,n,e) = setup(); n.replies = [.error,.data(payload([3]))]
        let d = runSync(p,n,e).start()
        check(n.fetches == 2 && p.tx.pins == [3], "retry can admit subsequent full response")
        d.dispose()
    }
}
if mode == "all" || mode == "race" {
    for cancelAtLastIdle in [false,true] {
        let (p,n,e) = setup(); n.replies = [.deferred,.deferred,.deferred,.data(payload([7]))]
        let d = runSync(p,n,e).start()
        for index in 1...3 {
            let a = savedSetter(account:Account(peerId:selfPeer,postbox:p,network:n),id:selfPeer,threadIds:[Int64(index+3)]).start()
            n.emit(payload([3]))
            check(p.tx.pins == [Int64(index+3)] && p.tx.pinWrites == index, "stale response preserves latest optimistic pin")
            check(p.tx.removed.isEmpty && n.fetches == index, "conflict waits real idle event and retains exact log")
            if index == 3 && cancelAtLastIdle { d.dispose() }
            n.finishSetter(); a.dispose()
        }
        check(n.fetches == 3 && n.replies.count == 1, "three total RPC budget includes stale responses")
        check(p.tx.messages.isEmpty && p.tx.infos.isEmpty && p.tx.peerWrites == 0, "all discarded stale responses import nothing")
        if cancelAtLastIdle { check(p.tx.removed.isEmpty && p.tx.log[1] != nil, "canceled last idle waiter cannot retire") }
        else { check(p.tx.removed == [1] && p.tx.log.isEmpty, "third stale waits idle then retires exact reconciliation") }
        d.dispose()
    }
    do {
        let (p,n,e) = setup(); let account = Account(peerId:selfPeer,postbox:p,network:n)
        let cold = savedSetter(account:account,id:selfPeer,threadIds:[4])
        check(n.setters == 0 && p.tx.pins == [99], "creating signal does not register or mutate")
        let a = cold.start(); check(n.setters == 1 && p.tx.pins == [4], "subscription starts optimistic setter")
        n.replies = [.data(payload([4]))]; var finished = false
        let d = runSync(p,n,e).start(completed: { finished = true })
        check(n.fetches == 0 && !finished && p.tx.removed.isEmpty, "sync starting after optimistic write waits pending RPC")
        n.finishSetter()
        check(n.fetches == 1 && finished && p.tx.pins == [4], "idle event wakes reconciliation once")
        a.dispose(); d.dispose()
    }
    do {
        let (p,n,e) = setup(); let account = Account(peerId:selfPeer,postbox:p,network:n)
        let a = savedSetter(account:account,id:selfPeer,threadIds:[4]).start()
        let b = savedSetter(account:account,id:selfPeer,threadIds:[5]).start()
        n.replies = [.data(payload([5]))]; let d = runSync(p,n,e).start()
        n.finishSetter(); check(n.fetches == 0 && p.tx.removed.isEmpty, "first overlapping mutation end does not wake")
        n.finishSetter(); check(n.fetches == 1 && p.tx.pins == [5], "last mutation end wakes exactly once")
        a.dispose(); b.dispose(); d.dispose()
    }
    for failure in [false,true] {
        let (p,n,e) = setup(); let account = Account(peerId:selfPeer,postbox:p,network:n)
        let a = savedSetter(account:account,id:selfPeer,threadIds:[4]).start()
        n.replies = [.data(payload([4]))]; let d = runSync(p,n,e).start()
        if failure { n.finishSetter(error:true) } else { a.dispose() }
        check(n.fetches == 1 && p.tx.pins == [4], "setter error/disposal releases pending token")
        a.dispose(); d.dispose()
    }
    do {
        let (p,n,e) = setup(); n.replies = [.deferred,.data(payload([5]))]
        let d = runSync(p,n,e).start(); check(n.fetches == 1, "initial request starts")
        let a = savedSetter(account:Account(peerId:selfPeer,postbox:p,network:n),id:selfPeer,threadIds:[5]).start()
        n.emit(payload([3])); check(n.fetches == 1 && p.tx.pins == [5] && p.tx.removed.isEmpty, "mutation during fetch prevents stale remote write")
        n.finishSetter(); check(n.fetches == 2 && p.tx.pins == [5], "epoch conflict retries once on idle event")
        a.dispose(); d.dispose()
    }
    do {
        let (p,n,e) = setup(); n.replies = [.deferred,.data(payload([5]))]
        let d = runSync(p,n,e).start()
        let a = savedSetter(account:Account(peerId:selfPeer,postbox:p,network:n),id:selfPeer,threadIds:[5]).start(); n.finishSetter()
        n.emit(payload([3])); check(n.fetches == 2 && p.tx.pins == [5], "completed mutation ABA still invalidates old generation")
        a.dispose(); d.dispose()
    }
    do {
        let (p,n,e) = setup(); n.replies = [.deferred,.data(payload([5]))]
        let d = runSync(p,n,e).start(); p.tx.pins = [5]
        n.emit(payload([3])); check(n.fetches == 2 && p.tx.pins == [5], "final transaction rereads non-registry local pin edits")
        d.dispose()
    }
    do {
        let (p,n,e) = setup(); let a = savedSetter(account:Account(peerId:selfPeer,postbox:p,network:n),id:selfPeer,threadIds:[5]).start()
        let d = runSync(p,n,e).start(); d.dispose(); n.finishSetter()
        check(n.fetches == 0 && p.tx.removed.isEmpty, "canceling waiter never fetches or retires")
        a.dispose()
    }
    for replacement in [false,true] {
        let (p,n,e) = setup(); n.replies = [.deferred]; let d = runSync(p,n,e).start()
        p.holdNextTransaction = true; n.emit(payload([3])); check(p.queued.count == 1, "final transaction queued")
        if replacement { p.tx.log[1]?.mergedIndex = 11 } else { d.dispose() }
        p.drain()
        check(p.tx.pins == [99] && p.tx.messageWrites == 0 && p.tx.peerWrites == 0, "late canceled/replaced transaction writes nothing")
        check(p.tx.removed.isEmpty && p.tx.log[1] != nil, "late transaction preserves replacement log")
        d.dispose()
    }
    do {
        let (p,n,e) = setup(); n.replies = [.deferred]; let a = runSync(p,n,e).start()
        let n2 = Network(); n2.replies = [.deferred]; let b = runSync(p,n2,e).start()
        p.holdNextTransaction = true; n.emit(payload([3])); a.dispose(); p.drain()
        check(p.tx.pins == [99] && p.tx.removed.isEmpty, "canceled A lease invalid while B keeps registry state alive")
        n2.emit(payload([5])); check(p.tx.pins == [5], "live B retains independent lease")
        b.dispose()
    }
    do {
        let (p,n,e) = setup(); p.tx.log[1] = nil; p.tx.log[2] = OperationEntry(mergedIndex:11,contents:SynchronizePinnedChatsOperation(),peerId:PeerId(0),localIndex:2)
        let d = runSync(p,n,e).start()
        check(n.fetches == 0 && p.tx.log[2] != nil && p.tx.removed.isEmpty, "superseded local-index op cannot start or retire new op")
        d.dispose()
    }
    do {
        let (p,n,e) = setup(); n.replies = [.deferred]; let d = runSync(p,n,e).start()
        p.tx.log[1] = nil; p.tx.log[2] = OperationEntry(mergedIndex:11,contents:SynchronizePinnedChatsOperation(),peerId:PeerId(0),localIndex:2)
        n.emit(payload([3])); check(p.tx.pins == [99] && p.tx.log[2] != nil && p.tx.removed.isEmpty, "new local op during fetch survives old completion")
        d.dispose()
    }
}
if mode == "all" || mode == "manager" {
    let (p,n,e) = setup(); n.replies = [.deferred]
    let registered = DispatchSemaphore(value: 0); n.onRegistration = { registered.signal() }
    let d = managedSynchronizePinnedChatsOperations(postbox:p,network:n,accountPeerId:selfPeer,stateManager:AccountStateManager(),tag:OperationLogTags.SynchronizePinnedSavedChats).start()
    p.view.set(.single(MergedView(entries:[e])))
    check(registered.wait(timeout: .now() + 5) == .success, "manager request registration handoff completes")
    check(n.fetches == 1, "actual managed delayed Saved entry starts")
    p.tx.log[1]?.mergedIndex = 11
    n.emit(payload([3]))
    check(p.tx.pins == [99] && p.tx.removed.isEmpty, "actual common manager then does not remove superseding Saved entry")
    d.dispose()
}
if mode == "all" {
    check(!hasActualThreadIndex(topIndex: nil, info: StoredMessageHistoryThreadInfo(value: 1)), "actual index admission rejects info-only bootstrap")
    check(!hasActualThreadIndex(topIndex: MessageIndex(id: MessageId(peerId: selfPeer,namespace:0,id:1)), info: nil), "actual index admission requires info with top")
    check(hasActualThreadIndex(topIndex: MessageIndex(id: MessageId(peerId:selfPeer,namespace:0,id:1)), info: StoredMessageHistoryThreadInfo(value:1)), "actual index admission accepts top and info together")
}
print("PASS \(checks) source-executing saved-pin checks (real SwiftSignalKit; synthetic Postbox/API/network)")
