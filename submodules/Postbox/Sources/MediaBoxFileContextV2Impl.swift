import Foundation
import RangeSet
import SwiftSignalKit

// SuperGram: the on-disk .meta of a partial file is flushed lazily (see PartialState), so path-based
// readers (MediaBox.internal_resourceData / internal_resourceDataIsCached) consult the in-memory map of
// the open context first. An entry only ever describes bytes that were already written to the partial file.
final class MediaBoxLiveFileMaps {
    enum Availability {
        case untracked
        case unavailable
        case available(Range<Int64>)
    }

    private struct Entry {
        let token: Int64
        let ranges: RangeSet<Int64>
        let truncationSize: Int64?
    }

    static let shared = MediaBoxLiveFileMaps()

    private var lock = pthread_mutex_t()
    private var entries: [String: Entry] = [:]
    private var nextToken: Int64 = 1

    private init() {
        pthread_mutex_init(&self.lock, nil)
    }

    func register(path: String, ranges: RangeSet<Int64>, truncationSize: Int64?) -> Int64 {
        pthread_mutex_lock(&self.lock)
        let token = self.nextToken
        self.nextToken += 1
        self.entries[path] = Entry(token: token, ranges: ranges, truncationSize: truncationSize)
        pthread_mutex_unlock(&self.lock)
        return token
    }

    func update(path: String, token: Int64, ranges: RangeSet<Int64>, truncationSize: Int64?) {
        pthread_mutex_lock(&self.lock)
        if let current = self.entries[path], current.token > token {
            // A newer context owns this path, a stale context must not overwrite its map
        } else {
            self.entries[path] = Entry(token: token, ranges: ranges, truncationSize: truncationSize)
        }
        pthread_mutex_unlock(&self.lock)
    }

    func unregister(path: String, token: Int64) {
        pthread_mutex_lock(&self.lock)
        if let current = self.entries[path], current.token == token {
            self.entries.removeValue(forKey: path)
        }
        pthread_mutex_unlock(&self.lock)
    }

    func remove(path: String) {
        pthread_mutex_lock(&self.lock)
        self.entries.removeValue(forKey: path)
        pthread_mutex_unlock(&self.lock)
    }

    func availability(path: String, range: Range<Int64>) -> Availability {
        pthread_mutex_lock(&self.lock)
        let entry = self.entries[path]
        pthread_mutex_unlock(&self.lock)

        guard let entry else {
            return .untracked
        }
        let maxValue = entry.truncationSize ?? Int64.max
        let clippedUpperBound = min(maxValue, range.upperBound)
        let clippedRange: Range<Int64> = min(range.lowerBound, clippedUpperBound) ..< clippedUpperBound
        if entry.ranges.isSuperset(of: RangeSet<Int64>(clippedRange)) {
            return .available(clippedRange)
        } else {
            return .unavailable
        }
    }
}

func mediaBoxCompleteFileSize(_ path: String) -> Int64? {
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, access(path, R_OK) == 0 else {
        return nil
    }
    return info.st_size
}

func mediaBoxCompleteFilesMatch(_ first: String, _ second: String) -> Bool {
    var firstInfo = stat()
    var secondInfo = stat()
    return lstat(first, &firstInfo) == 0 && lstat(second, &secondInfo) == 0
        && firstInfo.st_mode & S_IFMT == S_IFREG && secondInfo.st_mode & S_IFMT == S_IFREG
        && firstInfo.st_dev == secondInfo.st_dev && firstInfo.st_ino == secondInfo.st_ino
}

public final class MediaBoxFileContextV2Impl: MediaBoxFileContext {
    private final class RangeRequest {
        let value: Range<Int64>
        let priority: MediaBoxFetchPriority
        let isFullRange: Bool
        let error: (MediaResourceDataFetchError) -> Void
        let completed: () -> Void
        
        init(
            value: Range<Int64>,
            priority: MediaBoxFetchPriority,
            isFullRange: Bool,
            error: @escaping (MediaResourceDataFetchError) -> Void,
            completed: @escaping () -> Void
        ) {
            self.value = value
            self.priority = priority
            self.isFullRange = isFullRange
            self.error = error
            self.completed = completed
        }
    }
    
    private final class StatusRequest {
        let size: Int64?
        let next: (MediaResourceStatus) -> Void
        let completed: () -> Void
        
        var reportedStatus: MediaResourceStatus?
        
        init(size: Int64?, next: @escaping (MediaResourceStatus) -> Void, completed: @escaping () -> Void) {
            self.size = size
            self.next = next
            self.completed = completed
        }
    }
    
    private final class PartialDataRequest {
        let range: Range<Int64>
        let next: (MediaResourceData) -> Void
        
        var waitingUntilAfterInitialFetch: Bool
        var reportedStatus: MediaResourceData?
        
        init(
            range: Range<Int64>,
            waitUntilAfterInitialFetch: Bool,
            next: @escaping (MediaResourceData) -> Void
        ) {
            self.range = range
            self.waitingUntilAfterInitialFetch = waitUntilAfterInitialFetch
            self.next = next
        }
    }
    
    private final class RangeStatusRequest {
        let next: (RangeSet<Int64>) -> Void
        let completed: () -> Void
        
        var reportedStatus: RangeSet<Int64>?
        
