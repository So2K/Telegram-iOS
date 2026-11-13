import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import NaturalLanguage
import TelegramCore
import SwiftUI
import Translation
import Combine

// Incuding at least one Objective-C class in a swift file ensures that it doesn't get stripped by the linker
private final class LinkHelperClass: NSObject {
}

public var supportedTranslationLanguages = [
    "af",
    "sq",
    "am",
    "ar",
    "hy",
    "az",
    "eu",
    "be",
    "bn",
    "bs",
    "bg",
    "ca",
    "ceb",
    "zh",
    "co",
    "hr",
    "cs",
    "da",
    "nl",
    "en",
    "eo",
    "et",
    "fi",
    "fr",
    "fy",
    "gl",
    "ka",
    "de",
    "el",
    "gu",
    "ht",
    "ha",
    "haw",
    "he",
    "hi",
    "hmn",
    "hu",
    "is",
    "ig",
    "id",
    "ga",
    "it",
    "ja",
    "jv",
    "kn",
    "kk",
    "km",
    "rw",
    "ko",
    "ku",
    "ky",
    "lo",
    "lv",
    "lt",
    "lb",
    "mk",
    "mg",
    "ms",
    "ml",
    "mt",
    "mi",
    "mr",
    "mn",
    "my",
    "ne",
    "no",
    "ny",
    "or",
    "ps",
    "fa",
    "pl",
    "pt",
    "pt-BR",
    "pa",
    "ro",
    "ru",
    "sm",
    "gd",
    "sr",
    "st",
    "sn",
    "sd",
    "si",
    "sk",
    "sl",
    "so",
    "es",
    "su",
    "sw",
    "sv",
    "tl",
    "tg",
    "ta",
    "tt",
    "te",
    "th",
    "tr",
    "tk",
    "uk",
    "ur",
    "ug",
    "uz",
    "vi",
    "cy",
    "xh",
    "yi",
    "yo",
    "zu"
]

public var popularTranslationLanguages = [
    "en",
    "ar",
    "zh",
    "fr",
    "de",
    "it",
    "ja",
    "ko",
    "pt-BR",
    "ru",
    "es",
    "uk"
]

@available(iOS 12.0, *)
func sgTranslationLanguageRecognizer() -> NLLanguageRecognizer {
    let key = "SuperGram.Translation.LanguageRecognizer"
    if let recognizer = Thread.current.threadDictionary[key] as? NLLanguageRecognizer {
        return recognizer
    }
    let recognizer = NLLanguageRecognizer()
    Thread.current.threadDictionary[key] = recognizer
    return recognizer
}

public func effectiveIgnoredTranslationLanguages(context: AccountContext, ignoredLanguages: [String]?) -> Set<String> {
    var baseLang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    let rawSuffix = "-raw"
    if baseLang.hasSuffix(rawSuffix) {
        baseLang = String(baseLang.dropLast(rawSuffix.count))
    }
    
    var dontTranslateLanguages = Set<String>()
    if let ignoredLanguages = ignoredLanguages {
        dontTranslateLanguages = Set(ignoredLanguages)
    } else {
        dontTranslateLanguages.insert(baseLang)
        for language in systemLanguageCodes() {
            dontTranslateLanguages.insert(language)
        }
    }
    return dontTranslateLanguages
}

public func normalizeTranslationLanguage(_ code: String) -> String {
    var code = code
    if code.contains("-") {
        code = code.components(separatedBy: "-").first ?? code
    }
    if code == "nb" {
        code = "no"
    }
    return code
}

public func canTranslateChats(context: AccountContext) -> Bool {
    let translationConfiguration = TranslationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
    var chatTranslationAvailable = true
    switch translationConfiguration.auto {
    case .system:
        if #available(iOS 18.0, *) {
        } else {
            chatTranslationAvailable = false
        }
    case .alternative, .disabled:
        chatTranslationAvailable = false
    default:
        break
    }
    // MARK: Swiftgram
    // SuperGram: behind sgTranslateChatsWithoutPremium (Swiftgram: `|| true`). Requests still go to Telegram or on-device, never to Google.
    return chatTranslationAvailable || sgCanTranslateChatsWithoutPremium()
}

