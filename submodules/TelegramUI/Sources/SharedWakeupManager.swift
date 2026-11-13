import Foundation
import BackgroundTasks
import AVFAudio
import UIKit
import SwiftSignalKit
import TelegramCore
import TelegramCallsUI
import AccountContext
import UniversalMediaPlayer
import TelegramAudio
import TelegramPresentationData

private struct AccountTasks {
    let stateSynchronization: Bool
    let importantTasks: AccountRunningImportantTasks
    let backgroundLocation: Bool
    let backgroundDownloads: Bool
    let backgroundAudio: Bool
    let activeCalls: Bool
    let watchTasks: Bool
    let userInterfaceInUse: Bool

    var hasBackgroundDownloads: Bool {
        return self.backgroundDownloads && superGramBackgroundDownloadsEnabled()
    }
    
    var isEmpty: Bool {
        if self.stateSynchronization {
            return false
        }
        if !self.importantTasks.isEmpty {
            return false
        }
        if self.backgroundLocation {
            return false
        }
        if self.hasBackgroundDownloads {
            return false
        }
        if self.backgroundAudio {
            return false
        }
        if self.activeCalls {
            return false
        }
        if self.watchTasks {
            return false
        }
        if self.userInterfaceInUse {
            return false
        }
        return true
    }
}

private let backgroundTaskSubmissionDelay: Double = 10.0

private func superGramBackgroundDownloadsEnabled() -> Bool {
    return UserDefaults.standard.object(forKey: "sgBackgroundDownloads") as? Bool ?? true
}

/// SuperGram: how long "the user has a download running" is held after the FetchManager stops reporting one.
/// It exists to cover the windows in which a user-initiated entry is momentarily not *active* although the
/// download is still in progress — above all the exponential retry backoff, which tops out at 60 s
/// (`FetchManagerImpl.handleEntryFetchFailed`), plus the hand-over to the next file of a queue. It is a
/// bounded tail, deliberately: it is what keeps the background keep-alive from ending the moment a flaky
/// network drops a part, while still guaranteeing that the keep-alive stops a fixed time after the user's
/// last download ends. See AppDelegate's `accountHasUserInitiatedDownloads`.
let superGramUserInitiatedDownloadHoldPeriod: Double = 90.0

private struct PendingMediaUploadKey: Hashable {
    let accountId: AccountRecordId
    let messageId: EngineMessage.Id
}

private struct PendingStoryUploadKey: Hashable {
    let accountId: AccountRecordId
    let stableId: Int32
}

// SuperGram: there is exactly one SharedWakeupManager per process (AppDelegate owns it). The notification
// fallback in AuthorizedApplicationContext has no reference to it, so this weak hook lets it report that the
// background keep-alive just did its job, which resets the keep-alive's idle deadline (see P0-1 duty cycle).
private weak var sharedWakeupManagerInstance: SharedWakeupManager?

func superGramNoteBackgroundNotificationActivity() {
    if Queue.mainQueue().isCurrent() {
        sharedWakeupManagerInstance?.noteBackgroundNotificationActivity()
    } else {
        Queue.mainQueue().async {
            sharedWakeupManagerInstance?.noteBackgroundNotificationActivity()
        }
    }
}

public final class SharedWakeupManager {
    private let beginBackgroundTask: (String, @escaping () -> Void) -> UIBackgroundTaskIdentifier?
    private let endBackgroundTask: (UIBackgroundTaskIdentifier) -> Void
    private let backgroundTimeRemaining: () -> Double
    private let acquireIdleExtension: () -> Disposable?
    
    private var enableBackgroundTasks: Bool = false
    private let presentationData: () -> PresentationData?
    
    private var inForeground: Bool = false
    private var hasActiveAudioSession: Bool = false
    private var activeExplicitExtensionTimer: SwiftSignalKit.Timer?
    private var activeExplicitExtensionTask: UIBackgroundTaskIdentifier?
    private var allowBackgroundTimeExtensionDeadline: Double?
    private var allowBackgroundTimeExtensionDeadlineTimer: SwiftSignalKit.Timer?
    private var isInBackgroundExtension: Bool = false
    
    private var accountSettingsDisposable: Disposable?
    private var inForegroundDisposable: Disposable?
    private var hasActiveAudioSessionDisposable: Disposable?
    private var tasksDisposable: Disposable?
    private var pendingMediaUploadsDisposable: Disposable?
    private var pendingStoryUploadsDisposable: Disposable?
    private var currentTask: (UIBackgroundTaskIdentifier, Double, SwiftSignalKit.Timer)?
    private var backgroundExtensionBudgetExhausted = false
    private var currentExternalCompletion: (() -> Void, SwiftSignalKit.Timer)?
    private var currentExternalCompletionValidationTimer: SwiftSignalKit.Timer?
    
    private var managedPausedInBackgroundPlayer: Disposable?
    private var keepIdleDisposable: Disposable?
    private var silenceAudioRenderer: MediaPlayerAudioRenderer?
    // SuperGram: another app or a call can interrupt the background audio session at any time; iOS then
    // suspends the app. Being suspended while a Postbox (SQLite, app group container) transaction holds
    // a file lock terminates the app with 0xDEAD10CC, so an interruption releases the keep-alive through
    // the regular "no background work" path under a short background task.
    private var silenceAudioInterrupted: Bool = false
    private var silenceAudioInterruptionObserver: NSObjectProtocol?
    private var silenceAudioResetObserver: NSObjectProtocol?
    private var silenceAudioInterruptionTask: (UIBackgroundTaskIdentifier, SwiftSignalKit.Timer)?

    // SuperGram: duty cycle for the notification keep-alive. The keep-alive exists so that new messages can be
    // turned into local notifications while the app is in the background; when it cannot do that, running it is
    // pure battery cost. Two cases are detected here:
    //  * the primary account has had no network for a sustained stretch (airplane mode, no coverage) — nothing
    //    can arrive, so nothing can be notified,
    //  * nothing has arrived for a long time — the tail hours of an overnight background session, where the whole
    //    cost is paid and a delayed notification costs nothing.
    // Both only stop the *keep-alive*; notification delivery itself is untouched, and anything that shows the
    // keep-alive is earning its cost (foreground, a delivered fallback notification, an active download) restarts
    // it immediately while the app is still running.
    private static let keepAliveIdleTimeout: Double = 2.0 * 60.0 * 60.0
    private static let keepAliveLowPowerIdleTimeout: Double = 20.0 * 60.0
    private static let keepAliveNoNetworkGracePeriod: Double = 10.0 * 60.0
    private var keepAliveLastActivityTimestamp: Double = CFAbsoluteTimeGetCurrent()
    private var keepAliveIdleTimer: SwiftSignalKit.Timer?
    private var keepAliveIdleTimerDeadline: Double?
    private var primaryAccountHasNetwork: Bool = true
    private var primaryAccountNoNetworkSince: Double?
    private var primaryAccountNetworkDisposable: Disposable?
    private var backgroundStateObservers: [NSObjectProtocol] = []
    private var isKeepAliveSuspendedForIdle: Bool = false
    private var isKeepAliveSuspendedForNetwork: Bool = false
    private var isKeepAliveSuspendedForThermal: Bool = false
    
    private var accountsAndTasks: [(Account, Bool, AccountTasks)] = []
    
    private var pendingMediaUploadsByKey: [PendingMediaUploadKey: Float] = [:]
    private var backgroundProcessingTaskProgressByKey: [PendingMediaUploadKey: Float] = [:]
    private var nextBackgroundProcessingTaskId: Int = 0
    private var backgroundProcessingTaskId: String?
    private var backgroundProcessingTaskLaunched: Bool = false
    private var backgroundProcessingTaskCancellationRequestedByApp: Bool = false
    private var pendingBackgroundProcessingTaskTimer: SwiftSignalKit.Timer?

    private var pendingStoryUploadsByKey: [PendingStoryUploadKey: Float] = [:]
    private var pendingStoryUploadStatusesByKey: [PendingStoryUploadKey: PendingStoryUploadStatus] = [:]
    private var backgroundStoryProcessingTaskProgressByKey: [PendingStoryUploadKey: Float] = [:]
    private var nextBackgroundStoryProcessingTaskId: Int = 0
    private var backgroundStoryProcessingTaskId: String?
    private var backgroundStoryProcessingTaskLaunched: Bool = false
    private var backgroundStoryProcessingTaskCancellationRequestedByApp: Bool = false
    private var pendingBackgroundStoryProcessingTaskTimer: SwiftSignalKit.Timer?

