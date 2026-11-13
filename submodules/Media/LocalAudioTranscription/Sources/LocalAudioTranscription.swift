import Foundation
import SwiftSignalKit
import Speech
import AVFoundation

public struct LocallyTranscribedAudio {
    public var text: String
    public var isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

public enum LocalAudioTranscriptionError: Equatable {
    case notAuthorized
    case localeUnsupported(String)
    case onDeviceUnsupported(String)
    case recognizerUnavailable
    case noSpeech
    case timedOut
    case conversionFailed
    case fetchFailed
}

public enum LocalAudioTranscriptionOutcome {
    case success(LocallyTranscribedAudio)
    case failure(LocalAudioTranscriptionError)
}

// SuperGram: server-based SFSpeechRecognizer requests are limited to about one minute of audio,
// longer recordings are split into chunks that are recognized one after another.
private let chunkingThresholdDuration: Double = 55.0
private let maximumChunkDuration: Double = 50.0
private let minimumTailChunkDuration: Double = 2.0
private let recognitionIdleTimeout: Double = 30.0

private let canonicalSpeechRegions: [String: String] = [
    "ar": "SA",
    "ca": "ES",
    "cs": "CZ",
    "da": "DK",
    "de": "DE",
    "el": "GR",
    "en": "US",
    "es": "ES",
    "fi": "FI",
    "fr": "FR",
    "he": "IL",
    "hi": "IN",
    "hr": "HR",
    "hu": "HU",
    "id": "ID",
    "it": "IT",
    "ja": "JP",
    "kk": "KZ",
    "ko": "KR",
    "ms": "MY",
    "nb": "NO",
    "nl": "NL",
    "pl": "PL",
    "pt": "BR",
    "ro": "RO",
    "ru": "RU",
    "sk": "SK",
    "sv": "SE",
    "th": "TH",
    "tr": "TR",
    "uk": "UA",
    "vi": "VN",
    "zh": "CN"
]

private func normalizedLocaleIdentifier(_ identifier: String) -> String {
    var value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawSuffix = "-raw"
    if value.lowercased().hasSuffix(rawSuffix) {
        value = String(value.dropLast(rawSuffix.count))
    }
    return value.replacingOccurrences(of: "_", with: "-")
}

private func resolveLocalTranscriptionLocale(identifier: String, supportedLocales: Set<Locale>) -> Locale? {
    let normalizedIdentifier = normalizedLocaleIdentifier(identifier)
    if normalizedIdentifier.isEmpty || normalizedIdentifier == "auto" {
        return nil
    }
    let requestedKey = normalizedIdentifier.lowercased()
    if let exactLocale = supportedLocales.first(where: { normalizedLocaleIdentifier($0.identifier).lowercased() == requestedKey }) {
        return exactLocale
    }

    let requestedLocale = Locale(identifier: normalizedIdentifier)
    guard let languageCode = requestedLocale.languageCode?.lowercased() else {
        return nil
    }
    let matchingLocales = supportedLocales.filter { locale in
        return locale.languageCode?.lowercased() == languageCode
    }.sorted(by: { $0.identifier < $1.identifier })
    if matchingLocales.isEmpty {
        return nil
    }

    var preferredRegions: [String] = []
    if let regionCode = requestedLocale.regionCode {
        preferredRegions.append(regionCode.uppercased())
    }
    if let regionCode = Locale.current.regionCode {
        preferredRegions.append(regionCode.uppercased())
    }
    if let regionCode = canonicalSpeechRegions[languageCode] {
        preferredRegions.append(regionCode)
    }
    preferredRegions.append(languageCode.uppercased())
    for regionCode in preferredRegions {
        if let locale = matchingLocales.first(where: { $0.regionCode?.uppercased() == regionCode }) {
            return locale
        }
    }
    return matchingLocales.first
}

public func resolveLocalTranscriptionLocale(identifier: String) -> Locale? {
    return resolveLocalTranscriptionLocale(identifier: identifier, supportedLocales: SFSpeechRecognizer.supportedLocales())
}

private func speechRecognitionAuthorization() -> Signal<Bool, NoError> {
    return Signal { subscriber in
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            subscriber.putNext(true)
            subscriber.putCompletion()
        case .denied, .restricted:
            subscriber.putNext(false)
            subscriber.putCompletion()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                subscriber.putNext(status == .authorized)
                subscriber.putCompletion()
            }
        @unknown default:
            subscriber.putNext(false)
            subscriber.putCompletion()
        }
        return EmptyDisposable
    }
}