        init(
            next: @escaping (RangeSet<Int64>) -> Void,
            completed: @escaping () -> Void
        ) {
            self.next = next
            self.completed = completed
        }
    }
    
    private struct MaterializedRangeRequest: Equatable {
        let range: Range<Int64>
        let priority: MediaBoxFetchPriority
        
        init(
            range: Range<Int64>,
            priority: MediaBoxFetchPriority
        ) {
            self.range = range
            self.priority = priority
        }
    }
    
    private final class PendingFetch {
        let initialFilterRanges: RangeSet<Int64>
        let ranges = Promise<[(Range<Int64>, MediaBoxFetchPriority)]>()
        let disposable: Disposable
        
        init(initialFilterRanges: RangeSet<Int64>, disposable: Disposable) {
            self.initialFilterRanges = initialFilterRanges
            self.disposable = disposable
        }
    }
    
    private final class PartialState {
        private let queue: Queue
        private let manager: MediaBoxFileManager
        private let storageBox: StorageBox?
        private let resourceId: Data
        private let partialPath: String
        private let fullPath: String
        private let metaPath: String
        
        private let destinationFile: MediaBoxFileManager.Item?
        
        private let fileMap: MediaBoxFileMap
        private var rangeRequests = Bag<RangeRequest>()
        private var statusRequests = Bag<StatusRequest>()
        private var rangeStatusRequests = Bag<RangeStatusRequest>()
        private var partialDataRequests = Bag<PartialDataRequest>()
        
        private var fetchImpl: ((Signal<[(Range<Int64>, MediaBoxFetchPriority)], NoError>) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError>)?
        
        private var materializedRangeRequests: [MaterializedRangeRequest] = []
        private var pendingFetch: PendingFetch?
        private var hasPerformedAnyFetch: Bool = false
        
        private var isComplete: Bool = false

        // SuperGram: coalesced persistence. The partial file is always written before the in-memory map is
        // filled, and the .meta is written from the in-memory map, so a lagging .meta can only under-report.
        // The interval is the primary trigger; the byte thresholds are a *ceiling on the amount of bookkeeping at
        // risk*, not a second flush trigger. They used to be low enough (2 MB / 4 MB) that at high download speed
        // they, not the interval, decided the flush rate — at 30 MB/s a 2 MB threshold means 15 full
        // MediaBoxFileMap serialisations per second, each rewriting the whole range map, i.e. the write rate grew
        // with the download speed instead of being capped by it. Sized so the interval wins for any realistic
        // speed; losing this much range bookkeeping in a crash only costs a re-download of those ranges, because
        // the file data itself is already on disk. Completion, truncation and teardown still flush immediately.
        private static let metaFlushInterval: Double = 1.0
        private static let metaFlushByteThreshold: Int64 = 16 * 1024 * 1024
        private static let storageUpdateInterval: Double = 5.0
        private static let storageUpdateByteThreshold: Int64 = 32 * 1024 * 1024

        private let liveMapToken: Int64
        private var isMetaDirty: Bool = false
        private var unflushedMetaBytes: Int64 = 0
        private var lastMetaFlushTimestamp: Double = 0.0
        private var isMetaFlushScheduled: Bool = false
        private var lastStorageBoxSize: Int64 = 0
        private var lastStorageBoxUpdateTimestamp: Double = 0.0
        private var isStorageBoxSizeFinal: Bool = false

        init(
            queue: Queue,
            manager: MediaBoxFileManager,
            storageBox: StorageBox?,
            resourceId: Data,
            partialPath: String,
            fullPath: String,
            metaPath: String
        ) {
            self.queue = queue
            self.manager = manager
            self.storageBox = storageBox
            self.resourceId = resourceId
            self.partialPath = partialPath
            self.fullPath = fullPath
            self.metaPath = metaPath
            MediaBoxWriteStats.shared.contextOpened(resourceId: resourceId)

            if !FileManager.default.fileExists(atPath: self.partialPath) {
                let _ = try? FileManager.default.removeItem(atPath: self.metaPath)
                self.fileMap = MediaBoxFileMap()
                self.fileMap.serialize(manager: self.manager, to: self.metaPath)
            } else {
                if let readFileMap = try? MediaBoxFileMap.read(manager: self.manager, path: self.metaPath) {
                    // SuperGram: never trust a map that claims bytes beyond the end of the partial file
                    if let upperBound = readFileMap.ranges.ranges.last?.upperBound, let actualSize = fileSize(self.partialPath, useTotalFileAllocatedSize: false), upperBound > actualSize {
                        postboxLog("MediaBoxFileContextV2Impl: meta at \(self.metaPath) exceeds partial file size, resetting")
                        let _ = try? FileManager.default.removeItem(atPath: self.metaPath)
                        self.fileMap = MediaBoxFileMap()
                    } else {
                        self.fileMap = readFileMap
                    }
                } else {
                    let _ = try? FileManager.default.removeItem(atPath: self.metaPath)
                    self.fileMap = MediaBoxFileMap()
                }
            }

            self.destinationFile = self.manager.open(path: self.partialPath, mode: .readwrite)

            if mediaBoxCompleteFileSize(self.fullPath) != nil {
                self.isComplete = true
            }

            self.lastStorageBoxSize = self.fileMap.sum
            self.liveMapToken = MediaBoxLiveFileMaps.shared.register(path: self.partialPath, ranges: self.fileMap.ranges, truncationSize: self.fileMap.truncationSize)
        }

