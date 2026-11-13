import Foundation
import UIKit
import Display
import UniversalMediaPlayer
import AccountContext
import SwiftSignalKit
import TelegramCore
import CoreMedia
import CoreVideo

public protocol BatchVideoRenderingContextTarget: AnyObject {
    var batchVideoRenderingTargetState: BatchVideoRenderingContext.TargetState? { get set }
    
    func setSampleBuffer(sampleBuffer: CMSampleBuffer)
}

public final class BatchVideoRenderingContext {
    public typealias Target = BatchVideoRenderingContextTarget
    
    public final class TargetHandle {
        private weak var context: BatchVideoRenderingContext?
        private let id: Int
        
        init(context: BatchVideoRenderingContext, id: Int) {
            self.context = context
            self.id = id
        }
        
        deinit {
            // The handle can be released on any queue; hop to main so the context's
            // non-thread-safe state (targetContexts, disposables, displayLink) is only
            // mutated from one queue.
            let context = self.context
            let id = self.id
            Queue.mainQueue().async {
                context?.targetRemoved(id: id)
            }
        }
    }
    
    public final class TargetState {
        private var lastRenderedFrame: (timestamp: Double, pts: Double, duration: Double)?
        private(set) var sampleBuffers: [CMSampleBuffer] = []
        
        init() {
        }
        
        func addSampleBuffers(sampleBuffers: [CMSampleBuffer]) {
            for sampleBuffer in sampleBuffers {
                self.sampleBuffers.append(sampleBuffer)
            }
        }
        
        func render(at timestamp: Double) -> CMSampleBuffer? {
            if !self.sampleBuffers.isEmpty {
                let sampleBuffer = self.sampleBuffers[0]
                let sampleBufferPts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                let sampleBufferDuration = CMSampleBufferGetDuration(sampleBuffer).seconds
                if let lastRenderedFrame = self.lastRenderedFrame {
                    let elapsedTime = timestamp - lastRenderedFrame.timestamp
                    let ptsDifference = sampleBufferPts - lastRenderedFrame.pts
                    if ptsDifference < 0.0 {
                        // Loop
                        if elapsedTime >= lastRenderedFrame.duration {
                            self.lastRenderedFrame = (timestamp, sampleBufferPts, sampleBufferDuration)
                            self.sampleBuffers.removeFirst()
                            return sampleBuffer
                        } else {
                            return nil
                        }
                    } else {
                        if elapsedTime >= ptsDifference {
                            self.lastRenderedFrame = (timestamp, sampleBufferPts, sampleBufferDuration)
                            self.sampleBuffers.removeFirst()
                            return sampleBuffer
                        } else {
                            return nil
                        }
                    }
                } else {
                    self.lastRenderedFrame = (timestamp, sampleBufferPts, sampleBufferDuration)
                    self.sampleBuffers.removeFirst()
                    return sampleBuffer
                }
            } else {
                return nil
            }
        }
    }
    
    private final class ReadingContext {
        // SuperGram (KB-14): a GIF panel item loops forever, and before this the reader was thrown away and
        // rebuilt from the file at every end of stream, so every loop paid a full open + software decode of
        // the whole clip. Short clips - which is what the GIF panel, inline bot results and the peer GIF pane
        // show - are decoded once and then replayed from memory, and the decoder is released for good.
        //
        // The budget is what keeps this from trading CPU for jetsam: a clip that does not fit (long, or large
        // frames, or the process-wide budget is already spent) permanently falls back to re-decoding. Pressure
        // also disables the cache permanently for this context; the context itself only lives while the item is
        // on screen, so the next appearance gets a fresh attempt.
        //
        // Pressure is handled in two steps, and the difference matters. `constrained` is reached by sustained
        // *thermal* load as well as by a memory warning, and throwing away a finished cache under thermal load
        // is exactly backwards: every loop then pays a full open + software decode again, which is what made
        // the device hot in the first place. So `constrained` only stops the cache from growing, while an
        // already-complete one keeps playing from memory (its allocation is bounded and already made).
        // `critical` - a critical memory event, or a critical thermal state where nothing decorative should be
        // running anyway - gives the memory back.
        private enum CacheState {
            case collecting
            case complete
            case disabled
        }

