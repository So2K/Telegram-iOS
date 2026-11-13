import Foundation
import TelegramCore
import SwiftSignalKit

private let minimalStreamableSize: Int = 384 * 1024

// SuperGram: cached reads of the SuperGram streaming switches (UserDefaults.standard, same keys as SGSimpleSettings).
// These are consulted on hot paths (chat layout, gallery item creation), so values are cached and refreshed on
// UserDefaults.didChangeNotification instead of hitting UserDefaults on every call.
public final class SuperGramMediaStreamingSettings {
    public static let streamAllVideosKey = "sgStreamAllVideos"
    public static let preferDownloadedOriginalKey = "sgPreferDownloadedOriginal"

    private struct Values: Equatable {
        var streamAllVideos: Bool
        var preferDownloadedOriginal: Bool
    }

    private static func readValues() -> Values {
        let defaults = UserDefaults.standard
        return Values(
            streamAllVideos: defaults.object(forKey: SuperGramMediaStreamingSettings.streamAllVideosKey) as? Bool ?? true,
            preferDownloadedOriginal: defaults.object(forKey: SuperGramMediaStreamingSettings.preferDownloadedOriginalKey) as? Bool ?? true
        )
    }

    private static let values = Atomic<Values>(value: SuperGramMediaStreamingSettings.readValues())

    private static let defaultsObserver: NSObjectProtocol = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { _ in
        let updatedValues = SuperGramMediaStreamingSettings.readValues()
        let _ = SuperGramMediaStreamingSettings.values.swap(updatedValues)
    })

    private static func currentValues() -> Values {
        let _ = SuperGramMediaStreamingSettings.defaultsObserver
        return SuperGramMediaStreamingSettings.values.with { $0 }
    }

    /// Any non-secret regular video can be played while it is still downloading.
    public static var streamAllVideos: Bool {
        return SuperGramMediaStreamingSettings.currentValues().streamAllVideos
    }

    /// A downloaded (or partially downloaded, with a cached head) original is preferred over HLS alternates.
    public static var preferDownloadedOriginal: Bool {
        return SuperGramMediaStreamingSettings.currentValues().preferDownloadedOriginal
    }
}

private func superGramStreamsRegularVideo(_ media: TelegramMediaFile) -> Bool {
    // Round videos and GIF-like animations keep upstream streaming rules.
    if media.isInstantVideo || media.isAnimated {
        return false
    }
    if media.fileId.namespace == Namespaces.Media.CloudSecretFile {
        return false
    }
    // Streaming means serving the demuxer from byte ranges that are fetched on demand. Only a cloud document can
    // answer such a request: a file that is still being uploaded, a locally generated file, a web/HTTP reference or
    // a secret-chat file has no random-access fetch, so the player would block on a range nobody ever downloads and
    // the item would spin forever. Those keep the upstream rule (play once the whole file is on disk).
    if media.fileId.namespace != Namespaces.Media.CloudFile {
        return false
    }
    guard media.resource is CloudDocumentMediaResource else {
        return false
    }
    return SuperGramMediaStreamingSettings.streamAllVideos
}

public func isMediaStreamable(message: EngineMessage, media: TelegramMediaFile) -> Bool {
    if message.containsSecretMedia {
        return false
    }
    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
        return false
    }
    guard let size = media.size else {
        return false
    }
    if size < minimalStreamableSize {
        return false
    }
    for attribute in media.attributes {
        if case let .Video(_, _, flags, _, _, _) = attribute {
            if flags.contains(.supportsStreaming) || !media.alternativeRepresentations.isEmpty {
                return true
            }
            if superGramStreamsRegularVideo(media) {
                return true
            }
            break
        }
    }
    #if DEBUG
    if let fileName = media.fileName, fileName.hasSuffix(".mkv") {
        return true
    }
    #endif
    return false
}

public func isMediaStreamable(media: TelegramMediaFile) -> Bool {
    guard let size = media.size else {
        return false
    }
    if size < minimalStreamableSize {
        return false
    }
    for attribute in media.attributes {
        if case let .Video(_, _, flags, _, _, _) = attribute {
            if flags.contains(.supportsStreaming) {
                return true
            }
            if superGramStreamsRegularVideo(media) {
                return true
            }
            break
        }
    }
    return false
}

public func isMediaStreamable(resource: TelegramMediaResource) -> Bool {
    if let size = resource.size, size >= minimalStreamableSize  {
        return true
    } else {
        return false
    }
}