        deinit {
            self.pendingFetch?.disposable.dispose()

            // SuperGram: persist everything that was coalesced while the context was open
            if FileManager.default.fileExists(atPath: self.partialPath) {
                self.flushPersistentState(forceStorageUpdate: true)
            }
            MediaBoxLiveFileMaps.shared.unregister(path: self.partialPath, token: self.liveMapToken)
        }

        private func publishLiveMap() {
            MediaBoxLiveFileMaps.shared.update(path: self.partialPath, token: self.liveMapToken, ranges: self.fileMap.ranges, truncationSize: self.fileMap.truncationSize)
        }

        private func markMetaDirty(writtenBytes: Int64) {
            self.isMetaDirty = true
            self.unflushedMetaBytes += writtenBytes
            self.publishLiveMap()

            let timestamp = CFAbsoluteTimeGetCurrent()
            if self.unflushedMetaBytes >= PartialState.metaFlushByteThreshold || timestamp - self.lastMetaFlushTimestamp >= PartialState.metaFlushInterval {
                self.flushPersistentState(forceStorageUpdate: false)
            } else if !self.isMetaFlushScheduled {
                self.isMetaFlushScheduled = true
                let delay = max(0.05, PartialState.metaFlushInterval - (timestamp - self.lastMetaFlushTimestamp))
                self.queue.after(delay, { [weak self] in
                    guard let self else {
                        return
                    }
                    self.isMetaFlushScheduled = false
                    self.flushPersistentState(forceStorageUpdate: false)
                })
            }
        }

        private func flushPersistentState(forceStorageUpdate: Bool) {
            if self.isMetaDirty {
                self.lastMetaFlushTimestamp = CFAbsoluteTimeGetCurrent()
                if self.fileMap.serialize(manager: self.manager, to: self.metaPath) {
                    self.isMetaDirty = false
                    self.unflushedMetaBytes = 0
                }
            }
            self.updateStorageBoxSize(force: forceStorageUpdate)
        }

        private func persistMapChangeImmediately() {
            self.isMetaDirty = true
            self.publishLiveMap()
            self.flushPersistentState(forceStorageUpdate: false)
        }

        private func updateStorageBoxSize(force: Bool) {
            guard let storageBox = self.storageBox, !self.isStorageBoxSizeFinal else {
                return
            }
            let size = self.fileMap.sum
            if self.lastStorageBoxSize == size {
                return
            }
            let timestamp = CFAbsoluteTimeGetCurrent()
            if force || abs(size - self.lastStorageBoxSize) >= PartialState.storageUpdateByteThreshold || timestamp - self.lastStorageBoxUpdateTimestamp >= PartialState.storageUpdateInterval {
                self.lastStorageBoxSize = size
                self.lastStorageBoxUpdateTimestamp = timestamp
                storageBox.update(id: self.resourceId, size: size)
            }
        }
        
        func request(
            range: Range<Int64>,
            isFullRange: Bool,
            priority: MediaBoxFetchPriority,
            fetch: @escaping (Signal<[(Range<Int64>, MediaBoxFetchPriority)], NoError>) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError>,
            error: @escaping (MediaResourceDataFetchError) -> Void,
            completed: @escaping () -> Void
        ) -> Disposable {
            assert(self.queue.isCurrent())

            guard range.lowerBound >= 0 else {
                error(.generic)
                return EmptyDisposable
            }
            if !self.finalizeIfComplete() {
                self.processFetchError(error: .generic)
                error(.generic)
                return EmptyDisposable
            }
            
            self.fetchImpl = fetch
            
            let request = RangeRequest(
                value: range,
                priority: priority,
                isFullRange: isFullRange,
                error: error,
                completed: completed
            )
            if self.updateRangeRequest(request: request) {
                self.updateRequests()
                
                return EmptyDisposable
            } else {
                let index = self.rangeRequests.add(request)
                
                self.updateRequests()
                
                let queue = self.queue
                return ActionDisposable { [weak self] in
                    queue.async {
                        guard let `self` = self else {
                            return
                        }
                        self.rangeRequests.remove(index)
                        self.updateRequests()
                    }
                }
            }
        }
        
        func cancelFullRangeFetches() {
            // SuperGram: this cancels the full-range fetches of *every* owner of the resource, not just the one
            // that asked — MediaBox.cancelInteractiveResourceFetch is keyed by resource id, and several
            // independent owners (a bubble, a gallery item, a FetchManager entry, a preload) routinely share one
            // resource. Removing their requests without a terminal event left those owners' signals alive with
            // no completion and no error forever. For a FetchManager entry that means its fetch disposable never
            // resolves, so it keeps one of the very few per-category active slots for the rest of the session and
            // every status subscriber stays on .Fetching(isActive: false) — a spinner with a cancel button that
            // can never finish, for media that nobody is downloading.
            //
            // The owner that initiated the cancellation is not affected: every such path disposes its own
            // request first (on this same queue), so it is already out of the bag by the time we get here.
            // Reporting an error to the remaining owners is the honest outcome — they still want the resource,
            // and FetchManager's retry-with-backoff brings the download straight back.
            var cancelledRequests: [RangeRequest] = []
            for (index, rangeRequest) in self.rangeRequests.copyItemsWithIndices() {
                if rangeRequest.isFullRange {
                    self.rangeRequests.remove(index)
                    cancelledRequests.append(rangeRequest)
                }
            }
            self.updateRequests()
            for rangeRequest in cancelledRequests {
                // SuperGram: `.cancelled`, not `.generic`. These owners did nothing wrong and neither did the
                // network — somebody else asked for this resource id to stop being fetched. Reporting a generic
                // failure made FetchManager charge each of them a failure: a 2–60 s exponential backoff and a
                // step toward abandonment, so a still-visible second copy of the same media visibly reset its
                // progress and then sat idle for seconds. With `.cancelled` the entry restarts promptly and its
                // failure counters are left alone.
                rangeRequest.error(.cancelled)
            }
        }

