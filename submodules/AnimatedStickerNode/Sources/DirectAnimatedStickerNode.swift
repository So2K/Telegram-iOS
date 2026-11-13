import Foundation
import UIKit
import AsyncDisplayKit
import RLottieBinding
import SwiftSignalKit
import GZip
import Display

public final class DirectAnimatedStickerNode: ASDisplayNode, AnimatedStickerNode {
    private static let sharedQueue = Queue(name: "DirectAnimatedStickerNode", qos: .userInteractive)
    
    private final class LoadFrameTask {
        private let cancelled = Atomic<Bool>(value: false)

        var isCancelled: Bool {
            get {
                return self.cancelled.with { $0 }
            }
            set {
                let _ = self.cancelled.swap(newValue)
            }
        }
    }
    
    public var automaticallyLoadFirstFrame: Bool = false
    public var automaticallyLoadLastFrame: Bool = false
    public var playToCompletionOnStop: Bool = false
    
    private var didStart: Bool = false
    public var started: () -> Void = {}
    
    public var completed: (Bool) -> Void = { _ in }
    private var didComplete: Bool = false
    
    public var frameUpdated: (Int, Int) -> Void = { _, _ in }
    public var currentFrameIndex: Int {
        get {
            return self.frameIndex
        } set(value) {
        }
    }
    public var currentFrameCount: Int {
        get {
            if let lottieInstance = self.lottieInstance {
                return Int(lottieInstance.frameCount)
            } else if self.videoSource != nil {
                return self.videoFrameCount
            } else {
                return 0
            }
        } set(value) {
        }
    }
    public var currentFrameImage: UIImage? {
        if let contents = self.layer.contents {
            return UIImage(cgImage: contents as! CGImage)
        } else {
            return nil
        }
    }
    
    public private(set) var isPlaying: Bool = false
    public var stopAtNearestLoop: Bool = false
    
    private let statusPromise = Promise<AnimatedStickerStatus>()
    public var status: Signal<AnimatedStickerStatus, NoError> {
        return self.statusPromise.get()
    }
    
    public var autoplay: Bool = true
    
    public var visibility: Bool = false {
        didSet {
            self.updatePlayback()
        }
    }
    
    public var overrideVisibility: Bool = false
    
    public var isPlayingChanged: (Bool) -> Void = { _ in }
    
    private var sourceDisposable: Disposable?
    private var playbackSize: CGSize?
    
    private var lottieInstance: LottieInstance?
    private var videoSource: QueueLocalObject<AnimatedStickerFrameSourceWrapper>?
    private var videoFrameCount: Int = 0
    private var videoFrameRate: Int = 0
    private var frameIndex: Int = 0
    private var playbackMode: AnimatedStickerPlaybackMode = .loop
    private var isPlaybackPaused: Bool = false
    
    private var frameImages: [Int: UIImage] = [:]
    private var loadFrameTasks: [Int: LoadFrameTask] = [:]
    private var nextFrameTimer: SwiftSignalKit.Timer?
    
    override public init() {
        super.init()
    }
    
    deinit {
        self.sourceDisposable?.dispose()
        self.nextFrameTimer?.invalidate()
        for task in self.loadFrameTasks.values {
            task.isCancelled = true
        }
    }
    
    public func cloneCurrentFrame(from otherNode: AnimatedStickerNode?) {
    }
    
