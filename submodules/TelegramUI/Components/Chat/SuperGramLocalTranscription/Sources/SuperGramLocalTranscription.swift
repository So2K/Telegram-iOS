import Foundation
import NaturalLanguage
import SwiftSignalKit
import Postbox
import TelegramCore
import Display
import AccountContext
import TelegramPresentationData
import TelegramUIPreferences
import UndoUI
import ConvertOpusToAAC
import LocalAudioTranscription

// SuperGram: shared local (Apple Speech) transcription pipeline for voice and round video messages.

// MARK: - Policy

/// Decides how a voice or round video message is transcribed.
/// The chat nodes use the same policy for the button layout and for the tap handler.
public struct SuperGramTranscriptionPolicy: Equatable {
    /// Apple Speech is used instead of `messages.transcribeAudio`; no Premium upsell, trial or cooldown applies.
    public let useLocalTranscription: Bool
    /// The transcription button may be displayed for this message at all.
    public let isTranscriptionAllowed: Bool

    public init(context: AccountContext, message: Message, isPremium: Bool, providedByGroupBoost: Bool) {
        let settings = context.sharedContext.currentMediaDisplaySettings.with { $0 }
        let forceLocal = context.sharedContext.immediateExperimentalUISettings.localTranscription
        let localEnabled = settings.localVoiceTranscription || forceLocal

        if message.containsSecretMedia {
            // Self-destructing and view-once media is never revealed without being played
            self.useLocalTranscription = false
            self.isTranscriptionAllowed = false
        } else if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
            // Server transcription is impossible in secret chats; the local one is allowed only when the audio never leaves the device
            let isAllowed = localEnabled && settings.voiceTranscriptionOnDeviceOnly && message.minAutoremoveOrClearTimeout == nil
            self.useLocalTranscription = isAllowed
            self.isTranscriptionAllowed = isAllowed && settings.showVoiceTranscriptionButton
        } else {
            if !localEnabled {
                self.useLocalTranscription = false
            } else if forceLocal || settings.voiceTranscriptionOnDeviceOnly {
                self.useLocalTranscription = true
            } else {
                // Premium users and boosted groups keep Telegram's server transcription
                self.useLocalTranscription = !isPremium && !providedByGroupBoost
            }
            self.isTranscriptionAllowed = settings.showVoiceTranscriptionButton
        }
    }

    /// Secret chat messages live in the local namespaces; everything else must be a cloud message.
    public func canTranscribe(messageId: MessageId) -> Bool {
        if messageId.namespace == Namespaces.Message.Cloud {
            return true
        }
        if self.useLocalTranscription && messageId.peerId.namespace == Namespaces.Peer.SecretChat {
            return messageId.namespace == Namespaces.Message.Local || messageId.namespace == Namespaces.Message.SecretIncoming
        }
        return false
    }
}

// MARK: - Errors

public func superGramLocalTranscriptionErrorText(_ error: LocalAudioTranscriptionError, strings: PresentationStrings) -> String {
    let isRussian = strings.baseLanguageCode.lowercased().hasPrefix("ru")
    let localeName: (String) -> String = { identifier in
        let displayLocale = Locale(identifier: isRussian ? "ru" : "en")
        return displayLocale.localizedString(forIdentifier: identifier) ?? identifier
    }
    switch error {
    case .notAuthorized:
        return isRussian ? "Нет доступа к распознаванию речи. Разрешите его для SuperGram в настройках iOS." : "Speech Recognition access is turned off. Allow it for SuperGram in iOS Settings."
    case let .localeUnsupported(identifier):
        let name = localeName(identifier)
        return isRussian ? "Язык «\(name)» не поддерживается распознаванием речи iOS. Выберите другой язык голосовых в настройках." : "\(name) is not supported by iOS speech recognition. Choose another voice message language in Settings."
    case let .onDeviceUnsupported(identifier):
        let name = localeName(identifier)
        return isRussian ? "Локальное распознавание для языка «\(name)» недоступно на этом устройстве. Выберите другой язык голосовых в настройках." : "On-device recognition for \(name) is unavailable on this device. Choose another voice message language in Settings."
    case .recognizerUnavailable:
        return isRussian ? "Распознавание речи сейчас недоступно. Проверьте выбранный язык голосовых в настройках и попробуйте ещё раз." : "Speech recognition is unavailable right now. Check the voice message language in Settings and try again."
    case .noSpeech:
        return strings.Message_AudioTranscription_ErrorEmpty
    case .timedOut:
        return isRussian ? "Расшифровка заняла слишком много времени. Попробуйте ещё раз." : "Transcription took too long. Please try again."
    case .conversionFailed:
        return isRussian ? "Не удалось прочитать звук из этого сообщения." : "Couldn't read the audio of this message."
    case .fetchFailed:
        return isRussian ? "Не удалось загрузить сообщение для расшифровки. Попробуйте ещё раз." : "Couldn't download the message for transcription. Please try again."
    }
}