public func canTranslateText(context: AccountContext, text: String, showTranslate: Bool, showTranslateIfTopical: Bool = false, ignoredLanguages: [String]?) -> (canTranslate: Bool, language: String?) {
    guard showTranslate || showTranslateIfTopical, text.count > 0 else {
        return (false, nil)
    }

    let translationConfiguration = TranslationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
    var translateButtonAvailable = false
    switch translationConfiguration.manual {
    case .enabled, .alternative:
        translateButtonAvailable = true
    case .system:
        if #available(iOS 18.0, *) {
            translateButtonAvailable = true
        }
    default:
        break
    }

    let showTranslate = showTranslate && translateButtonAvailable
        
    if #available(iOS 12.0, *) {
        if context.sharedContext.immediateExperimentalUISettings.disableLanguageRecognition {
            return (true, nil)
        }
                
        let dontTranslateLanguages = effectiveIgnoredTranslationLanguages(context: context, ignoredLanguages: ignoredLanguages)
        
        let text = String(text.prefix(64))
        let languageRecognizer = sgTranslationLanguageRecognizer()
        languageRecognizer.processString(text)
        let hypotheses = languageRecognizer.languageHypotheses(withMaximum: 3)
        languageRecognizer.reset()
        
        var supportedTranslationLanguages = supportedTranslationLanguages
        if !showTranslate && showTranslateIfTopical {
            supportedTranslationLanguages = ["uk", "ru"]
        }
                
        let filteredLanguages = hypotheses.filter { supportedTranslationLanguages.contains(normalizeTranslationLanguage($0.key.rawValue)) }.sorted(by: { $0.value > $1.value })
        if let language = filteredLanguages.first {
            let languageCode = normalizeTranslationLanguage(language.key.rawValue)
            return (!dontTranslateLanguages.contains(languageCode), languageCode)
        } else {
            return (false, nil)
        }
    } else {
        return (false, nil)
    }
}

public func systemLanguageCodes() -> [String] {
    var languages: [String] = []
    for language in Locale.preferredLanguages.prefix(2) {
        let language = language.components(separatedBy: "-").first ?? language
        languages.append(language)
    }
    if languages.count == 2 && languages != ["en", "ru"] {
        languages = Array(languages.prefix(1))
    }
    return languages
}

@available(iOS 13.0, *)
class ExternalTranslationTrigger: ObservableObject {
    @Published var shouldInvalidate: Int = 0
}

@available(iOS 18.0, *)
private struct TranslationViewImpl: View {
    @State private var configuration: TranslationSession.Configuration?
    @ObservedObject var externalCondition: ExternalTranslationTrigger
    private let taskContainer: Atomic<ExperimentalInternalTranslationServiceImpl.TranslationTaskContainer>
    
    init(externalCondition: ExternalTranslationTrigger, taskContainer: Atomic<ExperimentalInternalTranslationServiceImpl.TranslationTaskContainer>) {
        self.externalCondition = externalCondition
        self.taskContainer = taskContainer
    }
    