    public init(beginBackgroundTask: @escaping (String, @escaping () -> Void) -> UIBackgroundTaskIdentifier?, endBackgroundTask: @escaping (UIBackgroundTaskIdentifier) -> Void, backgroundTimeRemaining: @escaping () -> Double, acquireIdleExtension: @escaping () -> Disposable?, activeAccounts: Signal<(primary: Account?, accounts: [(AccountRecordId, Account)]), NoError>, liveLocationPolling: Signal<AccountRecordId?, NoError>, watchTasks: Signal<AccountRecordId?, NoError>, inForeground: Signal<Bool, NoError>, hasActiveAudioSession: Signal<Bool, NoError>, notificationManager: SharedNotificationManager?, mediaManager: MediaManager, callManager: PresentationCallManager?, accountUserInterfaceInUse: @escaping (AccountRecordId) -> Signal<Bool, NoError>, accountHasUserInitiatedDownloads: @escaping (AccountRecordId) -> Signal<Bool, NoError>, presentationData: @escaping () -> PresentationData?) {
        assert(Queue.mainQueue().isCurrent())
        
        self.beginBackgroundTask = beginBackgroundTask
        self.endBackgroundTask = endBackgroundTask
        self.backgroundTimeRemaining = backgroundTimeRemaining
        self.acquireIdleExtension = acquireIdleExtension
        self.presentationData = presentationData
        
        self.accountSettingsDisposable = (activeAccounts
        |> mapToSignal { activeAccounts -> Signal<Bool, NoError> in
            guard let account = activeAccounts.primary else {
                return .single(false)
            }
            return account.postbox.transaction { transaction -> Bool in
                guard let data = currentAppConfiguration(transaction: transaction).data else {
                    return false
                }
                if data["ios_killswitch_disable_bgtasks"] != nil {
                    return false
                }
                return true
            }
        }
        |> deliverOnMainQueue
        |> distinctUntilChanged).startStrict(next: { [weak self] isEnabled in
            guard let self else {
                return
            }
            self.enableBackgroundTasks = isEnabled
        })
        
        // SuperGram: the keep-alive cannot turn anything into a notification while there is no network at all, so
        // track reachability on the primary account. Only `.waitingForNetwork` counts — that is the state MTProto
        // derives from reachability; `.connecting` is a live retry and must keep the keep-alive running.
        self.primaryAccountNetworkDisposable = (activeAccounts
        |> map { primary, _ -> Account? in
            return primary
        }
        |> distinctUntilChanged(isEqual: { lhs, rhs in
            return lhs?.id == rhs?.id
        })
        |> mapToSignal { primary -> Signal<Bool, NoError> in
            guard let primary else {
                return .single(true)
            }
            return primary.network.connectionStatus
            |> map { status -> Bool in
                if case .waitingForNetwork = status {
                    return false
                }
                return true
            }
            |> distinctUntilChanged
        }
        |> deliverOnMainQueue).startStrict(next: { [weak self] hasNetwork in
            guard let self else {
                return
            }
            if self.primaryAccountHasNetwork == hasNetwork {
                return
            }
            self.primaryAccountHasNetwork = hasNetwork
            if hasNetwork {
                self.primaryAccountNoNetworkSince = nil
            } else {
                self.primaryAccountNoNetworkSince = CFAbsoluteTimeGetCurrent()
            }
            self.checkTasks()
        })

        self.inForegroundDisposable = (inForeground
        |> deliverOnMainQueue).startStrict(next: { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            strongSelf.inForeground = value
            if value {
                strongSelf.backgroundExtensionBudgetExhausted = false
                strongSelf.activeExplicitExtensionTimer?.invalidate()
                strongSelf.activeExplicitExtensionTimer = nil
                if let activeExplicitExtensionTask = strongSelf.activeExplicitExtensionTask {
                    strongSelf.activeExplicitExtensionTask = nil
                    strongSelf.endBackgroundTask(activeExplicitExtensionTask)
                }
                strongSelf.allowBackgroundTimeExtensionDeadlineTimer?.invalidate()
                strongSelf.allowBackgroundTimeExtensionDeadlineTimer = nil
                strongSelf.pendingBackgroundProcessingTaskTimer?.invalidate()
                strongSelf.pendingBackgroundProcessingTaskTimer = nil
                strongSelf.pendingBackgroundStoryProcessingTaskTimer?.invalidate()
                strongSelf.pendingBackgroundStoryProcessingTaskTimer = nil
            }
            strongSelf.updateBackgroundProcessingTaskStateFromPendingMediaUploads()
            strongSelf.updateBackgroundProcessingTaskStateFromPendingStoryUploads()
            strongSelf.checkTasks()
        })
        
        self.hasActiveAudioSessionDisposable = (hasActiveAudioSession
        |> deliverOnMainQueue).startStrict(next: { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            strongSelf.hasActiveAudioSession = value
            strongSelf.checkTasks()
        })
        
        self.managedPausedInBackgroundPlayer = combineLatest(queue: .mainQueue(), mediaManager.activeGlobalMediaPlayerAccountId, inForeground).startStrict(next: { [weak mediaManager] accountAndActive, inForeground in
            guard let mediaManager = mediaManager else {
                return
            }
            if !inForeground, let accountAndActive = accountAndActive, !accountAndActive.1 {
                mediaManager.audioSession.dropAll()
            }
        })
        
        self.tasksDisposable = (activeAccounts
        |> deliverOnMainQueue
        |> mapToSignal { primary, accounts -> Signal<[(Account, Bool, AccountTasks)], NoError> in
            let signals: [Signal<(Account, Bool, AccountTasks), NoError>] = accounts.map { _, account in
                let hasActiveMedia = mediaManager.activeGlobalMediaPlayerAccountId
                |> map { idAndStatus -> Bool in
                    if let (id, isPlaying) = idAndStatus {
                        return id == account.id && isPlaying
                    } else {
                        return false
                    }
                }
                |> distinctUntilChanged
                let isPlayingBackgroundAudio = combineLatest(queue: .mainQueue(), hasActiveMedia, hasActiveAudioSession)
                |> map { hasActiveMedia, hasActiveAudioSession -> Bool in
                    return hasActiveMedia && hasActiveAudioSession
                }
                |> distinctUntilChanged
                
                let hasActiveCalls = (callManager?.currentCallSignal ?? .single(nil))
                |> map { call in
                    return call?.context.account.id == account.id
                }
                |> distinctUntilChanged
                
                let hasActiveGroupCalls = (callManager?.currentGroupCallSignal ?? .single(nil))
                |> map { call -> Bool in
                    guard let call else {
                        return false
                    }
                    switch call {
                    case let .conferenceSource(conferenceSource):
                        return conferenceSource.context.account.id == account.id
                    case let .group(groupCall):
                        return groupCall.accountContext.account.id == account.id
                    }
                }
                |> distinctUntilChanged
                
                let keepUpdatesForCalls = combineLatest(queue: .mainQueue(), hasActiveCalls, hasActiveGroupCalls)
                |> map { hasActiveCalls, hasActiveGroupCalls -> Bool in
                    return hasActiveCalls || hasActiveGroupCalls
                }
                |> distinctUntilChanged
                
                let isPlayingBackgroundActiveCall = combineLatest(queue: .mainQueue(), hasActiveCalls, hasActiveGroupCalls, hasActiveAudioSession)
                |> map { hasActiveCalls, hasActiveGroupCalls, hasActiveAudioSession -> Bool in
                    return (hasActiveCalls || hasActiveGroupCalls) && hasActiveAudioSession
                }
                |> distinctUntilChanged
                
                let hasActiveAudio = combineLatest(queue: .mainQueue(), isPlayingBackgroundAudio, isPlayingBackgroundActiveCall)
                |> map { isPlayingBackgroundAudio, isPlayingBackgroundActiveCall in
                    return isPlayingBackgroundAudio || isPlayingBackgroundActiveCall
                }
                |> distinctUntilChanged
                
                let hasActiveLiveLocationPolling = liveLocationPolling
                |> map { id in
                    return id == account.id
                }
                |> distinctUntilChanged
                
                let hasWatchTasks = watchTasks
                |> map { id in
                    return id == account.id
                }
                |> distinctUntilChanged
                
                let userInterfaceInUse = accountUserInterfaceInUse(account.id)
                
                // SuperGram: running user-visible downloads keep the account's download connections and the app
                // alive in background (Settings → SuperGram → Downloads, "sgBackgroundDownloads", default true).
                // MediaDownloadActivity is process-wide, so it is attributed to the primary account only: otherwise
                // any download (even an avatar) made every secondary account a service task master (.always)
                // and kept its connections for the duration of the download plus the idle tail.
                //
                // `MediaDownloadActivity` alone is NOT a sufficient condition, and this is the reason the
                // FetchManager term below exists. It is driven by the FetchV2 *interactive* part budget, and a
                // fetch counts as interactive when it is user-initiated, when it is a playhead part **or when the
                // resource is merely small** (`isSmallResource`, <= 512 KB — FetchV2.swift:986). Chat photos,
                // avatars, stickers and thumbnails are all under that, so any incoming media auto-download kept
                // `hasActiveDownloads` true. While the app is kept awake it keeps syncing, which produces more
                // such fetches, which keeps it awake: on a busy account the keep-alive below — which is
                // deliberately *not* duty-cycled (see updateKeepAliveDutyCycle) — could run for the whole time the
                // app was backgrounded, for work the user never asked for and would not miss.
                //
                // The user-visible promise is "the download I started keeps going after I leave the app", so the
                // keep-alive is armed only while the FetchManager actually holds a user-initiated entry. That is
                // the same predicate as `continueInBackground` (FetchManagerImpl.swift:710 passes
                // `entry.userInitiated`), which is what already decides whether the media worker connections are
                // kept (Network.swift:1020) — so the two halves of the feature now agree on what a "background
                // download" is. Auto-downloaded media is still fetched for as long as the app happens to be
                // running; it just no longer keeps the process alive by itself.
                let isPrimaryAccount = primary?.id == account.id
                let hasDownloadNetwork = account.network.connectionStatus
                |> map { status -> Bool in
                    if case .waitingForNetwork = status {
                        return false
                    }
                    return true
                }
                |> distinctUntilChanged
                let hasBackgroundDownloads = combineLatest(queue: .mainQueue(),
                    MediaDownloadActivity.shared.hasActiveDownloads,
                    accountHasUserInitiatedDownloads(account.id),
                    hasDownloadNetwork
                )
                |> map { hasActiveDownloads, hasUserInitiatedDownloads, hasNetwork -> Bool in
                    // Offline entries stay queued, but cannot earn a background audio session.
                    // Apply the user setting when consuming the task so toggles take effect
                    // even when neither the download nor its activity signal changes.
                    return isPrimaryAccount && hasActiveDownloads && hasUserInitiatedDownloads && hasNetwork
                }
                |> distinctUntilChanged

                return combineLatest(queue: .mainQueue(), account.importantTasksRunning, notificationManager?.isPollingState(accountId: account.id) ?? .single(false), hasActiveAudio, keepUpdatesForCalls, hasActiveLiveLocationPolling, hasWatchTasks, userInterfaceInUse, hasBackgroundDownloads)
                |> map { importantTasksRunning, isPollingState, hasActiveAudio, keepUpdatesForCalls, hasActiveLiveLocationPolling, hasWatchTasks, userInterfaceInUse, hasBackgroundDownloads -> (Account, Bool, AccountTasks) in
                    return (account, primary?.id == account.id, AccountTasks(stateSynchronization: isPollingState, importantTasks: importantTasksRunning, backgroundLocation: hasActiveLiveLocationPolling, backgroundDownloads: hasBackgroundDownloads, backgroundAudio: hasActiveAudio, activeCalls: keepUpdatesForCalls, watchTasks: hasWatchTasks, userInterfaceInUse: userInterfaceInUse))
                }
            }
            return combineLatest(signals)
        }
        |> deliverOnMainQueue).startStrict(next: { [weak self] accountsAndTasks in
            guard let strongSelf = self else {
                return
            }
            strongSelf.accountsAndTasks = accountsAndTasks
            strongSelf.checkTasks()
        })
        
        self.pendingMediaUploadsDisposable = (activeAccounts
        |> deliverOnMainQueue
        |> mapToSignal { _, accounts -> Signal<[PendingMediaUploadKey: Float], NoError> in
            if accounts.isEmpty {
                return .single([:])
            }
            let signals: [Signal<[PendingMediaUploadKey: Float], NoError>] = accounts.map { accountId, account in
                return account.pendingMessageManager.pendingMediaUploads
                |> map { pendingMediaUploads in
                    var result: [PendingMediaUploadKey: Float] = [:]
                    result.reserveCapacity(pendingMediaUploads.count)
                    for (messageId, progress) in pendingMediaUploads {
                        result[PendingMediaUploadKey(accountId: accountId, messageId: messageId)] = progress
                    }
                    return result
                }
            }
            return combineLatest(signals)
            |> map { values in
                var result: [PendingMediaUploadKey: Float] = [:]
                for value in values {
                    for (key, progress) in value {
                        result[key] = progress
                    }
                }
                return result
            }
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).startStrict(next: { [weak self] pendingMediaUploadsByKey in
            guard let strongSelf = self else {
                return
            }
            strongSelf.pendingMediaUploadsByKey = pendingMediaUploadsByKey
            strongSelf.updateBackgroundProcessingTaskStateFromPendingMediaUploads()
        })
        
        self.pendingStoryUploadsDisposable = (activeAccounts
        |> deliverOnMainQueue
        |> mapToSignal { _, accounts -> Signal<[PendingStoryUploadKey: PendingStoryUploadStatus], NoError> in
            if accounts.isEmpty {
                return .single([:])
            }
            let signals: [Signal<[PendingStoryUploadKey: PendingStoryUploadStatus], NoError>] = accounts.map { accountId, account in
                return TelegramEngine(account: account).messages.pendingStoryUploadStatuses()
                |> map { pendingStoryUploadStatuses in
                    var result: [PendingStoryUploadKey: PendingStoryUploadStatus] = [:]
                    result.reserveCapacity(pendingStoryUploadStatuses.count)
                    for (stableId, status) in pendingStoryUploadStatuses {
                        result[PendingStoryUploadKey(accountId: accountId, stableId: stableId)] = status
                    }
                    return result
                }
            }
            return combineLatest(signals)
            |> map { values in
                var result: [PendingStoryUploadKey: PendingStoryUploadStatus] = [:]
                for value in values {
                    for (key, status) in value {
                        result[key] = status
                    }
                }
                return result
            }
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).startStrict(next: { [weak self] pendingStoryUploadStatusesByKey in
            guard let strongSelf = self else {
                return
            }
            strongSelf.pendingStoryUploadStatusesByKey = pendingStoryUploadStatusesByKey
            
            var pendingStoryUploadsByKey: [PendingStoryUploadKey: Float] = [:]
            pendingStoryUploadsByKey.reserveCapacity(pendingStoryUploadStatusesByKey.count)
            for (key, status) in pendingStoryUploadStatusesByKey {
                pendingStoryUploadsByKey[key] = status.progress
            }
            strongSelf.pendingStoryUploadsByKey = pendingStoryUploadsByKey
            strongSelf.updateBackgroundProcessingTaskStateFromPendingStoryUploads()
        })

        self.silenceAudioInterruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: OperationQueue.main, using: { [weak self] notification in
            guard let self, let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
                return
            }
            switch type {
            case .began:
                self.markSilenceAudioUnavailable(reason: "interrupted")
            case .ended:
                superGramNotificationLog("background audio interruption ended (keep-alive was interrupted: \(self.silenceAudioInterrupted))")
                if self.silenceAudioInterrupted {
                    self.silenceAudioInterrupted = false
                    self.checkTasks()
                }
            @unknown default:
                break
            }
        })

        // SuperGram: a media services reset tears the session down without an interruption notification; the app is
        // then no longer kept running by audio, so the keep-alive has to be released the same way.
        self.silenceAudioResetObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: OperationQueue.main, using: { [weak self] _ in
            self?.markSilenceAudioUnavailable(reason: "media services reset")
        })

