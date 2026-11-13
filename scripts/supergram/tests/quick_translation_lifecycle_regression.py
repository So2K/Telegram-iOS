#!/usr/bin/env python3
"""Offline exact-source Bubble/quick-translate lifecycle proof, real SwiftSignalKit.

Only node shell, UI/engine API, language recognition and presentation observers are synthetic.
Actual bounded cache, selector/request store methods, getter, renderer decision, complete
helper, failure mapping and Bubble property/method/deinit execute unchanged except access
modifiers required by the owned single-file host harness. Store observer bodies are excluded. No actual RPC,
SwiftUI/UIKit build, profile, device or credential access.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / 'CLAUDE.md').exists())
BUBBLE_REL = 'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift'
HELPER_REL = 'submodules/TranslateUI/Sources/SGTranslation.swift'
RENDERER = ROOT / 'submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift'
RUNTIME = sorted((ROOT / 'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start + len(marker) - 1)
    depth = 0
    for at in range(opening, len(source)):
        if source[at] == '{':
            depth += 1
        elif source[at] == '}':
            depth -= 1
            if depth == 0:
                return source[start:at + 1]
    raise AssertionError('unterminated source block: ' + marker)

parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=ROOT)
parser.add_argument('--fixtures-dir', type=Path, default=ROOT / 'scripts/supergram/tests/quick_translation_lifecycle')
parser.add_argument('--bubble-source', type=Path)
parser.add_argument('--expect-failure', action='store_true')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
FIXTURES = args.fixtures_dir.resolve()
bubble_path = args.bubble_source or args.source_root / BUBBLE_REL
helper_path = args.source_root / HELPER_REL
source = bubble_path.read_text()
helper = helper_path.read_text()
assert len(RUNTIME) == 26, 'runtime input inventory changed; review before executing'
property_line = next(line for line in source.splitlines() if 'private let quickTranslateDisposable = MetaDisposable()' in line)
assert source.count('self.quickTranslateDisposable.set(') == 1
request = block(source, '    private func quickTranslateButtonPressed() {').replace('private func', 'func', 1)
deinit = block(source, '    deinit {')
reason_enum = block(helper, 'public enum SGChatTranslationFailureReason: Equatable {').replace('public enum', 'enum', 1)
reason = block(helper, 'func sgChatTranslationFailureReason(error: TranslationError, onDevice: Bool) -> SGChatTranslationFailureReason? {')
toggle_marker = 'public func sgToggleQuickTranslation(context: AccountContext, messageId: EngineMessage.Id, text: String, updated: @escaping () -> Void, failed: @escaping (SGChatTranslationFailureReason) -> Void) -> Disposable {'
toggle = block(helper, toggle_marker).replace('public func', 'func', 1)
shell = '\nfinal class ChatMessageBubbleItemNode {\n    var item: ChatMessageItem?\n' + property_line + '\n' + deinit + '\n' + request + '\n    func quickTranslateDisposableForTestDispose() { self.quickTranslateDisposable.dispose() }\n}\n'
cache = block(helper, 'private struct SGBoundedCache<Key: Hashable, Value> {')
store_start = helper.index('private final class SGQuickTranslationStore {')
store_end = helper.index('    /// Target language of quick translations', store_start)
store = helper[store_start:store_end] + '\n}\n'
getter = block(helper, 'public func sgQuickTranslationLanguage(messageId: EngineMessage.Id) -> String? {').replace('public func', 'func', 1)
renderer = RENDERER.read_text()
render_start = renderer.index('                    // MARK: Swiftgram: a message quick-translated with the bubble button')
render_end = renderer.index('\n                }\n', render_start)
render_body = renderer[render_start:render_end]
render = '\nfunc actualRenderer(item: ChatMessageItem) -> Bool {\nvar isTranslating = false; var rawText = item.message.text; var messageEntities: [Int]? = []; let incoming = true; var isSummaryApplied = false\n' + render_body + '\n_ = rawText; _ = messageEntities; _ = isSummaryApplied\nreturn isTranslating\n}\n'
store_setup = '\nprivate var sgQuickTranslationStore = SGQuickTranslationStore()\nfunc resetSyntheticStore() { sgQuickTranslationStore = SGQuickTranslationStore() }\n'
code = (FIXTURES / 'adapters.swift').read_text() + '\n' + cache + '\n' + store + store_setup + reason_enum + '\n' + reason + '\n' + getter + '\n' + toggle + shell + render + '\n' + (FIXTURES / 'cases.swift').read_text() + '\n' + (FIXTURES / 'reentry_cases.swift').read_text()
has_request_phases = '    final class Request {' in helper
if has_request_phases:
    code += '\n' + (FIXTURES / 'phase_cases.swift').read_text()
code += r'''
print("RESULT \(checks) checks; \(failures.count) failures")
for failure in failures { print("FAIL: \(failure)") }
if !failures.isEmpty { exit(42) }
'''
result = {
    'bubble_sha256': sha(bubble_path),
    'helper_sha256': sha(helper_path),
    'renderer_sha256': sha(RENDERER),
    'runtime_sha256': {str(path.relative_to(ROOT)): sha(path) for path in RUNTIME},
    'harness_sha256': sha(Path(__file__)),
    'adapters_sha256': sha(FIXTURES / 'adapters.swift'),
    'cases_sha256': sha(FIXTURES / 'cases.swift'),
    'reentry_cases_sha256': sha(FIXTURES / 'reentry_cases.swift'),
    'phase_cases_sha256': sha(FIXTURES / 'phase_cases.swift'),
    'typed_request_phase_controls_executed': has_request_phases,
    'limits': 'Real26 SwiftSignalKit plus actual bounded cache, selector/request store methods, getter, full helper, node request/deinit and renderer decision; synthetic Telegram/UI/engine, recognition and observed target-language services. No real network/database/device/UI or whole TelegramUI typecheck.',
}
input_paths = [bubble_path, helper_path, RENDERER, Path(__file__), *RUNTIME, *(FIXTURES / name for name in ['adapters.swift', 'cases.swift', 'reentry_cases.swift', 'phase_cases.swift'])]
input_hashes = {str(path.resolve()): sha(path) for path in input_paths}
result['input_sha256_before'] = input_hashes
with tempfile.TemporaryDirectory(prefix='sg-quick-translate-proof-') as scratch_string:
    scratch = Path(scratch_string)
    unit = scratch / 'main.swift'
    unit.write_text(code)
    library = subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-emit-library', '-emit-module',
        '-module-name', 'SwiftSignalKit', '-emit-module-path', str(scratch / 'SwiftSignalKit.swiftmodule'),
        '-o', str(scratch / 'libSwiftSignalKit.dylib'), *map(str, RUNTIME)
    ], capture_output=True, text=True, timeout=90)
    result['runtime_compile_exit'] = library.returncode
    if library.returncode:
        result['compile_output'] = library.stderr
    else:
        compile_result = subprocess.run([
            'xcrun', 'swiftc', '-swift-version', '5', '-I', str(scratch), '-L', str(scratch),
            '-lSwiftSignalKit', '-Xlinker', '-rpath', '-Xlinker', str(scratch), str(unit), '-o', str(scratch / 'probe')
        ], capture_output=True, text=True, timeout=60)
        result['fixture_compile_exit'] = compile_result.returncode
        result['compile_output'] = compile_result.stderr
        if compile_result.returncode == 0:
            run = subprocess.run([str(scratch / 'probe')], capture_output=True, text=True, timeout=10)
            result['run_exit'] = run.returncode
            result['run_stdout'] = run.stdout
            result['run_stderr'] = run.stderr
result['input_sha256_after'] = {path: sha(Path(path)) for path in input_hashes}
result['changed_inputs'] = [path for path in input_hashes if input_hashes[path] != result['input_sha256_after'][path]]
result['inputs_unchanged_during_execution'] = not result['changed_inputs']
result['expected_failure'] = args.expect_failure
result['passed'] = result.get('run_exit') == (42 if args.expect_failure else 0) and result['inputs_unchanged_during_execution']
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2) + '\n')
print(result.get('run_stdout', '') + result.get('compile_output', ''), end='')
print('PASS' if result['passed'] else 'FAIL', 'expected baseline failure' if args.expect_failure else 'current lifecycle fixture')
raise SystemExit(0 if result['passed'] else 1)