        // SuperGram: last-resort self-heal, see MediaBox.resetResourceFetchState. Tears the fetch state down the
        // same way a reported fetch error does — dispose the pending fetch, forget the materialized ranges (so an
        // identical retry is not deduplicated away), fail the outstanding range requests so their owners retry,
        // and push the real status (.Remote, because nothing is running) to every live status subscriber. The
        // bytes already on disk and the file map are deliberately kept: this un-sticks a download, it does not
        // throw work away.
        func resetFetchState() {
            self.processFetchError(error: .generic)
        }

        var hasPendingFetch: Bool {
            return self.pendingFetch != nil
        }
        
        func status(next: @escaping (MediaResourceStatus) -> Void, completed: @escaping () -> Void, size: Int64?) -> Disposable {
            assert(self.queue.isCurrent())
            
            let request = StatusRequest(
                size: size,
                next: next,
                completed: completed
            )
            if self.updateStatusRequest(request: request) {
                return EmptyDisposable
            } else {
                let index = self.statusRequests.add(request)
                
                let queue = self.queue
                return ActionDisposable { [weak self] in
                    queue.async {
                        guard let `self` = self else {
                            return
                        }
                        self.statusRequests.remove(index)
                    }
                }
            }
        }
        
        func partialData(range: Range<Int64>, waitUntilAfterInitialFetch: Bool, next: @escaping (MediaResourceData) -> Void) -> Disposable {
            let request = PartialDataRequest(
                range: range,
                waitUntilAfterInitialFetch: waitUntilAfterInitialFetch && !self.hasPerformedAnyFetch,
                next: next
            )
            if self.updatePartialDataRequest(request: request) {
                return EmptyDisposable
            } else {
                let index = self.partialDataRequests.add(request)
                
                let queue = self.queue
                return ActionDisposable { [weak self] in
                    queue.async {
                        guard let `self` = self else {
                            return
                        }
                        self.partialDataRequests.remove(index)
                    }
                }
            }
        }
        
        func rangeStatus(
            next: @escaping (RangeSet<Int64>) -> Void,
            completed: @escaping () -> Void
        ) -> Disposable {
            assert(self.queue.isCurrent())
            
            let request = RangeStatusRequest(
                next: next,
                completed: completed
            )
            if self.updateRangeStatusRequest(request: request) {
                return EmptyDisposable
            } else {
                let index = self.rangeStatusRequests.add(request)
                
                let queue = self.queue
                return ActionDisposable { [weak self] in
                    queue.async {
                        guard let `self` = self else {
                            return
                        }
                        self.rangeStatusRequests.remove(index)
                    }
                }
            }
        }
        
        func internalStore(data: Data, range: Range<Int64>) {
            assert(self.queue.isCurrent())
            
            if data.count == Int(range.upperBound - range.lowerBound) {
                self.processFetchResult(result: .dataPart(resourceOffset: range.lowerBound, data: data, range: 0 ..< Int64(data.count), complete: false))
            } else {
                assertionFailure()
            }
        }
        
        private func updateRequests() {
            var rangesByPriority: [MediaBoxFetchPriority: RangeSet<Int64>] = [:]
            for (index, rangeRequest) in self.rangeRequests.copyItemsWithIndices() {
                if self.updateRangeRequest(request: rangeRequest) {
                    self.rangeRequests.remove(index)
                    continue
                }
                
                if rangesByPriority[rangeRequest.priority] == nil {
                    rangesByPriority[rangeRequest.priority] = RangeSet()
                }
                rangesByPriority[rangeRequest.priority]?.formUnion(RangeSet<Int64>(rangeRequest.value))
            }
            
            let initialFilterRanges: RangeSet<Int64>
            if let current = self.pendingFetch {
                initialFilterRanges = current.initialFilterRanges
            } else {
                initialFilterRanges = self.fileMap.ranges
            }
            
            var materializedRangeRequests: [MaterializedRangeRequest] = []
            for (priority, ranges) in rangesByPriority.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let filteredRanges = ranges.subtracting(initialFilterRanges)
                for range in filteredRanges.ranges {
                    materializedRangeRequests.append(MaterializedRangeRequest(range: range, priority: priority))
                }
            }
            