private func audioFileDuration(url: URL, fallback: Double?) -> Signal<Double, NoError> {
    return Signal { subscriber in
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        if seconds.isFinite && seconds > 0.0 {
            subscriber.putNext(seconds)
        } else {
            subscriber.putNext(max(0.0, fallback ?? 0.0))
        }
        subscriber.putCompletion()
        return EmptyDisposable
    }
    |> runOn(Queue.concurrentDefaultQueue())
}

private enum SpeechRecognitionMode {
    case server
    case onDevice
}

private enum SpeechChunkOutcome {
    /// The recognizer reported a final result for the whole chunk.
    case text(String)
    /// Recognition stopped early but text was already produced: usable, yet not final.
    case partial(String, LocalAudioTranscriptionError)
    case failed(LocalAudioTranscriptionError)
}

@available(iOS 13.0, *)
private final class SpeechRecognitionSession {
    private let recognizer: SFSpeechRecognizer
    private let url: URL
    private let mode: SpeechRecognitionMode
    private let duration: Double
    private let completion: (SpeechChunkOutcome) -> Void

    private var task: SFSpeechRecognitionTask?
    private var idleTimer: SwiftSignalKit.Timer?
    private var overallTimer: SwiftSignalKit.Timer?
    private var latestText: String = ""
    private var isCompleted: Bool = false

    init(recognizer: SFSpeechRecognizer, url: URL, mode: SpeechRecognitionMode, duration: Double, completion: @escaping (SpeechChunkOutcome) -> Void) {
        self.recognizer = recognizer
        self.url = url
        self.mode = mode
        self.duration = duration
        self.completion = completion
    }

    deinit {
        self.idleTimer?.invalidate()
        self.overallTimer?.invalidate()
        if !self.isCompleted {
            self.task?.cancel()
        }
    }

    func start() {
        let request = SFSpeechURLRecognitionRequest(url: self.url)
        request.taskHint = .dictation
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        request.requiresOnDeviceRecognition = self.mode == .onDevice
        request.shouldReportPartialResults = true

        let overallTimer = SwiftSignalKit.Timer(timeout: max(90.0, self.duration * 4.0 + 30.0), repeat: false, completion: { [weak self] in
            guard let self else {
                return
            }
            self.fail(.timedOut)
        }, queue: Queue.mainQueue())
        self.overallTimer = overallTimer
        overallTimer.start()
        // The first result of a long on-device recognition can take a while, later partials arrive continuously
        self.restartIdleTimer(timeout: max(recognitionIdleTimeout, self.duration))

        let task = self.recognizer.recognitionTask(with: request, resultHandler: { [weak self] result, error in
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                self.handle(result: result, error: error)
            }
        })
        if self.isCompleted {
            task.cancel()
        } else {
            self.task = task
        }
    }

    func cancel() {
        if self.isCompleted {
            return
        }
        self.isCompleted = true
        self.invalidateTimers()
        self.task?.cancel()
        self.task = nil
    }

    private func invalidateTimers() {
        self.idleTimer?.invalidate()
        self.idleTimer = nil
        self.overallTimer?.invalidate()
        self.overallTimer = nil
    }

    private func restartIdleTimer(timeout: Double = recognitionIdleTimeout) {
        self.idleTimer?.invalidate()
        let idleTimer = SwiftSignalKit.Timer(timeout: timeout, repeat: false, completion: { [weak self] in
            guard let self else {
                return
            }
            self.fail(.timedOut)
        }, queue: Queue.mainQueue())
        self.idleTimer = idleTimer
        idleTimer.start()
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if self.isCompleted {
            return
        }
        if let result {
            let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                self.latestText = text
            }
            if result.isFinal {
                self.complete(.text(self.latestText))
                return
            }
            self.restartIdleTimer()
        }
        if let error {
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 1110 || nsError.code == 203) {
                // An error is not a final result. Keep any partial text retryable, even when
                // Apple's recognizer reports "no speech" after having produced a partial.
                self.fail(.noSpeech)
            } else {
                // SuperGram: a partial result is never silently reported as a final one
                self.fail(.recognizerUnavailable)
            }
        }
    }

    /// Keeps whatever was recognized so far: the caller can retry with another mode and, failing that,
    /// still show the text as a non-final (retryable) transcription instead of losing it.
    private func fail(_ error: LocalAudioTranscriptionError) {
        if self.latestText.isEmpty {
            self.complete(.failed(error))
        } else {
            self.complete(.partial(self.latestText, error))
        }
    }

    private func complete(_ outcome: SpeechChunkOutcome) {
        if self.isCompleted {
            return
        }
        self.isCompleted = true
        self.invalidateTimers()
        // SuperGram: finish() would keep recognizing the whole file in the background after a timeout or error
        self.task?.cancel()
        self.task = nil
        let completion = self.completion
        // SuperGram: the owner releases this session from inside the callback, so it must not run on our own stack
        Queue.mainQueue().justDispatch {
            completion(outcome)
        }
    }
}

