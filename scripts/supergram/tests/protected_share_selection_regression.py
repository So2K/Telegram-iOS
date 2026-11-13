#!/usr/bin/env python3
"""Execute exact protected-share method and exact stock controller share closure.
Real SwiftSignalKit; UI, engine/Postbox and message models are controlled doubles.
No real messages/UI/RPC/defaults/photos; compilation uses temporary scratch outside the repository.
Production is the default source; --source-root accepts a frozen before/candidate tree.
Evidence is written only to explicit --output/--artifacts-dir destinations.
"""
from pathlib import Path
import argparse, subprocess, tempfile, hashlib, json
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
FIXTURES=HERE / "protected_share_selection"
P=Path("submodules/TelegramUI/Components/Chat/ChatMessageSelectionInputPanelNode/Sources/ChatMessageSelectionInputPanelNode.swift")
C=Path("submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift")
PI=Path("submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift")
PB=Path("submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSelectionPanelNode.swift")
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--source-root", type=Path, default=ROOT);parser.add_argument("--expect-bug",action="store_true");parser.add_argument("--expect-regression",action="store_true");parser.add_argument("--output", type=Path);parser.add_argument("--artifacts-dir", type=Path);args=parser.parse_args()
source=args.source_root/P
text=source.read_text();method=text[text.index("    @objc private func shareButtonPressed() {"):text.index("\n    @objc private func tagButtonPressed()",text.index("    @objc private func shareButtonPressed() {"))]
getterSource=ROOT/"submodules/TelegramUI/Sources/ChatController.swift"
getterText=getterSource.read_text();getterStart=getterText.index("    public var selectedMessageIds: Set<EngineMessage.Id>? {");getterEnd=getterText.index("\n    }",getterStart)+len("\n    }");getter=getterText[getterStart:getterEnd]
controller=(ROOT/C).read_text();start=controller.index("}, shareSelectedMessages: { [weak self] in")+len("}, shareSelectedMessages: ");end=controller.index("}, updateTextInputStateAndMode:",start)
closure=controller[start:end]+"}"
peerText=(ROOT/PI).read_text();peerStart=peerText.index("}, shareMessages: { [weak self] in")+len("}, shareMessages: ");peerEnd=peerText.index("}, forwardMessages:",peerStart);peerClosure=peerText[peerStart:peerEnd]+"}"
bridgeText=(ROOT/PB).read_text();bridgeStart=bridgeText.index("}, shareSelectedMessages: {")+len("}, shareSelectedMessages: ");bridgeEnd=bridgeText.index("}, updateTextInputStateAndMode:",bridgeStart);bridge=bridgeText[bridgeStart:bridgeEnd]+"}"
swift=(FIXTURES/"adapters.swift").read_text().replace("    // ACTUAL_PANEL_METHOD",method).replace("    // ACTUAL_CONTROLLER_CLOSURE","    func shareAction()->()->Void { return "+closure+" }").replace("    // ACTUAL_SELECTED_ID_GETTER",getter).replace("    // ACTUAL_PEERINFO_CLOSURE","    func shareAction()->()->Void { return "+peerClosure+" }").replace("// ACTUAL_PEERINFO_BRIDGE",bridge)+(FIXTURES/"cases.swift").read_text()
deps=sorted((ROOT/"submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"));assert len(deps)==26
hashes={str(p.resolve()):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,ROOT/C,ROOT/PI,ROOT/PB,getterSource,FIXTURES/"adapters.swift",FIXTURES/"cases.swift",*deps]}
if args.artifacts_dir is not None:
 args.artifacts_dir.mkdir(parents=True, exist_ok=True)
 (args.artifacts_dir/"extracted.swift").write_text(swift)
with tempfile.TemporaryDirectory(prefix="supergram-share-race-") as directory:
 scratch=Path(directory)
 commands=[["xcrun","swiftc","-swift-version","5","-module-name","SwiftSignalKit","-parse-as-library","-emit-module","-emit-module-path",str(scratch/"SwiftSignalKit.swiftmodule"),"-emit-library","-o",str(scratch/"libSwiftSignalKit.dylib"),*map(str,deps)]]
 src=scratch/"main.swift";src.write_text(swift);binary=scratch/"regression"
 commands.append(["xcrun","swiftc","-swift-version","5","-warnings-as-errors","-I",str(scratch),"-L",str(scratch),"-lSwiftSignalKit","-Xlinker","-rpath","-Xlinker",str(scratch),str(src),"-o",str(binary)])
 for command in commands:
  r=subprocess.run(command,text=True,capture_output=True,timeout=90)
  if r.returncode:print(r.stdout+r.stderr);raise SystemExit(r.returncode)
 r=subprocess.run([str(binary)]+(["--expect-bug"] if args.expect_bug else []),text=True,capture_output=True,timeout=8)
 print(r.stdout+r.stderr)
 assert r.returncode==(42 if args.expect_regression else 0)
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
if args.output is not None:
 args.output.parent.mkdir(parents=True, exist_ok=True)
 args.output.write_text(json.dumps({"input_hashes":hashes,"exit":r.returncode,"result":r.stdout,"controller_closure_sha256":hashlib.sha256(closure.encode()).hexdigest(),"panel_method_sha256":hashlib.sha256(method.encode()).hexdigest(),"limits":"Real SwiftSignalKit; engine requests, UI and models doubled. No physical reproduction, real DB, photos or RPC."},indent=2)+"\n")