        // A 480x270 NV12 frame is ~190 KB, so 12 MB is roughly a two-and-a-half second loop at 25 fps -
        // the length of a typical GIF-panel clip - and a 720p one stops fitting almost immediately, which
        // is the intent. Caching a clip also lets its decoder go, and an h264 codec context with its
        // reference frames and pixel-buffer pool is itself megabytes, so the net cost is well under the
        // budget. The process-wide cap is first-come-first-served: with a full panel on screen the first
        // few clips stop decoding and the rest keep the old behaviour, which is a strict improvement.
        private static let maxCachedFrameCount: Int = 200
        private static let maxCachedFrameBytes: Int = 12 * 1024 * 1024
        private static let maxTotalCachedFrameBytes: Int = 32 * 1024 * 1024
        // Only ever touched from BatchVideoRenderingContext.sharedQueue, which owns every ReadingContext
        // (they are created, used and deallocated through a QueueLocalObject bound to that queue).
        private static var totalCachedFrameBytes: Int = 0

        let dataPath: String

        var isFailed: Bool = false
        var reader: FFMpegFileReader?
        var readerProducedFrame: Bool = false

        private var cacheState: CacheState = .collecting
        private var cachedFrames: [CMSampleBuffer] = []
        private var cachedFrameBytes: Int = 0
        private var cachePlaybackIndex: Int = 0

        init(dataPath: String) {
            self.dataPath = dataPath
        }

        deinit {
            ReadingContext.totalCachedFrameBytes -= self.cachedFrameBytes
        }

        private func disableCache() {
            if case .disabled = self.cacheState {
                return
            }
            self.cacheState = .disabled
            self.cachedFrames.removeAll()
            ReadingContext.totalCachedFrameBytes -= self.cachedFrameBytes
            self.cachedFrameBytes = 0
            self.cachePlaybackIndex = 0
        }

        private func addToCache(_ sampleBuffer: CMSampleBuffer) {
            guard case .collecting = self.cacheState else {
                return
            }
            var frameBytes = 0
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                frameBytes = CVPixelBufferGetDataSize(imageBuffer)
            }
            if frameBytes <= 0 {
                frameBytes = CMSampleBufferGetTotalSampleSize(sampleBuffer)
            }
            if frameBytes <= 0 {
                // The frame size can't be accounted for, so it can't be bounded either.
                self.disableCache()
                return
            }
            if self.cachedFrames.count >= ReadingContext.maxCachedFrameCount
                || self.cachedFrameBytes + frameBytes > ReadingContext.maxCachedFrameBytes
                || ReadingContext.totalCachedFrameBytes + frameBytes > ReadingContext.maxTotalCachedFrameBytes {
                self.disableCache()
                return
            }
            self.cachedFrames.append(sampleBuffer)
            self.cachedFrameBytes += frameBytes
            ReadingContext.totalCachedFrameBytes += frameBytes
        }

        private func nextCachedFrame() -> CMSampleBuffer? {
            if self.cachedFrames.isEmpty {
                return nil
            }
            if self.cachePlaybackIndex >= self.cachedFrames.count {
                self.cachePlaybackIndex = 0
            }
            let sampleBuffer = self.cachedFrames[self.cachePlaybackIndex]
            self.cachePlaybackIndex += 1
            // A copy gives the renderer its own timing info and attachment dictionary each time around the
            // loop. The pixel buffer is shared, so no image data is copied.
            return createSampleBuffer(fromSampleBuffer: sampleBuffer, withTimeOffset: .zero, duration: nil, displayImmediately: true) ?? sampleBuffer
        }

        // Called from the pressure observer through QueueLocalObject (so still on sharedQueue): in the
        // background the display link is stopped and `advance()` never runs, so without this the cached
        // pixel buffers would stay resident for exactly the stretch where jetsam is looking at us.
        func dropCacheUnderPressure() {
            self.disableCache()
        }

