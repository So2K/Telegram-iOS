import Foundation
import CoreFoundation
import Darwin

public struct SharedApiCredentials: Equatable, Codable {
    public let apiId: Int32
    public let apiHash: String

    public init?(apiId: Int32, apiHash: String) {
        guard apiId > 0, apiHash.utf8.count == 32, apiHash.unicodeScalars.allSatisfy({ scalar in
            switch scalar.value {
            case 48 ... 57, 65 ... 70, 97 ... 102:
                return true
            default:
                return false
            }
        }) else {
            return nil
        }
        self.apiId = apiId
        self.apiHash = apiHash.lowercased()
    }

    public init?(apiIdNumber: NSNumber, apiHash: String) {
        guard CFGetTypeID(apiIdNumber) != CFBooleanGetTypeID(),
              apiIdNumber.doubleValue.isFinite,
              let apiId = Int32(exactly: apiIdNumber.int64Value),
              apiId > 0,
              apiIdNumber.compare(NSNumber(value: apiId)) == .orderedSame else {
            return nil
        }
        self.init(apiId: apiId, apiHash: apiHash)
    }
}

public enum SharedApiCredentialsStore {
    public static let appGroupIdentifier = "group.ffcd1c12e1a9728e.1"

    private struct Snapshot: Codable {
        let version: Int
        let baseAppBundleId: String
        let credentials: SharedApiCredentials?
    }

    private enum ReadResult {
        case missing
        case valid(SharedApiCredentials?)
        case invalid
        case foreign
    }

    private static let lock = NSLock()
    private static var isMutating = false
    private static let maximumSnapshotBytes = 4096