            if self.materializedRangeRequests != materializedRangeRequests {
                self.materializedRangeRequests = materializedRangeRequests
                
                if !materializedRangeRequests.isEmpty {
                    if let fetchImpl = self.fetchImpl {
                        let pendingFetch: PendingFetch
                        if let current = self.pendingFetch {
                            pendingFetch = current
                        } else {
                            let disposable = MetaDisposable()
                            pendingFetch = PendingFetch(initialFilterRanges: initialFilterRanges, disposable: disposable)
                            self.pendingFetch = pendingFetch
                            self.hasPerformedAnyFetch = true
                            
                            let queue = self.queue
                            disposable.set(fetchImpl(pendingFetch.ranges.get()).startStrict(next: { [weak self, weak pendingFetch] result in
                                queue.async { [weak self, weak pendingFetch] in
                                    // Disposal cannot remove an event already queued by the old attempt. In
                                    // particular, its .reset/error must not overwrite or fail a replacement fetch.
                                    guard let self, let pendingFetch, self.pendingFetch === pendingFetch else {
                                        return
                                    }
                                    self.processFetchResult(result: result)
                                }
                            }, error: { [weak self, weak pendingFetch] error in
                                queue.async { [weak self, weak pendingFetch] in
                                    guard let self, let pendingFetch, self.pendingFetch === pendingFetch else {
                                        return
                                    }
                                    self.processFetchError(error: error)
                                }
                            }, completed: { [weak self, weak pendingFetch] in
                                queue.async { [weak self, weak pendingFetch] in
                                    guard let self, let pendingFetch, self.pendingFetch === pendingFetch else {
                                        return
                                    }
                                    // A completed source with missing ranges cannot produce any more bytes.
                                    // Successful results remove the pending fetch in updateRequests first.
                                    self.processFetchError(error: .generic)
                                }
                            }))
                        }
                        pendingFetch.ranges.set(.single(materializedRangeRequests.map { request -> (Range<Int64>, MediaBoxFetchPriority) in
                            return (request.range, request.priority)
                        }))
                    }
                } else {
                    if let pendingFetch = self.pendingFetch {
                        self.pendingFetch = nil
                        pendingFetch.disposable.dispose()

                        // SuperGram: the fetch went idle, persist the coalesced map now
                        self.flushPersistentState(forceStorageUpdate: true)
                    }
                }
            }
            
            self.updateStatusRequests()
        }
        
        private func processFetchResult(result: MediaResourceDataFetchResult) {
            assert(self.queue.isCurrent())

            var didFailToWrite = false

            switch result {
            case let .dataPart(resourceOffset, data, dataRange, complete):
                if !self.processWrite(resourceOffset: resourceOffset, data: data, dataRange: dataRange) {
                    didFailToWrite = true
                }

                if complete && !didFailToWrite {
                    if let maxOffset = self.fileMap.ranges.ranges.reversed().first?.upperBound {
                        let maxValue = max(resourceOffset + Int64(dataRange.count), Int64(maxOffset))
                        if self.fileMap.truncationSize != maxValue {
                            self.fileMap.truncate(maxValue)
                            self.persistMapChangeImmediately()
                        }
                    }
                }
            case let .resourceSizeUpdated(size):
                if size < 0 {
                    didFailToWrite = true
                } else if self.fileMap.truncationSize != size {
                    self.fileMap.truncate(size)
                    self.persistMapChangeImmediately()
                }
            case let .progressUpdated(progress):
                self.fileMap.progressUpdated(progress)
                self.updateStatusRequests()
            case let .replaceHeader(data, range):
                // A header rewrite overwrites bytes the file map already accounts for, so a failure here does not
                // leave a range that nobody will ever fetch again — don't fail the whole download over it.
                let _ = self.processWrite(resourceOffset: 0, data: data, dataRange: range)
            case let .moveLocalFile(path):
                do {
                    try FileManager.default.moveItem(atPath: path, toPath: self.fullPath)
                    didFailToWrite = !self.processMovedFile()
                } catch let e {
                    postboxLog("MediaBoxFileContextV2Impl: error moving temp file at \(self.fullPath): \(e)")
                    didFailToWrite = true
                }
            case let .moveTempFile(file):
                do {
                    try FileManager.default.moveItem(atPath: file.path, toPath: self.fullPath)
                    didFailToWrite = !self.processMovedFile()
                } catch let e {
                    postboxLog("MediaBoxFileContextV2Impl: error moving temp file at \(self.fullPath): \(e)")
                    didFailToWrite = true
                }
                TempBox.shared.dispose(file)
            case let .copyLocalItem(localItem):
                do {
                    if localItem.copyTo(url: URL(fileURLWithPath: self.fullPath)) {
                        didFailToWrite = !self.processMovedFile()
                        if !didFailToWrite {
                            unlink(self.partialPath)
                            unlink(self.metaPath)
                        }
                    } else {
                        didFailToWrite = true
                    }
                }
            case .reset:
                if !self.fileMap.ranges.isEmpty {
                    self.fileMap.reset()
                    // A reset must reach the disk before any new bytes can overwrite the old ones
                    self.persistMapChangeImmediately()
                }

            }

            if didFailToWrite {
                // SuperGram: bytes that could not be written (no space left, a failed seek, a malformed part) are
                // simply gone. The fetch treats the range as delivered and stops scheduling it, while this context
                // still reports the range as missing - so the download would sit at the same progress forever with
                // no error. Fail the fetch instead: the status falls back to .Remote and FetchManager retries.
                postboxLog("MediaBoxFileContextV2Impl: failed to write fetched data at \(self.partialPath), failing the fetch")
                self.processFetchError(error: .generic)
                return
            }

            if !self.finalizeIfComplete() {
                self.processFetchError(error: .generic)
                return
            }

            self.updateRequests()
        }