@available(iOS 13.0, *)
private final class LocalTranscriptionContext {
    private let url: URL
    private let duration: Double
    private let recognizer: SFSpeechRecognizer
    private var primaryMode: SpeechRecognitionMode
    private var fallbackMode: SpeechRecognitionMode?
    private let shouldChunk: Bool
    private let completion: (LocalAudioTranscriptionOutcome) -> Void

    private var chunks: [(start: Double, duration: Double)] = []
    private var chunkIndex: Int = 0
    /// Best text an earlier attempt at the current chunk produced. Retrying in the other recognition
    /// mode starts from scratch, so without this a retry that hears nothing would throw the text away.
    private var retainedChunkText: String = ""
    private var texts: [String] = []
    private var isPartialResult: Bool = false
    private var currentExportSession: AVAssetExportSession?
    private var currentChunkURL: URL?
    private var currentRecognition: SpeechRecognitionSession?
    private var isFinished: Bool = false

    init(url: URL, duration: Double, recognizer: SFSpeechRecognizer, primaryMode: SpeechRecognitionMode, fallbackMode: SpeechRecognitionMode?, shouldChunk: Bool, completion: @escaping (LocalAudioTranscriptionOutcome) -> Void) {
        self.url = url
        self.duration = duration
        self.recognizer = recognizer
        self.primaryMode = primaryMode
        self.fallbackMode = fallbackMode
        self.shouldChunk = shouldChunk
        self.completion = completion
    }

    deinit {
        self.cleanup()
    }

    func start() {
        if self.shouldChunk && self.duration > chunkingThresholdDuration {
            var chunks: [(start: Double, duration: Double)] = []
            var start: Double = 0.0
            while start < self.duration {
                var length = min(maximumChunkDuration, self.duration - start)
                if self.duration - (start + length) < minimumTailChunkDuration {
                    length = self.duration - start
                }
                chunks.append((start: start, duration: length))
                start += length
            }
            self.chunks = chunks
        }
        self.processNextChunk()
    }

    func cancel() {
        if self.isFinished {
            return
        }
        self.isFinished = true
        self.cleanup()
    }

    private func processNextChunk() {
        if self.isFinished {
            return
        }
        if self.chunks.isEmpty {
            self.recognize(url: self.url, duration: self.duration)
            return
        }
        if self.chunkIndex >= self.chunks.count {
            self.finishWithCollectedText()
            return
        }

        let chunk = self.chunks[self.chunkIndex]
        let asset = AVURLAsset(url: self.url)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            self.finish(.failure(.conversionFailed))
            return
        }
        let chunkURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("supergram-transcription-\(UInt64.random(in: 0 ... UInt64.max)).m4a")
        exportSession.outputURL = chunkURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = CMTimeRange(start: CMTime(seconds: chunk.start, preferredTimescale: 1000), duration: CMTime(seconds: chunk.duration, preferredTimescale: 1000))
        self.currentExportSession = exportSession
        self.currentChunkURL = chunkURL

