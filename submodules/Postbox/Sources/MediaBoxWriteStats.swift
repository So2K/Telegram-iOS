import Foundation

// SuperGram: accounting of downloaded media bytes, to find out what a session really wrote to disk and how much of
// it was written twice. "rewritten" counts bytes written over a range of the same partial file that was already
// present; "sessions" counts how many separate file contexts wrote to one resource since the last snapshot (a
// resource that is fetched, evicted and fetched again shows up here). Read and reset by the diagnostics journal.
public final class MediaBoxWriteStats {
    public static let shared = MediaBoxWriteStats()

    public struct ResourceEntry {
        public var written: Int64 = 0
        public var rewritten: Int64 = 0
        public var contexts: Int = 0
    }

    public struct Snapshot {
        public var written: Int64
        public var rewritten: Int64
        public var resourceCount: Int
        public var refetchedResourceCount: Int
        public var top: [(id: String, entry: ResourceEntry)]
    }

    private let lock = NSLock()
    private var entries: [Data: ResourceEntry] = [:]
    private var written: Int64 = 0
    private var rewritten: Int64 = 0

    func contextOpened(resourceId: Data) {
        self.lock.lock()
        self.entries[resourceId, default: ResourceEntry()].contexts += 1
        self.lock.unlock()
    }

    func add(resourceId: Data, written: Int64, newBytes: Int64) {
        let rewritten = max(0, written - newBytes)
        self.lock.lock()
        self.written += written
        self.rewritten += rewritten
        var entry = self.entries[resourceId, default: ResourceEntry()]
        entry.written += written
        entry.rewritten += rewritten
        self.entries[resourceId] = entry
        self.lock.unlock()
    }

    public func snapshotAndReset() -> Snapshot {
        self.lock.lock()
        let active = self.entries.filter { $0.value.written > 0 }
        let top = active.sorted(by: { $0.value.written > $1.value.written }).prefix(6).map { item -> (id: String, entry: ResourceEntry) in
            return (String(data: item.key, encoding: .utf8) ?? item.key.base64EncodedString(), item.value)
        }
        let result = Snapshot(
            written: self.written,
            rewritten: self.rewritten,
            resourceCount: active.count,
            refetchedResourceCount: active.filter({ $0.value.contexts > 1 }).count,
            top: Array(top)
        )
        self.entries.removeAll()
        self.written = 0
        self.rewritten = 0
        self.lock.unlock()
        return result
    }
}