public func superGramPresentLocalTranscriptionError(context: AccountContext, error: LocalAudioTranscriptionError, present: (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let text = superGramLocalTranscriptionErrorText(error, strings: presentationData.strings)
    let isRussian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")

    var customUndoText: String?
    if case .notAuthorized = error {
        customUndoText = isRussian ? "Настройки" : "Settings"
    }
    let controller = UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: 6.0, customUndoText: customUndoText), elevatedLayout: false, position: .top, animateInAsReplacement: false, action: { action in
        if case .undo = action, case .notAuthorized = error {
            context.sharedContext.applicationBindings.openSettings()
        }
        return false
    })
    present(controller)
}

// MARK: - Locale

private func superGramPredictedChatLanguage(context: AccountContext, message: Message) -> Signal<String?, NoError> {
    let peerId = message.id.peerId
    if peerId.namespace == Namespaces.Peer.SecretChat {
        return .single(nil)
    }
    return context.account.postbox.transaction { transaction -> [String] in
        var texts: [String] = []
        transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 60, { message in
            if texts.count >= 24 {
                return false
            }
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 10 {
                texts.append(String(text.prefix(256)))
            }
            return true
        })
        return texts
    }
    |> deliverOn(Queue.concurrentDefaultQueue())
    |> map { texts -> String? in
        let recognizer = NLLanguageRecognizer()
        var weights: [String: Int] = [:]
        var totalWeight = 0
        for text in texts {
            recognizer.processString(text)
            if let language = recognizer.dominantLanguage, language != .undetermined {
                weights[language.rawValue, default: 0] += text.count
                totalWeight += text.count
            }
            recognizer.reset()
        }
        guard totalWeight >= 40, let best = weights.max(by: { $0.value < $1.value }) else {
            return nil
        }
        return best.key
    }
}

private func superGramLocaleIdentifiers(predictedLanguage: String?, appLocale: String) -> [String] {
    // "auto": predicted chat language, then the app language, then the system languages
    var candidates: [String] = []
    if let predictedLanguage {
        candidates.append(predictedLanguage)
    }
    candidates.append(appLocale)
    candidates.append(contentsOf: Locale.preferredLanguages)
    candidates.append(Locale.current.identifier)

    var result: [String] = []
    for candidate in candidates {
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && !result.contains(value) {
            result.append(value)
        }
    }
    return result
}

// MARK: - Fetch

/// No progress for this long means the download is stuck and the transcription gives up.
private let superGramFetchIdleTimeout: Double = 90.0
/// Decoding a voice message or a round video takes seconds; anything longer is a hang.
private let superGramConversionTimeout: Double = 120.0
/// Last line of defence: the transcription button must never spin forever.
private let superGramJobTimeout: Double = 15.0 * 60.0
/// A finished job keeps counting as active for this long after its result is written, so that a
/// layout pass landing between the postbox write and the message view update cannot collapse the bubble.
private let superGramActiveKeyReleaseGrace: Double = 0.5

private final class SuperGramIdleWatchdog {
    private let timeout: Double
    private let action: () -> Void
    private var timer: SwiftSignalKit.Timer?
    private var lastActivityTimestamp: Double

    init(timeout: Double, action: @escaping () -> Void) {
        self.timeout = timeout
        self.action = action
        self.lastActivityTimestamp = CFAbsoluteTimeGetCurrent()
    }

    deinit {
        self.timer?.invalidate()
    }

