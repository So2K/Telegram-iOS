#!/usr/bin/env python3
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
FIXTURES=HERE/'search_share_selection'
P=Path("submodules/ChatListUI/Sources/ChatListSearchMessageSelectionPanelNode.swift")
C=Path("submodules/ChatListUI/Sources/ChatListSearchContainerNode.swift")
parser=argparse.ArgumentParser()
parser.add_argument("--output",type=Path,required=True)
parser.add_argument("--artifacts-dir",type=Path)
parser.add_argument("--source-dir",type=Path,default=ROOT,help="Read the two sources from another root; defaults to the working repository")
parser.add_argument("--expect-bug",action="store_true")
parser.add_argument("--expect-regression",action="store_true")
args=parser.parse_args()
source_root=args.source_dir.resolve()
source=source_root/P
text=source.read_text()
start=text.index("    @objc func shareButtonPressed() {")
method=text[start:text.rfind("\n}")]
container_source=source_root/C
text=container_source.read_text()
start=text.index("}, shareMessages: { [weak self] in")+len("}, shareMessages: ")
end=text.index("}, forwardMessages:",start)
closure=text[start:end]+"}"
start=text.index("    private func updateState(")
end=text.index("\n    public func removeAds()",start)
state=text[start:end].replace("ChatListSearchContainerNodeSearchState","SearchState")
if "getSelectedMessageIds: { [weak self] in" in text:
    getter_start=text.index("getSelectedMessageIds: { [weak self] in")+len("getSelectedMessageIds: ")
    getter_end=text.index("}, deleteMessages:",getter_start)
    getter=text[getter_start:getter_end]+"}"
else:
    getter="{ [weak self] in return self?.stateValue.selectedMessageIds }"
secret_source=ROOT/"submodules/TelegramCore/Sources/Utils/SuperGramContentProtection.swift"
timeout_source=ROOT/"submodules/TelegramCore/Sources/SyncCore/SyncCore_AutoremoveTimeoutMessageAttribute.swift"
def block(text,key,start=0):
    index=text.index(key,start);opening=text.index("{",index);depth=0
    for end in range(opening,len(text)):
        depth+=(text[end]=="{")-(text[end]=="}")
        if depth==0:return text[index:end+1]
    raise AssertionError(key)
secret_text=secret_source.read_text()
raw_secret=block(secret_text,"var sgIsSecretContent:")
engine_secret=block(secret_text,"var sgIsSecretContent:",secret_text.index("public extension EngineMessage"))
constant=next(line for line in timeout_source.read_text().splitlines() if line.startswith("public let viewOnceTimeout:"))
swift=(FIXTURES/"adapters.swift").read_text().replace("// ACTUAL_RAW_SECRET",raw_secret).replace("// ACTUAL_ENGINE_SECRET",engine_secret).replace("// ACTUAL_VIEW_ONCE_CONSTANT",constant).replace("    // ACTUAL_SELECTED_IDS_GETTER", "    func selectedIdsAction()->()->Set<MessageId>? { return "+getter+" }").replace("    // ACTUAL_PANEL_METHOD",method).replace("    // ACTUAL_STATE_UPDATE",state).replace("    // ACTUAL_SHARE_CLOSURE","    func shareAction()->()->Void { return "+closure+" }")+(FIXTURES/"cases.swift").read_text()
deps=sorted((ROOT/"submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"));assert len(deps)==26
inputs=[source,container_source,secret_source,timeout_source,FIXTURES/"adapters.swift",FIXTURES/"cases.swift",*deps]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
if args.artifacts_dir:
    args.artifacts_dir.mkdir(parents=True,exist_ok=True)
    (args.artifacts_dir/"source-extracted.swift").write_text(swift)
with tempfile.TemporaryDirectory(prefix="sg-search-share-") as temp:
    scratch=Path(temp);src=scratch/"main.swift";src.write_text(swift);binary=scratch/"regression"
    commands=[
        ["xcrun","swiftc","-swift-version","5","-module-name","SwiftSignalKit","-parse-as-library","-emit-module","-emit-module-path",str(scratch/"SwiftSignalKit.swiftmodule"),"-emit-library","-o",str(scratch/"libSwiftSignalKit.dylib"),*map(str,deps)],
        ["xcrun","swiftc","-swift-version","5","-warnings-as-errors","-I",str(scratch),"-L",str(scratch),"-lSwiftSignalKit","-Xlinker","-rpath","-Xlinker",str(scratch),str(src),"-o",str(binary)]
    ]
    for command in commands:
        result=subprocess.run(command,text=True,capture_output=True,timeout=90)
        if result.returncode:print(result.stdout+result.stderr);raise SystemExit(result.returncode)
    result=subprocess.run([str(binary)]+(["--expect-bug"] if args.expect_bug else []),text=True,capture_output=True,timeout=8)
    print(result.stdout+result.stderr)
    assert result.returncode==(42 if args.expect_regression else 0)
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps({"input_hashes":hashes,"exit":result.returncode,"stdout":result.stdout,"stderr":result.stderr,"limits":"Exact search button/helper, owned source state update, Share callback and candidate weak parent getter with26 real SSK; engine/UI/models controlled. No export/RPC/account data."},indent=2)+"\n")