        @discardableResult
        private func processWrite(resourceOffset: Int64, data: Data, dataRange: Range<Int64>) -> Bool {
            // Validate before seeking, counting or deriving EOF. A failed part must not overflow in
            // the completion path or claim bytes that could not be written.
            guard resourceOffset >= 0, dataRange.lowerBound >= 0, dataRange.upperBound <= Int64(data.count),
                  resourceOffset <= Int64.max - (dataRange.upperBound - dataRange.lowerBound) else {
                return false
            }
            if let destinationFile = self.destinationFile {
                do {
                    var success = true
                    try destinationFile.access { fd in
                        if fd.seek(position: resourceOffset) {
                            // SuperGram: an empty buffer has no base address, and a range that points past the
                            // buffer would make fd.write read out of bounds. Treat both as a failed write.
                            guard dataRange.lowerBound >= 0, dataRange.upperBound <= Int64(data.count) else {
                                success = false
                                return
                            }
                            let written = data.withUnsafeBytes { rawBytes -> Int in
                                guard let bytes = rawBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                                    return 0
                                }
                                
                                return fd.write(bytes.advanced(by: Int(dataRange.lowerBound)), count: dataRange.count)
                            }
                            if written != dataRange.count {
                                // SuperGram: never mark bytes as present unless they were fully written
                                success = false
                            }
                        } else {
                            success = false
                        }
                    }
                    if success {
                        let range: Range<Int64> = resourceOffset ..< (resourceOffset + Int64(dataRange.count))
                        let sumBeforeFill = self.fileMap.sum
                        self.fileMap.fill(range)
                        MediaBoxWriteStats.shared.add(resourceId: self.resourceId, written: Int64(dataRange.count), newBytes: self.fileMap.sum - sumBeforeFill)
                        // SuperGram: .meta and StorageBox are persisted in batches, see markMetaDirty
                        self.markMetaDirty(writtenBytes: Int64(dataRange.count))
                        return true
                    } else {
                        postboxLog("MediaBoxFileContextV2Impl: error seeking file to \(resourceOffset) at \(self.partialPath)")
                        return false
                    }
                } catch let e {
                    postboxLog("MediaBoxFileContextV2Impl: error writing file at \(self.partialPath): \(e)")
                    return false
                }
            }
            // The partial file could not be opened at all, so nothing can ever be stored here
            postboxLog("MediaBoxFileContextV2Impl: no destination file for \(self.partialPath)")
            return false
        }

        private func finalizeIfComplete() -> Bool {
            guard !self.isComplete, let size = self.fileMap.truncationSize, size >= 0,
                  self.fileMap.contains(0 ..< size) != nil else {
                return true
            }

            self.flushPersistentState(forceStorageUpdate: true)
            // Reset/revalidation can leave a physical tail beyond the current EOF. A linked
            // resource must have exactly the advertised size, including a legitimate empty file.
            guard let destinationFile = self.destinationFile else { return false }
            do {
                var resized = false
                try destinationFile.access { fd in
                    resized = fd.truncate(count: size)
                }
                guard resized else { return false }
            } catch {
                return false
            }

            let linkResult = link(self.partialPath, self.fullPath)
            if linkResult != 0 && errno != EEXIST {
                postboxLog("MediaBoxFileContextV2Impl: error while linking \(self.partialPath): \(linkResult)")
                return false
            }
            guard mediaBoxCompleteFileSize(self.fullPath) == size, mediaBoxCompleteFilesMatch(self.partialPath, self.fullPath) else {
                if linkResult == 0 { unlink(self.fullPath) }
                return false
            }
            self.isComplete = true
            self.isStorageBoxSizeFinal = true
            self.storageBox?.update(id: self.resourceId, size: size)
            return true
        }

        private func processMovedFile() -> Bool {
            if let size = mediaBoxCompleteFileSize(self.fullPath) {
                self.isComplete = true
                self.isStorageBoxSizeFinal = true
                self.storageBox?.update(id: self.resourceId, size: size)
                return true
            }
            return false
        }

        private func processFetchError(error: MediaResourceDataFetchError) {
            assert(self.queue.isCurrent())

            self.flushPersistentState(forceStorageUpdate: true)

            // SuperGram: a failed fetch used to leave this context permanently poisoned, which is the main way a
            // download "spins forever":
            //  * `pendingFetch` stayed non-nil, so updateStatusRequest() kept reporting .Fetching(isActive: true)
            //    to every new subscriber even though nothing was running any more;
            //  * `materializedRangeRequests` kept its old value, so an identical retry (FetchManager backoff, a
            //    second tap, a re-entered chat) compared equal and never started a new fetch;
            //  * every status/rangeStatus subscriber was dropped without a terminal event, freezing the UI at the
            //    last reported progress.
            // Upstream rarely reached this path because FetchV2 stalled silently instead of reporting an error;
            // this fork reports errors (retry limit, CDN reupload, file reference revalidation), so it must reset.
            if let pendingFetch = self.pendingFetch {
                self.pendingFetch = nil
                pendingFetch.disposable.dispose()
            }
            self.materializedRangeRequests = []

            let rangeRequests = self.rangeRequests.copyItems()
            self.rangeRequests.removeAll()

            // Status subscribers stay subscribed: they now see .Remote(progress:) (nothing is downloading) and
            // will follow the next attempt instead of being stranded on a spinner.
            self.updateStatusRequests()

            for rangeRequest in rangeRequests {
                rangeRequest.error(error)
            }
        }
        
        private func updateRangeRequest(request: RangeRequest) -> Bool {
            assert(self.queue.isCurrent())
            
            if self.isComplete || self.fileMap.contains(request.value) != nil {
                request.completed()
                return true
            } else {
                return false
            }
        }
        
        private func updateStatusRequests() {
            for (index, partialDataRequest) in self.partialDataRequests.copyItemsWithIndices() {
                if self.updatePartialDataRequest(request: partialDataRequest) {
                    self.partialDataRequests.remove(index)
                }
            }
            for (index, statusRequest) in self.statusRequests.copyItemsWithIndices() {
                if self.updateStatusRequest(request: statusRequest) {
                    self.statusRequests.remove(index)
                }
            }
            for (index, rangeStatusRequest) in self.rangeStatusRequests.copyItemsWithIndices() {
                if self.updateRangeStatusRequest(request: rangeStatusRequest) {
                    self.rangeStatusRequests.remove(index)
                }
            }
        }
        
        private func updatePartialDataRequest(request: PartialDataRequest) -> Bool {
            assert(self.queue.isCurrent())
            
            if self.isComplete, let size = mediaBoxCompleteFileSize(self.fullPath) {
                var clampedLowerBound = request.range.lowerBound
                var clampedUpperBound = request.range.upperBound
                if clampedUpperBound > size {
                    clampedUpperBound = size
                }
                if clampedLowerBound > clampedUpperBound {
                    clampedLowerBound = clampedUpperBound
                }
                
                let updatedStatus = MediaResourceData(path: self.fullPath, offset: clampedLowerBound, size: clampedUpperBound - clampedLowerBound, complete: true)
                if request.reportedStatus != updatedStatus {
                    request.reportedStatus = updatedStatus
                    request.next(updatedStatus)
                }
                return true
            } else if let availableRange = self.fileMap.contains(request.range) {
                let updatedStatus = MediaResourceData(path: self.partialPath, offset: availableRange.lowerBound, size: availableRange.upperBound - availableRange.lowerBound, complete: true)
                if request.reportedStatus != updatedStatus {
                    request.reportedStatus = updatedStatus
                    request.next(updatedStatus)
                }
                return true
            } else {
                let updatedStatus = MediaResourceData(path: self.partialPath, offset: request.range.lowerBound, size: 0, complete: false)
                if request.reportedStatus != updatedStatus {
                    if request.waitingUntilAfterInitialFetch {
                        if self.hasPerformedAnyFetch {
                            request.waitingUntilAfterInitialFetch = false
                            request.reportedStatus = updatedStatus
                            request.next(updatedStatus)
                        }
                    } else {
                        request.reportedStatus = updatedStatus
                        request.next(updatedStatus)
                    }
                }
                return false
            }
        }
        
        private func updateStatusRequest(request: StatusRequest) -> Bool {
            assert(self.queue.isCurrent())
            
            let updatedStatus: MediaResourceStatus
            if self.isComplete {
                updatedStatus = .Local
            } else if let totalSize = self.fileMap.truncationSize ?? request.size {
                let progress = Float(self.fileMap.sum) / Float(totalSize)
                if self.pendingFetch != nil {
                    updatedStatus = .Fetching(isActive: true, progress: progress)
                } else {
                    updatedStatus = .Remote(progress: progress)
                }
            } else if self.pendingFetch != nil {
                if let progress = self.fileMap.progress {
                    updatedStatus = .Fetching(isActive: true, progress: progress)
                } else {
                    updatedStatus = .Fetching(isActive: true, progress: 0.0)
                }
            } else {
                updatedStatus = .Remote(progress: 0.0)
            }
            
            if request.reportedStatus != updatedStatus {
                request.reportedStatus = updatedStatus
                request.next(updatedStatus)
            }
            
            return false
        }
        
        private func updateRangeStatusRequest(request: RangeStatusRequest) -> Bool {
            assert(self.queue.isCurrent())
            
            let status: RangeSet<Int64>
            if self.isComplete, let size = mediaBoxCompleteFileSize(self.fullPath) {
                status = RangeSet(0 ..< size)
            } else {
                status = self.fileMap.ranges
            }
            if request.reportedStatus != status {
                request.reportedStatus = status
                request.next(status)
                
                if let truncationSize = self.fileMap.truncationSize, self.fileMap.sum == truncationSize {
                    request.completed()
                    return true
                }
            }
            
            return false
        }
    }
    
    private let queue: Queue
    private let manager: MediaBoxFileManager
    private let storageBox: StorageBox?
    private let resourceId: Data
    private let path: String
    private let partialPath: String
    private let metaPath: String
    
    private let references = Bag<Void>()
    
    private var partialState: PartialState?
    
    var isEmpty: Bool {
        return self.references.isEmpty
    }
    
    public init?(
        queue: Queue,
        manager: MediaBoxFileManager,
        storageBox: StorageBox?,
        resourceId: Data,
        path: String,
        partialPath: String,
        metaPath: String
    ) {
        self.queue = queue
        self.manager = manager
        self.storageBox = storageBox
        self.resourceId = resourceId
        self.path = path
        self.partialPath = partialPath
        self.metaPath = metaPath
    }
    
    func addReference() -> Int {
        assert(self.queue.isCurrent())
        return self.references.add(Void())
    }
    
    func removeReference(_ index: Int) {
        assert(self.queue.isCurrent())
        return self.references.remove(index)
    }
    
    private func withPartialState<T>(_ f: (PartialState) -> T) -> T {
        if let partialState = self.partialState {
            return f(partialState)
        } else {
            let partialState = PartialState(
                queue: self.queue,
                manager: self.manager,
                storageBox: self.storageBox,
                resourceId: self.resourceId,
                partialPath: self.partialPath,
                fullPath: self.path,
                metaPath: self.metaPath
            )
            self.partialState = partialState
            return f(partialState)
        }
    }
    
    public func data(range: Range<Int64>, waitUntilAfterInitialFetch: Bool, next: @escaping (MediaResourceData) -> Void) -> Disposable {
        assert(self.queue.isCurrent())
        
        if let size = mediaBoxCompleteFileSize(self.path) {
            var clampedLowerBound = range.lowerBound
            var clampedUpperBound = range.upperBound
            if clampedUpperBound > size {
                clampedUpperBound = size
            }
            if clampedLowerBound > clampedUpperBound {
                clampedLowerBound = clampedUpperBound
            }
            next(MediaResourceData(path: self.path, offset: clampedLowerBound, size: clampedUpperBound - clampedLowerBound, complete: true))
            return EmptyDisposable
        } else {
            return self.withPartialState { partialState in
                return partialState.partialData(
                    range: range,
                    waitUntilAfterInitialFetch: waitUntilAfterInitialFetch,
                    next: next
                )
            }
        }
    }
    
    public func fetched(
        range: Range<Int64>,
        priority: MediaBoxFetchPriority,
        fetch: @escaping (Signal<[(Range<Int64>, MediaBoxFetchPriority)], NoError>) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError>,
        error: @escaping (MediaResourceDataFetchError) -> Void,
        completed: @escaping () -> Void
    ) -> Disposable {
        assert(self.queue.isCurrent())
        
        if mediaBoxCompleteFileSize(self.path) != nil {
            completed()
            return EmptyDisposable
        } else {
            return self.withPartialState { partialState in
                return partialState.request(
                    range: range,
                    isFullRange: false,
                    priority: priority,
                    fetch: fetch,
                    error: error,
                    completed: completed
                )
            }
        }
    }
    
    public func fetchedFullRange(
        fetch: @escaping (Signal<[(Range<Int64>, MediaBoxFetchPriority)], NoError>) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError>,
        error: @escaping (MediaResourceDataFetchError) -> Void,
        completed: @escaping () -> Void
    ) -> Disposable {
        assert(self.queue.isCurrent())
        
        if mediaBoxCompleteFileSize(self.path) != nil {
            completed()
            return EmptyDisposable
        } else {
            return self.withPartialState { partialState in
                return partialState.request(
                    range: 0 ..< Int64.max,
                    isFullRange: true,
                    priority: .default,
                    fetch: fetch,
                    error: error,
                    completed: completed
                )
            }
        }
    }
    
    public func cancelFullRangeFetches() {
        assert(self.queue.isCurrent())

        if let partialState = self.partialState {
            partialState.cancelFullRangeFetches()
        }
    }

    // SuperGram: see PartialState.resetFetchState. Returns whether anything was actually reset, so the caller can
    // report how many resources it un-stuck. A context with no partial state has nothing in flight by definition.
    @discardableResult
    public func resetFetchState() -> Bool {
        assert(self.queue.isCurrent())

        guard let partialState = self.partialState else {
            return false
        }
        let wasFetching = partialState.hasPendingFetch
        partialState.resetFetchState()
        return wasFetching
    }
    
    public func rangeStatus(next: @escaping (RangeSet<Int64>) -> Void, completed: @escaping () -> Void) -> Disposable {
        assert(self.queue.isCurrent())
        
        if let size = mediaBoxCompleteFileSize(self.path) {
            next(RangeSet<Int64>([0 ..< Int64(size) as Range<Int64>]))
            completed()
            
            return EmptyDisposable
        } else {
            return self.withPartialState { partialState in
                return partialState.rangeStatus(next: next, completed: completed)
            }
        }
    }
    
    public func status(next: @escaping (MediaResourceStatus) -> Void, completed: @escaping () -> Void, size: Int64?) -> Disposable {
        assert(self.queue.isCurrent())
        
        if let _ = mediaBoxCompleteFileSize(self.path) {
            next(.Local)
            completed()
            
            return EmptyDisposable
        } else {
            return self.withPartialState { partialState in
                return partialState.status(next: next, completed: completed, size: size)
            }
        }
    }
    
    public func internalStore(data: Data, range: Range<Int64>) {
        if let _ = mediaBoxCompleteFileSize(self.path) {
        } else {
            self.withPartialState { partialState in
                partialState.internalStore(data: data, range: range)
            }
        }
    }
}