        func advance() -> CMSampleBuffer? {
            let pressureLevel = MediaDownloadPressure.shared.level
            if pressureLevel >= .critical {
                self.disableCache()
            } else if pressureLevel >= .constrained, case .collecting = self.cacheState {
                self.disableCache()
            }
            if case .complete = self.cacheState, !self.cachedFrames.isEmpty {
                return self.nextCachedFrame()
            }

            outer: while true {
                if self.isFailed {
                    break outer
                }
                if self.reader == nil {
                    let reader = FFMpegFileReader(
                        source: .file(self.dataPath),
                        useHardwareAcceleration: false,
                        selectedStream: .mediaType(.video),
                        seek: nil,
                        maxReadablePts: nil
                    )
                    if reader == nil {
                        self.isFailed = true
                        break outer
                    }
                    self.reader = reader
                    self.readerProducedFrame = false
                }
                
                guard let reader = self.reader else {
                    break outer
                }
                
                switch reader.readFrame() {
                case let .frame(frame):
                    guard let sampleBuffer = createSampleBuffer(fromSampleBuffer: frame.sampleBuffer, withTimeOffset: .zero, duration: nil, displayImmediately: true) else {
                        continue outer
                    }
                    self.readerProducedFrame = true
                    self.addToCache(sampleBuffer)
                    return sampleBuffer
                case .error:
                    self.isFailed = true
                    break outer
                case .endOfStream:
                    // Unsupported video formats can reach EOF without producing a
                    // frame. Reopening the same file here would spin forever on the
                    // shared decode queue and pin a CPU core.
                    if !self.readerProducedFrame {
                        self.isFailed = true
                        break outer
                    }
                    self.reader = nil
                    // SuperGram (KB-14): the first pass just ended and every frame of it fits in the budget,
                    // so the decoder is done for good and the rest of the loops come out of memory.
                    if case .collecting = self.cacheState, !self.cachedFrames.isEmpty {
                        self.cacheState = .complete
                        self.cachePlaybackIndex = 0
                        return self.nextCachedFrame()
                    }
                case .waitingForMoreData:
                    // Invariant: the reader is only constructed once the consumer's
                    // `data.isComplete == true` (see `BatchVideoRenderingContext.update`),
                    // so a `.file(...)` source should never report waitingForMoreData.
                    // Treat it as fatal rather than spin if the invariant is ever violated.
                    self.isFailed = true
                    break outer
                }
            }
            return nil
        }
    }
    
    private final class TargetContext {
        weak var target: Target?
        let file: FileMediaReference
        let userLocation: MediaResourceUserLocation
        
        var readingContext: QueueLocalObject<ReadingContext>?
        var fetchDisposable: Disposable?
        var dataDisposable: Disposable?
        var dataPath: String?
        // SuperGram (MEM-12): main-queue mirror of ReadingContext.isFailed, which lives on the decode queue.
        var isRenderingFailed: Bool = false

        init(
            target: Target,
            file: FileMediaReference,
            userLocation: MediaResourceUserLocation
        ) {
            self.target = target
            self.file = file
            self.userLocation = userLocation
        }
        
        deinit {
            self.fetchDisposable?.dispose()
            self.dataDisposable?.dispose()
        }
    }
    
    private static let sharedQueue = Queue(name: "BatchVideoRenderingContext", qos: .default)
    
    private let context: AccountContext
    
    private var targetContexts: [Int: TargetContext] = [:]
    private var nextId: Int = 0
    
    private var isRendering: Bool = false
    private var displayLink: SharedDisplayLinkDriver.Link?
    private var displayLinkFramesPerSecond: SharedDisplayLinkDriver.FramesPerSecond?
    private var pressureDisposable: Disposable?
    private var memoryWarningObserver: NSObjectProtocol?

    public init(context: AccountContext) {
        self.context = context

        // SuperGram (MEM-12): the tick rate and the lookahead depth follow the process-wide pressure level,
        // so a warm or memory-starved device stops spending a full 60 Hz main-queue tick on decorative GIFs.
        self.pressureDisposable = (MediaDownloadPressure.shared.levelSignal
        |> deliverOnMainQueue).startStrict(next: { [weak self] level in
            guard let self else {
                return
            }
            if level >= .critical {
                // Push the release rather than waiting for the next `advance()`: a critical event usually
                // arrives while the app is in the background, where the display link is stopped and
                // `advance()` would not run again until the user came back.
                self.dropFrameCaches()
            }
            self.updateDisplayLink()
        })

        // The pressure level deliberately conflates memory and thermal state, and only the memory axis is a
        // reason to throw decoded frames away (see ReadingContext). This is the unambiguous one, and it also
        // fires while the app is in the background with the display link stopped.
        self.memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil, using: { [weak self] _ in
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                self.dropFrameCaches()
            }
        })
    }

    deinit {
        self.pressureDisposable?.dispose()
        if let memoryWarningObserver = self.memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    /// Releases every cached decoded frame. The clips go back to re-decoding each loop, which is the right
    /// trade only when the process is actually short of memory.
    private func dropFrameCaches() {
        for (_, targetContext) in self.targetContexts {
            targetContext.readingContext?.with { readingContext in
                readingContext.dropCacheUnderPressure()
            }
        }
    }

    private static func targetBufferDepth() -> Int {
        return MediaDownloadPressure.shared.level >= .constrained ? 1 : 2
    }

    private static func currentDisplayLinkFramesPerSecond() -> SharedDisplayLinkDriver.FramesPerSecond {
        switch MediaDownloadPressure.shared.level {
        case .normal:
            return .fps(60)
        case .reduced, .constrained:
            return .fps(30)
        case .critical:
            return .fps(15)
        }
    }

    public func add(target: Target, file: FileMediaReference, userLocation: MediaResourceUserLocation) -> TargetHandle {
        let id = self.nextId
        self.nextId += 1
        
        self.targetContexts[id] = TargetContext(
            target: target,
            file: file,
            userLocation: userLocation
        )
        self.update()
        
        return TargetHandle(context: self, id: id)
    }
    
    private func targetRemoved(id: Int) {
        if let removed = self.targetContexts.removeValue(forKey: id) {
            // Clear the leftover TargetState so a recycled target doesn't start its
            // next session by replaying our queued buffers and stale lastRenderedFrame.
            removed.target?.batchVideoRenderingTargetState = nil
            self.update()
        }
    }
    
    private func update() {
        var removeIds: [Int] = []
        for (id, targetContext) in self.targetContexts {
            if targetContext.target != nil {
                if targetContext.fetchDisposable == nil {
                    targetContext.fetchDisposable = fetchedMediaResource(
                        mediaBox: self.context.account.postbox.mediaBox,
                        userLocation: targetContext.userLocation,
                        userContentType: .sticker,
                        reference: targetContext.file.resourceReference(targetContext.file.media.resource)
                    ).startStrict()
                }
                if targetContext.dataDisposable == nil {
                    targetContext.dataDisposable = (self.context.engine.resources.data(resource: EngineMediaResource(targetContext.file.media.resource))
                    |> deliverOnMainQueue).startStrict(next: { [weak self, weak targetContext] data in
                        guard let self, let targetContext else {
                            return
                        }
                        if data.isComplete && targetContext.dataPath == nil {
                            targetContext.dataPath = data.path
                            self.update()
                        }
                    })
                }
                if targetContext.readingContext == nil, let dataPath = targetContext.dataPath {
                    targetContext.readingContext = QueueLocalObject(queue: BatchVideoRenderingContext.sharedQueue, generate: {
                        return ReadingContext(dataPath: dataPath)
                    })
                }
            } else {
                removeIds.append(id)
            }
        }
        for id in removeIds {
            self.targetContexts.removeValue(forKey: id)
        }
        
        self.updateDisplayLink()
    }

    private func updateDisplayLink() {
        // SuperGram (MEM-12): a target alone is not work. Until its file is on disk there is nothing to
        // decode, and once its reader has failed there never will be, so in both cases a running display
        // link is a pure main-queue wakeup at up to 60 Hz. Only run it while some target can actually
        // produce a frame.
        var hasRenderableTarget = false
        for (_, targetContext) in self.targetContexts {
            if targetContext.target != nil && targetContext.readingContext != nil && !targetContext.isRenderingFailed {
                hasRenderableTarget = true
                break
            }
        }

        if hasRenderableTarget {
            let framesPerSecond = BatchVideoRenderingContext.currentDisplayLinkFramesPerSecond()
            if self.displayLink == nil || self.displayLinkFramesPerSecond != framesPerSecond {
                // The rate is fixed when a link is created, so a changed rate means a new link.
                self.displayLink?.isPaused = true
                self.displayLinkFramesPerSecond = framesPerSecond
                self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: framesPerSecond, { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.updateRendering()
                })
            }
        } else if let displayLink = self.displayLink {
            // Pausing before releasing makes the driver drop its CADisplayLink right away instead of
            // ticking once more before it notices the link is gone.
            displayLink.isPaused = true
            self.displayLink = nil
            self.displayLinkFramesPerSecond = nil
        }
    }

    private func updateRendering() {
        if self.isRendering {
            return
        }
        
        var removeIds: [Int] = []
        var renderIds: [Int: Int] = [:]
        // SuperGram (MEM-12): one frame of lookahead instead of two once the process is under pressure -
        // every buffered frame is a retained decoded pixel buffer per visible item.
        let targetBufferDepth = BatchVideoRenderingContext.targetBufferDepth()
        for (id, targetContext) in self.targetContexts {
            guard let target = targetContext.target else {
                removeIds.append(id)
                continue
            }
            if targetContext.isRenderingFailed {
                continue
            }
            let targetState: TargetState
            if let current = target.batchVideoRenderingTargetState {
                targetState = current
            } else {
                targetState = TargetState()
                target.batchVideoRenderingTargetState = targetState
            }

            if targetState.sampleBuffers.count < targetBufferDepth {
                renderIds[id] = targetBufferDepth - targetState.sampleBuffers.count
            }
        }
        
        for id in removeIds {
            self.targetContexts.removeValue(forKey: id)
        }
        
        if !renderIds.isEmpty {
            self.isRendering = true
            
            var readingContexts: [Int: (Int, QueueLocalObject<ReadingContext>)] = [:]
            for (id, count) in renderIds {
                guard let targetContext = self.targetContexts[id] else {
                    continue
                }
                if let readingContext = targetContext.readingContext {
                    readingContexts[id] = (count, readingContext)
                }
            }
            BatchVideoRenderingContext.sharedQueue.async { [weak self] in
                var sampleBuffers: [Int: [CMSampleBuffer]] = [:]
                var failedIds: [Int] = []
                for (id, (count, readingContext)) in readingContexts {
                    guard let readingContext = readingContext.unsafeGet() else {
                        sampleBuffers[id] = []
                        continue
                    }
                    sampleBuffers[id] = []
                    for _ in 0 ..< count {
                        if let sampleBuffer = readingContext.advance() {
                            sampleBuffers[id]?.append(sampleBuffer)
                        }
                    }
                    if readingContext.isFailed {
                        failedIds.append(id)
                    }
                }

                Queue.mainQueue().async {
                    guard let self else {
                        return
                    }
                    self.isRendering = false

                    for (id, targetSampleBuffers) in sampleBuffers {
                        guard let targetContext = self.targetContexts[id], let target = targetContext.target, let targetState = target.batchVideoRenderingTargetState else {
                            continue
                        }
                        targetState.addSampleBuffers(sampleBuffers: targetSampleBuffers)
                    }
                    for id in failedIds {
                        self.targetContexts[id]?.isRenderingFailed = true
                    }

                    self.updateFrames()
                    if !failedIds.isEmpty {
                        self.updateDisplayLink()
                    }
                }
            }
        } else {
            self.updateFrames()
        }
        
        self.updateDisplayLink()
    }
    
    private func updateFrames() {
        let timestamp = CACurrentMediaTime()
        for (_, targetContext) in self.targetContexts {
            guard let target = targetContext.target, let targetState = target.batchVideoRenderingTargetState else {
                continue
            }
            if let sampleBuffer = targetState.render(at: timestamp) {
                target.setSampleBuffer(sampleBuffer: sampleBuffer)
            }
        }
    }
}