        var previousBackgroundSettings = (superGramBackgroundDownloadsEnabled(), self.superGramBackgroundKeepAliveEnabled)
        self.backgroundStateObservers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: OperationQueue.main, using: { [weak self] _ in
            guard let self else {
                return
            }
            let settings = (superGramBackgroundDownloadsEnabled(), self.superGramBackgroundKeepAliveEnabled)
            if settings != previousBackgroundSettings {
                previousBackgroundSettings = settings
                self.checkTasks()
            }
        }))
        // Reading the initial state enables ProcessInfo's thermal change notifications.
        _ = ProcessInfo.processInfo.thermalState
        for notification in [Notification.Name.NSProcessInfoPowerStateDidChange, UIDevice.batteryStateDidChangeNotification, ProcessInfo.thermalStateDidChangeNotification] {
            self.backgroundStateObservers.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: OperationQueue.main, using: { [weak self] _ in
                self?.checkTasks()
            }))
        }

        sharedWakeupManagerInstance = self
    }

    // SuperGram: called when the local notification fallback delivers something, i.e. the keep-alive just paid for
    // itself. Resets the idle deadline and re-arms the keep-alive if it had been stopped for idleness while the app
    // was still running.
    fileprivate func noteBackgroundNotificationActivity() {
        assert(Queue.mainQueue().isCurrent())
        self.keepAliveLastActivityTimestamp = CFAbsoluteTimeGetCurrent()
        if self.isKeepAliveSuspendedForIdle {
            self.checkTasks()
        }
    }

    // SuperGram: the silent-audio keep-alive is what stops iOS from suspending the app in background. When it is
    // gone (interrupted by a call or another app, reset, or never activated at all), the app can be suspended at any
    // moment. Being suspended while a Postbox/SQLite transaction holds a lock on the app-group container terminates
    // the process with 0xDEAD10CC, so the keep-alive is released through the regular "no background work" path —
    // which calls setCanBeginTransactions(false, afterTransactionIfRunning:) — under a short background task that
    // gives a running transaction time to finish.
    fileprivate func markSilenceAudioUnavailable(reason: String) {
        assert(Queue.mainQueue().isCurrent())
        guard self.silenceAudioRenderer != nil, !self.silenceAudioInterrupted else {
            return
        }
        self.silenceAudioInterrupted = true
        superGramNotificationLog("background audio session unavailable: \(reason)")
        self.beginSilenceAudioReleaseTask(name: "silence-audio-interrupted")
        self.checkTasks()
    }

    // SuperGram: a short background task that covers the window between "the keep-alive is going away" and
    // "setCanBeginTransactions(false, afterTransactionIfRunning:) has actually drained the running Postbox
    // transaction". Without it, iOS can suspend the process while SQLite still holds a lock on the app-group
    // container, which is terminated as 0xDEAD10CC.
    private func beginSilenceAudioReleaseTask(name: String) {
        guard self.silenceAudioInterruptionTask == nil else {
            return
        }
        guard let taskId = self.beginBackgroundTask(name, { [weak self] in
            self?.endSilenceAudioInterruptionTask()
        }) else {
            return
        }
        let timer = SwiftSignalKit.Timer(timeout: 5.0, repeat: false, completion: { [weak self] in
            self?.endSilenceAudioInterruptionTask()
        }, queue: Queue.mainQueue())
        self.silenceAudioInterruptionTask = (taskId, timer)
        timer.start()
    }

    private func endSilenceAudioInterruptionTask() {
        if let (taskId, timer) = self.silenceAudioInterruptionTask {
            self.silenceAudioInterruptionTask = nil
            timer.invalidate()
            self.endBackgroundTask(taskId)
        }
    }
    
    deinit {
        for observer in self.backgroundStateObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let silenceAudioInterruptionObserver = self.silenceAudioInterruptionObserver {
            NotificationCenter.default.removeObserver(silenceAudioInterruptionObserver)
        }
        if let silenceAudioResetObserver = self.silenceAudioResetObserver {
            NotificationCenter.default.removeObserver(silenceAudioResetObserver)
        }
        if let (taskId, timer) = self.silenceAudioInterruptionTask {
            timer.invalidate()
            self.endBackgroundTask(taskId)
        }
        self.keepAliveIdleTimer?.invalidate()
        self.primaryAccountNetworkDisposable?.dispose()
        self.accountSettingsDisposable?.dispose()
        self.inForegroundDisposable?.dispose()
        self.hasActiveAudioSessionDisposable?.dispose()
        self.tasksDisposable?.dispose()
        self.pendingMediaUploadsDisposable?.dispose()
        self.pendingStoryUploadsDisposable?.dispose()
        self.managedPausedInBackgroundPlayer?.dispose()
        self.keepIdleDisposable?.dispose()
        self.pendingBackgroundProcessingTaskTimer?.invalidate()
        self.pendingBackgroundStoryProcessingTaskTimer?.invalidate()
        if let (taskId, _, timer) = self.currentTask {
            timer.invalidate()
            self.endBackgroundTask(taskId)
        }
    }
    
    private func updateBackgroundProcessingTaskStateFromPendingMediaUploads() {
        if !self.enableBackgroundTasks {
            return
        }
        
        let shouldHaveTask = !self.pendingMediaUploadsByKey.isEmpty && !self.inForeground
        let hadTask = self.backgroundProcessingTaskId != nil

        if shouldHaveTask {
            if !hadTask && self.pendingBackgroundProcessingTaskTimer == nil {
                let timer = SwiftSignalKit.Timer(timeout: backgroundTaskSubmissionDelay, repeat: false, completion: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.pendingBackgroundProcessingTaskTimer = nil
                    self.startBackgroundProcessingTaskIfNeeded()
                }, queue: .mainQueue())
                self.pendingBackgroundProcessingTaskTimer = timer
                timer.start()
            }
        } else {
            self.pendingBackgroundProcessingTaskTimer?.invalidate()
            self.pendingBackgroundProcessingTaskTimer = nil

            if let backgroundProcessingTaskId = self.backgroundProcessingTaskId {
                if !self.backgroundProcessingTaskCancellationRequestedByApp {
                    self.backgroundProcessingTaskCancellationRequestedByApp = true
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundProcessingTaskId)
                    Logger.shared.log("Wakeup", "Requested BG task cancellation by app: \(backgroundProcessingTaskId)")
                }

                if !self.backgroundProcessingTaskLaunched {
                    self.backgroundProcessingTaskId = nil
                    self.backgroundProcessingTaskProgressByKey = [:]
                    self.backgroundProcessingTaskCancellationRequestedByApp = false
                    self.checkTasks()
                }
            }
        }
    }
    
    private func updateBackgroundProcessingTaskStateFromPendingStoryUploads() {
        if !self.enableBackgroundTasks {
            return
        }
        
        let shouldHaveTask = !self.pendingStoryUploadStatusesByKey.isEmpty && !self.inForeground
        let hadTask = self.backgroundStoryProcessingTaskId != nil

        if shouldHaveTask {
            if !hadTask && self.pendingBackgroundStoryProcessingTaskTimer == nil {
                let timer = SwiftSignalKit.Timer(timeout: backgroundTaskSubmissionDelay, repeat: false, completion: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.pendingBackgroundStoryProcessingTaskTimer = nil
                    self.startBackgroundStoryProcessingTaskIfNeeded()
                }, queue: .mainQueue())
                self.pendingBackgroundStoryProcessingTaskTimer = timer
                timer.start()
            }
        } else {
            self.pendingBackgroundStoryProcessingTaskTimer?.invalidate()
            self.pendingBackgroundStoryProcessingTaskTimer = nil

            if let backgroundStoryProcessingTaskId = self.backgroundStoryProcessingTaskId {
                if !self.backgroundStoryProcessingTaskCancellationRequestedByApp {
                    self.backgroundStoryProcessingTaskCancellationRequestedByApp = true
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundStoryProcessingTaskId)
                    Logger.shared.log("Wakeup", "Requested story BG task cancellation by app: \(backgroundStoryProcessingTaskId)")
                }

                if !self.backgroundStoryProcessingTaskLaunched {
                    self.backgroundStoryProcessingTaskId = nil
                    self.backgroundStoryProcessingTaskProgressByKey = [:]
                    self.backgroundStoryProcessingTaskCancellationRequestedByApp = false
                    self.checkTasks()
                }
            }
        }
    }
    
    private func cancelUploadingMessagesForCurrentTask() {
        let keys = Array(self.pendingMediaUploadsByKey.keys)
        if keys.isEmpty {
            Logger.shared.log("Wakeup", "BG task external cancel: no pending uploads to delete")
            return
        }
        
        var messageIdsByAccount: [AccountRecordId: [EngineMessage.Id]] = [:]
        for key in keys {
            if messageIdsByAccount[key.accountId] == nil {
                messageIdsByAccount[key.accountId] = []
            }
            messageIdsByAccount[key.accountId]?.append(key.messageId)
        }
        
        for key in keys {
            self.pendingMediaUploadsByKey.removeValue(forKey: key)
        }
        
        Logger.shared.log("Wakeup", "BG task external cancel: deleting \(keys.count) uploading messages across \(messageIdsByAccount.count) accounts")
        
        for (accountId, messageIds) in messageIdsByAccount {
            guard let account = self.accountsAndTasks.first(where: { $0.0.id == accountId })?.0 else {
                Logger.shared.log("Wakeup", "BG task external cancel: missing account \(accountId.int64), skip \(messageIds.count) messages")
                continue
            }
            Logger.shared.log("Wakeup", "BG task external cancel: deleting \(messageIds.count) messages in account \(accountId.int64)")
            let _ = TelegramEngine(account: account).messages.deleteMessagesInteractively(messageIds: messageIds, type: .forLocalPeer).startStandalone()
        }
    }
    
    private func cancelUploadingStoriesForCurrentTask() {
        let keys = Array(self.pendingStoryUploadsByKey.keys)
        if keys.isEmpty {
            Logger.shared.log("Wakeup", "Story BG task external cancel: no pending uploads to cancel")
            return
        }
        
        var stableIdsByAccount: [AccountRecordId: [Int32]] = [:]
        for key in keys {
            if stableIdsByAccount[key.accountId] == nil {
                stableIdsByAccount[key.accountId] = []
            }
            stableIdsByAccount[key.accountId]?.append(key.stableId)
        }
        
        for key in keys {
            self.pendingStoryUploadsByKey.removeValue(forKey: key)
            self.pendingStoryUploadStatusesByKey.removeValue(forKey: key)
        }
        
        Logger.shared.log("Wakeup", "Story BG task external cancel: cancelling \(keys.count) uploading stories across \(stableIdsByAccount.count) accounts")
        
        for (accountId, stableIds) in stableIdsByAccount {
            guard let account = self.accountsAndTasks.first(where: { $0.0.id == accountId })?.0 else {
                Logger.shared.log("Wakeup", "Story BG task external cancel: missing account \(accountId.int64), skip \(stableIds.count) stories")
                continue
            }
            Logger.shared.log("Wakeup", "Story BG task external cancel: cancelling \(stableIds.count) stories in account \(accountId.int64)")
            let engineMessages = TelegramEngine(account: account).messages
            for stableId in stableIds {
                engineMessages.cancelStoryUpload(stableId: stableId)
            }
        }
    }
    
    private func startBackgroundProcessingTaskIfNeeded() {
#if compiler(>=6.2)
        guard #available(iOS 26.0, *) else {
            return
        }
        guard !self.inForeground else {
            return
        }
        guard self.backgroundProcessingTaskId == nil else {
            return
        }
        guard let presentationData = self.presentationData() else {
            return
        }
        
        let baseAppBundleId = Bundle.main.bundleIdentifier!
        let uploadTaskId = "\(baseAppBundleId).upload.message\(self.nextBackgroundProcessingTaskId)"
        self.nextBackgroundProcessingTaskId += 1
        self.backgroundProcessingTaskProgressByKey = [:]
        self.backgroundProcessingTaskLaunched = false
        self.backgroundProcessingTaskCancellationRequestedByApp = false
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: uploadTaskId, using: nil, launchHandler: { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else {
                return
            }
            guard let self else {
                task.updateTitle(task.title, subtitle: presentationData.strings.BackgroundTasks_MediaFinished)
                task.setTaskCompleted(success: true)
                return
            }
            
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                if self.backgroundProcessingTaskId == task.identifier {
                    self.backgroundProcessingTaskLaunched = true
                }
            }
            
            var wasExpired = false
            
            task.expirationHandler = { [weak self] in
                wasExpired = true
                
                Queue.mainQueue().async {
                    guard let self else {
                        return
                    }
                    if self.backgroundProcessingTaskId == task.identifier {
                        let cancelledByApp = self.backgroundProcessingTaskCancellationRequestedByApp
                        self.backgroundProcessingTaskCancellationRequestedByApp = false
                        if cancelledByApp {
                            Logger.shared.log("Wakeup", "BG task expired after app cancellation: \(task.identifier)")
                        } else {
                            Logger.shared.log("Wakeup", "BG task expired externally, will delete uploading messages: \(task.identifier)")
                            self.cancelUploadingMessagesForCurrentTask()
                        }
                        self.backgroundProcessingTaskId = nil
                        self.backgroundProcessingTaskProgressByKey = [:]
                        self.backgroundProcessingTaskLaunched = false
                        self.checkTasks()
                        self.updateBackgroundProcessingTaskStateFromPendingMediaUploads()
                    } else if !self.backgroundProcessingTaskCancellationRequestedByApp {
                        Logger.shared.log("Wakeup", "Non-current BG task expired externally, will delete uploading messages: \(task.identifier)")
                        self.cancelUploadingMessagesForCurrentTask()
                        self.checkTasks()
                        self.updateBackgroundProcessingTaskStateFromPendingMediaUploads()
                    }
                }
            }
            
            Task { @MainActor [weak self] in
                guard let self else {
                    task.updateTitle(task.title, subtitle: presentationData.strings.BackgroundTasks_MediaFinished)
                    task.setTaskCompleted(success: true)
                    return
                }
                
                var foregroundCancellationRequested = false
                
                while true {
                    if wasExpired {
                        break
                    }
                    
                    if self.backgroundProcessingTaskId != task.identifier || self.pendingMediaUploadsByKey.isEmpty {
                        self.backgroundProcessingTaskProgressByKey = [:]
                        task.updateTitle(task.title, subtitle: presentationData.strings.BackgroundTasks_MediaFinished)
                        task.setTaskCompleted(success: true)
                        if self.backgroundProcessingTaskId == task.identifier {
                            self.backgroundProcessingTaskId = nil
                            self.backgroundProcessingTaskLaunched = false
                            self.backgroundProcessingTaskCancellationRequestedByApp = false
                            self.checkTasks()
                            self.updateBackgroundProcessingTaskStateFromPendingMediaUploads()
                        }
                        return
                    }
                    
                    if self.inForeground {
                        if !foregroundCancellationRequested {
                            foregroundCancellationRequested = true
                            if !self.backgroundProcessingTaskCancellationRequestedByApp {
                                self.backgroundProcessingTaskCancellationRequestedByApp = true
                                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: task.identifier)
                                Logger.shared.log("Wakeup", "Requested BG task cancellation due to foreground: \(task.identifier)")
                            }
                            self.backgroundProcessingTaskProgressByKey = [:]
                        }
                        try await Task.sleep(for: .seconds(1.0))
                        continue
                    } else {
                        foregroundCancellationRequested = false
                    }
                    
                    if self.backgroundProcessingTaskId != task.identifier {
                        return
                    }
                    
                    var currentKeys = Set<PendingMediaUploadKey>()
                    for (key, progress) in self.pendingMediaUploadsByKey {
                        currentKeys.insert(key)
                        let clampedProgress = min(1.0, max(0.0, progress))
                        if let currentProgress = self.backgroundProcessingTaskProgressByKey[key] {
                            self.backgroundProcessingTaskProgressByKey[key] = max(currentProgress, clampedProgress)
                        } else {
                            self.backgroundProcessingTaskProgressByKey[key] = clampedProgress
                        }
                    }
                    for key in self.backgroundProcessingTaskProgressByKey.keys where !currentKeys.contains(key) {
                        self.backgroundProcessingTaskProgressByKey[key] = 1.0
                    }
                    
                    let progressPrecision: Int64 = 1000
                    let totalItemCount = max(1, self.backgroundProcessingTaskProgressByKey.count)
                    let totalUnitCount = Int64(totalItemCount) * progressPrecision
                    
                    var completedUnitCount: Int64 = 0
                    for progress in self.backgroundProcessingTaskProgressByKey.values {
                        completedUnitCount += Int64((progress * Float(progressPrecision)).rounded(.down))
                    }
                    completedUnitCount = min(totalUnitCount, max(0, completedUnitCount))
                    
                    task.progress.totalUnitCount = totalUnitCount
                    task.progress.completedUnitCount = completedUnitCount
                    
                    let title: String = presentationData.strings.BackgroundTasks_UploadingMedia(Int32(self.pendingMediaUploadsByKey.count))
                    if task.title != title {
                        task.updateTitle(title, subtitle: presentationData.strings.BackgroundTasks_MediaSubtitle)
                    }
                    
                    try await Task.sleep(for: .seconds(1.0))
                }
            }
        })
        
        let title: String = presentationData.strings.BackgroundTasks_UploadingMedia(Int32(self.pendingMediaUploadsByKey.count))
        
        let request = BGContinuedProcessingTaskRequest(
            identifier: uploadTaskId,
            title: title,
            subtitle: presentationData.strings.BackgroundTasks_MediaSubtitle
        )
        request.strategy = .fail
        
        do {
            try BGTaskScheduler.shared.submit(request)
            self.backgroundProcessingTaskId = uploadTaskId
            self.backgroundProcessingTaskLaunched = false
            self.checkTasks()
        } catch let e {
            Logger.shared.log("Wakeup", "BGTaskScheduler submit error: \(e)")
        }