    func start() {
        self.lastActivityTimestamp = CFAbsoluteTimeGetCurrent()
        let timer = SwiftSignalKit.Timer(timeout: 5.0, repeat: true, completion: { [weak self] in
            guard let self else {
                return
            }
            if CFAbsoluteTimeGetCurrent() - self.lastActivityTimestamp > self.timeout {
                self.invalidate()
                self.action()
            }
        }, queue: Queue.mainQueue())
        self.timer = timer
        timer.start()
    }

    func noteActivity() {
        self.lastActivityTimestamp = CFAbsoluteTimeGetCurrent()
    }

    func invalidate() {
        self.timer?.invalidate()
        self.timer = nil
    }
}

private func superGramFetchCompleteResourcePath(context: AccountContext, message: Message, file: TelegramMediaFile) -> Signal<String?, NoError> {
    return Signal { subscriber in
        let isCompleted = Atomic<Bool>(value: false)
        let complete: (String?) -> Void = { path in
            if !isCompleted.swap(true) {
                subscriber.putNext(path)
                subscriber.putCompletion()
            }
        }

        // A failed download must end the transcription (FetchV2 failures can also be silent, so watch the progress)
        let watchdog = SuperGramIdleWatchdog(timeout: superGramFetchIdleTimeout, action: {
            complete(nil)
        })
        watchdog.start()

        let resource = EngineMediaResource(file.resource)
        let resourceReference = FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource)
        let fetchDisposable = context.engine.resources.fetch(reference: resourceReference, userLocation: .peer(message.id.peerId), userContentType: MediaResourceUserContentType(file: file)).startStandalone(error: { _ in
            complete(nil)
        })
        let dataDisposable = (context.engine.resources.data(resource: resource)
        |> filter { data in
            return data.isComplete
        }
        |> take(1)).startStandalone(next: { data in
            complete(data.path)
        })
        // Only a status that actually changed counts as progress: a download stuck at the same
        // percentage must not keep the watchdog alive forever
        var previousStatus: EngineMediaResource.FetchStatus?
        let statusDisposable = (context.engine.resources.status(resource: resource)
        |> deliverOnMainQueue).startStandalone(next: { status in
            if previousStatus != status {
                previousStatus = status
                watchdog.noteActivity()
            }
        })

        return ActionDisposable {
            fetchDisposable.dispose()
            dataDisposable.dispose()
            statusDisposable.dispose()
            Queue.mainQueue().async {
                watchdog.invalidate()
            }
        }
    }
    |> runOn(Queue.mainQueue())
}

// MARK: - Manager

/// Runs local transcriptions one at a time, deduplicates requests per message and keeps a started
/// transcription running (and storing its result) when the requesting chat node goes away.
public final class SuperGramLocalTranscriptionManager {
    public static let shared = SuperGramLocalTranscriptionManager()

    private static let maxConcurrentRecognitions = 1

    private struct JobKey: Hashable {
        let accountId: AccountRecordId
        let messageId: MessageId
    }

    private final class Job {
        let subscribers = Bag<(LocalAudioTranscriptionOutcome) -> Void>()
        let disposable = MetaDisposable()
    }

    // Accessed on the main queue only
    private var jobs: [JobKey: Job] = [:]
    private var runningRecognitions: Int = 0
    private var pendingRecognitions: [(id: Int, start: () -> Void)] = []
    private var nextPendingRecognitionId: Int = 0

    // Read from asynchronous layout
    private let activeKeys = Atomic<[JobKey: ObjectIdentifier]>(value: [:])

    private init() {
    }

    public func isTranscribing(context: AccountContext, messageId: MessageId) -> Bool {
        let key = JobKey(accountId: context.account.id, messageId: messageId)
        return self.activeKeys.with { keys in
            return keys[key] != nil
        }
    }

    /// Emits exactly one outcome. Success and "no speech" are already stored in the message when the outcome arrives;
    /// other failures are not stored, so a later tap retries.
    public func transcribe(context: AccountContext, message: Message, file: TelegramMediaFile) -> Signal<LocalAudioTranscriptionOutcome, NoError> {
        return Signal { subscriber in
            let key = JobKey(accountId: context.account.id, messageId: message.id)
            let job: Job
            let isNewJob: Bool
            if let current = self.jobs[key] {
                job = current
                isNewJob = false
            } else {
                job = Job()
                self.jobs[key] = job
                isNewJob = true
            }

            let index = job.subscribers.add({ outcome in
                subscriber.putNext(outcome)
                subscriber.putCompletion()
            })

            if isNewJob {
                let _ = self.activeKeys.modify { keys in
                    var keys = keys
                    keys[key] = ObjectIdentifier(job)
                    return keys
                }
                self.startJob(job, key: key, context: context, message: message, file: file)
            }

            return ActionDisposable { [weak job] in
                Queue.mainQueue().async {
                    job?.subscribers.remove(index)
                }
            }
        }
        |> runOn(Queue.mainQueue())
    }

