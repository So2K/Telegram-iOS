import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

/// How much of the original file has to be on disk before it is preferred over the HLS renditions.
public enum SuperGramDownloadedOriginalRequirement {
    /// The whole file is on disk. Playback needs no network at all and no byte range has to be guessed.
    case complete
    /// The whole file, or a cached head *and* a cached midpoint. Downloads progress head→tail, so a cached
    /// midpoint means a real local copy rather than the 2 MB head that every preload, cancelled download and
    /// earlier streaming session leaves behind.
    case completeOrHalfPresent
}

private struct SuperGramDownloadedOriginalCacheKey: Hashable {
    let storagePath: String
    let resourceId: String
    let requiresComplete: Bool
}

private struct SuperGramDownloadedOriginalCacheEntry {
    let value: Bool
    let timestamp: Double
}

private let superGramDownloadedOriginalCacheTimeout: Double = 10.0
private let superGramDownloadedOriginalCacheLimit: Int = 256
private let superGramDownloadedOriginalCache = Atomic<[SuperGramDownloadedOriginalCacheKey: SuperGramDownloadedOriginalCacheEntry]>(value: [:])

/// SuperGram: is the original file worth playing from disk instead of streaming the HLS variants?
///
/// The probes underneath hit the filesystem — `completedResourcePath` stats a file, and `internal_resourceDataIsCached`
/// stats the partial file and, on a miss, opens and parses its `.meta` — on the **calling** thread. Both the gallery
/// (`galleryItemForEntry`, while the controller is being presented) and the chat bubble layout ask this question on
/// the main thread, once or twice per video, for every entry of a shared-media gallery. The answer can only flip when
/// a download finishes, so it is memoized for a few seconds; anything longer would make a just-finished download wait
/// for the next screen.
public func superGramPrefersDownloadedOriginal(mediaBox: MediaBox, resource: TelegramMediaResource, size: Int64?, requirement: SuperGramDownloadedOriginalRequirement) -> Bool {
    let requiresComplete: Bool
    switch requirement {
    case .complete:
        requiresComplete = true
    case .completeOrHalfPresent:
        requiresComplete = false
    }
    let key = SuperGramDownloadedOriginalCacheKey(storagePath: mediaBox.basePath, resourceId: resource.id.stringRepresentation, requiresComplete: requiresComplete)
    let timestamp = CFAbsoluteTimeGetCurrent()

    let cachedValue = superGramDownloadedOriginalCache.with { cache -> Bool? in
        if let entry = cache[key], timestamp - entry.timestamp < superGramDownloadedOriginalCacheTimeout {
            return entry.value
        }
        return nil
    }
    if let cachedValue {
        return cachedValue
    }

    var result = false
    if mediaBox.completedResourcePath(resource) != nil {
        result = true
    } else if !requiresComplete, let size, size > 0 {
        let probeSize: Int64 = 128 * 1024
        let headRange: Range<Int64> = 0 ..< min(size, probeSize)
        let midLowerBound = max(0, min(size - probeSize, size / 2))
        let midRange: Range<Int64> = midLowerBound ..< min(size, midLowerBound + probeSize)
        if !headRange.isEmpty && !midRange.isEmpty
            && mediaBox.internal_resourceDataIsCached(id: resource.id, size: size, in: headRange)
            && mediaBox.internal_resourceDataIsCached(id: resource.id, size: size, in: midRange) {
            result = true
        }
    }

    let _ = superGramDownloadedOriginalCache.modify { cache in
        var cache = cache
        if cache.count >= superGramDownloadedOriginalCacheLimit {
            cache = cache.filter { timestamp - $0.value.timestamp < superGramDownloadedOriginalCacheTimeout }
            if cache.count >= superGramDownloadedOriginalCacheLimit {
                cache.removeAll()
            }
        }
        cache[key] = SuperGramDownloadedOriginalCacheEntry(value: result, timestamp: timestamp)
        return cache
    }

    return result
}