    public func setup(source: AnimatedStickerNodeSource, width: Int, height: Int, playbackMode: AnimatedStickerPlaybackMode, mode: AnimatedStickerMode) {
        self.reset()
        guard width > 0, height > 0 else {
            return
        }
        
        self.playbackSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        self.playbackMode = playbackMode
        
        self.sourceDisposable = (source.directDataPath(attemptSynchronously: false)
        |> filter { $0 != nil }
        |> take(1)
        |> deliverOnMainQueue).startStrict(next: { [weak self] path in
            guard let strongSelf = self, let path = path else {
                return
            }
            
            if source.isVideo {
                if let videoSource = makeVideoStickerDirectFrameSource(queue: DirectAnimatedStickerNode.sharedQueue, path: path, hintVP9: true, width: width, height: height, cachePathPrefix: nil, unpremultiplyAlpha: false) {
                    let frameCount = videoSource.frameCount
                    let frameRate = videoSource.frameRate
                    let source = QueueLocalObject(queue: DirectAnimatedStickerNode.sharedQueue, generate: {
                        return AnimatedStickerFrameSourceWrapper(videoSource)
                    })
                    strongSelf.setupPlayback(videoSource: source, frameCount: frameCount, frameRate: frameRate)
                }
            } else {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                    return
                }
                
                let decompressedData = TGGUnzipData(data, 8 * 1024 * 1024) ?? data
                
                guard let lottieInstance = LottieInstance(data: decompressedData, fitzModifier: source.fitzModifier?.lottieFitzModifier ?? .none, colorReplacements: nil, cacheKey: "") else {
                    print("Could not load sticker data")
                    return
                }
                
                strongSelf.setupPlayback(lottieInstance: lottieInstance)
            }
        }).strict()
    }
    
    private func updatePlayback() {
        let isVisible = self.visibility
        let isStill: Bool
        if case .still = self.playbackMode {
            isStill = true
        } else {
            isStill = false
        }
        let isPlaying = isVisible && !isStill && !self.isPlaybackPaused && !self.didComplete && (self.lottieInstance != nil || self.videoSource != nil)
        if self.isPlaying != isPlaying {
            self.isPlaying = isPlaying
            
            if self.isPlaying {
                self.startNextFrameTimerIfNeeded()
                self.updateLoadFrameTasks()
            } else {
                self.nextFrameTimer?.invalidate()
                self.nextFrameTimer = nil
            }
            
            self.isPlayingChanged(self.isPlaying)
        }
        if isVisible {
            self.updateLoadFrameTasks()
        }
    }
    
    private func startNextFrameTimerIfNeeded() {
        // A frame render can finish after visibility changed or pause() invalidated the timer.
        // Only live playback may schedule its replacement.
        guard self.isPlaying, !self.didComplete else {
            return
        }
        var frameRate: Double?
        if let lottieInstance = self.lottieInstance {
            frameRate = Double(lottieInstance.frameRate)
        } else if self.videoSource != nil {
            frameRate = Double(self.videoFrameRate)
        }
        
        if self.nextFrameTimer == nil, let frameRate = frameRate, frameRate > 0.0, self.frameImages[self.frameIndex] != nil {
            let nextFrameTimer = SwiftSignalKit.Timer(timeout: 1.0 / frameRate, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.nextFrameTimer = nil
                strongSelf.advanceFrameIfPossible()
            }, queue: .mainQueue())
            self.nextFrameTimer = nextFrameTimer
            nextFrameTimer.start()
        }
    }
    
    private func advanceFrameIfPossible() {
        guard self.isPlaying else {
            return
        }
        var frameCount: Int?
        if let lottieInstance = self.lottieInstance {
            frameCount = Int(lottieInstance.frameCount)
        } else if self.videoSource != nil {
            frameCount = self.videoFrameCount
        }
        guard let frameCount = frameCount, frameCount > 0 || self.videoSource != nil else {
            return
        }
        
        if self.frameIndex == frameCount - 1 {
            switch self.playbackMode {
            case .loop:
                self.completed(false)
            case let .count(count):
                if count <= 1 {
                    if !self.didComplete {
                        self.didComplete = true
                        self.updatePlayback()
                        self.completed(true)
                    }
                    return
                } else {
                    self.playbackMode = .count(count - 1)
                    self.completed(false)
                }
            case .once:
                if !self.didComplete {
                    self.didComplete = true
                    self.updatePlayback()
                    self.completed(true)
                }
                return
            case .still:
                break
            }
        }
        
        // A video source discovers its frame count on its first pass through the decoder.
        let nextFrameIndex = frameCount > 0 ? (self.frameIndex + 1) % frameCount : self.frameIndex + 1
        self.frameIndex = nextFrameIndex
        
        self.updateFrameImageIfNeeded()
        self.updateLoadFrameTasks()
    }
    
    private func updateFrameImageIfNeeded() {
        var frameCount: Int?
        if let lottieInstance = self.lottieInstance {
            frameCount = Int(lottieInstance.frameCount)
        } else if self.videoSource != nil {
            frameCount = self.videoFrameCount
        }
        guard let frameCount = frameCount, frameCount > 0 || self.videoSource != nil else {
            return
        }
        
        var allowedIndices: [Int] = []
        for i in 0 ..< 2 {
            let mappedIndex = frameCount > 0 ? (self.frameIndex + i) % frameCount : self.frameIndex + i
            allowedIndices.append(mappedIndex)
        }
        
        var removeKeys: [Int] = []
        for index in self.frameImages.keys {
            if !allowedIndices.contains(index) {
                removeKeys.append(index)
            }
        }
        for index in removeKeys {
            self.frameImages.removeValue(forKey: index)
        }
        
        for (index, task) in self.loadFrameTasks {
            if !allowedIndices.contains(index) {
                task.isCancelled = true
            }
        }
        
        if let image = self.frameImages[self.frameIndex] {
            self.layer.contents = image.cgImage
            
            self.frameUpdated(self.frameIndex, frameCount)
            
            if !self.didComplete {
                self.startNextFrameTimerIfNeeded()
            }
            
            if !self.didStart {
                self.didStart = true
                self.started()
            }
        }
    }
    
    private func updateLoadFrameTasks() {
        var frameCount: Int?
        if let lottieInstance = self.lottieInstance {
            frameCount = Int(lottieInstance.frameCount)
        } else if self.videoSource != nil {
            frameCount = self.videoFrameCount
        }
        guard let frameCount = frameCount, frameCount > 0 || self.videoSource != nil else {
            return
        }
                
        let frameIndex = frameCount > 0 ? self.frameIndex % frameCount : self.frameIndex
        if self.frameImages[frameIndex] == nil {
            self.maybeStartLoadFrameTask(frameIndex: frameIndex)
        } else if self.isPlaying {
            self.maybeStartLoadFrameTask(frameIndex: frameCount > 0 ? (frameIndex + 1) % frameCount : frameIndex + 1)
        }
    }
    
    private func maybeStartLoadFrameTask(frameIndex: Int) {
        guard self.lottieInstance != nil || self.videoSource != nil else {
            return
        }
        guard let playbackSize = self.playbackSize else {
            return
        }
        if self.frameImages[frameIndex] != nil || self.loadFrameTasks[frameIndex] != nil {
            return
        }
        
        let task = LoadFrameTask()
        self.loadFrameTasks[frameIndex] = task
        
        let lottieInstance = self.lottieInstance
        let videoSource = self.videoSource
        
        DirectAnimatedStickerNode.sharedQueue.async { [weak self] in
            var image: UIImage?
            var videoFrameCount: Int?
            
            if !task.isCancelled {
                if let lottieInstance = lottieInstance {
                    if let drawingContext = DrawingContext(size: playbackSize, scale: 1.0, opaque: false, clear: false) {
                        lottieInstance.renderFrame(with: Int32(frameIndex), into: drawingContext.bytes.assumingMemoryBound(to: UInt8.self), width: Int32(drawingContext.scaledSize.width), height: Int32(drawingContext.scaledSize.height), bytesPerRow: Int32(drawingContext.bytesPerRow))
                        
                        image = drawingContext.generateImage()
                    }
                } else if let videoSource = videoSource {
                    let frame = videoSource.syncWith { source -> AnimatedStickerFrame? in
                        let frame = source.value.takeFrame(draw: true)
                        videoFrameCount = source.value.frameCount
                        return frame
                    }
                    if let frame = frame {
                        if let drawingContext = DrawingContext(size: CGSize(width: frame.width, height: frame.height), scale: 1.0, opaque: false, clear: false, bytesPerRow: frame.bytesPerRow) {   
                            frame.data.copyBytes(to: drawingContext.bytes.assumingMemoryBound(to: UInt8.self), from: 0 ..< min(frame.data.count, drawingContext.length))
                            
                            image = drawingContext.generateImage()
                        }
                    }
                }
            }
            
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                
                guard let currentTask = strongSelf.loadFrameTasks[frameIndex], currentTask === task else {
                    return
                }
                strongSelf.loadFrameTasks.removeValue(forKey: frameIndex)
                guard !task.isCancelled else {
                    return
                }
                let previousVideoFrameCount = strongSelf.videoFrameCount
                if let videoFrameCount = videoFrameCount {
                    strongSelf.videoFrameCount = videoFrameCount
                }
                
                if !task.isCancelled, let image = image {
                    strongSelf.frameImages[frameIndex] = image
                    strongSelf.updateFrameImageIfNeeded()
                    strongSelf.updateLoadFrameTasks()
                } else if let videoFrameCount = videoFrameCount, videoFrameCount > 0, previousVideoFrameCount == 0 {
                    // End-of-stream supplies the previously unknown count without a new frame.
                    // Allow the timer on the last image to complete or wrap with that count.
                    strongSelf.updateLoadFrameTasks()
                }
            }
        }
    }
    
    private func setupPlayback(lottieInstance: LottieInstance) {
        self.lottieInstance = lottieInstance
        
        self.updatePlayback()
    }
    
    private func setupPlayback(videoSource: QueueLocalObject<AnimatedStickerFrameSourceWrapper>, frameCount: Int, frameRate: Int) {
        self.videoSource = videoSource
        self.videoFrameCount = frameCount
        self.videoFrameRate = frameRate
        
        self.updatePlayback()
    }
    
    public func reset() {
        self.sourceDisposable?.dispose()
        self.sourceDisposable = nil
        self.nextFrameTimer?.invalidate()
        self.nextFrameTimer = nil
        for task in self.loadFrameTasks.values {
            task.isCancelled = true
        }
        self.loadFrameTasks.removeAll()
        self.frameImages.removeAll()
        self.lottieInstance = nil
        self.videoSource = nil
        self.videoFrameCount = 0
        self.videoFrameRate = 0
        self.frameIndex = 0
        self.didStart = false
        self.didComplete = false
        self.isPlaybackPaused = false
        self.layer.contents = nil
        self.updatePlayback()
    }
    
    public func playOnce() {
        self.playbackMode = .once
        self.play(firstFrame: false, fromIndex: 0)
    }
    
    public func playLoop() {
        self.playbackMode = .loop
        self.play(firstFrame: false, fromIndex: nil)
    }
    
    public func play(firstFrame: Bool, fromIndex: Int?) {
        if let fromIndex = fromIndex {
            if self.currentFrameCount > 0 {
                self.frameIndex = max(0, min(fromIndex, self.currentFrameCount - 1))
            } else {
                self.frameIndex = max(0, fromIndex)
            }
        }
        self.isPlaybackPaused = firstFrame
        self.didComplete = false
        self.updatePlayback()
        self.updateFrameImageIfNeeded()
        self.updateLoadFrameTasks()
    }
    
    public func pause() {
        self.isPlaybackPaused = true
        self.updatePlayback()
    }
    
    public func stop() {
        self.pause()
    }
    
    public func seekTo(_ position: AnimatedStickerPlaybackPosition) {
    }
    
    public func playIfNeeded() -> Bool {
        if !self.isPlaying {
            self.play(firstFrame: false, fromIndex: nil)
            return self.isPlaying
        }
        return false
    }
    
    public func updateLayout(size: CGSize) {
    }
    
    public func setOverlayColor(_ color: UIColor?, replace: Bool, animated: Bool) {
    }
}
