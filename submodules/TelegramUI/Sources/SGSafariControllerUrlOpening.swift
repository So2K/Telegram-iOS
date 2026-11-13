// MARK: Swiftgram
// SuperGram (SGM-F4): open a link in an in-app `SFSafariViewController` instead of handing it to an external
// browser. Ported from Swiftgram's `SGSafariControllerUrlOpening` module; the Swiftgram original also refreshed
// its server-side web settings when the sheet closed (`SG_API_WEBAPP_URL_PARSED` / `SFSafariViewControllerPlusDidFinish`),
// which is a Pro/server feature and is not ported — so plain `SFSafariViewController` is enough and the
// `SFSafariViewControllerPlus` module is not vendored.
import Foundation
import UIKit
import SafariServices
import Display
import AccountContext
import TelegramPresentationData

/// Schemes `SFSafariViewController` accepts. Initializing it with anything else throws an exception at runtime,
/// so every other URL falls back to the system handler.
private let sgSafariControllerSchemes: Set<String> = ["http", "https"]

func sgCanOpenUrlWithSafariController(_ parsedUrl: URL) -> Bool {
    guard let scheme = parsedUrl.scheme?.lowercased() else {
        return false
    }
    return sgSafariControllerSchemes.contains(scheme)
}

func sgOpenUrlWithSafariController(
    parsedUrl: URL,
    originalUrl: String,
    context: AccountContext,
    presentationData: PresentationData,
    navigationController: NavigationController?
) {
    guard sgCanOpenUrlWithSafariController(parsedUrl) else {
        context.sharedContext.applicationBindings.openUrl(originalUrl)
        return
    }
    guard let rootViewController = navigationController?.view.window?.rootViewController else {
        context.sharedContext.applicationBindings.openUrl(originalUrl)
        return
    }
    // A link can be opened from a screen that is itself presented over the root controller (gallery, story
    // viewer, an attachment or web-app sheet). `-present:` on a controller that is already presenting is a
    // no-op with a console warning, i.e. the link would silently do nothing, so present from the topmost
    // presented controller instead. Swiftgram always uses the root controller here.
    var presentingViewController = rootViewController
    while let presentedViewController = presentingViewController.presentedViewController, !presentedViewController.isBeingDismissed {
        presentingViewController = presentedViewController
    }
    let controller = SFSafariViewController(url: parsedUrl)
    controller.preferredBarTintColor = presentationData.theme.rootController.navigationBar.opaqueBackgroundColor
    controller.preferredControlTintColor = presentationData.theme.rootController.navigationBar.accentTextColor
    presentingViewController.present(controller, animated: true)
}
