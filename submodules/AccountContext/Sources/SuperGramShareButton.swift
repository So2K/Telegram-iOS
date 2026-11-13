import Foundation

// SuperGram: the per-message share / repost button is hidden by default — it sits under the thumb and is
// easy to hit by accident. Key "sgShowShareButton" (Settings → SuperGram → Chat) brings it back.
// The value is cached because it is read during message layout.
private final class SuperGramShareButtonSetting {
    static let shared = SuperGramShareButtonSetting()

    private let lock = NSLock()
    private var cachedValue: Bool?
    private var generation: UInt64 = 0
    private var cachedGeneration: UInt64 = 0
    private var observer: NSObjectProtocol?

    private init() {
        self.cachedValue = SuperGramShareButtonSetting.readValue()
        self.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            guard let self else {
                return
            }
            // UserDefaults.didChangeNotification is posted synchronously on the writing thread for every `set`, and
            // a dozen SuperGram singletons listen to it. Doing the actual read here made every settings write fan
            // out into a dozen UserDefaults reads on that thread; invalidate instead and re-read on the next
            // access, which is the same shape as sgAllowScreenCaptureProtected() in UIKitUtils.m. The generation
            // counter makes sure a value read before a change can never be stored after it.
            self.lock.lock()
            self.generation &+= 1
            self.cachedValue = nil
            self.lock.unlock()
        })
    }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private static func readValue() -> Bool {
        return UserDefaults.standard.object(forKey: "sgShowShareButton") as? Bool ?? false
    }

    var isEnabled: Bool {
        self.lock.lock()
        if let cachedValue = self.cachedValue, self.cachedGeneration == self.generation {
            self.lock.unlock()
            return cachedValue
        }
        let generation = self.generation
        self.lock.unlock()

        let value = SuperGramShareButtonSetting.readValue()

        self.lock.lock()
        if self.generation == generation {
            self.cachedValue = value
            self.cachedGeneration = generation
        }
        self.lock.unlock()
        return value
    }
}

/// Whether the share / repost button next to a message bubble may be shown at all.
public var superGramShowsMessageShareButton: Bool {
    return SuperGramShareButtonSetting.shared.isEnabled
}