        let chunkDuration = chunk.duration
        exportSession.exportAsynchronously { [weak self] in
            Queue.mainQueue().async {
                guard let self, !self.isFinished, self.currentChunkURL == chunkURL, let exportSession = self.currentExportSession else {
                    let _ = try? FileManager.default.removeItem(at: chunkURL)
                    return
                }
                self.currentExportSession = nil
                if exportSession.status == .completed {
                    self.recognize(url: chunkURL, duration: chunkDuration)
                } else {
                    self.finish(.failure(.conversionFailed))
                }
            }
        }
    }

    private func recognize(url: URL, duration: Double) {
        let session = SpeechRecognitionSession(recognizer: self.recognizer, url: url, mode: self.primaryMode, duration: duration, completion: { [weak self] outcome in
            guard let self, !self.isFinished else {
                return
            }
            self.currentRecognition = nil
            switch outcome {
            case let .text(text):
                if text.isEmpty && !self.retainedChunkText.isEmpty {
                    // The retry in the other mode heard nothing: keep what the first attempt produced
                    self.isPartialResult = true
                    self.chunkRecognized(text: self.takeRetainedChunkText())
                } else {
                    self.retainedChunkText = ""
                    self.chunkRecognized(text: text)
                }
            case let .partial(text, _):
                // Recognition stopped early: retry in the other mode, or keep the text as a pending result
                self.retainChunkText(text)
                if !self.switchToFallbackMode(url: url, duration: duration) {
                    self.isPartialResult = true
                    self.chunkRecognized(text: self.takeRetainedChunkText())
                }
            case let .failed(error):
                if !self.switchToFallbackMode(url: url, duration: duration) {
                    if !self.retainedChunkText.isEmpty {
                        // An earlier attempt at this chunk did produce text: never throw it away
                        self.isPartialResult = true
                        self.chunkRecognized(text: self.takeRetainedChunkText())
                    } else if self.texts.isEmpty {
                        self.finish(.failure(error))
                    } else {
                        // Earlier chunks produced text: keep it as a non-final result instead of losing everything
                        self.isPartialResult = true
                        self.removeCurrentChunkFile()
                        self.finishWithCollectedText()
                    }
                }
            }
        })
        self.currentRecognition = session
        session.start()
    }

    private func retainChunkText(_ text: String) {
        if text.count > self.retainedChunkText.count {
            self.retainedChunkText = text
        }
    }

    private func takeRetainedChunkText() -> String {
        let text = self.retainedChunkText
        self.retainedChunkText = ""
        return text
    }

    /// Continues in the other recognition mode, if one is still available.
    private func switchToFallbackMode(url: URL, duration: Double) -> Bool {
        guard let fallbackMode = self.fallbackMode else {
            return false
        }
        self.primaryMode = fallbackMode
        self.fallbackMode = nil
        self.recognize(url: url, duration: duration)
        return true
    }

    private func chunkRecognized(text: String) {
        if !text.isEmpty {
            self.texts.append(text)
        }
        self.removeCurrentChunkFile()
        if self.chunks.isEmpty {
            self.finishWithCollectedText()
        } else {
            self.chunkIndex += 1
            self.processNextChunk()
        }
    }

    private func finishWithCollectedText() {
        let text = self.texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            self.finish(.failure(.noSpeech))
        } else {
            // A partial result stays pending: the bubble shows the text and a tap runs the transcription again
            self.finish(.success(LocallyTranscribedAudio(text: text, isFinal: !self.isPartialResult)))
        }
    }

    private func removeCurrentChunkFile() {
        if let currentChunkURL = self.currentChunkURL {
            self.currentChunkURL = nil
            let _ = try? FileManager.default.removeItem(at: currentChunkURL)
        }
    }

    private func cleanup() {
        if let exportSession = self.currentExportSession {
            self.currentExportSession = nil
            exportSession.cancelExport()
        }
        if let recognition = self.currentRecognition {
            self.currentRecognition = nil
            recognition.cancel()
        }
        self.removeCurrentChunkFile()
    }

    private func finish(_ outcome: LocalAudioTranscriptionOutcome) {
        if self.isFinished {
            return
        }
        self.isFinished = true
        self.cleanup()
        let completion = self.completion
        // SuperGram: delivering the outcome releases the subscription (and this object), so it must not run on our own stack
        Queue.mainQueue().justDispatch {
            completion(outcome)
        }
    }
}

