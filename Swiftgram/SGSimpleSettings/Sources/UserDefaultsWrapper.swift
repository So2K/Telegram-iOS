import Foundation

public protocol AllowedUserDefaultTypes {}

/* // This one is more painful than helpful
extension Bool: AllowedUserDefaultTypes {}
extension String: AllowedUserDefaultTypes {}
extension Int: AllowedUserDefaultTypes {}
extension Int32: AllowedUserDefaultTypes {}
extension Double: AllowedUserDefaultTypes {}
extension Float: AllowedUserDefaultTypes {}
extension Data: AllowedUserDefaultTypes {}
extension URL: AllowedUserDefaultTypes {}
//extension Dictionary<String, Any>: AllowedUserDefaultTypes {}
extension Array: AllowedUserDefaultTypes where Element: AllowedUserDefaultTypes {}
*/

// SuperGram: one process-wide counter bumped on every `UserDefaults.didChangeNotification`, so a cached
// `UserDefault` value can tell whether anything has been written since it was read.
//
// Some SGSimpleSettings keys are also written without going through SGSimpleSettings (for example
// `sgFileLogging`, which DebugSettingsUI writes straight into `UserDefaults.standard`), and app-group keys
// can be written by a different screen. Without this, the first read of a key cached its value for the whole
// process lifetime and the SuperGram settings screen kept showing the stale one.
//
// A single shared observer (not one per property) keeps the cost of a cache hit at one uncontended lock:
// the generation only moves when something is actually written, which outside the settings screens is rare.
private final class UserDefaultChangeTracker {
    static let shared = UserDefaultChangeTracker()

    private let lock = NSLock()
    private var generationValue: Int = 0
    private var observer: NSObjectProtocol?

    private init() {
        // The handler must not read any setting: `UserDefaults` posts this notification synchronously from
        // `set` / `register(defaults:)`, and a read would re-enter `SGSimpleSettings.shared` while it is
        // still being initialized. Bumping a counter is all that happens here.
        self.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.lock.lock()
            self.generationValue &+= 1
            self.lock.unlock()
        })
    }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var generation: Int {
        self.lock.lock()
        let result = self.generationValue
        self.lock.unlock()
        return result
    }
}

// Does not support Optional types due to caching
// SuperGram: hardened. The cached value is guarded by a lock (settings are read from arbitrary
// queues), and reads never force-cast a missing value: when the key is absent the explicit
// `defaultValue` is used, otherwise String/Array/Data fall back to an empty value and numbers are clamped.
// The cache is also dropped whenever anything writes to UserDefaults (see UserDefaultChangeTracker), so a
// value written outside SGSimpleSettings is picked up instead of being shadowed forever.
@propertyWrapper
public class UserDefault<T> /*where T: AllowedUserDefaultTypes*/ {
    public let key: String
    public let userDefaults: UserDefaults
    private let defaultValue: T?
    private var cachedValue: T?
    private var cachedGeneration: Int = -1
    private let lock = NSLock()

    public init(key: String, userDefaults: UserDefaults = .standard, defaultValue: T? = nil) {
        self.key = key
        self.userDefaults = userDefaults
        self.defaultValue = defaultValue
    }

    public var wrappedValue: T {
        get {
            let generation = UserDefaultChangeTracker.shared.generation

            self.lock.lock()
            if let strongCachedValue = self.cachedValue, self.cachedGeneration == generation {
                self.lock.unlock()
                return strongCachedValue
            }
            self.lock.unlock()

            // Read outside of the lock: UserDefaults may post notifications whose observers read settings.
            let value = self.readFromUserDefaults()

            self.lock.lock()
            self.cachedValue = value
            self.cachedGeneration = generation
            self.lock.unlock()

            return value
        }
        set {
            let generation = UserDefaultChangeTracker.shared.generation
            self.lock.lock()
            self.cachedValue = newValue
            self.cachedGeneration = generation
            self.lock.unlock()
            // Must be called outside of the lock: UserDefaults posts didChangeNotification synchronously
            // and observers may read this very setting. The notification also bumps the generation, so the
            // next read goes back to UserDefaults — which by then holds exactly the value written here.
            self.userDefaults.set(newValue, forKey: self.key)
        }
    }

    /// Drops the cached value so the next read goes to UserDefaults again.
    public func invalidateCache() {
        self.lock.lock()
        self.cachedValue = nil
        self.cachedGeneration = -1
        self.lock.unlock()
    }

