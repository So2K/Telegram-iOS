import Foundation
import UIKit
import UserNotifications
import Intents
import TelegramPresentationData
import TelegramUIPreferences
import SwiftSignalKit
import Postbox
import TelegramCore
import Display
import LegacyComponents
import DeviceAccess
import TelegramUpdateUI
import AccountContext
import AlertUI
import PresentationDataUtils
import TelegramPermissions
import TelegramNotices
import LegacyUI
import TelegramPermissionsUI
import PasscodeUI
import ImageBlur
import FastBlur
import SettingsUI
import AppLock
import AccountUtils
import ContextUI
import TelegramCallsUI
import AuthorizationUI
import ChatListUI
import StoryContainerScreen
import ChatMessageNotificationItem
import PhoneNumberFormat
import AttachmentUI
import MinimizedContainer
import BrowserUI
import TelegramStringFormatting

final class UnauthorizedApplicationContext {
    let sharedContext: SharedAccountContextImpl
    let account: UnauthorizedAccount
    
    let rootController: AuthorizationSequenceController
    
    let isReady = Promise<Bool>()
    
    var authorizationCompleted: Bool = false

    private var serviceNotificationEventsDisposable: Disposable?
    
    init(apiId: Int32, apiHash: String, sharedContext: SharedAccountContextImpl, account: UnauthorizedAccount, otherAccountPhoneNumbers: ((String, AccountRecordId, Bool)?, [(String, AccountRecordId, Bool)])) {
        self.sharedContext = sharedContext
        self.account = account
        let presentationData = sharedContext.currentPresentationData.with { $0 }
        
        var authorizationCompleted: (() -> Void)?
        
        self.rootController = AuthorizationSequenceController(sharedContext: sharedContext, account: account, otherAccountPhoneNumbers: otherAccountPhoneNumbers, presentationData: presentationData, openUrl: sharedContext.applicationBindings.openUrl, apiId: apiId, apiHash: apiHash, authorizationCompleted: {
            authorizationCompleted?()
        })
        (self.rootController as NavigationController).statusBarHost = sharedContext.mainWindow?.statusBarHost
        
        authorizationCompleted = { [weak self] in
            self?.authorizationCompleted = true
        }
        
        self.isReady.set(self.rootController.ready.get())
        
        account.shouldBeServiceTaskMaster.set(sharedContext.applicationBindings.applicationInForeground |> map { value -> AccountServiceTaskMasterMode in
            if value {
                return .always
            } else {
                return .never
            }
        })
        
        DeviceAccess.authorizeAccess(to: .cellularData, presentationData: sharedContext.currentPresentationData.with { $0 }, present: { [weak self] c, a in
            if let strongSelf = self {
                (strongSelf.rootController.viewControllers.last as? ViewController)?.present(c, in: .window(.root))
            }
        }, openSettings: {
            sharedContext.applicationBindings.openSettings()
        }, { result in
            ApplicationSpecificNotice.setPermissionWarning(accountManager: sharedContext.accountManager, permission: .cellularData, value: 0)
        })

        self.serviceNotificationEventsDisposable = (account.serviceNotificationEvents
        |> deliverOnMainQueue).start(next: { [weak self] text in
            if let strongSelf = self {
                let presentationData = strongSelf.sharedContext.currentPresentationData.with { $0 }
                let alertController = textAlertController(sharedContext: strongSelf.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})])

                (strongSelf.rootController.viewControllers.last as? ViewController)?.present(alertController, in: .window(.root))
            }
        })
    }

    deinit {
        self.serviceNotificationEventsDisposable?.dispose()
    }
}

private struct BackgroundMessageNotificationAlbumKey: Hashable {
    let peerId: PeerId
    let namespace: Int32
    let groupingKey: Int64
}

private func coalescedBackgroundMessageNotificationBatch(_ messageList: [([Message], PeerGroupId, Bool, MessageHistoryThreadData?)]) -> [([Message], PeerGroupId, Bool, MessageHistoryThreadData?)] {
    // This batch belongs to one account context. Each incoming album member can resolve to the
    // same complete album, with that member first; schedule only the first eligible entry here.
    var seenAlbums = Set<BackgroundMessageNotificationAlbumKey>()
    var result: [([Message], PeerGroupId, Bool, MessageHistoryThreadData?)] = []
    result.reserveCapacity(messageList.count)
    for entry in messageList {
        guard entry.2, let firstMessage = entry.0.first else {
            continue
        }
        // Scheduled reminders keep their existing semantics and do not consume an incoming album key.
        if !firstMessage.flags.contains(.WasScheduled), let groupingKey = firstMessage.groupingKey {
            let key = BackgroundMessageNotificationAlbumKey(peerId: firstMessage.id.peerId, namespace: firstMessage.id.namespace, groupingKey: groupingKey)
            guard seenAlbums.insert(key).inserted else {
                continue
            }
        }
        result.append(entry)
    }
    return result
}

// SuperGram: how long the background local fallback waits for the server's plaintext APNs alert before it decides
// the push did not come (see AuthorizedApplicationContext.scheduleBackgroundMessageNotification).
private let superGramApnsDeduplicationDelay: Double = 4.0

// SuperGram: true when `notification` is a server APNs alert (not this fork's local fallback) for `messageId`.
// Plaintext Telegram pushes carry msg_id plus from_id / chat_id / channel_id (or encryption_id for secret chats),
// either at the top level or inside the "custom" dictionary; both locations are accepted.
private func superGramApnsNotification(_ notification: UNNotification, covers messageId: MessageId) -> Bool {
    let userInfo = notification.request.content.userInfo
    if (userInfo[telegramLocalNotificationFallbackKey] as? Bool) == true {
        return false
    }
    var payloads: [[AnyHashable: Any]] = [userInfo]
    if let custom = userInfo["custom"] as? [AnyHashable: Any] {
        payloads.append(custom)
    }
    let peerRawId = messageId.peerId.id._internalGetInt64Value()
    for payload in payloads {
        if messageId.peerId.namespace == Namespaces.Peer.SecretChat {
            // The secret-chat push is the generic ENCRYPTED_MESSAGE alert without a message id.
            if let encryptionId = managedNotificationPayloadInt64(payload["encryption_id"]), encryptionId == peerRawId {
                return true
            }
            continue
        }
        guard let pushMessageId = managedNotificationPayloadInt64(payload["msg_id"]), pushMessageId == Int64(messageId.id) else {
            continue
        }
        for key in ["from_id", "chat_id", "channel_id"] {
            if let value = managedNotificationPayloadInt64(payload[key]), value == peerRawId {
                return true
            }
        }
    }
    return false
}

final class AuthorizedApplicationContext {
    let sharedApplicationContext: SharedApplicationContext
    let mainWindow: Window1
    let lockedCoveringView: LockedWindowCoveringView
    
    let context: AccountContextImpl
    
    let rootController: TelegramRootController
    let notificationController: NotificationContainerController
    
    private let scheduledCallPeerDisposable = MetaDisposable()
    private var scheduledOpenExternalUrl: URL?
        
    private let passcodeStatusDisposable = MetaDisposable()
    private let passcodeLockDisposable = MetaDisposable()
    private let loggedOutDisposable = MetaDisposable()
    private let inAppNotificationSettingsDisposable = MetaDisposable()
    private let notificationMessagesDisposable = MetaDisposable()
    private let termsOfServiceUpdatesDisposable = MetaDisposable()
    private let termsOfServiceProceedToBotDisposable = MetaDisposable()
    private let watchNavigateToMessageDisposable = MetaDisposable()
    private let permissionsDisposable = MetaDisposable()
    private let appUpdateInfoDisposable = MetaDisposable()
    // SuperGram: pending notification-tap resolution; a newer tap replaces (cancels) an older one.
    private let superGramNotificationOpenDisposable = MetaDisposable()

    private var inAppNotificationSettings: InAppNotificationSettings?
    
    var passcodeController: PasscodeEntryController?
    
    private var currentAppUpdateInfo: AppUpdateInfo?
    private var currentTermsOfServiceUpdate: TermsOfServiceUpdate?
    private var currentPermissionsController: PermissionController?
    private var currentPermissionsState: PermissionState?