/// Transcribes an audio file (m4a/AAC) with Apple Speech.
/// - Parameters:
///   - duration: duration hint used when the file duration can't be read.
///   - localeIdentifiers: candidates in priority order, the first one supported by Speech is used.
///   - requiresOnDeviceRecognition: audio never leaves the device.
public func transcribeAudioLocally(path: String, duration: Double?, localeIdentifiers: [String], requiresOnDeviceRecognition: Bool) -> Signal<LocalAudioTranscriptionOutcome, NoError> {
    guard #available(iOS 13.0, *) else {
        return .single(.failure(.recognizerUnavailable))
    }
    let url = URL(fileURLWithPath: path)
    return speechRecognitionAuthorization()
    |> mapToSignal { isAuthorized -> Signal<LocalAudioTranscriptionOutcome, NoError> in
        if !isAuthorized {
            return .single(.failure(.notAuthorized))
        }
        return audioFileDuration(url: url, fallback: duration)
        |> mapToSignal { audioDuration -> Signal<LocalAudioTranscriptionOutcome, NoError> in
            return Signal<LocalAudioTranscriptionOutcome, NoError> { subscriber in
                let supportedLocales = SFSpeechRecognizer.supportedLocales()
                var resolvedLocale: Locale?
                var resolvedRecognizer: SFSpeechRecognizer?
                for identifier in localeIdentifiers {
                    if let locale = resolveLocalTranscriptionLocale(identifier: identifier, supportedLocales: supportedLocales), let candidate = SFSpeechRecognizer(locale: locale) {
                        if resolvedLocale == nil {
                            resolvedLocale = locale
                        }
                        // "auto" may contain a server-only locale followed by an installed
                        // on-device locale. Check eligibility before committing to a candidate.
                        if !requiresOnDeviceRecognition || candidate.supportsOnDeviceRecognition {
                            resolvedLocale = locale
                            resolvedRecognizer = candidate
                            break
                        }
                    }
                }
                guard let locale = resolvedLocale else {
                    subscriber.putNext(.failure(.localeUnsupported(resolvedLocale?.identifier ?? localeIdentifiers.first ?? "")))
                    subscriber.putCompletion()
                    return EmptyDisposable
                }
                guard let recognizer = resolvedRecognizer else {
                    subscriber.putNext(.failure(.onDeviceUnsupported(locale.identifier)))
                    subscriber.putCompletion()
                    return EmptyDisposable
                }
                recognizer.defaultTaskHint = .dictation

                let supportsOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
                let primaryMode: SpeechRecognitionMode
                if requiresOnDeviceRecognition {
                    if !supportsOnDeviceRecognition {
                        subscriber.putNext(.failure(.onDeviceUnsupported(locale.identifier)))
                        subscriber.putCompletion()
                        return EmptyDisposable
                    }
                    primaryMode = .onDevice
                } else if supportsOnDeviceRecognition {
                    // Prefer the installed model for short recordings as well. A server request
                    // is permitted only after the user explicitly turns Offline Only off.
                    primaryMode = .onDevice
                } else if recognizer.isAvailable {
                    primaryMode = .server
                } else {
                    subscriber.putNext(.failure(.recognizerUnavailable))
                    subscriber.putCompletion()
                    return EmptyDisposable
                }

                // Chunking only compensates for the server request length limit
                let shouldChunk = primaryMode == .server

                let context = LocalTranscriptionContext(url: url, duration: audioDuration, recognizer: recognizer, primaryMode: primaryMode, fallbackMode: nil, shouldChunk: shouldChunk, completion: { outcome in
                    subscriber.putNext(outcome)
                    subscriber.putCompletion()
                })
                context.start()

                return ActionDisposable {
                    Queue.mainQueue().async {
                        context.cancel()
                    }
                }
            }
            |> runOn(Queue.mainQueue())
        }
    }
}

public func transcribeAudio(path: String, appLocale: String, preferredLocale: String, requiresOnDeviceRecognition: Bool) -> Signal<LocallyTranscribedAudio?, NoError> {
    var localeIdentifiers: [String] = []
    if preferredLocale.isEmpty || preferredLocale == "auto" {
        localeIdentifiers.append(appLocale)
        localeIdentifiers.append(contentsOf: Locale.preferredLanguages)
    } else {
        localeIdentifiers.append(preferredLocale)
    }
    return transcribeAudioLocally(path: path, duration: nil, localeIdentifiers: localeIdentifiers, requiresOnDeviceRecognition: requiresOnDeviceRecognition)
    |> map { outcome -> LocallyTranscribedAudio? in
        if case let .success(result) = outcome {
            return result
        } else {
            return nil
        }
    }
}