    var body: some View {
        Color.clear
        .frame(width: 1.0, height: 1.0)
        .onAppear {
            // A request can be enqueued before SwiftUI starts observing the trigger counter.
            self.scheduleNextTask()
        }
        .onChange(of: self.externalCondition.shouldInvalidate) { _ in
            self.scheduleNextTask()
        }
        .translationTask(self.configuration, action: { session in
            let task = self.taskContainer.with { taskContainer -> ExperimentalInternalTranslationServiceImpl.TranslationTask? in
                guard taskContainer.activeTask == nil, !taskContainer.tasks.isEmpty else {
                    return nil
                }
                let next = taskContainer.tasks[0]
                guard session.sourceLanguage == Locale.Language(identifier: next.fromLang), session.targetLanguage == Locale.Language(identifier: next.toLang) else {
                    // An old SwiftUI callback may arrive after a timeout changed the configuration.
                    return nil
                }
                let task = taskContainer.tasks.removeFirst()
                taskContainer.activeTask = task
                return task
            }
            guard let task else {
                return
            }

            // An unstructured child gives signal disposal and the watchdog a cancellation handle.
            // Cancellation of SwiftUI's parent task must also cancel that child explicitly.
            var clientIdentifierMap: [String: AnyHashable] = [:]
            var requestTexts: [String: String] = [:]
            var emptyResults: [AnyHashable: String] = [:]
            for (key, text) in task.texts {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyResults[key] = text
                } else {
                    let identifier = String(requestTexts.count)
                    clientIdentifierMap[identifier] = key
                    requestTexts[identifier] = text
                }
            }
            let sourceLanguage = task.fromLang
            let targetLanguage = task.toLang
            // Only String keys cross the async task boundary. Arbitrary AnyHashable keys
            // stay in this view's main-actor context and are restored after awaiting.
            let worker = Task { @MainActor () -> [String: String]? in
                do {
                    try Task.checkCancellation()
                    let availability = LanguageAvailability()
                    let status = await availability.status(from: Locale.Language(identifier: sourceLanguage), to: Locale.Language(identifier: targetLanguage))
                    guard status != .unsupported else {
                        return nil
                    }
                    try Task.checkCancellation()
                    let requests = requestTexts.map { identifier, text in
                        return TranslationSession.Request(sourceText: text, clientIdentifier: identifier)
                    }
                    if requests.isEmpty {
                        return [:]
                    }
                    // Apple shows its model-download consent UI when a supported pair is not installed.
                    let responses = try await session.translations(from: requests)
                    try Task.checkCancellation()
                    var result: [String: String] = [:]
                    for response in responses {
                        if let identifier = response.clientIdentifier, requestTexts[identifier] != nil {
                            result[identifier] = response.targetText
                        }
                    }
                    return result.count == requestTexts.count ? result : nil
                } catch {
                    // Framework errors can include source text. Do not print message contents.
                    return nil
                }
            }
            task.setCancellation {
                worker.cancel()
            }
            let translatedTexts = await withTaskCancellationHandler(operation: {
                return await worker.value
            }, onCancel: {
                worker.cancel()
            })
            if let translatedTexts {
                var result = emptyResults
                for (identifier, text) in translatedTexts {
                    if let key = clientIdentifierMap[identifier] {
                        result[key] = text
                    }
                }
                task.finish(result)
            } else {
                task.finish(nil)
            }
            await MainActor.run {
                let wasActive = self.taskContainer.with { taskContainer -> Bool in
                    if taskContainer.activeTask?.id == task.id {
                        taskContainer.activeTask = nil
                        return true
                    }
                    return false
                }
                if wasActive {
                    self.scheduleNextTask()
                }
            }
        })
    }

    private func scheduleNextTask() {
        let state = self.taskContainer.with { taskContainer -> (isActive: Bool, task: ExperimentalInternalTranslationServiceImpl.TranslationTask?) in
            return (taskContainer.activeTask != nil, taskContainer.tasks.first)
        }
        guard !state.isActive else {
            // Appending to the queue must not invalidate a session that is already translating.
            return
        }
        guard let task = state.task else {
            self.configuration = nil
            return
        }
        let next = TranslationSession.Configuration(source: Locale.Language(identifier: task.fromLang), target: Locale.Language(identifier: task.toLang))
        if self.configuration?.source == next.source, self.configuration?.target == next.target {
            self.configuration?.invalidate()
        } else {
            self.configuration = next
        }
    }
}

@available(iOS 18.0, *)
public final class ExperimentalInternalTranslationServiceImpl: ExperimentalInternalTranslationService {
    fileprivate final class TranslationTask {
        let id: Int
        let texts: [AnyHashable: String]
        let fromLang: String
        let toLang: String
        private struct State {
            var completion: (([AnyHashable: String]?) -> Void)?
            var cancel: (() -> Void)?
            var isFinished = false
        }
        private let state: Atomic<State>
        private var timeoutTimer: SwiftSignalKit.Timer?
        
        init(id: Int, texts: [AnyHashable: String], fromLang: String, toLang: String, completion: @escaping ([AnyHashable: String]?) -> Void) {
            self.id = id
            self.texts = texts
            self.fromLang = fromLang
            self.toLang = toLang
            self.state = Atomic(value: State(completion: completion, cancel: nil))
        }

        deinit {
            self.timeoutTimer?.invalidate()
        }

        func startTimeout(_ expired: @escaping () -> Void) {
            let timer = SwiftSignalKit.Timer(timeout: 120.0, repeat: false, completion: { [weak self] in
                guard let self else {
                    return
                }
                if self.finish(nil) {
                    expired()
                }
            }, queue: .mainQueue())
            self.timeoutTimer = timer
            timer.start()
        }

        func setCancellation(_ cancel: @escaping () -> Void) {
            var isFinished = false
            let _ = self.state.modify { state in
                var state = state
                isFinished = state.isFinished
                if !state.isFinished {
                    state.cancel = cancel
                }
                return state
            }
            if isFinished {
                cancel()
            }
        }

        @discardableResult
        func finish(_ result: [AnyHashable: String]?, notify: Bool = true) -> Bool {
            var completion: (([AnyHashable: String]?) -> Void)?
            var cancel: (() -> Void)?
            var didFinish = false
            let _ = self.state.modify { state in
                var state = state
                if !state.isFinished {
                    didFinish = true
                    state.isFinished = true
                    completion = state.completion
                    cancel = state.cancel
                    state.completion = nil
                    state.cancel = nil
                }
                return state
            }
            cancel?()
            Queue.mainQueue().async {
                self.timeoutTimer?.invalidate()
                self.timeoutTimer = nil
                if notify {
                    completion?(result)
                }
            }
            return didFinish
        }
    }
    
