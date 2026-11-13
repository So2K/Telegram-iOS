#!/usr/bin/env python3
"""Exercise actual Saved pin sources with real SwiftSignalKit.

Postbox, API decoding and network interfaces are synthetic. This verifies
controlled ordering and cancellation, not disk storage, real RPC or iOS.
Use --source-root for a saved before/candidate tree; production is the default.
Compilation stays in temporary scratch. Optional evidence stays in explicitly
selected --artifacts-dir and --output paths, never beside this script.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
FIXTURES = HERE / "saved_pinned_chats"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-root", type=Path, default=REPO)
parser.add_argument("--case", choices=["all", "success", "error", "race", "manager", "network", "cancel"], default="all")
parser.add_argument("--expect-failure", action="store_true")
parser.add_argument("--output", type=Path)
parser.add_argument("--artifacts-dir", type=Path)
args = parser.parse_args()


def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        if text[end] == "{":
            depth += 1
        elif text[end] == "}":
            depth -= 1
        end += 1
    return text[start:end]


def save_artifact(name, content):
    if args.artifacts_dir is not None:
        args.artifacts_dir.mkdir(parents=True, exist_ok=True)
        (args.artifacts_dir / name).write_text(content)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


sync_path = args.source_root / "submodules/TelegramCore/Sources/State/ManagedSynchronizePinnedChatsOperations.swift"
setter_path = args.source_root / "submodules/TelegramCore/Sources/ForumChannels.swift"
sync = sync_path.read_text()
setter = setter_path.read_text()
fixed = "private enum SavedPinnedChatsAttemptStart" in sync
prefix = sync[:sync.index("private func synchronizePinnedChats(")]
prefix = "\n".join(line for line in prefix.splitlines() if not line.startswith("import "))
ordinary = """private func synchronizePinnedChats(transaction: Transaction, postbox: Postbox, network: Network, accountPeerId: PeerId, stateManager: AccountStateManager, groupId: PeerGroupId, operation: SynchronizePinnedChatsOperation) -> Signal<Void, NoError> { .complete() }"""
if fixed:
    saved = sync[sync.index("private enum SavedPinnedChatsAttemptStart"):]
    runner = """func runSync(_ p: Postbox, _ n: Network, _ e: PeerMergedOperationLogEntry) -> Signal<Void, NoError> { synchronizePinnedSavedChats(postbox:p,network:n,accountPeerId:PeerId(100),entry:e) }"""
else:
    saved = block(sync, "private func synchronizePinnedSavedChats(")
    runner = """func runSync(_ p: Postbox, _ n: Network, _ e: PeerMergedOperationLogEntry) -> Signal<Void, NoError> { synchronizePinnedSavedChats(transaction:p.tx,postbox:p,network:n,accountPeerId:PeerId(100),stateManager:AccountStateManager(),operation:SynchronizePinnedChatsOperation()) }"""
start = setter.index("func _internal_setForumChannelPinnedTopics(")
branch = block(setter[start:], "if id == account.peerId")
setter_fixture = """func savedSetter(account: Account, id: EnginePeer.Id, threadIds: [Int64]) -> Signal<Never, SetForumChannelTopicPinnedError> {
""" + branch + "\nreturn .complete()\n}"
setter_captured = ""
disposition_probe = ""
cases_source = (FIXTURES / "cases.swift").read_text()
if fixed:
    setter_next = block(branch, "|> mapToSignal { inputPeers -> Signal<Never, SetForumChannelTopicPinnedError> in")
    setter_next_body = setter_next.split("{ inputPeers -> Signal<Never, SetForumChannelTopicPinnedError> in", 1)[1][:-1]
    setter_next_type = "[Api.InputDialogPeer]?" if "guard let inputPeers" in setter_next else "[Api.InputDialogPeer]"
    setter_captured = "func capturedSetterNext(inputPeers: " + setter_next_type + ", scope: SavedPinnedThreadsSynchronizationState.Scope, account: Account) -> Signal<Never,SetForumChannelTopicPinnedError> { " + setter_next_body + " }\n"
    if "_ f: @escaping (Scope) -> Signal<T, E>" in block(sync, "static func withLocalMutation<"):
        disposition_probe = "func dispositionProbeMutation(postbox: Postbox, _ onDispose: @escaping () -> Void) -> Signal<Void,NoError> { SavedPinnedThreadsSynchronizationState.withLocalMutation(postbox:postbox,accountPeerId:PeerId(100),{ _ in Signal { _ in ActionDisposable { onDispose() } } }) }\n"
    else:
        disposition_probe = "func dispositionProbeMutation(postbox: Postbox, _ onDispose: @escaping () -> Void) -> Signal<Void,NoError> { SavedPinnedThreadsSynchronizationState.withLocalMutation(postbox:postbox,accountPeerId:PeerId(100),signal:Signal { _ in ActionDisposable { onDispose() } }) }\n"
else:
    # The original implementation has no registry types. Compile only its
    # applicable remote-order and finite-error controls, using the same assertions.
    if args.case not in ["all", "success", "error", "network"]:
        raise SystemExit("Original source supports success/error/network controls; registry race controls require a later revision.")
    common = cases_source[:cases_source.index('if mode == "all"')]
    cases_source = "\n".join([
        common,
        block(cases_source, 'if mode == "all" || mode == "success"'),
        block(cases_source, 'if mode == "all" || mode == "error" || mode == "network"'),
    ])
index_source = (REPO / "submodules/Postbox/Sources/MessageThreadIndexTable.swift").read_text()
index_condition = "if let topIndex = topIndex, let info = info"
assert index_condition in index_source
index_fixture = "func hasActualThreadIndex(topIndex: MessageIndex?, info: StoredMessageHistoryThreadInfo?) -> Bool { " + index_condition + " { _ = topIndex; _ = info; return true }; return false }\n"
fixture = "\n".join([
    index_fixture, (FIXTURES / "adapters.swift").read_text(), prefix,
    ordinary, saved, runner, setter_fixture, setter_captured, disposition_probe, cases_source,
])
save_artifact("fixture-source.swift", fixture)
with tempfile.TemporaryDirectory(prefix="saved-pinned-chats-") as temp:
    scratch = Path(temp)
    fixture_path = scratch / "fixture.swift"
    fixture_path.write_text(fixture)
    runtime = sorted((REPO / "submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"))
    assert len(runtime) >= 20, "SwiftSignalKit source tree missing"
    module = subprocess.run([
        "swiftc", "-swift-version", "5", "-emit-library", "-emit-module",
        "-module-name", "SwiftSignalKit", "-emit-module-path", str(scratch / "SwiftSignalKit.swiftmodule"),
        "-o", str(scratch / "libSwiftSignalKit.dylib"), *map(str, runtime),
    ], capture_output=True, text=True)
    save_artifact("swift-signal-kit-build.txt", module.stdout + module.stderr)
    if module.returncode:
        raise SystemExit(module.stderr)
    compiled = subprocess.run([
        "swiftc", "-swift-version", "5", "-I", str(scratch), "-L", str(scratch),
        "-lSwiftSignalKit", "-Xlinker", "-rpath", "-Xlinker", str(scratch),
        str(fixture_path), "-o", str(scratch / "fixture"),
    ], capture_output=True, text=True)
    save_artifact("fixture-build.txt", compiled.stdout + compiled.stderr)
    if compiled.returncode:
        raise SystemExit(compiled.stderr)
    run = subprocess.run([str(scratch / "fixture"), args.case], capture_output=True, text=True, timeout=20)
    print(run.stdout, end="")
    print(run.stderr, end="")
    passed = run.returncode == (42 if args.expect_failure else 0)
    record = {
        "source_root": str(args.source_root.resolve()), "case": args.case,
        "expected_failure": args.expect_failure, "exit_code": run.returncode, "passed": passed,
        "stdout": run.stdout, "stderr": run.stderr,
        "sources": {str(p.relative_to(args.source_root)): digest(p) for p in [sync_path, setter_path]},
        "swift_signal_kit_sources": {str(p.relative_to(REPO)): digest(p) for p in runtime},
        "fixture_sources": {p.name: digest(p) for p in [FIXTURES / "adapters.swift", FIXTURES / "cases.swift"]},
        "harness_sha256": digest(Path(__file__).resolve()),
        "limits": "Real SwiftSignalKit; synthetic Postbox/API/StoreMessage/network; no device, disk database, real RPC or whole TelegramCore typecheck.",
    }
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(record, indent=2) + "\n")
    if not passed:
        raise SystemExit(1)