#endif
    }
    
    private func startBackgroundStoryProcessingTaskIfNeeded() {
#if compiler(>=6.2)
        guard #available(iOS 26.0, *) else {
            return
        }
        guard !self.inForeground else {
            return
        }
        guard self.backgroundStoryProcessingTaskId == nil else {
            return
        }
        guard let presentationData = self.presentationData() else {
            return
        }
        
        let baseAppBundleId = Bundle.main.bundleIdentifier!
        let uploadTaskId = "\(baseAppBundleId).upload.story\(self.nextBackgroundStoryProcessingTaskId)"
        self.nextBackgroundStoryProcessingTaskId += 1
        self.backgroundStoryProcessingTaskProgressByKey = [:]
        self.backgroundStoryProcessingTaskLaunched = false
        self.backgroundStoryProcessingTaskCancellationRequestedByApp = false
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: uploadTaskId, using: nil, launchHandler: { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else {
                return
            }
            guard let self else {
                task.updateTitle(task.title, subtitle: presentationData.strings.BackgroundTasks_StoryFinished)
                task.setTaskCompleted(success: true)
                return
            }
            
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                if self.backgroundStoryProcessingTaskId == task.identifier {
                    self.backgroundStoryProcessingTaskLaunched = true
                }
            }
            
            var wasExpired = false
            
            task.expirationHandler = { [weak self] in
                wasExpired = true
                
                Queue.mainQueue().async {
                    guard let self else {
                        return
                    }
                    if self.backgroundStoryProcessingTaskId == task.identifier {
                        let cancelledByApp = self.backgroundStoryProcessingTaskCancellationRequestedByApp
                        self.backgroundStoryProcessingTaskCancellationRequestedByApp = false
                        if cancelledByApp {
                            Logger.shared.log("Wakeup", "Story BG task expired after app cancellation: \(task.identifier)")
                        } else {
                            Logger.shared.log("Wakeup", "Story BG task expired externally, will cancel uploading stories: \(task.identifier)")
                            self.cancelUploadingStoriesForCurrentTask()
                        }
                        self.backgroundStoryProcessingTaskId = nil
                        self.backgroundStoryProcessingTaskProgressByKey = [:]
                        self.backgroundStoryProcessingTaskLaunched = false
                        self.checkTasks()
                        self.updateBackgroundProcessingTaskStateFromPendingStoryUploads()
                    } else if !self.backgroundStoryProcessingTaskCancellationRequestedByApp {
                        Logger.shared.log("Wakeup", "Non-current story BG task expired externally, will cancel uploading stories: \(task.identifier)")
                        self.cancelUploadingStoriesForCurrentTask()
                        self.checkTasks()
                        self.updateBackgroundProcessingTaskStateFromPendingStoryUploads()
                    }
                }
            }
            
            Task { @MainActor [weak self] in
                guard let self else {
                    task.updateTitle(task.title, subtitle: presentationData.strings.BackgroundTasks_StoryFinished)
                    task.setTaskCompleted(success: true)
                    return
                }
                
                var foregroundCancellationRequested = false
                var currentDisplayedTitle: String?
                var currentDisplayedSubtitle: String?
                
                while true {
                    if wasExpired {
                        break
                    }
                    
                    if self.backgroundStoryProcessingTaskId != task.identifier || self.pendingStoryUploadStatusesByKey.isEmpty {
                        self.backgroundStoryProcessingTaskProgressByKey = [:]
                        task.updateTitle(task.title, subtitle: presentationData.strings.BackgroundTasks_StoryFinished)
                        task.setTaskCompleted(success: true)
                        if self.backgroundStoryProcessingTaskId == task.identifier {
                            self.backgroundStoryProcessingTaskId = nil
                            self.backgroundStoryProcessingTaskLaunched = false
                            self.backgroundStoryProcessingTaskCancellationRequestedByApp = false
                            self.checkTasks()
                            self.updateBackgroundProcessingTaskStateFromPendingStoryUploads()
                        }
                        return
                    }
                    
                    if self.inForeground {
                        if !foregroundCancellationRequested {
                            foregroundCancellationRequested = true
                            if !self.backgroundStoryProcessingTaskCancellationRequestedByApp {
                                self.backgroundStoryProcessingTaskCancellationRequestedByApp = true
                                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: task.identifier)
                                Logger.shared.log("Wakeup", "Requested story BG task cancellation due to foreground: \(task.identifier)")
                            }
                            self.backgroundStoryProcessingTaskProgressByKey = [:]
                        }
                        try await Task.sleep(for: .seconds(1.0))
                        continue
                    } else {
                        foregroundCancellationRequested = false
                    }
                    
                    if self.backgroundStoryProcessingTaskId != task.identifier {
                        return
                    }
                    
                    var currentKeys = Set<PendingStoryUploadKey>()
                    for (key, status) in self.pendingStoryUploadStatusesByKey {
                        currentKeys.insert(key)
                        let clampedProgress = min(1.0, max(0.0, status.progress))
                        if let currentProgress = self.backgroundStoryProcessingTaskProgressByKey[key] {
                            self.backgroundStoryProcessingTaskProgressByKey[key] = max(currentProgress, clampedProgress)
                        } else {
                            self.backgroundStoryProcessingTaskProgressByKey[key] = clampedProgress
                        }
                    }
                    for key in self.backgroundStoryProcessingTaskProgressByKey.keys where !currentKeys.contains(key) {
                        self.backgroundStoryProcessingTaskProgressByKey[key] = 1.0
                    }
                    
                    let progressPrecision: Int64 = 1000
                    let totalItemCount = max(1, self.backgroundStoryProcessingTaskProgressByKey.count)
                    let totalUnitCount = Int64(totalItemCount) * progressPrecision
                    
                    var completedUnitCount: Int64 = 0
                    for progress in self.backgroundStoryProcessingTaskProgressByKey.values {
                        completedUnitCount += Int64((progress * Float(progressPrecision)).rounded(.down))
                    }
                    completedUnitCount = min(totalUnitCount, max(0, completedUnitCount))
                    
                    task.progress.totalUnitCount = totalUnitCount
                    task.progress.completedUnitCount = completedUnitCount
                    
                    let title: String = presentationData.strings.BackgroundTasks_UploadingStories(Int32(self.pendingStoryUploadsByKey.count))
                    let subtitle: String
                    if self.pendingStoryUploadStatusesByKey.values.contains(where: { $0.phase == .processing }) {
                        subtitle = presentationData.strings.BackgroundTasks_StoryOpenAppToContinue
                    } else {
                        subtitle = presentationData.strings.BackgroundTasks_StorySubtitle
                    }
                    if currentDisplayedTitle != title || currentDisplayedSubtitle != subtitle {
                        task.updateTitle(title, subtitle: subtitle)
                        currentDisplayedTitle = title
                        currentDisplayedSubtitle = subtitle
                    }
                    
                    try await Task.sleep(for: .seconds(1.0))
                }
            }
        })
        
        let title: String = presentationData.strings.BackgroundTasks_UploadingStories(Int32(self.pendingStoryUploadsByKey.count))
        let subtitle: String
        if self.pendingStoryUploadStatusesByKey.values.contains(where: { $0.phase == .processing }) {
            subtitle = presentationData.strings.BackgroundTasks_StoryOpenAppToContinue
        } else {
            subtitle = presentationData.strings.BackgroundTasks_StorySubtitle
        }
        
        let request = BGContinuedProcessingTaskRequest(
            identifier: uploadTaskId,
            title: title,
            subtitle: subtitle
        )
        request.strategy = .fail
        /*if BGTaskScheduler.supportedResources.contains(.gpu) {
            request.requiredResources = .gpu
        }*/
        
        do {
            try BGTaskScheduler.shared.submit(request)
            self.backgroundStoryProcessingTaskId = uploadTaskId
            self.backgroundStoryProcessingTaskLaunched = false
            self.checkTasks()
        } catch let e {
            Logger.shared.log("Wakeup", "Story BGTaskScheduler submit error: \(e)")
        }