    private func superGramGenericNotificationBody(key: String = "PUSH_ENCRYPTED_MESSAGE") -> String {
        // SuperGram: reuse an existing localisation instead of adding a new key to every language.
        var value = Bundle.main.localizedString(forKey: key, value: "You have a new message", table: nil)
        value = value.replacingOccurrences(of: "%1$@", with: "")
        value = value.replacingOccurrences(of: "%2$@", with: "")
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You have a new message" : trimmed
    }

    private func scheduleBackgroundMessageNotification(messages: [Message], notify: Bool) {
        guard telegramLocalNotificationFallbackEnabled, notify, let firstMessage = messages.first else {
            return
        }
        // The state-manager event retains the notification decision, including scheduled reminders.
        // Resolve preview/sound policy again: that event drops the per-chat/global/topic preview value,
        // and the in-app preview toggle alone cannot authorize a system notification's contents.
        let _ = (self.context.account.postbox.transaction { transaction -> (PeerMessageSound, Bool, Bool) in
            let (_, resolvedNotify, sound, displayContents, _) = messagesForNotification(transaction: transaction, id: firstMessage.id, alwaysReturnMessage: true)
            return (sound, displayContents, resolvedNotify)
        }
        |> deliverOnMainQueue
        |> mapToSignal { [weak self] sound, displayContents, resolvedNotify -> Signal<(Bool, PeerMessageSound, Bool, Bool), NoError> in
            guard let self else {
                return .complete()
            }
            // Take the lock snapshot after policy resolution, immediately before enqueueing on main.
            let appLockContext = self.context.sharedContext.appLockContext as? AppLockContextImpl
            let lockedSignal: Signal<Bool, NoError>
            if let appLockContext {
                // SuperGram: AppLockContextImpl.isCurrentlyLocked is `!appInForeground || locked`, i.e. always true
                // while the app is in the background — even with no passcode at all. That made every background
                // notification anonymous ("no sender, no text"). Only a configured passcode may hide the content.
                lockedSignal = combineLatest(
                    appLockContext.isCurrentlyLocked |> take(1),
                    self.context.sharedContext.accountManager.accessChallengeData() |> take(1)
                )
                |> map { isCurrentlyLocked, accessChallengeData -> Bool in
                    return isCurrentlyLocked && accessChallengeData.data.isLockable
                }
            } else {
                lockedSignal = .single(false)
            }
            return lockedSignal
            |> map { isLocked in
                return (isLocked, sound, displayContents, resolvedNotify)
            }
        }
        |> deliverOnMainQueue).start(next: { [weak self] policyAndLock in
            guard let self else {
                return
            }
            // SuperGram: de-duplication with plaintext APNs alerts. When this account's token is registered without
            // a secret (no NotificationService extension, see SharedAccountContext), the server pushes a readable
            // alert for every unmuted, unread message while the client is offline, and iOS displays it by itself
            // while the app is in the background. Posting the local fallback as well would show the message twice.
            // In the foreground-inactive state the APNs alert goes through willPresent, which suppresses it for the
            // current account, so the fallback stays the only notification there and is posted immediately.
            // In the background, wait briefly and post the fallback only if no APNs alert for this message has been
            // delivered — this keeps the fallback for whatever APNs does not cover (muted chats with an override,
            // a server that skipped the push because the session was still online, a push that never arrived).
            let accountId = self.context.account.id
            let serverWillPush = policyAndLock.3
            SuperGramNotificationDiagnostics.shared.log("fallback candidate msg=\(firstMessage.id.peerId.namespace._internalGetInt32Value()):\(firstMessage.id.peerId.id._internalGetInt64Value()):\(firstMessage.id.id) account=\(accountId.int64) locked=\(policyAndLock.0) displayContents=\(policyAndLock.2) notify=\(serverWillPush) inAppPreviews=\((self.inAppNotificationSettings ?? InAppNotificationSettings.defaultSettings).displayPreviews)")
            let isPlaintextPushAccount = superGramPlaintextPushAccountIds.with { $0.contains(accountId) }
            if serverWillPush && isPlaintextPushAccount && UIApplication.shared.applicationState == .background {
                let messageId = firstMessage.id
                Queue.mainQueue().after(superGramApnsDeduplicationDelay, { [weak self] in
                    UNUserNotificationCenter.current().getDeliveredNotifications(completionHandler: { delivered in
                        let coveredByApns = delivered.contains(where: { superGramApnsNotification($0, covers: messageId) })
                        Queue.mainQueue().async {
                            guard let self else {
                                return
                            }
                            if coveredByApns {
                                superGramNotificationLog("skipped \(messageId): delivered by APNs")
                                return
                            }
                            self.enqueueBackgroundMessageNotification(messages: messages, notify: notify, isLocked: policyAndLock.0, sound: policyAndLock.1, displayContents: policyAndLock.2)
                        }
                    })
                })
            } else {
                self.enqueueBackgroundMessageNotification(messages: messages, notify: notify, isLocked: policyAndLock.0, sound: policyAndLock.1, displayContents: policyAndLock.2)
            }
        })
    }

    private func enqueueBackgroundMessageNotification(messages: [Message], notify: Bool, isLocked: Bool, sound: PeerMessageSound, displayContents: Bool) {
        guard telegramLocalNotificationFallbackEnabled, notify, let firstMessage = messages.first else {
            return
        }
        if let forwardInfo = firstMessage.forwardInfo, forwardInfo.flags.contains(.isImported) {
            return
        }
        for media in firstMessage.media {
            if let action = media as? TelegramMediaAction {
                if case .messageAutoremoveTimeoutUpdated = action.action {
                    return
                } else if case .conferenceCall = action.action {
                    return
                }
            }
        }

        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        guard let peer = messageMainPeer(EngineMessage(firstMessage)) else {
            return
        }

        // SuperGram: secret chats never get a content preview in a system notification. The server-side push for a
        // secret chat is the generic ENCRYPTED_MESSAGE payload with no sender, and this local fallback must not be
        // more revealing than the push path it replaces — a delivered notification persists in Notification Center,
        // on the lock screen and on a paired watch.
        let isSecretChat = firstMessage.id.peerId.namespace == Namespaces.Peer.SecretChat

        let content = UNMutableNotificationContent()
        content.title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)

        let (description, _, _) = descriptionStringForMessage(
            contentSettings: self.context.currentContentSettings.with { $0 },
            message: EngineMessage(firstMessage),
            strings: presentationData.strings,
            nameDisplayOrder: presentationData.nameDisplayOrder,
            dateTimeFormat: presentationData.dateTimeFormat,
            accountPeerId: self.context.account.peerId
        )
        var body = description.string
        if body.isEmpty {
            body = firstMessage.text
        }
        if let author = firstMessage.author, author.id != peer.id {
            body = "\(EnginePeer(author).compactDisplayTitle): \(body)"
        }
        let inAppNotificationSettings = self.inAppNotificationSettings ?? InAppNotificationSettings.defaultSettings
        let isMuted = firstMessage.attributes.contains(where: { attribute in
            if let attribute = attribute as? NotificationInfoMessageAttribute {
                return attribute.flags.contains(.muted)
            }
            return false
        })
        if isSecretChat {
            // No sender and no content for secret chats, exactly like the ENCRYPTED_MESSAGE push.
            content.title = ""
            body = self.superGramGenericNotificationBody(key: "PUSH_ENCRYPTED_MESSAGE")
        } else if isLocked {
            // SuperGram: never leak the sender or the message text while a passcode-protected app is locked.
            content.title = ""
            body = self.superGramGenericNotificationBody(key: "PUSH_LOCKED_MESSAGE")
        } else if !displayContents || !inAppNotificationSettings.displayPreviews {
            // SuperGram: "Message preview" off (per chat or for the chat type) hides the text but, like the official
            // client, still says who wrote.
            body = self.superGramGenericNotificationBody(key: "PUSH_ENCRYPTED_MESSAGE")
        } else if body.isEmpty {
            body = self.superGramGenericNotificationBody()
        }
        content.body = body
        SuperGramNotificationDiagnostics.shared.log("fallback content msg=\(firstMessage.id.id) title=\(content.title.isEmpty ? "<empty>" : "\(content.title.count)ch") body=\(body.count)ch secret=\(isSecretChat) locked=\(isLocked) displayContents=\(displayContents) muted=\(isMuted)")
        content.sound = (isMuted || sound == .none || !inAppNotificationSettings.playSounds) ? nil : .default

