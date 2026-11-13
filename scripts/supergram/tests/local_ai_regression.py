#!/usr/bin/env python3
"""Run extracted production local-AI lifecycle, locale, and UTF-16 code on macOS.

Framework execution still requires a physical iOS device. These deterministic
checks exercise actual source blocks, with signal timer/queue doubles only.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]

def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    return source[start:end] + "\n"

translation = (ROOT / "submodules/TranslateUI/Sources/Translate.swift").read_text()
speech = (ROOT / "submodules/Media/LocalAudioTranscription/Sources/LocalAudioTranscription.swift").read_text()
chat = (ROOT / "submodules/TranslateUI/Sources/ChatTranslation.swift").read_text()
settings = (ROOT / "submodules/TelegramUIPreferences/Sources/MediaDisplaySettings.swift").read_text()
coding_key = (ROOT / "submodules/TelegramCore/Sources/TelegramEngine/Utils/StringCodingKey.swift").read_text()

swift = r'''
import Foundation
import Dispatch

final class Atomic<T> {
    private let lock = NSLock()
    private var value: T
    init(value: T) { self.value = value }
    @discardableResult func modify(_ f: (T) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        value = f(value); return value
    }
    func with<R>(_ f: (T) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return f(value)
    }
}
final class Queue {
    static let main = Queue()
    private let lock = NSLock()
    private var work: [() -> Void] = []
    static func mainQueue() -> Queue { main }
    func async(_ f: @escaping () -> Void) {
        lock.lock(); work.append(f); lock.unlock()
    }
    func drain() {
        while true {
            lock.lock()
            let next = work.isEmpty ? nil : work.removeFirst()
            lock.unlock()
            guard let next else { return }; next()
        }
    }
}
enum SwiftSignalKit {
    final class Timer {
        static var all: [Timer] = []
        let completion: () -> Void
        var invalidated = false
        init(timeout: Double, repeat: Bool, completion: @escaping () -> Void, queue: Queue) {
            precondition(timeout == 120.0)
            self.completion = completion
            Self.all.append(self)
        }
        func start() {}
        func invalidate() { invalidated = true }
    }
}
struct MessageTextEntity {
    enum Kind { case Pre, Code, Url, Email, Mention, Hashtag, BotCommand, Bold }
    let range: Range<Int>
    let type: Kind
}
'''
swift += block(translation, "fileprivate final class TranslationTask {").replace("fileprivate final class", "final class", 1)
swift += block(chat, "private func sgLanguageRecognitionSample(")
start = speech.index("private let canonicalSpeechRegions:")
end = speech.index("public func resolveLocalTranscriptionLocale(identifier:")
swift += speech[start:end]
swift += coding_key
swift += block(settings, "public struct MediaDisplaySettings:")
swift += r'''
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}
func locale(_ identifier: String) -> Locale { Locale(identifier: identifier) }
let supported: Set<Locale> = [locale("en-US"), locale("en-GB"), locale("ru-RU"), locale("pt-BR")]
check(resolveLocalTranscriptionLocale(identifier: " ru_RU-raw ", supportedLocales: supported)?.identifier == "ru-RU", "raw locale normalization")
check(resolveLocalTranscriptionLocale(identifier: "en-GB", supportedLocales: supported)?.identifier == "en-GB", "exact region preserved")
check(resolveLocalTranscriptionLocale(identifier: "pt", supportedLocales: supported)?.identifier == "pt-BR", "canonical region")
check(resolveLocalTranscriptionLocale(identifier: "auto", supportedLocales: supported) == nil, "auto is a policy candidate, not a locale")
check(resolveLocalTranscriptionLocale(identifier: "xx-YY", supportedLocales: supported) == nil, "unsupported language")

check(sgLanguageRecognitionSample(text: "😀 hello https://a.test", entities: [.init(range: 9..<23, type: .Url)]) == "😀 hello ", "UTF-16 offsets after emoji")
check(sgLanguageRecognitionSample(text: "0123456789abcdefghij", entities: [.init(range: 2..<8, type: .Code), .init(range: 4..<10, type: .Url)]) == "01abcdefghij", "overlapping entities merged")
check(sgLanguageRecognitionSample(text: "plain", entities: [.init(range: 0..<5, type: .Bold)]) == "plain", "formatting retained")
check(sgLanguageRecognitionSample(text: "abc code", entities: [.init(range: 4..<8, type: .Code)]) == "abc ", "entity ending at sample end removed")
check(sgLanguageRecognitionSample(text: "abc", entities: [.init(range: -2..<99, type: .Code), .init(range: 20..<40, type: .Url)]) == "abc", "out-of-bounds ignored")
check(sgLanguageRecognitionSample(text: String(repeating: "a", count: 300), entities: [.init(range: 250..<300, type: .Code)]).count == 250, "entity clipped at sampling boundary")

let decoder = JSONDecoder()
let oldSettings = try decoder.decode(MediaDisplaySettings.self, from: Data(#"{"showNextMediaOnTap":1,"voiceTranscriptionSettingsVersion":2,"voiceTranscriptionOnDeviceOnly":0}"#.utf8))
check(oldSettings.voiceTranscriptionOnDeviceOnly, "implicit cloud default migrated")
let explicitCloud = try decoder.decode(MediaDisplaySettings.self, from: Data(#"{"showNextMediaOnTap":1,"voiceTranscriptionSettingsVersion":3,"voiceTranscriptionOnDeviceOnly":0}"#.utf8))
check(!explicitCloud.voiceTranscriptionOnDeviceOnly, "new explicit opt-out retained")
check(MediaDisplaySettings.defaultSettings.voiceTranscriptionOnDeviceOnly, "local default")
let encoded = try JSONEncoder().encode(explicitCloud)
let roundTripped = try decoder.decode(MediaDisplaySettings.self, from: encoded)
check(!roundTripped.voiceTranscriptionOnDeviceOnly, "explicit mode round-trip")

var results = 0
var cancellations = 0
var expirations = 0
let completed = TranslationTask(id: 1, texts: [1:"text"], fromLang: "en", toLang: "ru") { _ in results += 1 }
completed.startTimeout { expirations += 1 }
completed.setCancellation { cancellations += 1 }
check(completed.finish([1:"текст"]), "first result accepted")
check(!completed.finish(nil), "duplicate result ignored")
Queue.main.drain()
check(results == 1 && cancellations == 1, "one completion and work release")
SwiftSignalKit.Timer.all.last!.completion()
Queue.main.drain()
check(expirations == 0 && results == 1, "late timeout cannot remove completed work")

let expired = TranslationTask(id: 2, texts: [1:"text"], fromLang: "en", toLang: "ru") { result in check(result == nil, "timeout result"); results += 1 }
expired.startTimeout { expirations += 1 }
expired.setCancellation { cancellations += 1 }
let expiredTimer = SwiftSignalKit.Timer.all.last!
expiredTimer.completion(); expiredTimer.completion()
Queue.main.drain()
check(expirations == 1 && results == 2 && cancellations == 2, "timeout one-shot and cancellation")
let disposed = TranslationTask(id: 3, texts: [1:"text"], fromLang: "en", toLang: "ru") { _ in results += 1 }
disposed.finish(nil, notify: false)
disposed.setCancellation { cancellations += 1 }
disposed.finish([1:"late"])
Queue.main.drain()
check(results == 2 && cancellations == 3, "cancel before worker attachment suppresses result")

let racedCompletions = Atomic(value: 0)
let racedCancellation = Atomic(value: 0)
let raced = TranslationTask(id: 4, texts: [1:"text"], fromLang: "en", toLang: "ru") { _ in racedCompletions.modify { $0 + 1 } }
raced.setCancellation { racedCancellation.modify { $0 + 1 } }
DispatchQueue.concurrentPerform(iterations: 100) { _ in raced.finish(nil) }
Queue.main.drain()
check(racedCompletions.with { $0 } == 1 && racedCancellation.with { $0 } == 1, "concurrent terminal callbacks one-shot")
print("PASS: local-AI locale, UTF-16 sampling, privacy settings migration, timeout, disposal, and concurrent completion regressions")
'''
with tempfile.TemporaryDirectory(prefix="supergram-local-ai-") as temporary:
    source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    source.write_text(swift)
    subprocess.run(["xcrun", "swiftc", "-suppress-warnings", str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