#endif
    }
    
    func allowBackgroundTimeExtension(timeout: Double, extendNow: Bool = false) {
        let shouldCheckTasks = self.allowBackgroundTimeExtensionDeadline == nil || self.backgroundExtensionBudgetExhausted
        self.backgroundExtensionBudgetExhausted = false
        self.allowBackgroundTimeExtensionDeadline = CFAbsoluteTimeGetCurrent() + timeout
        
        self.allowBackgroundTimeExtensionDeadlineTimer?.invalidate()
        self.allowBackgroundTimeExtensionDeadlineTimer = SwiftSignalKit.Timer(timeout: timeout, repeat: false, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.allowBackgroundTimeExtensionDeadlineTimer?.invalidate()
            strongSelf.allowBackgroundTimeExtensionDeadlineTimer = nil
            strongSelf.checkTasks()
        }, queue: .mainQueue())
        self.allowBackgroundTimeExtensionDeadlineTimer?.start()
        
        if extendNow {
            if self.activeExplicitExtensionTimer == nil {
                let activeExplicitExtensionTimer = SwiftSignalKit.Timer(timeout: 20.0, repeat: false, completion: { [weak self] in
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.activeExplicitExtensionTimer?.invalidate()
                    strongSelf.activeExplicitExtensionTimer = nil
                    if let activeExplicitExtensionTask = strongSelf.activeExplicitExtensionTask {
                        strongSelf.activeExplicitExtensionTask = nil
                        strongSelf.endBackgroundTask(activeExplicitExtensionTask)
                    }
                    strongSelf.checkTasks()
                }, queue: .mainQueue())
                self.activeExplicitExtensionTimer = activeExplicitExtensionTimer
                activeExplicitExtensionTimer.start()
                
                self.activeExplicitExtensionTask = self.beginBackgroundTask("explicit-extension") { [weak self, weak activeExplicitExtensionTimer] in
                    guard let self, let activeExplicitExtensionTimer else {
                        return
                    }
                    if self.activeExplicitExtensionTimer === activeExplicitExtensionTimer {
                        self.activeExplicitExtensionTimer?.invalidate()
                        self.activeExplicitExtensionTimer = nil
                        if let activeExplicitExtensionTask = self.activeExplicitExtensionTask {
                            self.activeExplicitExtensionTask = nil
                            self.endBackgroundTask(activeExplicitExtensionTask)
                        }
                        self.checkTasks()
                    }
                }
            }
        }
        if shouldCheckTasks || extendNow {
            self.checkTasks()
        }
    }
    
    func replaceCurrentExtensionWithExternalTime(completion: @escaping () -> Void, timeout: Double) {
        if let (currentCompletion, timer) = self.currentExternalCompletion {
            currentCompletion()
            timer.invalidate()
            self.currentExternalCompletion = nil
        }
        let timer = SwiftSignalKit.Timer(timeout: timeout - 5.0, repeat: false, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.currentExternalCompletionValidationTimer?.invalidate()
            strongSelf.currentExternalCompletionValidationTimer = nil
            if let (completion, timer) = strongSelf.currentExternalCompletion {
                strongSelf.currentExternalCompletion = nil
                timer.invalidate()
                completion()
            }
            strongSelf.checkTasks()
        }, queue: Queue.mainQueue())
        self.currentExternalCompletion = (completion, timer)
        timer.start()
        
        self.currentExternalCompletionValidationTimer?.invalidate()
        let validationTimer = SwiftSignalKit.Timer(timeout: 1.0, repeat: false, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.currentExternalCompletionValidationTimer?.invalidate()
            strongSelf.currentExternalCompletionValidationTimer = nil
            strongSelf.checkTasks()
        }, queue: Queue.mainQueue())
        self.currentExternalCompletionValidationTimer = validationTimer
        validationTimer.start()
        self.checkTasks()
    }
    
    // SuperGram: the silent-audio keep-alive is a user setting (Settings → SuperGram → App,
    // key "sgBackgroundKeepAlive", default true). It is the only notification path for this fork,
    // so it stays on by default, but the user must be able to turn the background activity off.
    private var superGramBackgroundKeepAliveEnabled: Bool {
        return UserDefaults.standard.object(forKey: "sgBackgroundKeepAlive") as? Bool ?? true
    }

    // SuperGram: returns whether the notification keep-alive is still able to earn its battery cost, and owns the
    // timer that re-evaluates that at the next deadline. Never called for the download keep-alive — an active
    // download is real work and is not duty-cycled.
    private func updateKeepAliveDutyCycle() -> Bool {
        if self.inForeground {
            self.keepAliveIdleTimer?.invalidate()
            self.keepAliveIdleTimer = nil
            self.keepAliveIdleTimerDeadline = nil
            self.isKeepAliveSuspendedForIdle = false
            self.isKeepAliveSuspendedForNetwork = false
            self.isKeepAliveSuspendedForThermal = false
            return true
        }

        // A charger does not remove CPU, network or thermal cost. Only real foreground/notification activity
        // advances the idle anchor. Critical heat stops speculative notification work until a thermal callback
        // reports cooling; actual downloads and audio/calls retain their independent checkTasks() paths.
        let thermalState = ProcessInfo.processInfo.thermalState
        if thermalState == .critical {
            if !self.isKeepAliveSuspendedForThermal {
                self.isKeepAliveSuspendedForThermal = true
                superGramNotificationLog("notification keep-alive paused: critical thermal state")
            }
            self.keepAliveIdleTimer?.invalidate()
            self.keepAliveIdleTimer = nil
            self.keepAliveIdleTimerDeadline = nil
            return false
        } else if self.isKeepAliveSuspendedForThermal {
            self.isKeepAliveSuspendedForThermal = false
            superGramNotificationLog("notification keep-alive thermal pause ended")
        }

        // SuperGram: no idle or no-network stop any more. This bundle cannot receive Telegram server pushes (the
        // server signs APNs with the official app's credentials), so the running process is the only notification
        // path: once the keep-alive is released iOS suspends the app, and nothing — no new message, no returning
        // network — can wake it again until the user opens it. Stopping after a quiet stretch or a short network
        // outage therefore turned notifications off silently for the rest of the day. Only critical heat (handled
        // above) pauses it; the user switch "sgBackgroundKeepAlive" still turns it off entirely.
        if self.isKeepAliveSuspendedForIdle || self.isKeepAliveSuspendedForNetwork {
            self.isKeepAliveSuspendedForIdle = false
            self.isKeepAliveSuspendedForNetwork = false
            superGramNotificationLog("keep-alive resumed")
        }
        self.keepAliveIdleTimer?.invalidate()
        self.keepAliveIdleTimer = nil
        self.keepAliveIdleTimerDeadline = nil
        return true
    }

    private func armKeepAliveIdleTimer(deadline: Double) {
        // Rebuild when activity or power/thermal policy moves the deadline earlier (it must not fire late), and
        // tolerate up to a minute of drift when it moved later — firing early just re-evaluates and re-arms.
        if self.keepAliveIdleTimer != nil, let existing = self.keepAliveIdleTimerDeadline, deadline >= existing - 1.0, deadline <= existing + 60.0 {
            return
        }
        self.keepAliveIdleTimer?.invalidate()
        let timer = SwiftSignalKit.Timer(timeout: max(1.0, deadline - CFAbsoluteTimeGetCurrent()), repeat: false, completion: { [weak self] in
            guard let self else {
                return
            }
            self.keepAliveIdleTimer = nil
            self.keepAliveIdleTimerDeadline = nil
            self.checkTasks()
        }, queue: Queue.mainQueue())
        self.keepAliveIdleTimer = timer
        self.keepAliveIdleTimerDeadline = deadline
        timer.start()
    }

    private func beginBackgroundExtensionTaskIfNeeded() {
        // Reuse the live task: state updates must not reset its expiry timer or
        // repeatedly acquire/end UIKit background assertions.
        guard self.currentTask == nil, !self.backgroundExtensionBudgetExhausted else {
            return
        }
        var actualTaskId: UIBackgroundTaskIdentifier?
        let handleExpiration: () -> Void = { [weak self] in
            guard let self, let actualTaskId, let (taskId, _, timer) = self.currentTask, taskId == actualTaskId else {
                return
            }
            timer.invalidate()
            self.backgroundExtensionBudgetExhausted = self.backgroundTimeRemaining() <= 5.0
            self.currentTask = nil
            self.isInBackgroundExtension = false
            self.endBackgroundTask(taskId)
            self.checkTasks()
        }
        if let taskId = self.beginBackgroundTask("background-wakeup", handleExpiration) {
            actualTaskId = taskId
            // Acquiring the first assertion can grant time that was unavailable
            // before beginBackgroundTask. Measure only after it succeeds.
            let timer = SwiftSignalKit.Timer(timeout: min(30.0, max(0.0, self.backgroundTimeRemaining() - 5.0)), repeat: false, completion: handleExpiration, queue: Queue.mainQueue())
            self.currentTask = (taskId, CFAbsoluteTimeGetCurrent(), timer)
            self.isInBackgroundExtension = true
            timer.start()
        } else {
            self.backgroundExtensionBudgetExhausted = true
        }
    }

    func checkTasks() {
        var hasTasksForBackgroundExtension = false
        
        var hasActiveCalls = false
        var pendingMessageCount = 0
        for (_, _, tasks) in self.accountsAndTasks {
            if tasks.activeCalls {
                hasActiveCalls = true
            }
            pendingMessageCount += tasks.importantTasks.pendingMessageCount
        }
        
        var endTaskAfterTransactionsComplete: UIBackgroundTaskIdentifier?
        
        if self.inForeground || self.hasActiveAudioSession || hasActiveCalls {
            if let (completion, timer) = self.currentExternalCompletion {
                self.currentExternalCompletion = nil
                completion()
                timer.invalidate()
            }
            
            if let (taskId, _, timer) = self.currentTask {
                self.currentTask = nil
                timer.invalidate()
                self.endBackgroundTask(taskId)
                self.isInBackgroundExtension = false
            }
        } else {
            for (_, _, tasks) in self.accountsAndTasks {
                if !tasks.isEmpty {
                    hasTasksForBackgroundExtension = true
                    break
                }
            }
            
            if !hasTasksForBackgroundExtension && self.currentExternalCompletionValidationTimer == nil {
                if let (completion, timer) = self.currentExternalCompletion {
                    self.currentExternalCompletion = nil
                    completion()
                    timer.invalidate()
                }
            }
            
            if self.activeExplicitExtensionTimer != nil {
                hasTasksForBackgroundExtension = true
            }
            
            let canBeginBackgroundExtensionTasks = self.allowBackgroundTimeExtensionDeadline.flatMap({ CFAbsoluteTimeGetCurrent() < $0 }) ?? false
            if hasTasksForBackgroundExtension {
                if canBeginBackgroundExtensionTasks {
                    self.beginBackgroundExtensionTaskIfNeeded()
                }
            } else if let (taskId, _, timer) = self.currentTask {
                self.currentTask = nil
                
                timer.invalidate()
                
                endTaskAfterTransactionsComplete = taskId
                
                self.isInBackgroundExtension = false
            }
        }
        
        if pendingMessageCount != 0 && !self.inForeground {
            if self.keepIdleDisposable == nil {
                self.keepIdleDisposable = self.acquireIdleExtension()
            }
        } else {
            if let keepIdleDisposable = self.keepIdleDisposable {
                self.keepIdleDisposable = nil
                keepIdleDisposable.dispose()
            }
        }
        
        let hasPrimaryAccount = self.accountsAndTasks.contains(where: { $0.1 })
        // SuperGram: while downloads are running, background audio keeps the app from being suspended even if
        // the notification keep-alive is off; it stops again once downloads finish.
        // AccountTasks applies the current setting to the retained download state. Both directions of
        // a setting change work without waiting for a download-activity emission.
        let hasBackgroundDownloads = self.accountsAndTasks.contains(where: { $0.2.hasBackgroundDownloads })
        if self.inForeground {
            self.silenceAudioInterrupted = false
            // SuperGram: the foreground is the strongest possible evidence that the keep-alive is worth running
            // again — it resets both duty-cycle deadlines.
            self.keepAliveLastActivityTimestamp = CFAbsoluteTimeGetCurrent()
        }
        // Evaluated unconditionally: it also owns the duty-cycle timer, which has to be torn down even when the
        // keep-alive setting itself is off.
        let keepAliveDutyCycleAllows = self.updateKeepAliveDutyCycle()
        let keepAliveForNotifications = self.superGramBackgroundKeepAliveEnabled && telegramLocalNotificationFallbackEnabled && keepAliveDutyCycleAllows
        // SuperGram: an "active" managed audio session only keeps the app running while something is really playing
        // (music / voice player, a call). A video left open in the gallery holds the session without producing
        // sound: iOS then suspends the app in the background — no notifications, and a Postbox transaction caught
        // mid-flight gets the process killed (device journal 2026-11-12: three suspensions and a crash right after
        // backgrounding with a gallery video open, keep-alive never started). Only real playback replaces the
        // silent keep-alive.
        let audioPlaybackKeepsAppRunning = self.hasActiveAudioSession && (hasActiveCalls || self.accountsAndTasks.contains(where: { $0.2.backgroundAudio || $0.2.activeCalls }))
        if (keepAliveForNotifications || hasBackgroundDownloads) && hasPrimaryAccount && !self.inForeground && !audioPlaybackKeepsAppRunning && !self.silenceAudioInterrupted {
            if self.silenceAudioRenderer == nil {
                let audioSession = AVAudioSession.sharedInstance()
                let silenceAudioRenderer = MediaPlayerAudioRenderer(
                    audioSession: .custom({ [weak self] control in
                        var activationError: Error?
                        do {
                            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                            try audioSession.setActive(true)
                            superGramNotificationLog("background audio session active")
                        } catch {
                            activationError = error
                            superGramNotificationLog("background audio session error: \(error)")
                        }
                        control.activate()

                        if let activationError {
                            // SuperGram: the session never became active, so nothing keeps the app running. Releasing
                            // the keep-alive through the interruption path lets updateAccounts() close Postbox
                            // transactions before iOS suspends the process (otherwise: 0xDEAD10CC).
                            Queue.mainQueue().async { [weak self] in
                                self?.markSilenceAudioUnavailable(reason: "activation failed: \(activationError)")
                            }
                        }

                        return ActionDisposable { [weak self] in
                            Queue.mainQueue().async {
                                // SuperGram: this runs after the stopped renderer is released on the audio queue;
                                // don't deactivate the shared session if a new silence renderer was started meanwhile
                                guard let self, !self.hasActiveAudioSession, self.silenceAudioRenderer == nil else {
                                    return
                                }
                                // SuperGram: AVAudioSession.setActive(false:) is a synchronous XPC round trip that
                                // can take tens of milliseconds. It runs when the keep-alive stops, which is
                                // typically the moment the app returns to the foreground, so keep it off the main
                                // thread; only the state check above needs to be on it.
                                Queue.concurrentDefaultQueue().async {
                                    try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
                                }
                            }
                        }
                    }),
                    forAudioVideoMessage: false,
                    playAndRecord: false,
                    useVoiceProcessingMode: false,
                    soundMuted: false,
                    ambient: true,
                    mixWithOthers: true,
                    forceAudioToSpeaker: false,
                    baseRate: 1.0,
                    audioLevelPipe: ValuePipe(),
                    updatedRate: {},
                    audioPaused: {}
                )
                self.silenceAudioRenderer = silenceAudioRenderer
                silenceAudioRenderer.start()
            }
        } else if let silenceAudioRenderer = self.silenceAudioRenderer {
            if !self.inForeground && !self.hasActiveAudioSession {
                self.beginSilenceAudioReleaseTask(name: "silence-audio-finished")
            }
            self.silenceAudioRenderer = nil
            silenceAudioRenderer.stop()
            superGramNotificationLog("background audio session stopped")
        }

        self.updateAccounts(hasTasks: hasTasksForBackgroundExtension, endTaskAfterTransactionsComplete: endTaskAfterTransactionsComplete)
    }
    
    private func updateAccounts(hasTasks: Bool, endTaskAfterTransactionsComplete: UIBackgroundTaskIdentifier?) {
        let hasBackgroundLocationTask = self.accountsAndTasks.contains(where: { $0.2.backgroundLocation })
        let hasActiveCallTask = self.accountsAndTasks.contains(where: { $0.2.activeCalls })
        
        if self.inForeground || self.hasActiveAudioSession || hasActiveCallTask || self.isInBackgroundExtension || self.backgroundProcessingTaskId != nil || self.backgroundStoryProcessingTaskId != nil || hasBackgroundLocationTask || (hasTasks && self.currentExternalCompletion != nil) || self.activeExplicitExtensionTimer != nil || self.silenceAudioRenderer != nil {
            Logger.shared.log("Wakeup", "enableBeginTransactions: true (active)")
            
            for (account, primary, tasks) in self.accountsAndTasks {
                account.postbox.setCanBeginTransactions(true)
                
                if (self.inForeground && primary) || !tasks.isEmpty || (self.activeExplicitExtensionTimer != nil && primary) || (self.silenceAudioRenderer != nil && primary) {
                    account.shouldBeServiceTaskMaster.set(.single(.always))
                } else {
                    account.shouldBeServiceTaskMaster.set(.single(.never))
                }
                // SuperGram: the silent-audio keep-alive needs the *service* connection above (updates -> local
                // notifications). It must not also pin the media worker connections: with nothing to transfer those
                // are idle sockets kept alive by pings for as long as the app stays backgrounded, which is pure
                // battery cost. Worker connections are still kept for the cases that actually use them below.
                account.shouldExplicitelyKeepWorkerConnections.set(.single(tasks.backgroundAudio || tasks.backgroundLocation || tasks.hasBackgroundDownloads || tasks.importantTasks.pendingStoryCount != 0 || tasks.importantTasks.pendingMessageCount != 0))
                account.shouldKeepOnlinePresence.set(.single(primary && self.inForeground))
                account.shouldKeepBackgroundDownloadConnections.set(.single(tasks.hasBackgroundDownloads))
            }
            
            if let endTaskAfterTransactionsComplete {
                self.endBackgroundTask(endTaskAfterTransactionsComplete)
            }
        } else {
            var enableBeginTransactions = false
            if self.allowBackgroundTimeExtensionDeadlineTimer != nil && !self.backgroundExtensionBudgetExhausted {
                enableBeginTransactions = true
            }
            Logger.shared.log("Wakeup", "enableBeginTransactions: \(enableBeginTransactions)")
            
            final class CompletionObservationState {
                var isCompleted: Bool = false
                var remainingAccounts: [AccountRecordId]
                
                init(remainingAccounts: [AccountRecordId]) {
                    self.remainingAccounts = remainingAccounts
                }
            }
            let completionState = Atomic<CompletionObservationState>(value: CompletionObservationState(remainingAccounts: self.accountsAndTasks.map(\.0.id)))
            let checkCompletionState: (AccountRecordId?) -> Void = { id in
                Queue.mainQueue().async {
                    var shouldComplete = false
                    completionState.with { state in
                        if let id {
                            state.remainingAccounts.removeAll(where: { $0 == id })
                        }
                        if state.remainingAccounts.isEmpty && !state.isCompleted {
                            state.isCompleted = true
                            shouldComplete = true
                        }
                    }
                    if shouldComplete, let endTaskAfterTransactionsComplete {
                        self.endBackgroundTask(endTaskAfterTransactionsComplete)
                    }
                }
            }
            
            for (account, _, _) in self.accountsAndTasks {
                let accountId = account.id
                account.postbox.setCanBeginTransactions(enableBeginTransactions, afterTransactionIfRunning: {
                    checkCompletionState(accountId)
                })
                account.shouldBeServiceTaskMaster.set(.single(.never))
                account.shouldExplicitelyKeepWorkerConnections.set(.single(false))
                account.shouldKeepOnlinePresence.set(.single(false))
                account.shouldKeepBackgroundDownloadConnections.set(.single(false))
            }
            
            checkCompletionState(nil)
        }
    }
}