        if let channel = firstMessage.peers[firstMessage.id.peerId] as? TelegramChannel {
            if case .broadcast = channel.info {
                content.categoryIdentifier = "c"
            } else {
                content.categoryIdentifier = "gr"
            }
        } else if firstMessage.id.peerId.namespace == Namespaces.Peer.CloudGroup {
            content.categoryIdentifier = "gr"
        } else {
            content.categoryIdentifier = "r"
        }

        content.threadIdentifier = "account-\(self.context.account.id.int64)-peer-\(firstMessage.id.peerId.toInt64())"
        var userInfo: [AnyHashable: Any] = [
            // SuperGram: marks a notification produced by this fork's local fallback. The app can be in the
            // foreground-but-inactive state (app switcher, Control Center, call banner) when the request is added,
            // in which case `userNotificationCenter(_:willPresent:)` runs and would otherwise suppress it while the
            // in-app overlay path was already skipped — the notification would be lost entirely.
            telegramLocalNotificationFallbackKey: true,
            "accountId": "\(self.context.account.id.int64)",
            "peerId": "\(firstMessage.id.peerId.toInt64())",
            "msg_id": "\(firstMessage.id.id)",
            "messageId.namespace": firstMessage.id.namespace,
            "messageId.id": firstMessage.id.id
        ]
        // SuperGram: every supergroup message carries a thread id (1 or the replied-to message id); only a real forum
        // topic may be stored, otherwise a tap would open a fake, empty "topic" screen
        if let threadId = firstMessage.threadId {
            var isForumThread = false
            if let channel = firstMessage.peers[firstMessage.id.peerId] as? TelegramChannel {
                isForumThread = channel.flags.contains(.isForum) || channel.flags.contains(.isMonoforum)
            } else if let user = firstMessage.peers[firstMessage.id.peerId] as? TelegramUser, let botInfo = user.botInfo {
                isForumThread = botInfo.flags.contains(.hasForum)
            }
            if isForumThread {
                userInfo["threadId"] = threadId
            }
        }
        content.userInfo = userInfo
        if #available(iOS 15.0, *) {
            // SuperGram: muted chats and secret chats must not bypass Focus.
            if isMuted || firstMessage.id.peerId.namespace == Namespaces.Peer.SecretChat {
                content.interruptionLevel = .active
            } else {
                content.interruptionLevel = .timeSensitive
            }
            content.relevanceScore = 1.0
        }

        // Account identity prevents the same channel message on two accounts from replacing the other request.
        let identifier = "a\(self.context.account.id.int64):m\(firstMessage.id.peerId.toInt64()):\(firstMessage.id.namespace):\(firstMessage.id.id)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        let notificationCenter = UNUserNotificationCenter.current()
        // SuperGram: tell the wakeup manager that the background keep-alive just earned its battery cost, so its
        // idle duty cycle does not stop it under an active conversation (see SharedWakeupManager, P0-1).
        superGramNoteBackgroundNotificationActivity()
        notificationCenter.add(request, withCompletionHandler: { error in
            if let error {
                superGramNotificationLog("failed to add \(identifier): \(error)")
            } else {
                superGramNotificationLog("added \(identifier)")
            }
        })
    }
    
    private let unlockedStatePromise = Promise<Bool>()
    var unlockedState: Signal<Bool, NoError> {
        return self.unlockedStatePromise.get()
    }
    
    var applicationBadge: Signal<Int32, NoError> {
        return renderedTotalUnreadCount(accountManager: self.context.sharedContext.accountManager, engine: self.context.engine)
        |> map {
            $0.0
        }
    }
    
    let isReady = Promise<Bool>()
    
    private var presentationDataDisposable: Disposable?
    private var displayAlertsDisposable: Disposable?
    private var removeNotificationsDisposable: Disposable?
    
    private var applicationInForegroundDisposable: Disposable?
    
    private var showCallsTab: Bool
    private var showCallsTabDisposable: Disposable?
    private var enablePostboxTransactionsDiposable: Disposable?
    
    init(sharedApplicationContext: SharedApplicationContext, mainWindow: Window1, context: AccountContextImpl, accountManager: AccountManager<TelegramAccountManagerTypes>, showCallsTab: Bool, reinitializedNotificationSettings: @escaping () -> Void) {
        self.sharedApplicationContext = sharedApplicationContext
        
        setupLegacyComponents(context: context)
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        self.mainWindow = mainWindow
        self.lockedCoveringView = LockedWindowCoveringView(theme: presentationData.theme)
        
        self.context = context
        
        self.showCallsTab = showCallsTab
        
        self.notificationController = NotificationContainerController(context: context)
        
        self.rootController = TelegramRootController(context: context)
        self.rootController.minimizedContainer = self.sharedApplicationContext.minimizedContainer[context.account.id]
        self.rootController.minimizedContainerUpdated = { [weak self] minimizedContainer in
            guard let self else {
                return
            }
            self.sharedApplicationContext.minimizedContainer[self.context.account.id] = minimizedContainer
        }
        
        self.rootController.globalOverlayControllersUpdated = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            var hasContext = false
            for controller in strongSelf.rootController.globalOverlayControllers {
                if controller is ContextController {
                    hasContext = true
                    break
                }
            }
            
            strongSelf.notificationController.updateIsTemporaryHidden(hasContext)
        }
        
        if KeyShortcutsController.isAvailable {
            let keyShortcutsController = KeyShortcutsController { [weak self] f in
                if let strongSelf = self, let appLockContext = strongSelf.context.sharedContext.appLockContext as? AppLockContextImpl {
                    let _ = (appLockContext.isCurrentlyLocked
                    |> take(1)
                    |> deliverOnMainQueue).start(next: { locked in
                        guard !locked else {
                            return
                        }
                        if let tabController = strongSelf.rootController.rootTabController {
                            let selectedController = tabController.controllers[tabController.selectedIndex]
                            
                            if let index = strongSelf.rootController.viewControllers.lastIndex(where: { controller in
                                guard let controller = controller as? ViewController else {
                                    return false
                                }
                                if controller === tabController {
                                    return false
                                }
                                switch controller.navigationPresentation {
                                case .master:
                                    return true
                                default:
                                    break
                                }
                                return false
                            }), let controller = strongSelf.rootController.viewControllers[index] as? ViewController {
                                if !f(controller) {
                                    return
                                }
                            } else {
                                if !f(selectedController) {
                                    return
                                }
                            }
                            
                            if let controller = strongSelf.rootController.topViewController as? ViewController, controller !== selectedController {
                                if !f(controller) {
                                    return
                                }
                            }
                        }
                        strongSelf.mainWindow.forEachViewController(f)
                        if let globalOverlayController = strongSelf.rootController.globalOverlayControllers.last {
                            if !f(globalOverlayController) {
                                return
                            }
                        }
                    })
                }
            }
            context.keyShortcutsController = keyShortcutsController
        }
        
        if self.rootController.rootTabController == nil {
            self.rootController.addRootControllers(showCallsTab: self.showCallsTab)
        }
        // SuperGram: one-time switch of existing installs to the new default (no Contacts / Calls tabs). Later
        // changes made in Settings are kept.
        if !UserDefaults.standard.bool(forKey: "sgTabsDefaultMigration1") {
            UserDefaults.standard.set(true, forKey: "sgTabsDefaultMigration1")
            let _ = updateCallListSettingsInteractively(accountManager: accountManager, { settings in
                return settings.withUpdatedShowContactsTab(false).withUpdatedShowTab(false)
            }).start()
        }
        if let tabsController = self.rootController.viewControllers.first as? TabBarController, !tabsController.controllers.isEmpty, tabsController.selectedIndex >= 0 {
            let controller = tabsController.controllers[tabsController.selectedIndex]
            let combinedReady = combineLatest(tabsController.ready.get(), controller.ready.get())
            |> map { $0 && $1 }
            |> filter { $0 }
            |> take(1)
            self.isReady.set(combinedReady)
        } else {
            self.isReady.set(.single(true))
        }
        
        let accountId = context.account.id
        self.loggedOutDisposable.set((context.account.loggedOut
        |> deliverOnMainQueue).start(next: { [weak self] value in
            if value {
                Logger.shared.log("ApplicationContext", "account logged out")
                let _ = logoutFromAccount(id: accountId, accountManager: accountManager, alreadyLoggedOutRemotely: false).start()
                if let strongSelf = self {
                    strongSelf.rootController.currentWindow?.forEachController { controller in
                        if let controller = controller as? TermsOfServiceController {
                            controller.dismiss()
                        }
                    }
                }
            }
        }))
        
        self.inAppNotificationSettingsDisposable.set(((context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.inAppNotificationSettings])) |> deliverOnMainQueue).start(next: { [weak self] sharedData in
            if let strongSelf = self {
                if let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.inAppNotificationSettings]?.get(InAppNotificationSettings.self) {
                    let previousSettings = strongSelf.inAppNotificationSettings
                    strongSelf.inAppNotificationSettings = settings
                    if let previousSettings = previousSettings, previousSettings.displayNameOnLockscreen != settings.displayNameOnLockscreen {
                        reinitializedNotificationSettings()
                    }
                }
            }
        }))

        let engine = context.engine
        self.notificationMessagesDisposable.set((context.account.stateManager.notificationMessages
        |> mapToSignal { messageList -> Signal<[([Message], PeerGroupId, Bool, MessageHistoryThreadData?)], NoError> in
            return engine.data.get(EngineDataMap(
                messageList.compactMap { item -> TelegramEngine.EngineData.Item.Messages.ChatListIndex? in
                    if let message = item.0.first {
                        return TelegramEngine.EngineData.Item.Messages.ChatListIndex(id: message.id.peerId)
                    } else {
                        return nil
                    }
                }
            ))
            |> map { chatListIndexMap -> [([Message], PeerGroupId, Bool, MessageHistoryThreadData?)] in
                return messageList.filter { item in
                    guard let message = item.0.first else {
                        return false
                    }
                    if let maybeChatListIndex = chatListIndexMap[message.id.peerId], maybeChatListIndex != nil {
                        return true
                    } else {
                        return false
                    }
                }
            }
        }
        |> deliverOn(Queue.mainQueue())).start(next: { [weak self] messageList in
            if messageList.isEmpty {
                return
            }

            if let strongSelf = self, let (messages, _, notify, threadData) = messageList.last, let firstMessage = messages.first {
                if UIApplication.shared.applicationState == .active {
                    let chatLocation: NavigateToChatControllerParams.Location
                    if let _ = threadData, let threadId = firstMessage.threadId {
                        chatLocation = .replyThread(ChatReplyThreadMessage(
                            peerId: firstMessage.id.peerId, threadId: threadId, channelMessageId: nil, isChannelPost: false, isForumPost: true, isMonoforumPost: false, maxMessage: nil, maxReadIncomingMessageId: nil, maxReadOutgoingMessageId: nil, unreadCount: 0, initialFilledHoles: IndexSet(), initialAnchor: .automatic, isNotAvailable: false
                        ).normalized)
                    } else {
                        guard let peer = firstMessage.peers[firstMessage.id.peerId] else {
                            return
                        }
                        chatLocation = .peer(EnginePeer(peer))
                    }
                    
                    var chatIsVisible = false
                    if let topController = strongSelf.rootController.topViewController as? ChatControllerImpl, topController.traceVisibility() {
                        if topController.chatLocation.peerId == firstMessage.id.peerId, (topController.chatLocation.threadId == nil || topController.chatLocation.threadId == firstMessage.threadId) {
                            chatIsVisible = true
                        }
                    }
                    
                    if !notify {
                        chatIsVisible = true
                    }
                    
                    if !chatIsVisible {
                        strongSelf.mainWindow.forEachViewController({ controller in
                            if let controller = controller as? ChatControllerImpl, controller.chatLocation.peerId == chatLocation.peerId, (chatLocation.threadId == nil || chatLocation.threadId == controller.chatLocation.threadId) {
                                chatIsVisible = true
                                return false
                            }
                            return true
                        })
                    }
                    
                    let inAppNotificationSettings: InAppNotificationSettings
                    if let current = strongSelf.inAppNotificationSettings {
                        inAppNotificationSettings = current
                    } else {
                        inAppNotificationSettings = InAppNotificationSettings.defaultSettings
                    }
                    
                    if let appLockContext = strongSelf.context.sharedContext.appLockContext as? AppLockContextImpl {
                        let _ = (appLockContext.isCurrentlyLocked
                        |> take(1)
                        |> deliverOnMainQueue).start(next: { locked in
                            guard let strongSelf = self else {
                                return
                            }
                            
                            guard !locked else {
                                return
                            }
                            let isMuted = firstMessage.attributes.contains(where: { attribute in
                                if let attribute = attribute as? NotificationInfoMessageAttribute {
                                    return attribute.flags.contains(.muted)
                                } else {
                                    return false
                                }
                            })
                            if !isMuted {
                                if firstMessage.id.peerId == context.account.peerId, !firstMessage.flags.contains(.WasScheduled) {
                                } else {
                                    if inAppNotificationSettings.playSounds {
                                        serviceSoundManager.playIncomingMessageSound()
                                    }
                                    if inAppNotificationSettings.vibrate {
                                        serviceSoundManager.playVibrationSound()
                                    }
                                }
                            }
                            if let forwardInfo = firstMessage.forwardInfo, forwardInfo.flags.contains(.isImported) {
                                return
                            }
                            for media in firstMessage.media {
                                if let action = media as? TelegramMediaAction {
                                    if case .messageAutoremoveTimeoutUpdated = action.action {
                                        return
                                    } else if case .conferenceCall = action.action {
                                        return
                                    }
                                }
                            }
                            
                            if chatIsVisible {
                                return
                            }
                            
                            if firstMessage.restrictionReason(platform: "ios", contentSettings: strongSelf.context.currentContentSettings.with { $0 }) != nil {
                                return
                            }
                            if let chatPeer = firstMessage.peers[firstMessage.id.peerId] {
                                if EnginePeer(chatPeer).restrictionText(platform: "ios", contentSettings: strongSelf.context.currentContentSettings.with { $0 }) != nil {
                                    return
                                }
                            }
                            
                            if inAppNotificationSettings.displayPreviews {
                                let presentationData = strongSelf.context.sharedContext.currentPresentationData.with { $0 }
                                strongSelf.notificationController.enqueue(ChatMessageNotificationItem(context: strongSelf.context, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, messages: messages, threadData: threadData, tapAction: {
                                    if let strongSelf = self {
                                        var foundOverlay = false
                                        strongSelf.mainWindow.forEachViewController({ controller in
                                            if isOverlayControllerForChatNotificationOverlayPresentation(controller) {
                                                foundOverlay = true
                                                return false
                                            }
                                            return true
                                        }, excludeNavigationSubControllers: true)
                                        
                                        if foundOverlay {
                                            return true
                                        }
                                        
                                        if let topController = strongSelf.rootController.topViewController as? ViewController, isInlineControllerForChatNotificationOverlayPresentation(topController) {
                                            return true
                                        }
                                        
                                        if let topController = strongSelf.rootController.topViewController as? ChatControllerImpl, topController.chatLocation.peerId == chatLocation.peerId, (topController.chatLocation.threadId == nil || topController.chatLocation.threadId == chatLocation.threadId) {
                                            strongSelf.notificationController.removeItemsWithGroupingKey(firstMessage.id.peerId)
                                            
                                            return false
                                        }

                                        // A regular tap navigates to the chat, including an existing controller lower
                                        // in the stack. The banner's explicit expansion gesture owns the reply overlay.
                                        let proceedAction: () -> Bool = {
                                            if let minimizedContainer = strongSelf.rootController.minimizedContainer, minimizedContainer.isExpanded {
                                                minimizedContainer.collapse()
                                            } else if let topContoller = strongSelf.rootController.topViewController as? AttachmentController {
                                                topContoller.minimizeIfNeeded()
                                            }  else if let topContoller = strongSelf.rootController.topViewController as? BrowserScreen {
                                                topContoller.requestMinimize(topEdgeOffset: nil, initialVelocity: nil)
                                            }

                                            strongSelf.notificationController.removeItemsWithGroupingKey(firstMessage.id.peerId)

                                            var processed = false
                                            for media in firstMessage.media {
                                                if let action = media as? TelegramMediaAction, case .geoProximityReached = action.action {
                                                    strongSelf.context.sharedContext.openLocationScreen(context: strongSelf.context, messageId: firstMessage.id, navigationController: strongSelf.rootController)
                                                    processed = true
                                                    break
                                                }
                                            }

                                            if !processed {
                                                // SuperGram: same routing as a system notification tap — topic / discussion
                                                // thread / Replies source at the message instead of the bare chat root.
                                                strongSelf.openChatFromNotification(peerId: firstMessage.id.peerId, threadId: chatLocation.threadId, messageId: firstMessage.id, storyId: nil)
                                            }

                                            return false
                                        }

                                        if let topController = strongSelf.rootController.topViewController as? ChatControllerImpl {
                                            let didPresentAlert = topController.presentVoiceMessageDiscardAlert(action: {
                                                let _ = proceedAction()
                                            }, discardIfVideo: true, performAction: false)
                                            if didPresentAlert {
                                                return false
                                            }
                                        }
                                        
                                        return proceedAction()
                                    }
                                    return false
                                }, expandAction: { expandData in
                                    if let strongSelf = self {
                                        let chatController = ChatControllerImpl(context: strongSelf.context, chatLocation: chatLocation.asChatLocation, mode: .overlay(strongSelf.rootController))
                                        chatController.presentationArguments = ChatControllerOverlayPresentationData(expandData: expandData())
                                        (strongSelf.rootController.viewControllers.last as? ViewController)?.present(chatController, in: .window(.root), with: ChatControllerOverlayPresentationData(expandData: expandData()))
                                    }
                                }))
                            }
                        })
                    }
                } else if UIApplication.shared.applicationState != .active {
                    // SuperGram: notify while the app is merely inactive as well (app switcher, call banner,
                    // partial cover), not only when it is fully in the background. The fallback replaces the
                    // missing push path for this fork.
                    for (backgroundMessages, _, backgroundNotify, _) in coalescedBackgroundMessageNotificationBatch(messageList) {
                        strongSelf.scheduleBackgroundMessageNotification(messages: backgroundMessages, notify: backgroundNotify)
                    }
                }
            }
        }))
        
        self.termsOfServiceUpdatesDisposable.set((context.account.stateManager.termsOfServiceUpdate
        |> deliverOnMainQueue).start(next: { [weak self] termsOfServiceUpdate in
            guard let strongSelf = self, strongSelf.currentTermsOfServiceUpdate != termsOfServiceUpdate else {
                return
            }
            
            strongSelf.currentTermsOfServiceUpdate = termsOfServiceUpdate
            if let termsOfServiceUpdate = termsOfServiceUpdate {
                let presentationData = strongSelf.context.sharedContext.currentPresentationData.with { $0 }
                var acceptImpl: ((String?) -> Void)?
                var declineImpl: (() -> Void)?
                let controller = TermsOfServiceController(context: strongSelf.context, presentationData: presentationData, text: termsOfServiceUpdate.text, entities: termsOfServiceUpdate.entities, ageConfirmation: termsOfServiceUpdate.ageConfirmation, signingUp: false, accept: { proccedBot in
                    acceptImpl?(proccedBot)
                }, decline: {
                    declineImpl?()
                }, openUrl: { url in
                    if let parsedUrl = URL(string: url) {
                        UIApplication.shared.open(parsedUrl, options: [:], completionHandler: nil)
                    }
                })
                
                acceptImpl = { [weak controller] botName in
                    controller?.inProgress = true
                    guard let strongSelf = self else {
                        return
                    }
                    let _ = (strongSelf.context.engine.accountData.acceptTermsOfService(id: termsOfServiceUpdate.id)
                    |> deliverOnMainQueue).start(completed: {
                        controller?.dismiss()
                        if let strongSelf = self, let botName = botName {
                            strongSelf.termsOfServiceProceedToBotDisposable.set((strongSelf.context.engine.peers.resolvePeerByName(name: botName, referrer: nil, ageLimit: 10)
                            |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                                guard case let .result(result) = result else {
                                    return .complete()
                                }
                                return .single(result)
                            }
                            |> deliverOnMainQueue).start(next: { peer in
                                if let strongSelf = self, let peer = peer {
                                    self?.rootController.pushViewController(ChatControllerImpl(context: strongSelf.context, chatLocation: .peer(id: peer.id)))
                                }
                            }))
                        }
                    })
                }
                
                declineImpl = { [weak controller] in
                    guard let strongSelf = self else {
                        return
                    }
                    let accountId = strongSelf.context.account.id
                    let accountManager = strongSelf.context.sharedContext.accountManager
                    let _ = (strongSelf.context.engine.auth.deleteAccount(reason: "GDPR", password: nil)
                    |> deliverOnMainQueue).start(error: { _ in
                        guard let strongSelf = self else {
                            return
                        }
                        let presentationData = strongSelf.context.sharedContext.currentPresentationData.with { $0 }
                        let controller = textAlertController(context: strongSelf.context, title: nil, text: presentationData.strings.Login_UnknownError, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})])
                        (strongSelf.rootController.viewControllers.last as? ViewController)?.present(controller, in: .window(.root))
                    }, completed: {
                        controller?.dismiss()
                        let _ = logoutFromAccount(id: accountId, accountManager: accountManager, alreadyLoggedOutRemotely: true).start()
                    })
                }
                
                (strongSelf.rootController.viewControllers.last as? ViewController)?.present(controller, in: .window(.root))
            }
        }))
        
        self.appUpdateInfoDisposable.set((context.account.stateManager.appUpdateInfo
        |> deliverOnMainQueue).start(next: { [weak self] appUpdateInfo in
            guard let strongSelf = self, strongSelf.currentAppUpdateInfo != appUpdateInfo else {
                return
            }
            
            strongSelf.currentAppUpdateInfo = appUpdateInfo
            if let appUpdateInfo = appUpdateInfo {
                let controller = updateInfoController(context: strongSelf.context, appUpdateInfo: appUpdateInfo)
                strongSelf.mainWindow.present(controller, on: .update)
            }
        }))
        
        if #available(iOS 10.0, *) {
            let permissionsPosition = ValuePromise(0, ignoreRepeated: true)
            self.permissionsDisposable.set((combineLatest(queue: .mainQueue(), requiredPermissions(context: context), permissionUISplitTest(postbox: context.account.postbox), permissionsPosition.get(), context.sharedContext.accountManager.noticeEntry(key: ApplicationSpecificNotice.permissionWarningKey(permission: .contacts)!), context.sharedContext.accountManager.noticeEntry(key: ApplicationSpecificNotice.permissionWarningKey(permission: .notifications)!), context.sharedContext.accountManager.noticeEntry(key: ApplicationSpecificNotice.permissionWarningKey(permission: .cellularData)!))
            |> deliverOnMainQueue).start(next: { [weak self] required, splitTest, position, contactsPermissionWarningNotice, notificationsPermissionWarningNotice, cellularDataPermissionWarningNotice in
                guard let strongSelf = self else {
                    return
                }
                
                let contactsTimestamp = contactsPermissionWarningNotice.value.flatMap({ ApplicationSpecificNotice.getTimestampValue($0) })
                let notificationsTimestamp = notificationsPermissionWarningNotice.value.flatMap({ ApplicationSpecificNotice.getTimestampValue($0) })
                let cellularDataTimestamp = cellularDataPermissionWarningNotice.value.flatMap({ ApplicationSpecificNotice.getTimestampValue($0) })
                if contactsTimestamp == nil, case .requestable = required.0.status {
                    ApplicationSpecificNotice.setPermissionWarning(accountManager: context.sharedContext.accountManager, permission: .contacts, value: 1)
                }
                if notificationsTimestamp == nil, case .requestable = required.1.status {
                    ApplicationSpecificNotice.setPermissionWarning(accountManager: context.sharedContext.accountManager, permission: .notifications, value: 1)
                }
                
                let config = splitTest.configuration
                var order = config.order
                if !order.contains(.cellularData) {
                    order.append(.cellularData)
                }
                if !order.contains(.siri) {
                    order.append(.siri)
                }
                var requestedPermissions: [(PermissionState, Bool)] = []
                var i: Int = 0
                for subject in order {
                    if i < position {
                        i += 1
                        continue
                    }
                    var modal = false
                    switch subject {
                        case .contacts:
                            if case .modal = config.contacts {
                                modal = true
                            }
                            if case .requestable = required.0.status, contactsTimestamp != 0 {
                                requestedPermissions.append((required.0, modal))
                            }
                        case .notifications:
                            if case .modal = config.notifications {
                                modal = true
                            }
                            if case .requestable = required.1.status, notificationsTimestamp != 0 {
                                requestedPermissions.append((required.1, modal))
                            }
                        case .cellularData:
                            if case .denied = required.2.status, cellularDataTimestamp != 0 {
                                requestedPermissions.append((required.2, true))
                            }
                        case .siri:
                            if case .requestable = required.3.status {
                                requestedPermissions.append((required.3, false))
                            }
                    }
                    i += 1
                }
                
                if let (state, modal) = requestedPermissions.first {
                    if modal {
                        var didAppear = false
                        let controller: PermissionController
                        if let currentController = strongSelf.currentPermissionsController {
                            controller = currentController
                            didAppear = true
                        } else {
                            controller = PermissionController(context: context, splitTest: splitTest)
                            strongSelf.currentPermissionsController = controller
                        }
                        
                        controller.setState(.permission(state), animated: didAppear)
                        controller.proceed = { resolved in
                            permissionsPosition.set(position + 1)
                            switch state {
                                case .contacts:
                                    ApplicationSpecificNotice.setPermissionWarning(accountManager: context.sharedContext.accountManager, permission: .contacts, value: 0)
                                case .notifications:
                                    ApplicationSpecificNotice.setPermissionWarning(accountManager: context.sharedContext.accountManager, permission: .notifications, value: 0)
                                case .cellularData:
                                    ApplicationSpecificNotice.setPermissionWarning(accountManager: context.sharedContext.accountManager, permission: .cellularData, value: 0)
                                default:
                                    break
                            }
                        }
                        
                        if !didAppear {
                            Queue.mainQueue().after(0.15, {
                                (strongSelf.rootController.viewControllers.last as? ViewController)?.present(controller, in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                            })
                        }
                    } else {
                        if strongSelf.currentPermissionsState != state {
                            strongSelf.currentPermissionsState = state
                            switch state {
                                case .contacts:
                                    splitTest.addEvent(.ContactsRequest)
                                    DeviceAccess.authorizeAccess(to: .contacts, presentationData: context.sharedContext.currentPresentationData.with { $0 }, { result in
                                        if result {
                                            splitTest.addEvent(.ContactsAllowed)
                                        } else {
                                            splitTest.addEvent(.ContactsDenied)
                                        }
                                        permissionsPosition.set(position + 1)
                                        ApplicationSpecificNotice.setPermissionWarning(accountManager: context.sharedContext.accountManager, permission: .contacts, value: 0)
                                    })
                                case .notifications:
                                    splitTest.addEvent(.NotificationsRequest)
                                    DeviceAccess.authorizeAccess(to: .notifications, registerForNotifications: { result in
                                        context.sharedContext.applicationBindings.registerForNotifications(result)
                                    }, { result in
                                        if result {
                                            splitTest.addEvent(.NotificationsAllowed)
                                        } else {
                                            splitTest.addEvent(.NotificationsDenied)
                                        }
                                        permissionsPosition.set(position + 1)
                                        ApplicationSpecificNotice.setPermissionWarning(accountManager: context.sharedContext.accountManager, permission: .notifications, value: 0)
                                    })
                                case .cellularData:
                                    DeviceAccess.authorizeAccess(to: .cellularData, presentationData: context.sharedContext.currentPresentationData.with { $0 }, present: { [weak self] c, a in
                                        if let strongSelf = self {
                                            (strongSelf.rootController.viewControllers.last as? ViewController)?.present(c, in: .window(.root))
                                        }
                                    }, openSettings: {
                                        context.sharedContext.applicationBindings.openSettings()
                                    }, { result in
                                        permissionsPosition.set(position + 1)
                                        ApplicationSpecificNotice.setPermissionWarning(accountManager: context.sharedContext.accountManager, permission: .cellularData, value: 0)
                                    })
                                case .siri:
                                    DeviceAccess.authorizeAccess(to: .siri, requestSiriAuthorization: { completion in
                                        return context.sharedContext.applicationBindings.requestSiriAuthorization(completion)
                                    }, { result in
                                        permissionsPosition.set(position + 1)
                                    })
                            }
                        }
                    }
                } else {
                    if let controller = strongSelf.currentPermissionsController {
                        strongSelf.currentPermissionsController = nil
                        controller.dismiss(completion: {})
                    }
                    strongSelf.currentPermissionsState = nil
                }
            }))
        }
        
        self.displayAlertsDisposable = (context.account.stateManager.displayAlerts
        |> deliverOnMainQueue).start(next: { [weak self] alerts in
            if let strongSelf = self {
                for (text, isDropAuth) in alerts {
                    let presentationData = strongSelf.context.sharedContext.currentPresentationData.with { $0 }
                    let actions: [TextAlertAction]
                    if isDropAuth {
                        actions = [TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}), TextAlertAction(type: .genericAction, title: presentationData.strings.LogoutOptions_LogOut, action: {
                            if let strongSelf = self {
                                let _ = logoutFromAccount(id: strongSelf.context.account.id, accountManager: strongSelf.context.sharedContext.accountManager, alreadyLoggedOutRemotely: false).start()
                            }
                        })]
                    } else {
                        actions = [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                    }
                    let controller = textAlertController(context: strongSelf.context, title: nil, text: text, actions: actions)
                    (strongSelf.rootController.viewControllers.last as? ViewController)?.present(controller, in: .window(.root))
                }
            }
        })
        
        self.removeNotificationsDisposable = (context.account.stateManager.appliedIncomingReadMessages
        |> deliverOnMainQueue).start(next: { [weak self] ids in
            if let strongSelf = self {
                strongSelf.context.sharedContext.applicationBindings.clearMessageNotificationsForAccount(strongSelf.context.account.id, ids)
            }
        })
       
        let importableContacts = self.context.sharedContext.contactDataManager?.importable() ?? .single([:])
        let optionalImportableContacts = self.context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: PreferencesKeys.contactsSettings))
        |> mapToSignal { preferences -> Signal<[DeviceContactNormalizedPhoneNumber: ImportableDeviceContactData], NoError> in
            let settings: ContactsSettings = preferences?.get(ContactsSettings.self) ?? .defaultSettings
            if settings.synchronizeContacts {
                return importableContacts
            } else {
                return .single([:])
            }
        }
        self.context.account.importableContacts.set(optionalImportableContacts)
        self.context.sharedContext.deviceContactPhoneNumbers.set(optionalImportableContacts
        |> map { contacts in
            return Set(contacts.keys.map { cleanPhoneNumber($0.rawValue) })
        })
        
        let previousTheme = Atomic<PresentationTheme?>(value: nil)
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                if previousTheme.swap(presentationData.theme) !== presentationData.theme {
                    strongSelf.lockedCoveringView.updateTheme(presentationData.theme)
                    strongSelf.rootController.updateTheme(NavigationControllerTheme(presentationTheme: presentationData.theme))
                }
            }
        })
        
        let showCallsTabSignal = context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings])
        |> map { sharedData -> Bool in
            var value = CallListSettings.defaultSettings.showTab
            if let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) {
                value = settings.showTab
            }
            return value
        }
        self.showCallsTabDisposable = (showCallsTabSignal |> deliverOnMainQueue).start(next: { [weak self] value in
            if let strongSelf = self {
                if strongSelf.showCallsTab != value {
                    strongSelf.showCallsTab = value
                    strongSelf.rootController.updateRootControllers(showCallsTab: value)
                }
            }
        })
        
        self.rootController.setForceInCallStatusBar((self.context.sharedContext as! SharedAccountContextImpl).currentCallStatusBarNode)
        if let groupCallController = self.context.sharedContext.currentGroupCallController as? VoiceChatController {
            if let overlayController = groupCallController.currentOverlayController {
                groupCallController.parentNavigationController = self.rootController
                self.rootController.presentOverlay(controller: overlayController, inGlobal: true, blockInteraction: false)
            }
        }
    }
    
    deinit {
        self.context.account.postbox.clearCaches()
        self.context.account.shouldKeepOnlinePresence.set(.single(false))
        self.context.account.shouldBeServiceTaskMaster.set(.single(.never))
        self.loggedOutDisposable.dispose()
        self.inAppNotificationSettingsDisposable.dispose()
        self.notificationMessagesDisposable.dispose()
        self.termsOfServiceUpdatesDisposable.dispose()
        self.passcodeLockDisposable.dispose()
        self.passcodeStatusDisposable.dispose()
        self.displayAlertsDisposable?.dispose()
        self.removeNotificationsDisposable?.dispose()
        self.presentationDataDisposable?.dispose()
        self.enablePostboxTransactionsDiposable?.dispose()
        self.termsOfServiceProceedToBotDisposable.dispose()
        self.watchNavigateToMessageDisposable.dispose()
        self.permissionsDisposable.dispose()
        self.scheduledCallPeerDisposable.dispose()
        self.superGramNotificationOpenDisposable.dispose()
    }

    func openNotificationSettings() {
        self.rootController.pushViewController(notificationsAndSoundsController(context: self.context, exceptionsList: nil))
    }
    
    func startCall(peerId: PeerId, isVideo: Bool) {
        guard let appLockContext = self.context.sharedContext.appLockContext as? AppLockContextImpl else {
            return
        }
        self.scheduledCallPeerDisposable.set((appLockContext.isCurrentlyLocked
        |> filter {
            !$0
        }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            let _ = strongSelf.context.sharedContext.callManager?.requestCall(context: strongSelf.context, peerId: peerId, isVideo: isVideo, endCurrentIfAny: false)
        }))
    }
    
    func openChatWithPeerId(peerId: PeerId, threadId: Int64?, messageId: MessageId? = nil, activateInput: Bool = false, storyId: StoryId?, openAppIfAny: Bool = false, alwaysKeepMessageId: Bool = false) {
        if let storyId {
            var controllers = self.rootController.viewControllers
            controllers = controllers.filter { c in
                if c is StoryContainerScreen {
                    return false
                }
                return true
            }
            self.rootController.setViewControllers(controllers, animated: false)
            
            self.rootController.chatListController?.openStoriesFromNotification(peerId: storyId.peerId, storyId: storyId.id)
        } else {
            var visiblePeerId: PeerId?
            if let controller = self.rootController.topViewController as? ChatControllerImpl, controller.chatLocation.peerId == peerId, controller.chatLocation.threadId == threadId {
                visiblePeerId = peerId
            }
            
            if visiblePeerId != peerId || messageId != nil {
                let isOutgoingMessage: Signal<Bool, NoError>
                if let messageId {
                    let accountPeerId = self.context.account.peerId
                    isOutgoingMessage = self.context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
                    |> map { message -> Bool in
                        if let message {
                            return !message._asMessage().effectivelyIncoming(accountPeerId)
                        } else {
                            return false
                        }
                    }
                } else {
                    isOutgoingMessage = .single(false)
                }
                let _ = combineLatest(
                    queue: Queue.mainQueue(),
                    self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)),
                    isOutgoingMessage
                ).start(next: { peer, isOutgoingMessage in
                    guard let peer = peer else {
                        return
                    }
                    
                    let chatLocation: NavigateToChatControllerParams.Location
                    if let threadId = threadId {
                        chatLocation = .replyThread(ChatReplyThreadMessage(
                            peerId: peerId, threadId: threadId, channelMessageId: nil, isChannelPost: false, isForumPost: true, isMonoforumPost: false, maxMessage: nil, maxReadIncomingMessageId: nil, maxReadOutgoingMessageId: nil, unreadCount: 0, initialFilledHoles: IndexSet(), initialAnchor: .automatic, isNotAvailable: false
                        ))
                    } else {
                        chatLocation = .peer(peer)
                    }
                    
                    if openAppIfAny, case let .user(user) = peer, let botInfo = user.botInfo, botInfo.flags.contains(.hasWebApp), let parentController = self.rootController.viewControllers.last as? ViewController {
                        self.context.sharedContext.openWebApp(
                            context: self.context,
                            parentController: parentController,
                            updatedPresentationData: nil,
                            botPeer: peer,
                            chatPeer: nil,
                            threadId: nil,
                            buttonText: "",
                            url: "",
                            simple: true,
                            source: .generic,
                            skipTermsOfService: true,
                            payload: nil,
                            verifyAgeCompletion: nil
                        )
                    } else {
                        self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: self.rootController, context: self.context, chatLocation: chatLocation, subject: alwaysKeepMessageId || isOutgoingMessage ? messageId.flatMap { .message(id: .id($0), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false) } : nil, activateInput: activateInput ? .text : nil))
                    }
                })
            }
        }
    }

    // SuperGram: notification-tap routing, shared by the system notification default action (APNs and the local
    // fallback notifications) and the in-app banner. It opens the place the message actually lives, scrolled to it:
    //  - forum topic → that topic at the message;
    //  - "Replies" service-chat entry → the discussion thread of the original post at the comment, else the discussion
    //    group at the comment, and only as a last resort the Replies chat itself;
    //  - comment in a channel discussion thread → that discussion thread at the message, else the group at it;
    //  - any other group / channel message → that chat at the message;
    //  - private and secret chats → the unchanged upstream path (openChatWithPeerId).
    // A peer or message that is not in the local database yet (cold start from the tap) is waited for with a short
    // timeout instead of opening an empty chat. A non-forum thread id is never turned into a forum replyThread: in
    // supergroups Message.threadId is 1 for every plain message and the replied-to id for every reply, and the old
    // `.replyThread(isForumPost: true)` built from it opened an empty, input-less "Replies" thread screen.
    // Navigation goes through navigateToChatController with the default keepStack, so the SuperGram screen chain is kept.
    func openChatFromNotification(peerId: PeerId, threadId: Int64?, messageId: MessageId?, storyId: StoryId?) {
        if storyId != nil {
            self.openChatWithPeerId(peerId: peerId, threadId: nil, messageId: messageId, storyId: storyId)
            return
        }
        let context = self.context
        let peerSignal: Signal<EnginePeer?, NoError> = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> filter { $0 != nil }
        |> take(1)
        |> timeout(superGramNotificationPeerTimeout, queue: Queue.mainQueue(), alternate: .single(nil))

        self.superGramNotificationOpenDisposable.set((peerSignal
        |> mapToSignal { peer -> Signal<(EnginePeer?, Message?), NoError> in
            guard let peer, let messageId else {
                return .single((peer, nil))
            }
            // Private / secret chats keep the upstream path and do not need the message; avoid a network wait there.
            if (peerId.namespace == Namespaces.Peer.CloudUser && !peerId.isReplies && !peer._asPeer().isForum) || peerId.namespace == Namespaces.Peer.SecretChat {
                return .single((peer, nil))
            }
            return superGramNotificationMessage(context: context, id: messageId, timeout: superGramNotificationMessageTimeout)
            |> map { message -> (EnginePeer?, Message?) in
                return (peer, message)
            }
        }
        |> deliverOnMainQueue).start(next: { [weak self] peer, message in
            guard let self else {
                return
            }
            guard let peer else {
                Logger.shared.log("NotificationTap", "peer \(peerId) is not available locally; not opening an empty chat")
                SuperGramNotificationDiagnostics.shared.log("tap route: peer \(peerId) not available, nothing opened")
                return
            }
            self.superGramOpenNotificationTarget(peer: peer, message: message, messageId: messageId, threadId: threadId)
        }))
    }

    private func superGramOpenNotificationTarget(peer: EnginePeer, message: Message?, messageId: MessageId?, threadId: Int64?) {
        let rawPeer = peer._asPeer()
        SuperGramNotificationDiagnostics.shared.log("tap route peer=\(peer.id.namespace._internalGetInt32Value()):\(peer.id.id._internalGetInt64Value()) msg=\(messageId.flatMap { "\($0.id)" } ?? "-") thread=\(threadId.flatMap { "\($0)" } ?? "-") messageLoaded=\(message != nil) replies=\(peer.id.isReplies) forum=\(rawPeer.isForumOrMonoForum)")

        // "Replies" service chat (comment replies in discussion groups the account may not have joined).
        if peer.id.isReplies, let message {
            var sourceMessageId: MessageId?
            var threadRootId: MessageId?
            for attribute in message.attributes {
                if let attribute = attribute as? SourceReferenceMessageAttribute {
                    sourceMessageId = attribute.messageId
                } else if let attribute = attribute as? ReplyMessageAttribute {
                    threadRootId = attribute.threadMessageId
                }
            }
            if let sourceMessageId {
                let repliesMessageId = message.id
                let openRepliesChat: () -> Void = { [weak self] in
                    self?.superGramNavigateToNotificationChat(location: .peer(peer), messageId: repliesMessageId)
                }
                let openDiscussionGroup: () -> Void = { [weak self] in
                    self?.superGramOpenPeerAtMessage(peerId: sourceMessageId.peerId, messageId: sourceMessageId, fallback: openRepliesChat)
                }
                if let threadRootId, threadRootId.peerId == sourceMessageId.peerId {
                    self.superGramOpenDiscussionThread(rootId: threadRootId, messageId: sourceMessageId, fallback: openDiscussionGroup)
                } else {
                    openDiscussionGroup()
                }
                return
            }
        }

        // Forum topics (and forum bots / monoforums): the thread id is a real topic id here.
        if rawPeer.isForumOrMonoForum {
            if let topicId = message?.threadId ?? threadId {
                let location: NavigateToChatControllerParams.Location = .replyThread(ChatReplyThreadMessage(
                    peerId: peer.id, threadId: topicId, channelMessageId: nil, isChannelPost: false, isForumPost: true, isMonoforumPost: rawPeer.isMonoForum, maxMessage: nil, maxReadIncomingMessageId: nil, maxReadOutgoingMessageId: nil, unreadCount: 0, initialFilledHoles: IndexSet(), initialAnchor: .automatic, isNotAvailable: false
                ))
                self.superGramNavigateToNotificationChat(location: location, messageId: message?.id)
            } else {
                self.superGramNavigateToNotificationChat(location: .peer(peer), messageId: nil)
            }
            return
        }

        // Non-forum groups and channels.
        if peer.id.namespace == Namespaces.Peer.CloudChannel || peer.id.namespace == Namespaces.Peer.CloudGroup {
            let targetMessageId = message?.id
            let openChat: () -> Void = { [weak self] in
                self?.superGramNavigateToNotificationChat(location: .peer(peer), messageId: targetMessageId)
            }
            // 1 is the "no thread" marker for channel messages; any other value is the thread root or the replied-to id.
            var rootCandidate: Int64? = message?.threadId ?? threadId
            if let value = rootCandidate, value <= 1 || value > Int64(Int32.max) {
                rootCandidate = nil
            }
            if case let .channel(channel) = peer, case .group = channel.info, let rootCandidate, let targetMessageId, Int64(targetMessageId.id) != rootCandidate {
                // Only a thread whose root is an auto-forwarded channel post is a comment thread; a plain reply stays in the group.
                let rootId = MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(rootCandidate))
                self.superGramNotificationOpenDisposable.set((superGramNotificationMessage(context: self.context, id: rootId, timeout: superGramNotificationMessageTimeout)
                |> deliverOnMainQueue).start(next: { [weak self] root in
                    guard let self else {
                        return
                    }
                    if let root, root.attributes.contains(where: { $0 is SourceReferenceMessageAttribute }) {
                        self.superGramOpenDiscussionThread(rootId: rootId, messageId: targetMessageId, fallback: openChat)
                    } else {
                        openChat()
                    }
                }))
            } else {
                openChat()
            }
            return
        }

        // Private chats, secret chats, Saved Messages, Replies entries without a source: upstream behaviour.
        self.openChatWithPeerId(peerId: peer.id, threadId: nil, messageId: messageId, storyId: nil)
    }

    private func superGramNavigateToNotificationChat(location: NavigateToChatControllerParams.Location, messageId: MessageId?, chatLocationContextHolder: Atomic<ChatLocationContextHolder?> = Atomic<ChatLocationContextHolder?>(value: nil)) {
        let subject: ChatControllerSubject? = messageId.flatMap { .message(id: .id($0), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false) }
        self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: self.rootController, context: self.context, chatLocation: location, chatLocationContextHolder: chatLocationContextHolder, subject: subject))
    }

    private func superGramOpenPeerAtMessage(peerId: PeerId, messageId: MessageId, fallback: @escaping () -> Void) {
        self.superGramNotificationOpenDisposable.set((self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self else {
                return
            }
            guard let peer else {
                fallback()
                return
            }
            self.superGramNavigateToNotificationChat(location: .peer(peer), messageId: messageId)
        }))
    }

    private func superGramOpenDiscussionThread(rootId: MessageId, messageId: MessageId?, fallback: @escaping () -> Void) {
        let signal: Signal<ReplyThreadInfo?, NoError> = fetchAndPreloadReplyThreadInfo(context: self.context, subject: .groupMessage(rootId), atMessageId: messageId, preload: false)
        |> map(Optional.init)
        |> `catch` { _ -> Signal<ReplyThreadInfo?, NoError> in
            return .single(nil)
        }
        |> take(1)
        |> timeout(superGramNotificationThreadTimeout, queue: Queue.mainQueue(), alternate: .single(nil))

        self.superGramNotificationOpenDisposable.set((signal
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self else {
                return
            }
            guard let result, !result.message.isNotAvailable else {
                fallback()
                return
            }
            self.superGramNavigateToNotificationChat(location: .replyThread(result.message), messageId: messageId, chatLocationContextHolder: result.contextHolder)
        }))
    }

    func openUrl(_ url: URL, external: Bool = false) {
        if self.rootController.rootTabController != nil {
            let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
            self.context.sharedContext.openExternalUrl(context: self.context, urlContext: external ? .external : .generic, url: url.absoluteString, forceExternal: false, presentationData: presentationData, navigationController: self.rootController, dismissInput: { [weak self] in
                self?.rootController.view.endEditing(true)
            })
        } else {
            self.scheduledOpenExternalUrl = url
        }
    }
    
    func openRootSearch() {
        self.rootController.openChatsController(activateSearch: true)
    }
    
    func openRootCompose() {
        self.rootController.openRootCompose()
    }
    
    func openRootCamera() {
        self.rootController.openRootCamera()
    }
    
    func openAppIcon() {
        self.rootController.openAppIcon()
    }
    
    func switchAccount() {
        let _ = (activeAccountsAndPeers(context: self.context)
        |> take(1)
        |> map { primaryAndAccounts -> (AccountContext, EnginePeer, Int32)? in
            return primaryAndAccounts.1.first
        }
        |> map { accountAndPeer -> AccountContext? in
            if let (context, _, _) = accountAndPeer {
                return context
            } else {
                return nil
            }
        }
        |> deliverOnMainQueue).start(next: { [weak self] context in
            guard let strongSelf = self, let context = context else {
                return
            }
            strongSelf.context.sharedContext.switchToAccount(id: context.account.id, fromSettingsController: nil, withChatListController: nil)
        })
    }
    
    private func updateCoveringViewSnaphot(_ visible: Bool) {
        if visible {
            let scale: CGFloat = 0.5
            let unscaledSize = self.mainWindow.hostView.containerView.frame.size
            let image = generateImage(CGSize(width: floor(unscaledSize.width * scale), height: floor(unscaledSize.height * scale)), rotatedContext: { size, context in
                context.clear(CGRect(origin: CGPoint(), size: size))
                context.scaleBy(x: scale, y: scale)
                UIGraphicsPushContext(context)
                self.mainWindow.hostView.containerView.drawHierarchy(in: CGRect(origin: CGPoint(), size: unscaledSize), afterScreenUpdates: false)
                UIGraphicsPopContext()
            }).flatMap(applyScreenshotEffectToImage)
            self.lockedCoveringView.updateSnapshot(image)
        } else {
            self.lockedCoveringView.updateSnapshot(nil)
        }
    }
}

// SuperGram: notification-tap routing limits. A tap must not hang on a slow network nor open an empty chat; each wait
// falls back to the next-best destination when it expires.
private let superGramNotificationPeerTimeout: Double = 4.0
private let superGramNotificationMessageTimeout: Double = 3.0
private let superGramNotificationThreadTimeout: Double = 5.0

// SuperGram: the message a notification refers to — local first, otherwise fetched from the cloud (a tap can cold-start
// the app before the update that carries it is applied). Emits nil when it cannot be resolved in time.
private func superGramNotificationMessage(context: AccountContext, id: MessageId, timeout timeoutValue: Double) -> Signal<Message?, NoError> {
    return context.engine.messages.getMessagesLoadIfNecessary([id], strategy: .cloud(skipLocal: false))
    |> `catch` { _ -> Signal<GetMessagesResult, NoError> in
        return .single(.result([]))
    }
    |> mapToSignal { result -> Signal<Message?, NoError> in
        switch result {
        case .progress:
            return .complete()
        case let .result(messages):
            return .single(messages.first(where: { $0.id == id }))
        }
    }
    |> take(1)
    |> timeout(timeoutValue, queue: Queue.mainQueue(), alternate: .single(nil))
}