    fileprivate func readFromUserDefaults() -> T {
        let key = self.key
        let userDefaults = self.userDefaults
        if userDefaults.object(forKey: key) == nil {
            if let defaultValue = self.defaultValue {
                return defaultValue
            }
            // Registered defaults may not be in place yet (see SGSimpleSettings.init), use the static default tables.
            return UserDefault.fallbackValue(SGSimpleSettings.defaultValues[key] ?? SGSimpleSettings.groupDefaultValues[key])
        }
        switch T.self {
        case is Bool.Type:
            return (userDefaults.bool(forKey: key) as! T)
        case is String.Type:
            return ((userDefaults.string(forKey: key) ?? "") as! T)
        case is Int64.Type:
            return (Int64(userDefaults.integer(forKey: key)) as! T)
        case is Int32.Type:
            return (Int32(clamping: userDefaults.integer(forKey: key)) as! T)
        case is Int.Type:
            return (userDefaults.integer(forKey: key) as! T)
        case is Double.Type:
            return (userDefaults.double(forKey: key) as! T)
        case is Float.Type:
            return (userDefaults.float(forKey: key) as! T)
        case is Data.Type:
            return ((userDefaults.data(forKey: key) ?? Data()) as! T)
        case is Array<String>.Type:
            return ((userDefaults.stringArray(forKey: key) ?? []) as! T)
        case is Array<Any>.Type:
            return ((userDefaults.array(forKey: key) ?? []) as! T)
        default:
            if let value = userDefaults.object(forKey: key) as? T {
                return value
            }
            if let defaultValue = self.defaultValue {
                return defaultValue
            }
            fatalError("Unsupported UserDefault type \(T.self)")
        }
    }

    private static func fallbackValue(_ value: Any?) -> T {
        switch T.self {
        case is Bool.Type:
            return (((value as? NSNumber)?.boolValue ?? false) as! T)
        case is String.Type:
            return (((value as? String) ?? "") as! T)
        case is Int64.Type:
            return (((value as? NSNumber)?.int64Value ?? 0) as! T)
        case is Int32.Type:
            return (((value as? NSNumber)?.int32Value ?? 0) as! T)
        case is Int.Type:
            return (((value as? NSNumber)?.intValue ?? 0) as! T)
        case is Double.Type:
            return (((value as? NSNumber)?.doubleValue ?? 0.0) as! T)
        case is Float.Type:
            return (((value as? NSNumber)?.floatValue ?? 0.0) as! T)
        case is Data.Type:
            return (((value as? Data) ?? Data()) as! T)
        case is Array<String>.Type:
            return (((value as? [String]) ?? []) as! T)
        case is Array<Any>.Type:
            return (((value as? [Any]) ?? []) as! T)
        default:
            if let value = value as? T {
                return value
            }
            fatalError("Unsupported UserDefault type \(T.self)")
        }
    }
}

//public class AtomicUserDefault<T>: UserDefault<T> {
//    private let atomicCachedValue: AtomicWrapper<T?> = AtomicWrapper(value: nil)
//    
//    public override var wrappedValue: T {
//        get {
//            return atomicCachedValue.modify({ value in
//                if let strongValue = value {
//                    return strongValue
//                }
//                return self.readFromUserDefaults()
//            })!
//        }
//        set {
//            let _ = atomicCachedValue.modify({ _ in
//                userDefaults.set(newValue, forKey: key)
//                return newValue
//            })
//        }
//    }
//}



//  Based on ConcurrentDictionary.swift from https://github.com/peterprokop/SwiftConcurrentCollections

/// Thread-safe UserDefaults dictionary wrapper
/// - Important: Note that this is a `class`, i.e. reference (not value) type
/// - Important: Key can only be String type
public class UserDefaultsBackedDictionary<Key: Hashable, Value> {
    public let userDefaultsKey: String
    public let userDefaults: UserDefaults
        
    private var container: [Key: Value]? = nil
    private let rwlock = RWLock()
    private let threadSafe: Bool