    private func startJob(_ job: Job, key: JobKey, context: AccountContext, message: Message, file: TelegramMediaFile) {
        let settings = context.sharedContext.currentMediaDisplaySettings.with { $0 }
        let appLocale = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        let messageId = message.id

        // A stored error must not show up while the retry is running
        for attribute in message.attributes {
            if let attribute = attribute as? AudioTranscriptionMessageAttribute {
                if attribute.text.isEmpty && !attribute.isPending {
                    let _ = context.engine.messages.storeLocallyTranscribedAudio(messageId: messageId, text: "", isFinal: false, error: nil).startStandalone()
                }
                break
            }
        }

        let resolvedMessageAndFile: Signal<(Message, TelegramMediaFile), NoError> = context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
        |> map { engineMessage -> (Message, TelegramMediaFile) in
            guard let engineMessage else {
                return (message, file)
            }
            let updatedMessage = engineMessage._asMessage()
            for media in updatedMessage.media {
                if let updatedFile = media as? TelegramMediaFile, updatedFile.fileId == file.fileId {
                    return (updatedMessage, updatedFile)
                }
            }
            return (updatedMessage, file)
        }

        let pipeline: Signal<LocalAudioTranscriptionOutcome, NoError> = resolvedMessageAndFile
        |> mapToSignal { [weak self] message, file -> Signal<LocalAudioTranscriptionOutcome, NoError> in
            guard let self else {
                return .single(.failure(.recognizerUnavailable))
            }

            let localeIdentifiers: Signal<[String], NoError>
            if settings.voiceTranscriptionLocale.isEmpty || settings.voiceTranscriptionLocale == "auto" {
                localeIdentifiers = superGramPredictedChatLanguage(context: context, message: message)
                |> map { predictedLanguage -> [String] in
                    return superGramLocaleIdentifiers(predictedLanguage: predictedLanguage, appLocale: appLocale)
                }
            } else {
                localeIdentifiers = .single([settings.voiceTranscriptionLocale])
            }

            return combineLatest(superGramFetchCompleteResourcePath(context: context, message: message, file: file), localeIdentifiers)
            |> take(1)
            |> mapToSignal { path, localeIdentifiers -> Signal<LocalAudioTranscriptionOutcome, NoError> in
                guard let path else {
                    return .single(.failure(.fetchFailed))
                }
                let tempFile = EngineTempBox.shared.tempFile(fileName: "audio.m4a")
                // The decoder runs on its own queue and has no failure timeout of its own
                let converted: Signal<String?, NoError> = convertOpusToAAC(sourcePath: path, allocateTempFile: {
                    return tempFile.path
                })
                |> timeout(superGramConversionTimeout, queue: Queue.concurrentDefaultQueue(), alternate: Signal<String?, NoError>.single(nil))

                let recognition: Signal<LocalAudioTranscriptionOutcome, NoError> = converted
                |> mapToSignal { convertedPath -> Signal<LocalAudioTranscriptionOutcome, NoError> in
                    guard let convertedPath else {
                        return .single(.failure(.conversionFailed))
                    }
                    return transcribeAudioLocally(path: convertedPath, duration: file.duration, localeIdentifiers: localeIdentifiers, requiresOnDeviceRecognition: settings.voiceTranscriptionOnDeviceOnly)
                }
                |> afterDisposed {
                    EngineTempBox.shared.dispose(tempFile)
                }
                return self.limitRecognition(recognition)
            }
        }

        // Whatever goes wrong below, the button must leave the in-progress state
        let guardedPipeline: Signal<LocalAudioTranscriptionOutcome, NoError> = pipeline
        |> take(1)
        |> timeout(superGramJobTimeout, queue: Queue.mainQueue(), alternate: Signal<LocalAudioTranscriptionOutcome, NoError>.single(.failure(.timedOut)))

        job.disposable.set((guardedPipeline
        |> deliverOnMainQueue).startStandalone(next: { [weak self] outcome in
            guard let self else {
                return
            }
            self.finishJob(job, key: key, context: context, messageId: messageId, outcome: outcome)
        }, completed: { [weak self] in
            guard let self else {
                return
            }
            // Only reached if the pipeline completed without an outcome
            self.finishJob(job, key: key, context: context, messageId: messageId, outcome: .failure(.recognizerUnavailable))
        }))
    }

