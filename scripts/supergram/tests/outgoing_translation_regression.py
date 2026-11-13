#!/usr/bin/env python3
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile
HERE=Path(__file__).resolve().parent
ROOT=HERE
while not (ROOT/'CLAUDE.md').is_file():
    if ROOT == ROOT.parent: raise RuntimeError('Repository root not found')
    ROOT=ROOT.parent
FIXTURES=ROOT/'scripts/supergram/tests/outgoing_translation'
P=Path("submodules/TelegramUI/Sources/Chat/ChatMessageDisplaySendMessageOptions.swift")
C=Path("submodules/ChatSendMessageActionUI/Sources/ChatSendMessageContextScreen.swift")
I=Path("submodules/ChatInterfaceState/Sources/ChatInterfaceState.swift")
T=Path("submodules/AccountContext/Sources/ChatController.swift")
G=Path("submodules/TextFormat/Sources/GenerateTextEntities.swift")
K=Path("submodules/TextFormat/Sources/ChatTextInputAttributes.swift")
parser=argparse.ArgumentParser();parser.add_argument("--source",type=Path,default=ROOT/P);parser.add_argument("--output",type=Path,required=True);parser.add_argument("--artifacts-dir",type=Path);parser.add_argument("--expect-bug",action="store_true");parser.add_argument("--expect-regression",action="store_true");parser.add_argument("--expect-quote-bug",action="store_true");parser.add_argument("--fixtures-dir",type=Path);parser.add_argument("--quote-control-group",choices=["all","request","nested-text-success","nested-text-error","nested-attributes-success","nested-attributes-error"],default="all");args=parser.parse_args()
if args.fixtures_dir: FIXTURES=args.fixtures_dir.resolve()
source=args.source.resolve()
text=source.read_text();start=text.index("        var sgTranslationContext:");end=text.index("\n        if let editMessage =",start);block=text[start:end]
text=(ROOT/C).read_text();start=text.index('id: AnyHashable("sgTranslate")');start=text.index("action: ",start)+len("action: ");end=text.index("\n                        )))",start);action=text[start:end].rstrip()
def extract(text,start,end):
    a=text.index(start);b=text.index(end,a);return text[a:b]
text=(ROOT/I).read_text()
getter=extract(text,"    public var effectiveInputState:","\n    public init()")
synchronizeable=extract(text,"    public var synchronizeableInputState:","\n    public func withUpdatedSynchronizeableInputState")
update=extract(text,"    public func withUpdatedEffectiveInputState(","\n    public func withUpdatedReplyMessageSubject")
text=(ROOT/T).read_text()
equality=extract(text,"    public static func ==(lhs: ChatTextInputState,","\n    public init()")
text=(ROOT/K).read_text();keys=extract(text,"public struct ChatTextInputAttributes {","\npublic let originalTextAttributeKey")
text=(ROOT/G).read_text();generator=extract(text,"public func generateChatInputTextEntities(","\npublic func generateTextEntities(")
quoteAttribute=extract((ROOT/K).read_text(),"public final class ChatTextInputTextQuoteAttribute:","\npublic final class ChatTextInputTextCustomEmojiAttribute:")
collapsedExpander=extract((ROOT/K).read_text(),"public func expandedInputStateAttributedString(","\npublic func stateAttributedStringForText(")
entityAdapters=(FIXTURES/"entity-adapters.swift").read_text().replace("// ACTUAL_ATTRIBUTE_KEYS",keys).replace("// ACTUAL_ENTITY_GENERATOR",generator).replace("// ACTUAL_QUOTE_ATTRIBUTE",quoteAttribute).replace("// ACTUAL_COLLAPSED_EXPANDER",collapsedExpander)
swift=(FIXTURES/"adapters.swift").read_text().replace("// ACTUAL_ENTITY_ADAPTERS",entityAdapters).replace("    // ACTUAL_SYNCHRONIZEABLE_GETTER",synchronizeable).replace("    // ACTUAL_TRANSLATION_BLOCK",block).replace("    // ACTUAL_EFFECTIVE_GETTER",getter).replace("    // ACTUAL_EFFECTIVE_UPDATE",update).replace("    // ACTUAL_INPUT_EQUALITY",equality).replace("    // ACTUAL_MENU_ACTION","    func action()->(Int,Int)->Void { return "+action+" }")+(FIXTURES/"cases.swift").read_text()
deps=sorted((ROOT/"submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"));assert len(deps)==26
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,ROOT/C,ROOT/I,ROOT/T,ROOT/G,ROOT/K,FIXTURES/"entity-adapters.swift",FIXTURES/"adapters.swift",FIXTURES/"cases.swift",Path(__file__),*deps]}
if args.artifacts_dir:
    args.artifacts_dir.mkdir(parents=True,exist_ok=True)
    (args.artifacts_dir/"source-extracted.swift").write_text(swift)
with tempfile.TemporaryDirectory(prefix="sg-outgoing-translation-") as temp:
    scratch=Path(temp);src=scratch/"main.swift";src.write_text(swift);binary=scratch/"regression"
    commands=[
        ["xcrun","swiftc","-swift-version","5","-module-name","SwiftSignalKit","-parse-as-library","-emit-module","-emit-module-path",str(scratch/"SwiftSignalKit.swiftmodule"),"-emit-library","-o",str(scratch/"libSwiftSignalKit.dylib"),*map(str,deps)],
        ["xcrun","swiftc","-swift-version","5","-warnings-as-errors","-I",str(scratch),"-L",str(scratch),"-lSwiftSignalKit","-Xlinker","-rpath","-Xlinker",str(scratch),str(src),"-o",str(binary)]
    ]
    for command in commands:
        result=subprocess.run(command,text=True,capture_output=True,timeout=90)
        if result.returncode:print(result.stdout+result.stderr);raise SystemExit(result.returncode)
    result=subprocess.run([str(binary)]+(["--expect-bug"] if args.expect_bug else [])+(["--expect-quote-bug"] if args.expect_quote_bug else [])+["--quote-control-group="+args.quote_control_group],text=True,capture_output=True,timeout=8)
    print(result.stdout+result.stderr);assert result.returncode==(42 if args.expect_regression else 0)
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps({"input_hashes":hashes,"exit":result.returncode,"stdout":result.stdout,"stderr":result.stderr,"limits":"Actual outgoing translation block/menu action/input equality/effective and synchronizeable getters/updater/attribute keys/entity generator/actual collapsed quote expander and quote attribute class with26 real SSK. Engine/UI/other state fields doubled; no user text, RPC, UI or send."},indent=2)+"\n")
