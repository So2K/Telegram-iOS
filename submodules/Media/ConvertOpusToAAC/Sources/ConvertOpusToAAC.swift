import Foundation
import UniversalMediaPlayer
import AVFoundation
import SwiftSignalKit

public func convertOpusToAAC(sourcePath: String, allocateTempFile: @escaping () -> String) -> Signal<String?, NoError> {
    return Signal { subscriber in
        let isCancelled = Atomic<Bool>(value: false)
        let currentWriter = Atomic<AVAssetWriter?>(value: nil)
        let outputPathToClean = Atomic<String?>(value: nil)
        let didDeliverOutput = Atomic<Bool>(value: false)
        let queue = Queue()
        let removeUnfinishedOutput: () -> Void = {
            if !didDeliverOutput.with({ $0 }), let path = outputPathToClean.swap(nil) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        
        queue.async {
            if isCancelled.with({ $0 }) {
                return
            }

            do {
                let audioSource = SoftwareAudioSource(path: sourcePath)

                // SuperGram: a video without an audio track (or an unreadable file) can't produce samples
                guard audioSource.hasStream else {
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                if isCancelled.with({ $0 }) {
                    return
                }

                let outputPath = allocateTempFile()
                let _ = outputPathToClean.swap(outputPath)
                
                let assetWriter = try AVAssetWriter(outputURL: URL(fileURLWithPath: outputPath), fileType: .m4a)
                let _ = currentWriter.swap(assetWriter)
                if isCancelled.with({ $0 }) {
                    assetWriter.cancelWriting()
                    removeUnfinishedOutput()
                    return
                }
                
                var channelLayout = AudioChannelLayout()
                memset(&channelLayout, 0, MemoryLayout<AudioChannelLayout>.size)
                channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
                
                let outputSettings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 48000,
                    AVEncoderBitRateKey: 32000,
                    AVNumberOfChannelsKey: 1,
                    AVChannelLayoutKey: NSData(bytes: &channelLayout, length: MemoryLayout<AudioChannelLayout>.size)
                ]
                
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
                guard assetWriter.canAdd(audioInput) else {
                    let _ = currentWriter.swap(nil)
                    removeUnfinishedOutput()
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                assetWriter.add(audioInput)
                
                guard assetWriter.startWriting() else {
                    let _ = currentWriter.swap(nil)
                    removeUnfinishedOutput()
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                assetWriter.startSession(atSourceTime: .zero)
                
                var didAppendSample = false
                var isFinishing = false
                let finishWriting: () -> Void = {
                    guard !isFinishing else {
                        return
                    }
                    isFinishing = true
                    assetWriter.finishWriting(completionHandler: {
                        queue.async {
                            let _ = currentWriter.swap(nil)
                            guard !isCancelled.with({ $0 }) else {
                                removeUnfinishedOutput()
                                return
                            }
                            if didAppendSample && assetWriter.status == .completed {
                                let _ = didDeliverOutput.swap(true)
                                subscriber.putNext(outputPath)
                            } else {
                                removeUnfinishedOutput()
                                subscriber.putNext(nil)
                            }
                            subscriber.putCompletion()
                        }
                    })
                }
                
                audioInput.requestMediaDataWhenReady(on: queue.queue, using: {
                    if isFinishing {
                        return
                    }
                    while audioInput.isReadyForMoreMediaData {
                        if isCancelled.with({ $0 }) {
                            audioInput.markAsFinished()
                            assetWriter.cancelWriting()
                            let _ = currentWriter.swap(nil)
                            removeUnfinishedOutput()
                            return
                        }

                        if let sampleBuffer = autoreleasepool(invoking: { audioSource.readSampleBuffer() }) {
                            if audioInput.append(sampleBuffer) {
                                didAppendSample = true
                            } else {
                                audioInput.markAsFinished()
                                finishWriting()
                                return
                            }
                        } else {
                            audioInput.markAsFinished()
                            finishWriting()
                            return
                        }
                    }
                })
            } catch {
                let _ = currentWriter.swap(nil)
                removeUnfinishedOutput()
                subscriber.putNext(nil)
                subscriber.putCompletion()
            }
        }
        
        return ActionDisposable {
            let _ = isCancelled.swap(true)
            // A writer stalled under backpressure may never invoke the readiness callback again.
            // Cancel explicitly on its queue instead of waiting for another sample request.
            queue.async {
                if let writer = currentWriter.swap(nil), writer.status == .writing {
                    writer.cancelWriting()
                }
                removeUnfinishedOutput()
            }
        }
    }
}