    private func finishJob(_ job: Job, key: JobKey, context: AccountContext, messageId: MessageId, outcome: LocalAudioTranscriptionOutcome) {
        guard let current = self.jobs[key], current === job else {
            return
        }
        self.jobs.removeValue(forKey: key)

        let store: Signal<Never, NoError>?
        switch outcome {
        case let .success(result):
            // A result that is not final keeps the attribute pending, so a later tap transcribes again
            store = context.engine.messages.storeLocallyTranscribedAudio(messageId: messageId, text: result.text, isFinal: result.isFinal, error: nil)
        case .failure(.noSpeech):
            store = context.engine.messages.storeLocallyTranscribedAudio(messageId: messageId, text: "", isFinal: true, error: .generic)
        case .failure:
            // Timeouts and other failures are never stored, a partial text must not become final
            store = nil
        }

        let releaseKey: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            let _ = self.activeKeys.modify { keys in
                var keys = keys
                // A retry can start during the postbox/layout grace interval. The earlier
                // job's delayed release must not clear the retry's in-progress marker.
                if keys[key] == ObjectIdentifier(job) {
                    keys.removeValue(forKey: key)
                }
                return keys
            }
        }
        let subscribers = job.subscribers.copyItems()
        job.subscribers.removeAll()
        job.disposable.dispose()
        let notifySubscribers: () -> Void = {
            for subscriber in subscribers {
                subscriber(outcome)
            }
        }
        if let store {
            // The message must carry the result before it stops counting as "being transcribed",
            // otherwise a layout pass in between sees neither and collapses the bubble.
            // The postbox write completing and the message view carrying the new attribute are two
            // separate hops onto the main queue, so hold the key for one more moment after the write:
            // both chat nodes fall back to `.collapsed` when nothing is running any more, and that
            // fallback must not win the race against the attribute becoming observable.
            let _ = (store
            |> deliverOnMainQueue).startStandalone(completed: {
                notifySubscribers()
                Queue.mainQueue().after(superGramActiveKeyReleaseGrace, {
                    releaseKey()
                })
            })
        } else {
            releaseKey()
            notifySubscribers()
        }
    }

    private func limitRecognition(_ signal: Signal<LocalAudioTranscriptionOutcome, NoError>) -> Signal<LocalAudioTranscriptionOutcome, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            let id = self.nextPendingRecognitionId
            self.nextPendingRecognitionId += 1

            var isStarted = false
            var isReleased = false
            let release: () -> Void = {
                if isStarted && !isReleased {
                    isReleased = true
                    self.runningRecognitions -= 1
                    self.startPendingRecognitions()
                }
            }
            let start: () -> Void = {
                isStarted = true
                self.runningRecognitions += 1
                disposable.set((signal
                |> deliverOnMainQueue).startStandalone(next: { outcome in
                    subscriber.putNext(outcome)
                }, completed: {
                    release()
                    subscriber.putCompletion()
                }))
            }

            if self.runningRecognitions < SuperGramLocalTranscriptionManager.maxConcurrentRecognitions {
                start()
            } else {
                self.pendingRecognitions.append((id: id, start: start))
            }

            return ActionDisposable {
                Queue.mainQueue().async {
                    if !isStarted {
                        self.pendingRecognitions.removeAll(where: { $0.id == id })
                    }
                    disposable.dispose()
                    release()
                }
            }
        }
        |> runOn(Queue.mainQueue())
    }

    private func startPendingRecognitions() {
        while self.runningRecognitions < SuperGramLocalTranscriptionManager.maxConcurrentRecognitions && !self.pendingRecognitions.isEmpty {
            let pending = self.pendingRecognitions.removeFirst()
            pending.start()
        }
    }
}
