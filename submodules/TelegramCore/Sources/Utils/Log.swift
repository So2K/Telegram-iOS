import Foundation
import SwiftSignalKit
import Postbox
import TelegramApi
import NetworkLogging
import ManagedFile

private let queue = DispatchQueue(label: "org.telegram.Telegram.trace", qos: .utility)

public func trace2(_ what: @autoclosure() -> String) {
    let string = what()
    var rawTime = time_t()
    time(&rawTime)
    var timeinfo = tm()
    localtime_r(&rawTime, &timeinfo)
    
    var curTime = timeval()
    gettimeofday(&curTime, nil)
    let milliseconds = curTime.tv_usec / 1000
    
    //queue.async {
        let result = String(format: "%d-%d-%d %02d:%02d:%03d %@", arguments: [Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), Int(milliseconds), string])
        print(result)
    //}
}

public func trace1(_ domain: String, what: @autoclosure() -> String) {
    let string = what()
    var rawTime = time_t()
    time(&rawTime)
    var timeinfo = tm()
    localtime_r(&rawTime, &timeinfo)
    
    var curTime = timeval()
    gettimeofday(&curTime, nil)
    let seconds = curTime.tv_sec
    let milliseconds = curTime.tv_usec / 1000
    
    queue.async {
        let result = String(format: "[%@] %d-%d-%d %02d:%02d:%02d.%03d %@", arguments: [domain, Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), Int(seconds), Int(milliseconds), string])
        
        print(result)
    }
}

public func registerLoggingFunctions() {
    setBridgingTraceFunction({ domain, what in
        if let what = what {
            if let domain = domain {
                Logger.shared.log(domain, what as String)
            } else {
                Logger.shared.log("", what as String)
            }
        }
    })
    setBridgingShortTraceFunction({ domain, what in
        if let what = what {
            if let domain = domain {
                Logger.shared.shortLog(domain, what as String)
            } else {
                Logger.shared.shortLog("", what as String)
            }
        }
    })
    setTelegramApiLogger({ what in
        Logger.shared.log("Api", what as String)
        Logger.shared.shortLog("Api", what as String)
    })
}

private var sharedLogger: Logger?

private let binaryEventMarker: UInt64 = 0xcadebabef00dcafe

public final class Logger {
    private static let fallback = Logger(rootPath: "", basePath: "", logToFile: false, logToConsole: false)

    private let queue = Queue(name: "org.telegram.Telegram.log", qos: .utility)
    private let maxLength: Int = 2 * 1024 * 1024
    private let maxShortLength: Int = 1 * 1024 * 1024
    private let maxFiles: Int = 20
    
    private let rootPath: String
    private let basePath: String
    private var file: (ManagedFile, Int)?
    private var shortFile: (ManagedFile, Int)?
    
    public var logToFile: Bool = true {
        didSet {
            if oldValue != self.logToFile {
                self.updateNetworkLoggingEnabled()
            }
        }
    }
    public var logToConsole: Bool = true {
        didSet {
            if oldValue != self.logToConsole {
                self.updateNetworkLoggingEnabled()
            }
        }
    }
    // SuperGram: full MTProto payload dumps (and the per-message MTProto critlog records) are expensive,
    // so file logging alone does not enable them; they are written to the log file only when network
    // logging ("sgNetworkLogging") is enabled as well, or while console logging is on.
    public var logNetwork: Bool = false {
        didSet {
            if oldValue != self.logNetwork {
                self.updateNetworkLoggingEnabled()
            }
        }
    }
    public var redactSensitiveData: Bool = true

    public var isNetworkLoggingEnabled: Bool {
        return self.logToConsole || (self.logToFile && self.logNetwork)
    }

    private func updateNetworkLoggingEnabled() {
        // SuperGram: only the shared logger owns the process-wide MTProto logging switch; temporary loggers
        // (fallback, log export) must not toggle it.
        if sharedLogger === self {
            NetworkSetLoggingEnabled(self.isNetworkLoggingEnabled)
        }
    }

    public static func setSharedLogger(_ logger: Logger) {
        sharedLogger = logger
        NetworkSetLoggingEnabled(logger.isNetworkLoggingEnabled)
        setPostboxLogger({ s in
            Logger.shared.log("Postbox", s)
            Logger.shared.shortLog("Postbox", s)
        }, sync: {
            Logger.shared.sync()
        })
    }
    
    public static var shared: Logger {
        return sharedLogger ?? self.fallback
    }
    
