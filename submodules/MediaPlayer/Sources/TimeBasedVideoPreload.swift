import Foundation
#if !os(macOS)
import UIKit
#else
import AppKit
#endif
import SwiftSignalKit
import Postbox
import TelegramCore
import FFMpegBinding

// SuperGram: every preload used to get its own GCD queue plus a dedicated FFmpeg reader thread, started
// immediately from up to four call sites (visible chat items, in-chat prefetch, chat list prefetch of up
// to 30 chats, FetchManager). Preloads now share one queue and at most `maxConcurrentPreloads` run at a
// time; the most recently requested preload (usually what is on screen) starts first.
private final class VideoPreloadLimiter {
    static let shared = VideoPreloadLimiter()

    let queue = Queue(name: "TimeBasedVideoPreload")

    private let maxConcurrentPreloads = 2
    // SuperGram: a queued preload that never gets a slot used to emit neither `next` nor `completion`, so its
    // caller — FetchManagerImpl's video-preload entry, PrefetchManager's fetchDisposable — considered it in
    // flight forever and kept holding an active fetch slot for it. Slots are served newest-first on purpose
    // (the newest request is the one nearest the screen), which means the tail of the queue can wait a long
    // time; these two bounds make "a long time" finite.
    private static let maxWaitTimeout: Double = 30.0
    private static let maxWaiting = 8

    private struct WaitingEntry {
        let id: Int
        let enqueueTimestamp: Double
        let start: () -> Void
        let drop: () -> Void
    }

    private var activeCount = 0
    private var nextId = 0
    private var waiting: [WaitingEntry] = []
    private var isSweepScheduled = false

    func enqueue(start: @escaping () -> Void, drop: @escaping () -> Void) -> Int {
        assert(self.queue.isCurrent())

        let id = self.nextId
        self.nextId += 1

        if self.activeCount < self.maxConcurrentPreloads {
            self.activeCount += 1
            start()
            return id
        }

        self.waiting.append(WaitingEntry(id: id, enqueueTimestamp: CFAbsoluteTimeGetCurrent(), start: start, drop: drop))

        // Bound the queue. Each entry retains the postbox, the resource reference and the subscriber, and
        // chat-list prefetch can enqueue far faster than two concurrent demuxers drain.
        var dropped: [WaitingEntry] = []
        while self.waiting.count > VideoPreloadLimiter.maxWaiting {
            dropped.append(self.waiting.removeFirst())
        }
        self.scheduleSweepIfNeeded()
        for entry in dropped {
            entry.drop()
        }
        return id
    }

    func removeWaiting(id: Int) {
        assert(self.queue.isCurrent())

        self.waiting.removeAll(where: { $0.id == id })
    }

    func release() {
        assert(self.queue.isCurrent())

        self.activeCount = max(0, self.activeCount - 1)
        while self.activeCount < self.maxConcurrentPreloads, let next = self.waiting.popLast() {
            self.activeCount += 1
            next.start()
        }
    }

    private func scheduleSweepIfNeeded() {
        if self.isSweepScheduled || self.waiting.isEmpty {
            return
        }
        self.isSweepScheduled = true
        self.queue.after(VideoPreloadLimiter.maxWaitTimeout, {
            VideoPreloadLimiter.shared.sweep()
        })
    }

    // Complete anything that has been queued too long instead of leaving it pending forever.
    private func sweep() {
        assert(self.queue.isCurrent())

        self.isSweepScheduled = false

        let timestamp = CFAbsoluteTimeGetCurrent()
        var dropped: [WaitingEntry] = []
        var remaining: [WaitingEntry] = []
        for entry in self.waiting {
            if timestamp - entry.enqueueTimestamp >= VideoPreloadLimiter.maxWaitTimeout {
                dropped.append(entry)
            } else {
                remaining.append(entry)
            }
        }
        self.waiting = remaining
        self.scheduleSweepIfNeeded()
        for entry in dropped {
            entry.drop()
        }
    }
}

private final class VideoPreloadSlotState {
    var waitingId: Int?
    var hasSlot = false
    var isDisposed = false
    // Set once the enqueued request has either started or been dropped, so the waiting id is not recorded for
    // a request that is already resolved.
    var isResolved = false
}

public func preloadVideoResource(postbox: Postbox, userLocation: MediaResourceUserLocation, userContentType: MediaResourceUserContentType, resourceReference: MediaResourceReference, duration: Double) -> Signal<Never, NoError> {
    return Signal { subscriber in
        let limiter = VideoPreloadLimiter.shared
        let queue = limiter.queue
        let disposable = MetaDisposable()
        let slotState = VideoPreloadSlotState()

        let releaseSlot: () -> Void = {
            assert(queue.isCurrent())
            if slotState.hasSlot {
                slotState.hasSlot = false
                limiter.release()
            }
        }

        queue.async {
            if slotState.isDisposed {
                return
            }
            let waitingId = limiter.enqueue(start: {
                slotState.waitingId = nil
                slotState.isResolved = true
                if slotState.isDisposed {
                    limiter.release()
                    return
                }
                slotState.hasSlot = true

                let maximumFetchSize = 2 * 1024 * 1024 + 128 * 1024
                let sourceImpl = FFMpegMediaFrameSource(queue: queue, postbox: postbox, userLocation: userLocation, userContentType: userContentType, resourceReference: resourceReference, tempFilePath: nil, limitedFileRange: nil, streamable: true, isSeekable: true, video: true, preferSoftwareDecoding: false, fetchAutomatically: true, maximumFetchSize: maximumFetchSize)
                let source = QueueLocalObject(queue: queue, generate: {
                    return sourceImpl
                })
                let signal = sourceImpl.seek(timestamp: 0.0)
                |> deliverOn(queue)
                |> mapToSignal { result -> Signal<Never, MediaFrameSourceSeekError> in
                    let result = result.syncWith({ $0 })
                    if let videoBuffer = result.buffers.videoBuffer {
                        let impl = source.syncWith({ $0 })

                        return impl.ensureHasFrames(until: min(duration, videoBuffer.duration.seconds))
                        |> ignoreValues
                        |> castError(MediaFrameSourceSeekError.self)
                    } else {
                        return .complete()
                    }
                }
                disposable.set(signal.start(error: { _ in
                    queue.async {
                        releaseSlot()
                    }
                    subscriber.putCompletion()
                }, completed: {
                    queue.async {
                        releaseSlot()
                    }
                    subscriber.putCompletion()
                }))

                // A preload that cannot make progress (no network, stalled fetch) must not hold a slot forever.
                queue.after(30.0, {
                    if slotState.hasSlot && !slotState.isDisposed {
                        releaseSlot()
                        disposable.dispose()
                        subscriber.putCompletion()
                    }
                })
            }, drop: {
                // Queued too long, or pushed out of a bounded queue. Nothing was fetched, but the caller has to
                // learn that this preload is over — an un-completed signal is an active fetch-manager slot.
                slotState.waitingId = nil
                slotState.isResolved = true
                if !slotState.isDisposed {
                    subscriber.putCompletion()
                }
            })
            if !slotState.hasSlot && !slotState.isResolved {
                slotState.waitingId = waitingId
            }
        }

        return ActionDisposable {
            disposable.dispose()
            queue.async {
                slotState.isDisposed = true
                if let waitingId = slotState.waitingId {
                    slotState.waitingId = nil
                    limiter.removeWaiting(id: waitingId)
                }
                releaseSlot()
            }
        }
    }
}