    public var keys: [Key] {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "KEYS")
        #endif
        let result: [Key]
        if threadSafe {
            // SuperGram: exclusive lock, the read may populate `container`
            rwlock.writeLock()
        }
        if container == nil {
            container = userDefaultsContainer
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "EXTRACTED: \(container!)")
            #endif
        } else {
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "FROM CACHE: \(container!)")
            #endif
        }
        result = Array(container!.keys)
        if threadSafe {
            rwlock.unlock()
        }
        return result
    }

    public var values: [Value] {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "VALUES")
        #endif
        let result: [Value]
        if threadSafe {
            // SuperGram: exclusive lock, the read may populate `container`
            rwlock.writeLock()
        }
        if container == nil {
            container = userDefaultsContainer
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "EXTRACTED: \(container!)")
            #endif
        } else {
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "FROM CACHE: \(container!)")
            #endif
        }
        result = Array(container!.values)
        if threadSafe {
            rwlock.unlock()
        }
        return result
    }
    
    public init(userDefaultsKey: String, userDefaults: UserDefaults = .standard, threadSafe: Bool) {
        self.userDefaultsKey = userDefaultsKey
        self.userDefaults = userDefaults
        self.threadSafe = threadSafe
    }

    /// Sets the value for key
    ///
    /// - Parameters:
    ///   - value: The value to set for key
    ///   - key: The key to set value for
    public func set(value: Value, forKey key: Key) {
        if threadSafe {
            rwlock.writeLock()
        }
        _set(value: value, forKey: key)
        if threadSafe {
            rwlock.unlock()
        }
    }

    @discardableResult
    public func remove(_ key: Key) -> Value? {
        let result: Value?
        if threadSafe {
            rwlock.writeLock()
        }
        result = _remove(key)
        if threadSafe {
            rwlock.unlock()
        }
        return result
    }
    
    @discardableResult
    public func removeValue(forKey: Key) -> Value? {
        return self.remove(forKey)
    }

    public func contains(_ key: Key) -> Bool {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "CONTAINS")
        #endif
        let result: Bool
        if threadSafe {
            // SuperGram: exclusive lock, the read may populate `container`
            rwlock.writeLock()
        }
        if container == nil {
            container = userDefaultsContainer
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "EXTRACTED: \(container!)")
            #endif
        } else {
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "FROM CACHE: \(container!)")
            #endif
        }
        result = container!.index(forKey: key) != nil
        if threadSafe {
            rwlock.unlock()
        }
        return result
    }

    public func value(forKey key: Key) -> Value? {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "VALUE")
        #endif
        let result: Value?
        if threadSafe {
            // SuperGram: exclusive lock, the read may populate `container`
            rwlock.writeLock()
        }
        if container == nil {
            container = userDefaultsContainer
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "EXTRACTED: \(container!)")
            #endif
        } else {
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "FROM CACHE: \(container!)")
            #endif
        }
        result = container![key]
        if threadSafe {
            rwlock.unlock()
        }
        return result
    }

    public func mutateValue(forKey key: Key, mutation: (Value) -> Value) {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "MUTATE")
        #endif
        if threadSafe {
            rwlock.writeLock()
        }
        if container == nil {
            container = userDefaultsContainer
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "EXTRACTED: \(container!)")
            #endif
        } else {
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "FROM CACHE: \(container!)")
            #endif
        }
        if let value = container![key] {
            container![key] = mutation(value)
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "UPDATING CACHE \(key): \(value), \(container!)")
            #endif
            userDefaultsContainer = container!
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "CACHE UPDATED \(key): \(value), \(container!)")
            #endif
        }
        if threadSafe {
            rwlock.unlock()
        }
    }
    
    public var isEmpty: Bool {
        return self.keys.isEmpty
    }

    // MARK: Subscript
    public subscript(key: Key) -> Value? {
        get {
            return value(forKey: key)
        }
        set {
            if threadSafe {
                rwlock.writeLock()
            }
            defer {
                if threadSafe {
                    rwlock.unlock()
                }
            }
            guard let newValue = newValue else {
                _remove(key)
                return
            }
            _set(value: newValue, forKey: key)
        }
    }

    // MARK: Private
    @inline(__always)
    private func _set(value: Value, forKey key: Key) {
        if container == nil {
            container = userDefaultsContainer
        }
        self.container![key] = value
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "UPDATING CACHE \(key): \(value), \(container!)")
        #endif
        userDefaultsContainer = container!
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "CACHE UPDATED \(key): \(value), \(container!)")
        #endif
    }

    @inline(__always)
    @discardableResult
    private func _remove(_ key: Key) -> Value? {
        if container == nil {
            container = userDefaultsContainer
        }
        guard let index = container!.index(forKey: key) else { return nil }

        let tuple = container!.remove(at: index)
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "UPDATING CACHE REMOVE \(key) \(container!)")
        #endif
        userDefaultsContainer = container!
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "CACHE UPDATED REMOVED \(key) \(container!)")
        #endif
        return tuple.value
    }
    
    private var userDefaultsContainer: [Key: Value] {
        get {
            // SuperGram: never crash on a missing or malformed stored dictionary
            return (userDefaults.dictionary(forKey: userDefaultsKey) as? [Key: Value]) ?? [:]
        }
        set {
            userDefaults.set(newValue, forKey: userDefaultsKey)
        }
    }
    
    public func drop() {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "DROPPING")
        #endif
        if threadSafe {
            rwlock.writeLock()
        }
        userDefaults.removeObject(forKey: userDefaultsKey)
        container = userDefaultsContainer
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "DROPPED: \(container!)")
        #endif
        if threadSafe {
            rwlock.unlock()
        }
    }

}


#if DEBUG
private let queue = DispatchQueue(label: "app.swiftgram.ios.trace", qos: .utility)

public func SGtrace(_ domain: String, what: @autoclosure() -> String) {
    let string = what()
    var rawTime = time_t()
    time(&rawTime)
    var timeinfo = tm()
    localtime_r(&rawTime, &timeinfo)
    
    var curTime = timeval()
    gettimeofday(&curTime, nil)
    let seconds = Int(curTime.tv_sec % 60)  // Extracting the current second
    let microseconds = curTime.tv_usec  // Full microsecond precision

    queue.async {
        let result = String(format: "[%@] %d-%d-%d %02d:%02d:%02d.%06d %@", arguments: [domain, Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), seconds, microseconds, string])
        
        print(result)
    }
}
#endif
