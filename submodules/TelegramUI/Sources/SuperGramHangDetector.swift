import Foundation
import Darwin
import UIKit
import UIKit.UIGestureRecognizerSubclass
import ChatMessageTextBubbleContentNode

// SuperGram: main-thread stall detector. A watchdog thread pings the main queue twice a second; when the main thread
// has not answered for `stallThreshold` seconds it suspends the main thread for a moment, walks its frame-pointer
// chain and writes the raw return addresses (image + load address) to the notification journal
// (SuperGramNotificationDiagnostics → logs/sg-notifications.txt). Symbolicate offline with
// `atos -arch arm64 -o <Framework binary> -l <load address> <addresses>`. It samples up to `maxSamplesPerStall` times
// per stall (one per second) so a stall that moves through several places is visible as well.
final class SuperGramHangDetector {
    static let shared = SuperGramHangDetector()

    private static let pingInterval: Double = 0.5
    private static let stallThreshold: Double = 2.0
    private static let maxSamplesPerStall = 5
    private static let maxFrames = 48

    private var mainThreadPort: thread_t = 0
    private let lock = NSLock()
    private var lastPong: Double = CFAbsoluteTimeGetCurrent()
    private var pingInFlight = false
    private var started = false

    private init() {
    }

    /// Must be called on the main thread.
    func start() {
        assert(Thread.isMainThread)
        if self.started {
            return
        }
        self.started = true
        self.mainThreadPort = mach_thread_self()
        let thread = Thread { [weak self] in
            self?.run()
        }
        thread.name = "SuperGramHangDetector"
        thread.qualityOfService = .utility
        thread.start()
    }

    private func run() {
        var stallStart: Double?
        var samplesTaken = 0
        var lastSampleTime: Double = 0.0
        while true {
            Thread.sleep(forTimeInterval: SuperGramHangDetector.pingInterval)
            let now = CFAbsoluteTimeGetCurrent()

            self.lock.lock()
            let shouldPing = !self.pingInFlight
            if shouldPing {
                self.pingInFlight = true
            }
            let lastPong = self.lastPong
            self.lock.unlock()

            if shouldPing {
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }
                    self.lock.lock()
                    self.pingInFlight = false
                    self.lastPong = CFAbsoluteTimeGetCurrent()
                    self.lock.unlock()
                }
            }

            let stalledFor = now - lastPong
            if stalledFor >= SuperGramHangDetector.stallThreshold {
                if stallStart == nil {
                    stallStart = lastPong
                    samplesTaken = 0
                    lastSampleTime = 0.0
                }
                if samplesTaken < SuperGramHangDetector.maxSamplesPerStall && now - lastSampleTime >= 1.0 {
                    samplesTaken += 1
                    lastSampleTime = now
                    self.sampleMainThread(label: "main thread stalled \(String(format: "%.1f", stalledFor))s (sample \(samplesTaken))")
                }
            } else if let start = stallStart {
                SuperGramNotificationDiagnostics.shared.log("hang: main thread recovered after \(String(format: "%.1f", lastPong - start))s")
                stallStart = nil
            }
        }
    }

    private func sampleMainThread(label: String) {
        #if arch(arm64)
        var addresses: [UInt] = []
        let thread = self.mainThreadPort
        guard thread_suspend(thread) == KERN_SUCCESS else {
            return
        }
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &state) { pointer -> kern_return_t in
            return pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { statePointer in
                return thread_get_state(thread, thread_state_flavor_t(ARM_THREAD_STATE64), statePointer, &count)
            }
        }
        if result == KERN_SUCCESS {
            let pointerMask: UInt = 0x0000_000F_FFFF_FFFF
            addresses.append(UInt(state.__pc) & pointerMask)
            addresses.append(UInt(state.__lr) & pointerMask)
            var framePointer = UInt(state.__fp)
            // No allocation and no locks while the main thread is suspended: the frame records are read with
            // vm_read_overwrite, which fails instead of crashing on a bad pointer.
            var frame: (UInt, UInt) = (0, 0)
            for _ in 0 ..< SuperGramHangDetector.maxFrames {
                if framePointer == 0 || framePointer & 0x7 != 0 {
                    break
                }
                var outSize: vm_size_t = 0
                let readResult = withUnsafeMutablePointer(to: &frame) { framePointerBuffer -> kern_return_t in
                    return vm_read_overwrite(mach_task_self_, vm_address_t(framePointer), vm_size_t(MemoryLayout<(UInt, UInt)>.size), vm_address_t(UInt(bitPattern: framePointerBuffer)), &outSize)
                }
                if readResult != KERN_SUCCESS {
                    break
                }
                let returnAddress = frame.1 & pointerMask
                if returnAddress == 0 {
                    break
                }
                addresses.append(returnAddress)
                if frame.0 <= framePointer {
                    break
                }
                framePointer = frame.0
            }
        }
        thread_resume(thread)

        // Symbol lookup only after the main thread runs again (dladdr takes the dyld lock).
        var lines: [String] = ["hang: \(label) footprint=\(superGramMemoryFootprintMB())MB"]
        for (index, address) in addresses.enumerated() {
            var info = Dl_info()
            if dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0, let fileName = info.dli_fname {
                let image = (String(cString: fileName) as NSString).lastPathComponent
                let base = UInt(bitPattern: info.dli_fbase)
                var symbol = ""
                if let name = info.dli_sname {
                    symbol = " " + String(cString: name)
                    if symbol.count > 160 {
                        symbol = String(symbol.prefix(160)) + "…"
                    }
                }
                lines.append("hang:   #\(index) \(image) 0x\(String(base, radix: 16)) 0x\(String(address, radix: 16)) +0x\(String(address - base, radix: 16))\(symbol)")
            } else {
                lines.append("hang:   #\(index) ? 0x\(String(address, radix: 16))")
            }
        }
        for line in lines {
            SuperGramNotificationDiagnostics.shared.log(line)
        }
        #endif
    }
}