    fileprivate final class TranslationTaskContainer {
        var tasks: [TranslationTask] = []
        var activeTask: TranslationTask?
        
        init() {
        }
    }
    
    private final class Impl {
        private let hostingController: UIViewController
        
        private let taskContainer = Atomic(value: TranslationTaskContainer())
        private let taskTrigger = ExternalTranslationTrigger()
        
        private var nextId: Int = 0
        
        init(view: UIView) {
            self.hostingController = UIHostingController(rootView: TranslationViewImpl(
                externalCondition: self.taskTrigger,
                taskContainer: self.taskContainer
            ))
            
            view.addSubview(self.hostingController.view)
            self.hostingController.view.backgroundColor = .clear
            self.hostingController.view.frame = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
            self.hostingController.view.isUserInteractionEnabled = false
        }

        deinit {
            let tasks = self.taskContainer.with { container -> [TranslationTask] in
                let tasks = container.tasks + (container.activeTask.map { [$0] } ?? [])
                container.tasks.removeAll()
                container.activeTask = nil
                return tasks
            }
            for task in tasks {
                task.finish(nil)
            }
            self.hostingController.view.removeFromSuperview()
        }
        
        func translate(texts: [AnyHashable: String], fromLang: String, toLang: String, onResult: @escaping ([AnyHashable: String]?) -> Void) -> Disposable {
            #if targetEnvironment(simulator)
            onResult(nil)
            return EmptyDisposable
            #endif
            guard !fromLang.isEmpty, !toLang.isEmpty else {
                onResult(nil)
                return EmptyDisposable
            }
            if texts.isEmpty || Locale.Language(identifier: fromLang) == Locale.Language(identifier: toLang) {
                onResult(texts)
                return EmptyDisposable
            }
            guard self.taskContainer.with({ $0.tasks.count < 64 }) else {
                onResult(nil)
                return EmptyDisposable
            }
            let id = self.nextId
            self.nextId += 1
            let task = TranslationTask(id: id, texts: texts, fromLang: fromLang, toLang: toLang, completion: onResult)
            self.taskContainer.with { $0.tasks.append(task) }
            task.startTimeout { [weak self] in
                self?.removeTask(id: id)
            }
            self.taskTrigger.shouldInvalidate += 1
            
            return ActionDisposable { [weak self] in
                Queue.mainQueue().async {
                    guard let self else {
                        return
                    }
                    task.finish(nil, notify: false)
                    self.removeTask(id: id)
                }
            }
        }

        private func removeTask(id: Int) {
            self.taskContainer.with { container in
                container.tasks.removeAll(where: { $0.id == id })
                if container.activeTask?.id == id {
                    container.activeTask = nil
                }
            }
            self.taskTrigger.shouldInvalidate += 1
        }
    }
    
    private let impl: QueueLocalObject<Impl>
    
    public init(view: UIView) {
        self.impl = QueueLocalObject(queue: .mainQueue(), generate: {
            return Impl(view: view)
        })
    }
    
    public func translate(texts: [AnyHashable: String], fromLang: String, toLang: String) -> Signal<[AnyHashable: String]?, NoError> {
        let impl = self.impl
        return Signal { subscriber in
            let signal: Signal<[AnyHashable: String]?, NoError> = impl.signalWith { value, subscriber in
                return value.translate(texts: texts, fromLang: fromLang, toLang: toLang, onResult: { result in
                    subscriber.putNext(result)
                    subscriber.putCompletion()
                })
            }
            let disposable = signal.start(next: { result in
                subscriber.putNext(result)
            }, completed: {
                subscriber.putCompletion()
            })
            // QueueLocalObject.signalWith only captures itself weakly. Retain the implementation
            // for both delayed subscription and the entire request so teardown cannot strand it.
            return ActionDisposable {
                withExtendedLifetime(impl) {
                    disposable.dispose()
                }
            }
        }
    }
}