    // SuperGram: the defaults used to be `logToFile: true, logToConsole: true`, so every caller that did not pass
    // them explicitly — the Share, Siri, WidgetKit and NotificationContent extensions — logged unconditionally into
    // the shared app-group logs directory AND (because `setSharedLogger` derives the MTProto switch from
    // logToConsole) turned on full MTProto payload dumps inside those processes. None of them ever consulted the
    // "sgFileLogging" switch, so they kept writing even in a build where the user had logging off. Logging is now
    // opt-in: the app passes the effective switches in AppDelegate, everything else stays silent.
    public init(rootPath: String, basePath: String, logToFile: Bool = false, logToConsole: Bool = false) {
        self.rootPath = rootPath
        self.basePath = basePath
        self.logToFile = logToFile
        self.logToConsole = logToConsole
    }
    
    public func sync() {
        self.queue.sync {
            if let (currentFile, _) = self.file {
                let _ = currentFile.sync()
            }
        }
    }
    
    public func collectLogs(prefix: String? = nil) -> Signal<[(String, String)], NoError> {
        return Signal { subscriber in
            self.queue.async {
                let logsPath: String
                if let prefix = prefix {
                    logsPath = self.rootPath + prefix
                } else {
                    logsPath = self.basePath
                }
                
                var result: [(Date, String, String)] = []
                if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: logsPath), includingPropertiesForKeys: [URLResourceKey.creationDateKey], options: []) {
                    for url in files {
                        if url.lastPathComponent.hasPrefix("log-") {
                            if let creationDate = (try? url.resourceValues(forKeys: Set([.creationDateKey])))?.creationDate {
                                result.append((creationDate, url.lastPathComponent, url.path))
                            }
                        }
                    }
                }
                result.sort(by: { $0.0 < $1.0 })
                subscriber.putNext(result.map { ($0.1, $0.2) })
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        }
    }
    
    public func collectLogs(basePath: String) -> Signal<[(String, String)], NoError> {
        return Signal { subscriber in
            self.queue.async {
                let logsPath: String = basePath
                
                var result: [(Date, String, String)] = []
                if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: logsPath), includingPropertiesForKeys: [URLResourceKey.creationDateKey], options: []) {
                    for url in files {
                        if url.lastPathComponent.hasPrefix("log-") {
                            if let creationDate = (try? url.resourceValues(forKeys: Set([.creationDateKey])))?.creationDate {
                                result.append((creationDate, url.lastPathComponent, url.path))
                            }
                        }
                    }
                }
                result.sort(by: { $0.0 < $1.0 })
                subscriber.putNext(result.map { ($0.1, $0.2) })
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        }
    }
    
    public func collectShortLogFiles() -> Signal<[(String, String)], NoError> {
        return Signal { subscriber in
            self.queue.async {
                var result: [(Date, String, String)] = []
                if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: self.basePath), includingPropertiesForKeys: [URLResourceKey.creationDateKey], options: []) {
                    for url in files {
                        if url.lastPathComponent.hasPrefix("critlog-") {
                            if let creationDate = (try? url.resourceValues(forKeys: Set([.creationDateKey])))?.creationDate {
                                result.append((creationDate, url.lastPathComponent, url.path))
                            }
                        }
                    }
                }
                result.sort(by: { $0.0 < $1.0 })
                subscriber.putNext(result.map { ($0.1, $0.2) })
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        }
    }
    
    public func collectShortLog() -> Signal<[(Double, String)], NoError> {
        return Signal { subscriber in
            self.queue.async {
                var result: [(Date, String, String)] = []
                if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: self.basePath), includingPropertiesForKeys: [URLResourceKey.creationDateKey], options: []) {
                    for url in files {
                        if url.lastPathComponent.hasPrefix("critlog-") {
                            if let creationDate = (try? url.resourceValues(forKeys: Set([.creationDateKey])))?.creationDate {
                                result.append((creationDate, url.lastPathComponent, url.path))
                            }
                        }
                    }
                }
                result.sort(by: { $0.0 < $1.0 })
                
                var events: [(Double, String)] = []
                for (_, _, filePath) in result.reversed() {
                    var fileEvents: [(Double, String)] = []
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath), options: .mappedRead) {
                        let dataLength = data.count
                        data.withUnsafeBytes { rawBytes -> Void in
                            // SuperGram: an empty file has no base address; the previous force unwrap trapped.
                            guard let baseAddress = rawBytes.baseAddress else {
                                return
                            }
                            let bytes = baseAddress.assumingMemoryBound(to: Int8.self)

                            var offset = 0
                            while offset < dataLength {
                                let remainingLength = dataLength - offset
                                if remainingLength < 8 + 4 + 8 {
                                    break
                                }
                                var maybeMarker: UInt64 = 0
                                memcpy(&maybeMarker, bytes.advanced(by: offset), 8)
                                if maybeMarker == binaryEventMarker {
                                    var length: Int32 = 0
                                    memcpy(&length, bytes.advanced(by: offset + 8), 4)
                                    if length < 0 || length > dataLength - offset {
                                        offset += 1
                                    } else {
                                        var timestamp: Double = 0.0
                                        memcpy(&timestamp, bytes.advanced(by: offset + 8 + 4), 8)
                                        let eventStringData = Data(bytes: bytes.advanced(by: offset + 8 + 4 + 8), count: Int(length - 8))
                                        if let string = String(data: eventStringData, encoding: .utf8) {
                                            fileEvents.append((timestamp, string))
                                        }
                                        offset += 8 + 4 + Int(length)
                                    }
                                } else {
                                    offset += 1
                                }
                            }
                        }
                        
                        events.append(contentsOf: fileEvents.reversed())
                        if events.count > 1000 {
                            break
                        }
                    }
                }
                if events.count > 1000 {
                    events.removeLast(events.count - 1000)
                }
                subscriber.putNext(events)
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        }
    }
    
    public func log(_ tag: String, _ what: @autoclosure () -> String) {
        if !self.logToFile && !self.logToConsole {
            return
        }
        
        let string = what()
        
        var rawTime = time_t()
        time(&rawTime)
        var timeinfo = tm()
        localtime_r(&rawTime, &timeinfo)
        
        var curTime = timeval()
        gettimeofday(&curTime, nil)
        let milliseconds = curTime.tv_usec / 1000
        
        var consoleContent: String?
        if self.logToConsole {
            let content = String(format: "[%@] %d-%d-%d %02d:%02d:%02d.%03d %@", arguments: [tag, Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), Int(timeinfo.tm_sec), Int(milliseconds), string])
            consoleContent = content
            print(content)
        }
        
        if self.logToFile {
            self.queue.async {
                let content: String
                if let consoleContent = consoleContent {
                    content = consoleContent
                } else {
                    content = String(format: "[%@] %d-%d-%d %02d:%02d:%02d.%03d %@", arguments: [tag, Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), Int(timeinfo.tm_sec), Int(milliseconds), string])
                }
                
                var currentFile: ManagedFile?
                var openNew = false
                if let (file, length) = self.file {
                    if length >= self.maxLength {
                        self.file = nil
                        openNew = true
                    } else {
                        currentFile = file
                    }
                } else {
                    openNew = true
                }
                if openNew {
                    let _ = try? FileManager.default.createDirectory(atPath: self.basePath, withIntermediateDirectories: true, attributes: nil)
                    
                    var createNew = false
                    if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: self.basePath), includingPropertiesForKeys: [URLResourceKey.creationDateKey], options: []) {
                        var minCreationDate: (Date, URL)?
                        var maxCreationDate: (Date, URL)?
                        var count = 0
                        for url in files {
                            if url.lastPathComponent.hasPrefix("log-") {
                                if let values = try? url.resourceValues(forKeys: Set([URLResourceKey.creationDateKey])), let creationDate = values.creationDate {
                                    count += 1
                                    if minCreationDate == nil || minCreationDate!.0 > creationDate {
                                        minCreationDate = (creationDate, url)
                                    }
                                    if maxCreationDate == nil || maxCreationDate!.0 < creationDate {
                                        maxCreationDate = (creationDate, url)
                                    }
                                }
                            }
                        }
                        if let (_, url) = minCreationDate, count >= self.maxFiles {
                            let _ = try? FileManager.default.removeItem(at: url)
                        }
                        if let (_, url) = maxCreationDate {
                            var value = stat()
                            if stat(url.path, &value) == 0 && Int(value.st_size) < self.maxLength {
                                if let file = ManagedFile(queue: self.queue, path: url.path, mode: .append) {
                                    self.file = (file, Int(value.st_size))
                                    currentFile = file
                                }
                            } else {
                                createNew = true
                            }
                        } else {
                            createNew = true
                        }
                    }
                    
                    if createNew {
                        let fileName = String(format: "log-%d-%d-%d_%02d-%02d-%02d.%03d.txt", arguments: [Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), Int(timeinfo.tm_sec), Int(milliseconds)])
                        
                        let path = self.basePath + "/" + fileName
                        
                        if let file = ManagedFile(queue: self.queue, path: path, mode: .append) {
                            self.file = (file, 0)
                            currentFile = file
                        }
                    }
                }
                
                if let currentFile = currentFile {
                    if let data = content.data(using: .utf8) {
                        data.withUnsafeBytes { rawBytes -> Void in
                            // SuperGram: empty content has no base address; the previous force unwrap trapped.
                            guard let baseAddress = rawBytes.baseAddress else {
                                return
                            }
                            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

                            let _ = currentFile.write(bytes, count: data.count)
                        }
                        var newline: UInt8 = 0x0a
                        let _ = currentFile.write(&newline, count: 1)
                        if let file = self.file {
                            self.file = (file.0, file.1 + data.count + 1)
                        } else {
                            assertionFailure()
                        }
                    }
                }
            }
        }
    }
    
    public func shortLog(_ tag: String, _ what: @autoclosure () -> String) {
        // SuperGram: the short ("critlog") log wrote every Postbox/Api/MTProto record straight to disk even when
        // file logging was off, so a build with logging disabled still produced a continuous stream of writes into
        // logs/app-logs/critlog-*.txt (up to 20 x 1 MB, rewritten forever). That is what triggered the excessive
        // disk-writes resource kill. It now follows the same switch as `log`.
        if !self.logToFile {
            return
        }

        let string = what()

        var rawTime = time_t()
        time(&rawTime)
        var timeinfo = tm()
        localtime_r(&rawTime, &timeinfo)
        
        var curTime = timeval()
        gettimeofday(&curTime, nil)
        let milliseconds = curTime.tv_usec / 1000
        
        let timestamp: Double = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970
        
        self.queue.async {
            let content = WriteBuffer()
            var binaryEventMarkerValue: UInt64 = binaryEventMarker
            content.write(&binaryEventMarkerValue, offset: 0, length: 8)
            let stringData = string.data(using: .utf8) ?? Data()
            var lengthValue: Int32 = 8 + Int32(stringData.count)
            content.write(&lengthValue, offset: 0, length: 4)
            var timestampValue: Double = timestamp
            content.write(&timestampValue, offset: 0, length: 8)
            content.write(stringData)
            let contentData = content.makeData()
            
            var currentFile: ManagedFile?
            var openNew = false
            if let (file, length) = self.shortFile {
                if length >= self.maxShortLength {
                    self.shortFile = nil
                    openNew = true
                } else {
                    currentFile = file
                }
            } else {
                openNew = true
            }
            if openNew {
                let _ = try? FileManager.default.createDirectory(atPath: self.basePath, withIntermediateDirectories: true, attributes: nil)
                
                var createNew = false
                if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: self.basePath), includingPropertiesForKeys: [URLResourceKey.creationDateKey], options: []) {
                    var minCreationDate: (Date, URL)?
                    var maxCreationDate: (Date, URL)?
                    var count = 0
                    for url in files {
                        if url.lastPathComponent.hasPrefix("critlog-") {
                            if let values = try? url.resourceValues(forKeys: Set([URLResourceKey.creationDateKey])), let creationDate = values.creationDate {
                                count += 1
                                if minCreationDate == nil || minCreationDate!.0 > creationDate {
                                    minCreationDate = (creationDate, url)
                                }
                                if maxCreationDate == nil || maxCreationDate!.0 < creationDate {
                                    maxCreationDate = (creationDate, url)
                                }
                            }
                        }
                    }
                    if let (_, url) = minCreationDate, count >= self.maxFiles {
                        let _ = try? FileManager.default.removeItem(at: url)
                    }
                    if let (_, url) = maxCreationDate {
                        var value = stat()
                        if stat(url.path, &value) == 0 && Int(value.st_size) < self.maxShortLength {
                            if let file = ManagedFile(queue: self.queue, path: url.path, mode: .append) {
                                self.shortFile = (file, Int(value.st_size))
                                currentFile = file
                            }
                        } else {
                            createNew = true
                        }
                    } else {
                        createNew = true
                    }
                }
                
                if createNew {
                    let fileName = String(format: "critlog-%d-%d-%d_%02d-%02d-%02d.%03d.txt", arguments: [Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), Int(timeinfo.tm_sec), Int(milliseconds)])
                    
                    let path = self.basePath + "/" + fileName
                    
                    if let file = ManagedFile(queue: self.queue, path: path, mode: .append) {
                        self.shortFile = (file, 0)
                        currentFile = file
                    }
                }
            }
            
            if let currentFile = currentFile {
                let contentDataCount = contentData.count
                contentData.withUnsafeBytes { rawBytes -> Void in
                    // SuperGram: empty content has no base address; the previous force unwrap trapped.
                    guard let baseAddress = rawBytes.baseAddress else {
                        return
                    }
                    let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
                    
                    let _ = currentFile.write(bytes, count: contentDataCount)
                }
                if let shortFile = self.shortFile {
                    self.shortFile = (shortFile.0, shortFile.1 + contentDataCount)
                } else {
                    assertionFailure()
                }
            }
        }
    }
}