// SuperGram: layer census. Returning from the background re-commits the whole layer tree to the render server on
// the main thread (CA::Context::commit_transaction → _copyRenderLayer for every layer), so the stall grows with the
// number of live layers. This logs the total and the classes that own most of them (by the layer's delegate view /
// node class, else the layer class) so a layer leak can be pinned down from the device journal.
enum SuperGramLayerCensus {
    static func log(reason: String) {
        assert(Thread.isMainThread)
        let start = CFAbsoluteTimeGetCurrent()
        var counts: [String: Int] = [:]
        var hiddenCounts: [String: Int] = [:]
        var total = 0
        var hiddenTotal = 0
        var maxDepth = 0
        var windowSummaries: [String] = []

        func visit(_ layer: CALayer, depth: Int, insideHidden: Bool) {
            total += 1
            maxDepth = max(maxDepth, depth)
            let owner: String
            if let delegate = layer.delegate {
                owner = String(describing: type(of: delegate))
            } else {
                owner = String(describing: type(of: layer))
            }
            let hidden = insideHidden || layer.isHidden || layer.opacity == 0.0
            if hidden {
                hiddenTotal += 1
                hiddenCounts[owner, default: 0] += 1
            }
            counts[owner, default: 0] += 1
            if let sublayers = layer.sublayers {
                for sublayer in sublayers {
                    visit(sublayer, depth: depth + 1, insideHidden: hidden)
                }
            }
        }

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else {
                continue
            }
            for window in windowScene.windows {
                let before = total
                visit(window.layer, depth: 0, insideHidden: false)
                windowSummaries.append("\(String(describing: type(of: window)))=\(total - before)")
            }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        SuperGramNotificationDiagnostics.shared.log("layers(\(reason)): footprint=\(superGramMemoryFootprintMB())MB total=\(total) hidden=\(hiddenTotal) maxDepth=\(maxDepth) windows=[\(windowSummaries.joined(separator: ", "))] census=\(Int(elapsed * 1000.0))ms")
        for (owner, count) in counts.sorted(by: { $0.value > $1.value }).prefix(25) {
            SuperGramNotificationDiagnostics.shared.log("layers:   \(count) \(owner) (hidden \(hiddenCounts[owner] ?? 0))")
        }
    }
}

/// Physical memory footprint of the process in MB (what jetsam and the memory compressor account for).
func superGramMemoryFootprintMB() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
        return pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { infoPointer in
            return task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), infoPointer, &count)
        }
    }
    if result != KERN_SUCCESS {
        return -1
    }
    return Int(info.phys_footprint / (1024 * 1024))
}

// SuperGram: passive touch journal for "the screen stopped reacting" reports where the main thread is still alive
// (no hang sample). Every touch-down logs which view the window hit-tests and that view's ancestor chain, so a stuck
// transition or an invisible overlay that swallows touches shows up by name. It fails immediately and never cancels
// or delays touches, so it cannot change gesture handling.
final class SuperGramTouchJournalRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var lastLogTimestamp: Double = 0.0

    init() {
        super.init(target: nil, action: nil)
        self.cancelsTouchesInView = false
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
        self.delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        defer {
            self.state = .failed
        }
        guard let touch = touches.first, let view = self.view else {
            return
        }
        let rootView: UIView = view.window ?? view
        let point = touch.location(in: rootView)
        let hitView = rootView.hitTest(point, with: event)
        // SuperGram: a touch outside an inline (double tap) text selection clears it
        ChatMessageTextBubbleContentNode.superGramHandleTouchDown(hitView: hitView)

        let timestamp = CFAbsoluteTimeGetCurrent()
        if timestamp - self.lastLogTimestamp < 0.15 {
            return
        }
        self.lastLogTimestamp = timestamp
        guard let hitView else {
            SuperGramNotificationDiagnostics.shared.log("touch (\(Int(point.x)),\(Int(point.y))) hit=nil")
            return
        }
        var chain: [String] = []
        var current: UIView? = hitView
        while let item = current, chain.count < 14 {
            var name = String(describing: type(of: item))
            if !item.isUserInteractionEnabled {
                name += "[noUI]"
            }
            if item.alpha < 0.01 || item.isHidden {
                name += "[invisible]"
            }
            chain.append(name)
            current = item.superview
        }
        SuperGramNotificationDiagnostics.shared.log("touch (\(Int(point.x)),\(Int(point.y))) taps=\(touches.count) " + chain.joined(separator: " < "))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
