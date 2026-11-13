#!/usr/bin/env python3
"""Run the actual foreground notification tap/expand closures with navigation doubles.

No production source is modified. UIKit presentation and account services are
spies; a real device remains necessary to verify gesture/system UI appearance.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
application = (ROOT / "submodules/TelegramUI/Sources/ApplicationContext.swift").read_text()
item = (ROOT / "submodules/TelegramUI/Components/Chat/ChatMessageNotificationItem/Sources/ChatMessageNotificationItem.swift").read_text()


def body(source, marker):
    beginning = source.index(marker)
    opening = source.index("{", beginning)
    depth, ending = 1, opening + 1
    while depth:
        depth += (source[ending] == "{") - (source[ending] == "}")
        ending += 1
    return source[opening + 1:ending - 1]


swift = r'''
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
final class ASDisplayNode {}
struct ChatLocation: Equatable {
    let peerId: Int
    var threadId: Int? = nil
    var asChatLocation: ChatLocation { self }
}
class ViewController {
    var preservesInlinePresentation = false
    var preservesOverlayPresentation = false
    var presented: [ChatControllerImpl] = []
    enum Window { case root }
    enum Presentation { case window(Window) }
    func present(_ controller: ChatControllerImpl, in presentation: Presentation, with arguments: ChatControllerOverlayPresentationData) {
        presented.append(controller)
    }
}
final class ChatControllerOverlayPresentationData {
    init(expandData: (ASDisplayNode?, () -> Void)) {}
}
final class ChatControllerImpl: ViewController {
    enum Mode { case overlay(RootController) }
    let chatLocation: ChatLocation
    var presentationArguments: ChatControllerOverlayPresentationData?
    var discardRequired = false
    var pendingDiscard: (() -> Void)?
    init(context: Context, chatLocation: ChatLocation, mode: Mode? = nil) { self.chatLocation = chatLocation }
    func presentVoiceMessageDiscardAlert(action: @escaping () -> Void, discardIfVideo: Bool, performAction: Bool) -> Bool {
        check(discardIfVideo && !performAction, "recording confirmation is preserved")
        if discardRequired { pendingDiscard = action; return true }
        return false
    }
}
final class AttachmentController: ViewController {
    var minimized = 0
    func minimizeIfNeeded() { minimized += 1 }
}
final class BrowserScreen: ViewController {
    var minimized = 0
    func requestMinimize(topEdgeOffset: Int?, initialVelocity: Double?) { minimized += 1 }
}
final class MinimizedContainer {
    var isExpanded = true
    var collapsed = 0
    func collapse() { collapsed += 1; isExpanded = false }
}
final class RootController {
    var viewControllers: [AnyObject] = []
    var topViewController: AnyObject? { viewControllers.last }
    var minimizedContainer: MinimizedContainer?
}
final class MainWindow {
    var controllers: [AnyObject] = []
    func forEachViewController(_ f: (AnyObject) -> Bool, excludeNavigationSubControllers: Bool) {
        for controller in controllers { if !f(controller) { break } }
    }
}
func isOverlayControllerForChatNotificationOverlayPresentation(_ controller: AnyObject) -> Bool {
    (controller as? ViewController)?.preservesOverlayPresentation ?? false
}
func isInlineControllerForChatNotificationOverlayPresentation(_ controller: ViewController) -> Bool {
    controller.preservesInlinePresentation
}
final class NotificationController {
    var removed: [Int] = []
    func removeItemsWithGroupingKey(_ id: Int) { removed.append(id) }
}
class Media {}
final class TelegramMediaAction: Media {
    enum Action { case geoProximityReached, other }
    let action: Action
    init(_ action: Action) { self.action = action }
}
struct MessageId { let peerId: Int }
struct Message { let id: MessageId; var media: [Media] = [] }
struct NavigateToChatControllerParams {
    let navigationController: RootController
    let context: Context
    let chatLocation: ChatLocation
}
final class SharedContext {
    var navigated: [ChatLocation] = []
    var locationsOpened = 0
    func navigateToChatController(_ params: NavigateToChatControllerParams) { navigated.append(params.chatLocation) }
    func openLocationScreen(context: Context, messageId: MessageId, navigationController: RootController) { locationsOpened += 1 }
}
final class Context { let sharedContext = SharedContext() }
final class Application {
    let context = Context()
    let rootController = RootController()
    let mainWindow = MainWindow()
    let notificationController = NotificationController()
    // SuperGram: the banner now routes through the shared notification-tap resolver; the double records the
    // destination it was asked for (peer + forum topic) as one normal navigation.
    func openChatFromNotification(peerId: Int, threadId: Int?, messageId: MessageId, storyId: Int?) {
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: rootController, context: context, chatLocation: ChatLocation(peerId: peerId, threadId: threadId)))
    }
    func makeItem(chatLocation: ChatLocation, firstMessage: Message) -> Item {
        let tap: () -> Bool = { [weak self] in
'''
swift += body(application, "tapAction: {")
swift += r'''
        }
        let expand: (@escaping () -> (ASDisplayNode?, () -> Void)) -> Void = { [weak self] expandData in
'''
expand_body = body(application, "}, expandAction: { expandData in")
swift += expand_body[expand_body.index("\n"):]
swift += r'''
        }
        return Item(tapAction: tap, expandAction: expand)
    }
}
final class Item {
    let tapAction: () -> Bool
    let expandAction: (@escaping () -> (ASDisplayNode?, () -> Void)) -> Void
    init(tapAction: @escaping () -> Bool, expandAction: @escaping (@escaping () -> (ASDisplayNode?, () -> Void)) -> Void) {
        self.tapAction = tapAction; self.expandAction = expandAction
    }
    func tapped(_ take: @escaping () -> (ASDisplayNode?, () -> Void)) {
'''
swift += body(item, "public func tapped(")
swift += "}\nfunc expand(_ take: @escaping () -> (ASDisplayNode?, () -> Void)) {\n"
swift += body(item, "public func expand(")
swift += "}\n}\n"
swift += r'''
let target = ChatLocation(peerId: 7, threadId: 42)
let message = Message(id: MessageId(peerId: target.peerId))
let take: () -> (ASDisplayNode?, () -> Void) = { (nil, {}) }

// Previously opened target below another chat: ordinary tap must navigate, never expand.
let app = Application()
let lower = ChatControllerImpl(context: app.context, chatLocation: target)
let top = ChatControllerImpl(context: app.context, chatLocation: ChatLocation(peerId: 8))
app.rootController.viewControllers = [lower, top]
let notification = app.makeItem(chatLocation: target, firstMessage: message)
notification.tapped(take)
check(app.context.sharedContext.navigated == [target], "normal tap navigates existing lower target with correct topic")
check(top.presented.isEmpty, "normal lower-stack tap does not open reply overlay")
check(app.notificationController.removed == [7], "normal navigation clears its banner once")
notification.expand(take)
check(top.presented.count == 1 && top.presented[0].chatLocation == target, "explicit expansion retains reply overlay and topic")
check(app.context.sharedContext.navigated.count == 1, "explicit expansion does not navigate normal stack")

// Recording confirmation must not secretly replace normal navigation with an overlay.
let recording = Application()
let recordingTop = ChatControllerImpl(context: recording.context, chatLocation: ChatLocation(peerId: 8))
recordingTop.discardRequired = true
recording.rootController.viewControllers = [ChatControllerImpl(context: recording.context, chatLocation: target), recordingTop]
recording.makeItem(chatLocation: target, firstMessage: message).tapped(take)
check(recording.context.sharedContext.navigated.isEmpty && recordingTop.presented.isEmpty, "recording prompt defers navigation")
check(recording.notificationController.removed.isEmpty, "cancelled discard keeps the pending banner")
recordingTop.pendingDiscard?()
check(recording.context.sharedContext.navigated == [target] && recordingTop.presented.isEmpty, "confirmed discard navigates normal target without reply overlay")

let visible = Application()
let visibleTop = ChatControllerImpl(context: visible.context, chatLocation: target)
visible.rootController.viewControllers = [visibleTop]
visible.makeItem(chatLocation: target, firstMessage: message).tapped(take)
check(visible.notificationController.removed == [7] && visible.context.sharedContext.navigated.isEmpty && visibleTop.presented.isEmpty, "already visible target only clears its banner")

let fresh = Application()
fresh.rootController.viewControllers = [ViewController()]
fresh.makeItem(chatLocation: target, firstMessage: message).tapped(take)
check(fresh.context.sharedContext.navigated == [target], "new chat uses normal navigation")

let geo = Application()
let geoTop = ViewController()
geo.rootController.viewControllers = [ChatControllerImpl(context: geo.context, chatLocation: target), geoTop]
geo.makeItem(chatLocation: target, firstMessage: Message(id: message.id, media: [TelegramMediaAction(.geoProximityReached)])).tapped(take)
check(geo.context.sharedContext.locationsOpened == 1 && geo.context.sharedContext.navigated.isEmpty && geoTop.presented.isEmpty, "proximity notification preserves location navigation")

for inline in [false, true] {
    let covered = Application()
    let cover = ViewController()
    cover.preservesInlinePresentation = inline
    cover.preservesOverlayPresentation = !inline
    covered.rootController.viewControllers = [cover]
    if !inline { covered.mainWindow.controllers = [cover] }
    covered.makeItem(chatLocation: target, firstMessage: message).tapped(take)
    check(covered.context.sharedContext.navigated.isEmpty && cover.presented.count == 1, "special active presentation retains explicit existing overlay policy")
}

let browser = Application()
let browserTop = BrowserScreen()
browser.rootController.viewControllers = [browserTop]
browser.makeItem(chatLocation: target, firstMessage: message).tapped(take)
check(browserTop.minimized == 1 && browser.context.sharedContext.navigated == [target], "browser is minimized before normal navigation")

let attachment = Application()
let attachmentTop = AttachmentController()
attachment.rootController.viewControllers = [attachmentTop]
attachment.makeItem(chatLocation: target, firstMessage: message).tapped(take)
check(attachmentTop.minimized == 1 && attachment.context.sharedContext.navigated == [target], "attachment controller is minimized before navigation")

let expanded = Application()
expanded.rootController.viewControllers = [ViewController()]
expanded.rootController.minimizedContainer = MinimizedContainer()
expanded.makeItem(chatLocation: target, firstMessage: message).tapped(take)
check(expanded.rootController.minimizedContainer!.collapsed == 1 && expanded.context.sharedContext.navigated == [target], "expanded minimized container collapses before navigation")

var releasedApp: Application? = Application()
let releasedItem = releasedApp!.makeItem(chatLocation: target, firstMessage: message)
weak var weakApp = releasedApp
releasedApp = nil
check(weakApp == nil && !releasedItem.tapAction(), "notification closures do not retain application")
releasedItem.expand(take)
print("PASS: actual-source normal banner tap, lower-stack/topic navigation, recording confirmation, explicit expansion, location and special presentation regressions")
'''

with tempfile.TemporaryDirectory(prefix="supergram-notification-tap-") as temporary:
    source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    source.write_text(swift)
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