private func createSampleBuffer(fromSampleBuffer sampleBuffer: CMSampleBuffer, withTimeOffset timeOffset: CMTime, duration: CMTime?, displayImmediately: Bool) -> CMSampleBuffer? {
    var itemCount: CMItemCount = 0
    var status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &itemCount)
    if status != 0 {
        return nil
    }
    
    var timingInfo = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: CMTimeMake(value: 0, timescale: 0), presentationTimeStamp: CMTimeMake(value: 0, timescale: 0), decodeTimeStamp: CMTimeMake(value: 0, timescale: 0)), count: itemCount)
    status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: itemCount, arrayToFill: &timingInfo, entriesNeededOut: &itemCount)
    if status != 0 {
        return nil
    }
    
    if let dur = duration {
        for i in 0 ..< itemCount {
            timingInfo[i].decodeTimeStamp = CMTimeAdd(timingInfo[i].decodeTimeStamp, timeOffset)
            timingInfo[i].presentationTimeStamp = CMTimeAdd(timingInfo[i].presentationTimeStamp, timeOffset)
            timingInfo[i].duration = dur
        }
    } else {
        for i in 0 ..< itemCount {
            timingInfo[i].decodeTimeStamp = CMTimeAdd(timingInfo[i].decodeTimeStamp, timeOffset)
            timingInfo[i].presentationTimeStamp = CMTimeAdd(timingInfo[i].presentationTimeStamp, timeOffset)
        }
    }
    
    var sampleBufferOffset: CMSampleBuffer?
    CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleTimingEntryCount: itemCount, sampleTimingArray: &timingInfo, sampleBufferOut: &sampleBufferOffset)
    guard let sampleBufferOffset else {
        return nil
    }
    
    if displayImmediately {
        // SuperGram: a sample buffer without samples yields an empty attachments array, so the previous
        // force-index/force-cast trapped instead of just skipping the flag. The array itself is also
        // optional - CMSampleBufferGetSampleAttachmentsArray returns NULL for a buffer that carries no
        // sample data at all, even with createIfNecessary - so the force-unwrap left here was the same
        // crash one step earlier (KB-11 / #2019).
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBufferOffset, createIfNecessary: true), let dict = (attachments as NSArray).firstObject as? NSMutableDictionary {
            dict[kCMSampleAttachmentKey_DisplayImmediately as NSString] = true as NSNumber
        }
    }
    
    return sampleBufferOffset
}
