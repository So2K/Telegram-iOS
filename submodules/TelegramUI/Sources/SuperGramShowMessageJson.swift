// SuperGram (W2-CONTEXT): Swiftgram message JSON viewer (port of Swiftgram/SGShowMessageJson/Sources/SGShowMessageJson.swift).
//
// Needs the vendored `//Swiftgram/Wrap:Wrap` library in the TelegramUI BUILD deps. Until that dependency is added the
// whole file (and the "JSON" context menu item) compiles out, so TelegramUI builds either way.
//
// Differences from Swiftgram:
// - `SGLogging` is replaced by TelegramCore `Logger` (no extra dependency).
// - The wrapped dictionary is sanitized before `JSONSerialization` (values Wrap passes through unchanged, such as
//   property-less classes or NaN numbers, otherwise raise an Objective-C exception and crash the app).
// - `hexStringToString` no longer indexes past the end of an odd-length string.
// - Sharing follows `sgAllowSaveProtectedContent` for protected chats and is never offered for secret chats.
#if canImport(Wrap)
import Foundation
import UIKit
import Wrap
import TelegramCore
import AccountContext
import ChatControllerInteraction
import ChatPresentationInterfaceState

// MARK: Swiftgram
func showMessageJson(controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, message: EngineRawMessage, context: AccountContext) {
    if let navigationController = controllerInteraction.navigationController(), let rootController = navigationController.view.window?.rootViewController {
        var writingOptions: JSONSerialization.WritingOptions = [
            .prettyPrinted
        ]
        if #available(iOS 13.0, *) {
            writingOptions.insert(.withoutEscapingSlashes)
        }

        var messageData: Data? = nil
        do {
            let wrappedMessage: WrappedDictionary = try wrap(message)
            let sanitizedMessage = superGramJsonSanitizedValue(wrappedMessage, depth: 0)
            if JSONSerialization.isValidJSONObject(sanitizedMessage) {
                messageData = try JSONSerialization.data(withJSONObject: sanitizedMessage, options: writingOptions)
            } else {
                Logger.shared.log("ShowMessageJSON", "Wrapped message is not a valid JSON object")
            }
        } catch {
            Logger.shared.log("ShowMessageJSON", "Error parsing data: \(error)")
            messageData = nil
        }

        guard let messageData = messageData else { return }

        let id = Int64.random(in: Int64.min ... Int64.max)
        let fileResource = LocalFileMediaResource(fileId: id, size: Int64(messageData.count), isSecretRelated: false)
        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(fileResource.id), data: messageData, synchronous: true)

        let file = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: fileResource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/json; charset=utf-8", size: Int64(messageData.count), attributes: [.FileName(fileName: "message.json")], alternativeRepresentations: [])

        let isSecretChat = message.id.peerId.namespace == Namespaces.Peer.SecretChat
        let canShare = !isSecretChat && (!message.isCopyProtected() || SuperGramContextMenuSettings.allowSaveProtectedContent)
        presentDocumentPreviewController(rootController: rootController, theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings, postbox: context.account.postbox, file: file, canShare: canShare)
    }
}

extension EngineMemoryBuffer: @retroactive WrapCustomizable {

    public func wrap(context: Any?, dateFormatter: DateFormatter?) -> Any? {
        let hexString = self.description
        return ["string": hexStringToString(hexString) ?? hexString]
    }
}

// There's a chacne we will need it for each empty/weird type, or it will be a runtime crash.
extension ContentRequiresValidationMessageAttribute: @retroactive WrapCustomizable {

    public func wrap(context: Any?, dateFormatter: DateFormatter?) -> Any? {
        return ["@type": "ContentRequiresValidationMessageAttribute"]
    }
}

func hexStringToString(_ hexString: String) -> String? {
    var chars = Array(hexString)
    var result = ""

    while chars.count > 0 {
        // SuperGram: an odd trailing character is not a hex byte
        if chars.count < 2 {
            return nil
        }
        let c = String(chars[0...1])
        chars = Array(chars.dropFirst(2))
        if let byte = UInt8(c, radix: 16) {
            let scalar = UnicodeScalar(byte)
            result.append(String(scalar))
        } else {
            return nil
        }
    }

    return result
}

// MARK: SuperGram
/// Converts everything `JSONSerialization` cannot encode into strings, so serialization never raises.
private func superGramJsonSanitizedValue(_ value: Any, depth: Int) -> Any {
    if depth > 96 {
        return "<max depth>"
    }
    switch value {
    case let string as String:
        return string
    case let dictionary as [String: Any]:
        var result: [String: Any] = [:]
        for (key, item) in dictionary {
            result[key] = superGramJsonSanitizedValue(item, depth: depth + 1)
        }
        return result
    case let array as [Any]:
        return array.map { superGramJsonSanitizedValue($0, depth: depth + 1) }
    case let number as NSNumber:
        if number.doubleValue.isNaN || number.doubleValue.isInfinite {
            return number.stringValue
        }
        return number
    case is NSNull:
        return NSNull()
    default:
        return String(describing: value)
    }
}
#endif