    public static func currentOverride(baseAppBundleId: String, migratingLegacy: (() -> SharedApiCredentials?)? = nil) -> SharedApiCredentials? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let url = self.snapshotURL(baseAppBundleId: baseAppBundleId) else {
            return self.migrateLegacy(migratingLegacy, url: nil, baseAppBundleId: baseAppBundleId)
        }
        switch self.readSnapshot(url: url, baseAppBundleId: baseAppBundleId) {
        case let .valid(credentials):
            return credentials
        case .missing:
            return self.migrateLegacy(migratingLegacy, url: url, baseAppBundleId: baseAppBundleId)
        case .invalid, .foreign:
            return nil
        }
    }

    @discardableResult
    public static func store(_ credentials: SharedApiCredentials, baseAppBundleId: String, commitLegacy: () -> Void = {}) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.isMutating else { return false }
        self.isMutating = true
        defer { self.isMutating = false }
        guard let validated = SharedApiCredentials(apiId: credentials.apiId, apiHash: credentials.apiHash),
              let url = self.snapshotURL(baseAppBundleId: baseAppBundleId),
              self.publish(validated, url: url, baseAppBundleId: baseAppBundleId) else {
            return false
        }
        // The snapshot is authoritative before observers see legacy preference changes.
        // Keep the mutation gate active, but allow synchronous getters on any queue.
        self.lock.unlock()
        commitLegacy()
        self.lock.lock()
        return true
    }

    @discardableResult
    public static func clear(baseAppBundleId: String, commitLegacy: () -> Void = {}) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.isMutating else { return false }
        self.isMutating = true
        defer { self.isMutating = false }
        guard let url = self.snapshotURL(baseAppBundleId: baseAppBundleId),
              self.publish(nil, url: url, baseAppBundleId: baseAppBundleId) else {
            return false
        }
        self.lock.unlock()
        commitLegacy()
        self.lock.lock()
        return true
    }

    private static func migrateLegacy(_ callback: (() -> SharedApiCredentials?)?, url: URL?, baseAppBundleId: String) -> SharedApiCredentials? {
        guard !self.isMutating, let callback else { return nil }
        self.isMutating = true
        defer { self.isMutating = false }
        self.lock.unlock()
        let credentials = callback()
        self.lock.lock()
        guard let credentials,
              let validated = SharedApiCredentials(apiId: credentials.apiId, apiHash: credentials.apiHash) else {
            return nil
        }
        if let url {
            // An unsuccessful migration leaves the existing main-only override intact.
            let _ = self.publish(validated, url: url, baseAppBundleId: baseAppBundleId)
        }
        return validated
    }

    private static func snapshotURL(baseAppBundleId: String) -> URL? {
        guard !baseAppBundleId.isEmpty, baseAppBundleId.utf8.count <= 190,
              baseAppBundleId.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.value {
                  case 45, 46, 48 ... 57, 65 ... 90, 95, 97 ... 122:
                      return true
                  default:
                      return false
                  }
              }),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: self.appGroupIdentifier)?.standardizedFileURL.resolvingSymlinksInPath() else {
            return nil
        }
        let directory = container.appendingPathComponent("telegram-data", isDirectory: true).appendingPathComponent("authorization-api", isDirectory: true)
        guard directory.resolvingSymlinksInPath().path.hasPrefix(container.path + "/") else {
            return nil
        }
        return directory.appendingPathComponent("override-\(baseAppBundleId)-v1.json")
    }

    private static func readSnapshot(url: URL, baseAppBundleId: String) -> ReadResult {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            return errno == ENOENT ? .missing : .invalid
        }
        defer { let _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size > 0, info.st_size <= self.maximumSnapshotBytes else {
            return .invalid
        }
        var bytes = [UInt8](repeating: 0, count: self.maximumSnapshotBytes + 1)
        var count = 0
        while count < bytes.count {
            let result = bytes.withUnsafeMutableBytes { buffer -> Int in
                return read(fd, buffer.baseAddress!.advanced(by: count), buffer.count - count)
            }
            if result == -1 && errno == EINTR {
                continue
            }
            guard result >= 0 else {
                return .invalid
            }
            if result == 0 {
                break
            }
            count += result
        }
        guard count > 0, count <= self.maximumSnapshotBytes,
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: Data(bytes.prefix(count))),
              snapshot.version == 1 else {
            return .invalid
        }
        guard snapshot.baseAppBundleId == baseAppBundleId else {
            return .foreign
        }
        if let credentials = snapshot.credentials {
            guard let validated = SharedApiCredentials(apiId: credentials.apiId, apiHash: credentials.apiHash) else {
                return .invalid
            }
            return .valid(validated)
        }
        return .valid(nil)
    }

    private static func publish(_ credentials: SharedApiCredentials?, url: URL, baseAppBundleId: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Snapshot(version: 1, baseAppBundleId: baseAppBundleId, credentials: credentials)),
              data.count <= self.maximumSnapshotBytes else {
            return false
        }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path) {
                guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                    return false
                }
            } else {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    return false
                }
                if case .foreign = self.readSnapshot(url: url, baseAppBundleId: baseAppBundleId) {
                    return false
                }
            }
        } catch {
            return false
        }

        let temporaryURL = directory.appendingPathComponent(".override-\(UUID().uuidString).tmp")
        let fd = open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else {
            return false
        }
        var needsClose = true
        defer {
            if needsClose { let _ = close(fd) }
            let _ = unlink(temporaryURL.path)
        }
        #if os(iOS)
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporaryURL.path)
        } catch {
            return false
        }
        #endif
        let written = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let result = write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if result == -1 && errno == EINTR { continue }
                guard result > 0 else { return false }
                offset += result
            }
            return true
        }
        guard written, fsync(fd) == 0 else {
            return false
        }
        let closeResult = close(fd)
        needsClose = false
        guard closeResult == 0 else {
            return false
        }
        switch self.readSnapshot(url: temporaryURL, baseAppBundleId: baseAppBundleId) {
        case let .valid(storedCredentials):
            guard storedCredentials == credentials else { return false }
        default:
            return false
        }
        return rename(temporaryURL.path, url.path) == 0
    }
}
