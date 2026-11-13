#!/usr/bin/env python3
"""Actual translation failure bus/handler and history/pin request boundaries; real SwiftSignalKit.

Only Account/UI/domain/Postbox/RPC shells are synthetic. The full history manager
closure, raw-intent method and insertion, effective language assignment, pinned
translation region, failure catch and complete UI/Undo handler execute unchanged.
No request, user settings, account data, phone, application build or signing.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / 'CLAUDE.md').exists())
RELS = ['submodules/TranslateUI/Sources/SGTranslation.swift', 'submodules/TranslateUI/Sources/ChatTranslation.swift', 'submodules/TelegramUI/Components/TranslateHeaderPanelComponent/Sources/ChatTranslationPanelNode.swift', 'submodules/TelegramUI/Sources/ChatHistoryListNode.swift', 'submodules/TelegramUI/Sources/ChatPinnedMessageTitlePanelNode.swift']
RUNTIME = sorted((ROOT / 'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
def block(source, marker):
    start = source.index(marker); opening = source.index('{', start); depth = 0
    for i in range(opening, len(source)):
        if source[i] == '{': depth += 1
        elif source[i] == '}':
            depth -= 1
            if depth == 0: return source[start:i + 1]
    raise AssertionError(marker)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=ROOT)
parser.add_argument('--fixtures-dir', type=Path, default=(HERE/'chat_translation_request_boundary' if (HERE/'chat_translation_request_boundary').is_dir() else HERE))
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--artifacts-dir', type=Path)
parser.add_argument('--expect-failure', action='store_true')
args = parser.parse_args()
paths = [args.source_root / p for p in RELS]
helper, chat, panel, history, pinned = [p.read_text() for p in paths]
scoped = 'public struct SGChatTranslationFailureEvent:' in helper
owned = 'translationRequestGeneration' in history
normalizer_path = ROOT / 'submodules/TranslateUI/Sources/Translate.swift'
normalizer = block(normalizer_path.read_text(), 'public func normalizeTranslationLanguage(_ code: String) -> String {').replace('public ', '')
event = block(helper, 'public struct SGChatTranslationFailureEvent: Equatable {').replace('public ', '') if scoped else ''
reason = block(helper, 'public enum SGChatTranslationFailureReason: Equatable {').replace('public enum', 'enum', 1)
reporter = block(helper, 'private final class SGChatTranslationFailureReporter {')
mapping = block(helper, 'func sgChatTranslationFailureReason(error: TranslationError, onDevice: Bool) -> SGChatTranslationFailureReason? {')
report = block(helper, ('func sgReportChatTranslationFailure(accountId: Int64, peerIds: Set<EnginePeer.Id>, toLang: String, error: TranslationError, onDevice: Bool) {' if scoped else 'func sgReportChatTranslationFailure(peerIds: Set<EnginePeer.Id>, error: TranslationError, onDevice: Bool) {'))
listen = block(helper, ('public func sgChatTranslationFailures(accountId: Int64, peerId: EnginePeer.Id) -> Signal<SGChatTranslationFailureEvent, NoError> {' if scoped else 'public func sgChatTranslationFailures(peerId: EnginePeer.Id) -> Signal<SGChatTranslationFailureReason, NoError> {')).replace('public func', 'func', 1)
prefix_start = panel.index('        let previousInfo = self.currentInfo')
subscription = panel[prefix_start:panel.index('        var themeUpdated = false', prefix_start)]
properties = '\n'.join(line.replace('private ', '', 1) for line in panel.splitlines() if ('let sgFailureDisposable' in line or 'var sgFailure' in line or 'var sgLastFailure' in line))
handler = block(panel, ('    private func sgHandleTranslationFailure(_ failure: SGChatTranslationFailureEvent) {' if scoped else '    private func sgHandleTranslationFailure(_ reason: SGChatTranslationFailureReason) {')).replace('private func', 'func', 1)
catch_callback = block(chat, '        |> `catch` { error -> Signal<Never, NoError> in')
catch_callback = catch_callback[catch_callback.index('{'):]
delivery = '\n    |> deliverOnMainQueue' if '|> deliverOnMainQueue\n        |> `catch`' in chat else ''
publisher = '''
func translateMessageIds(context: AccountContext, messageIds: [EngineMessage.Id], fromLang: String?, toLang: String, isCurrent: (() -> Bool)? = nil) -> Signal<Never, NoError> {
    let accountId = context.account.id.int64
    let peerIds = Set(messageIds.map(\\.peerId))
    let isOnDevice = false
    _ = accountId; _ = isCurrent
    return context.engine.request()
''' + delivery + '\n    |> `catch` ' + catch_callback + '\n}\n'
shell = '''
final class ChatTranslationPanelNode {
    let context: AccountContext
    let viewController = ViewController()
    var currentInfo: Info?
''' + properties + '''
    var toggleCount = 0
    var onToggle: (() -> Void)?
    lazy var toggle: () -> Void = { [weak self] in
        guard let self else { return }
        self.toggleCount += 1; self.currentInfo?.isActive.toggle(); self.onToggle?()
    }
    init(accountId: Int64, peerId: EnginePeer.Id) { context = AccountContext(accountId); currentInfo = Info(peer: Peer(id: peerId)) }
    func controller() -> ViewController? { viewController }
    func subscribe() { updateInfo(currentInfo!) }
    func updateInfo(_ info: Info) {
''' + subscription + '''
        _ = previousInfo
    }
    func dispose() { sgFailureDisposable.dispose() }
    deinit { sgFailureDisposable.dispose() }
''' + handler + '\n}\n'
history_properties = '\n'.join(line.replace('private ', '', 1) for line in history.splitlines() if ('var translationLang:' in line or 'var translationRequestGeneration:' in line or 'var translationRequestIntent:' in line))
manager = block(history, '        self.translationProcessingManager.process = {')
intent_method = block(history, '    private func updateTranslationRequestIntent(state: ChatTranslationState?, baseLanguageCode: String) {').replace('private func', 'func', 1) if owned else ''
early = ''
if owned:
    insertion = history.index('            if let self, case .default = source {\n                self.updateTranslationRequestIntent')
    early = block(history, '            if let self, case .default = source {\n                self.updateTranslationRequestIntent')
    assert insertion < history.index('            switch update.0 {') < history.index('                if case .Generic(.FillHole) = type {')
    assert 'let messageViewQueue = Queue.mainQueue()' in history
    assert 'combineLatest(queue: messageViewQueue,' in history
lang_start = history.index('                var translateToLanguage: (fromLang: String, toLang: String)?')
lang_region = history[lang_start:history.index('                var isSuspiciousPeer', lang_start)]
setter_start = history.index('                    if let translateToLanguage {\n                        strongSelf.translationLang')
setter_region = history[setter_start:history.index('                    if strongSelf.appliedScrollToMessageId', setter_start)]
history_shell = '''
func sgCanTranslateChatsWithoutPremium() -> Bool { true }
final class HistoryNode {
    let context: AccountContext
    let translationProcessingManager = ProcessingManager()
''' + history_properties + '''
    init(_ context: AccountContext) {
        self.context = context
''' + manager + '''
    }
''' + intent_method + '''
    func applyRaw(_ state: ChatTranslationState?, loading: Bool = false, fillHole: Bool = false, base: String = "de", source: Source = .default) {
        let translationState = state
        let chatPresentationData = (strings: Strings(baseLanguageCode: base), ignored: false)
        let callback: () -> Void = { [weak self] in
''' + early + '''
        if loading || fillHole { return }
        let isPremium = false; let autoTranslate = false
''' + lang_region + '''
        if let strongSelf = self, case .default = source {
''' + setter_region + '''
        }
        }
        callback()
    }
    func process(_ ids: [EngineMessage.Id]) { translationProcessingManager.process?(Set(ids.map { MessageAndThreadId(messageId: $0) })) }
}
'''
pin_properties = '\n'.join(line.replace('private ', '', 1) for line in pinned.splitlines() if ('var currentTranslateToLanguage:' in line or 'let translationDisposable =' in line or 'var translationRequestGeneration:' in line or 'var translationRequestMessageId:' in line))
pin_start = pinned.index('        var translateToLanguage: (fromLang: String, toLang: String)?')
pin_region = pinned[pin_start:pinned.index('        if self.currentLayout?.0', pin_start)]
pin_shell = '''
final class PinnedNode {
    let context: AccountContext
''' + pin_properties + '''
    init(_ context: AccountContext) { self.context = context }
    deinit { translationDisposable.dispose() }
    func update(_ interfaceState: PinnedInterfaceState, messageUpdated: Bool = true) {
''' + pin_region + '''
    }
}
'''
fixtures = [args.fixtures_dir / 'adapters.swift', args.fixtures_dir / 'cases.swift']
code = fixtures[0].read_text() + '\n' + normalizer + '\n' + reason + '\n' + event + '\n' + reporter + '\nprivate let sgChatTranslationFailureReporter = SGChatTranslationFailureReporter()\n' + mapping + '\n' + report + '\n' + listen + '\n' + shell + publisher + history_shell + pin_shell + fixtures[1].read_text()
inputs = paths + RUNTIME + [normalizer_path, *fixtures, Path(__file__)]
before = {str(p): sha(p) for p in inputs}
result = {'scope': __doc__, 'inputs_before': before, 'real_signal_sources': len(RUNTIME), 'scoped_bus': scoped, 'caller_generations': owned, 'early_intent_order_source_check': owned}
assert len(RUNTIME) == 26
with tempfile.TemporaryDirectory(prefix='sg-chat-request-boundary-') as tmp:
    scratch = Path(tmp); unit = scratch/'main.swift'; unit.write_text(code)
    if args.artifacts_dir:
        args.artifacts_dir.mkdir(parents=True, exist_ok=True)
        (args.artifacts_dir / 'extracted.swift').write_text(code)
    library = subprocess.run(['xcrun','swiftc','-swift-version','5','-emit-library','-emit-module','-module-name','SwiftSignalKit',*map(str,RUNTIME),'-o',str(scratch/'libSwiftSignalKit.dylib')], capture_output=True,text=True,timeout=90)
    result['runtime_compile_exit'] = library.returncode
    if library.returncode: result['compile_output'] = library.stderr
    else:
        build = subprocess.run(['xcrun','swiftc','-swift-version','5','-warnings-as-errors',*(['-D','SCOPED'] if scoped else []),'-I',str(scratch),'-L',str(scratch),'-lSwiftSignalKit','-Xlinker','-rpath','-Xlinker',str(scratch),str(unit),'-o',str(scratch/'probe')],capture_output=True,text=True,timeout=60)
        result['fixture_compile_exit'] = build.returncode; result['compile_output'] = build.stderr
        if build.returncode == 0:
            run = subprocess.run([str(scratch/'probe')],capture_output=True,text=True,timeout=20)
            result.update(run_exit=run.returncode, stdout=run.stdout, stderr=run.stderr)
result['inputs_after'] = {str(p): sha(p) for p in inputs}
result['inputs_unchanged'] = result['inputs_after'] == before
result['pass'] = result.get('run_exit') == (42 if args.expect_failure else 0) and result['inputs_unchanged']
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(result,indent=2)+'\n')
print(result.get('stdout','') + result.get('compile_output',''))
print(('PASS expected baseline failure' if args.expect_failure else 'PASS request boundaries') if result['pass'] else 'FAIL')
raise SystemExit(0 if result['pass'] else 1)
