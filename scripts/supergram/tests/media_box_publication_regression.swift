import Darwin
public struct MediaResourceId: Hashable {
    public let stringRepresentation: String
    public init(_ value: String) { self.stringRepresentation = value }
}
public protocol MediaResource { var id: MediaResourceId { get } }
public protocol CachedMediaResourceRepresentation {
    var uniqueId: String { get }
    var keepDuration: CachedMediaRepresentationKeepDuration { get }
}
private struct Resource: MediaResource { let id = MediaResourceId("synthetic") }
private struct Representation: CachedMediaResourceRepresentation {
    let uniqueId = "fixture"
    let keepDuration: CachedMediaRepresentationKeepDuration = .general
}
private final class Cleanup { func touch(paths: [String]) {} }
private final class MediaBoxHarness {
    let dataQueue = Queue(name: "Actual public MediaBox fixture")
    let concurrentQueue = Queue.concurrentDefaultQueue()
    let timeBasedCleanup = Cleanup()
    let cacheStorageBox = StorageBox()
    let wrappedFetchCachedResourceRepresentation = Promise<(MediaResource, CachedMediaResourceRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError>>()
    private var cachedRepresentationContexts: [CachedMediaResourceRepresentationKey: CachedMediaResourceRepresentationContext] = [:]
    let paths: ResourceStorePaths
    private lazy var manager = MediaBoxFileManager(queue: dataQueue)
    private var context: MediaBoxFileContextV2Impl?
    init(_ paths: ResourceStorePaths) { self.paths = paths }
    var alternatePaths: [MediaResourceId: ResourceStorePaths] = [:]
    func storePathsForId(_ id: MediaResourceId) -> ResourceStorePaths { alternatePaths[id] ?? paths }
    private func cachedRepresentationPathsForId(_ id: String, representationId: String, keepDuration: CachedMediaRepresentationKeepDuration) -> ResourceStorePaths { paths }
    private func fileContext(for id: MediaResourceId) -> (MediaBoxFileContext, () -> Void)? {
        if context == nil {
            context = MediaBoxFileContextV2Impl(queue: dataQueue, manager: manager, storageBox: nil, resourceId: Data(), path: paths.complete, partialPath: paths.partial, metaPath: paths.partial + ".meta")
        }
        guard let context else { return nil }
        return (context, {})
    }
    func drain() { dataQueue.sync {}; dataQueue.sync {} }
    func close() { dataQueue.sync { cachedRepresentationContexts.removeAll(); context = nil } }
    var contextCount: Int {
        var count = 0
        dataQueue.sync { count = cachedRepresentationContexts.count }
        return count
    }
    var retainedContext: CachedMediaResourceRepresentationContext? {
        var result: CachedMediaResourceRepresentationContext?
        dataQueue.sync { result = cachedRepresentationContexts.values.first }
        return result
    }
    func replayRetired(context: CachedMediaResourceRepresentationContext, next: CachedMediaResourceRepresentationResult) {
        let key = CachedMediaResourceRepresentationKey(resourceId: nil, representation: "fixture")
        let paths = self.paths
        let cacheStorageBox = self.cacheStorageBox
        dataQueue.sync {
            let callback = { [weak self, weak context] (next: CachedMediaResourceRepresentationResult) in
                // ACTUAL_RETIRED_CALLBACK
            }
            callback(next)
        }
    }
    // ACTUAL_PUBLIC_METHODS
}
private var checks = 0
private func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1; precondition(value(), message)
}
private func withBox(_ body: (MediaBoxHarness, ResourceStorePaths, String) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let paths = ResourceStorePaths(partial: directory + "/partial", complete: directory + "/full")
    let box = MediaBoxHarness(paths)
    defer { box.close() }
    try body(box, paths, directory)
}
private func custom(_ box: MediaBoxHarness, source: @escaping () -> Signal<CachedMediaResourceRepresentationResult, NoError>, complete: Bool = true) -> Signal<MediaResourceData, NoError> {
    box.customResourceData(id: "fixture", baseResourceId: nil, pathExtension: nil, complete: complete, fetch: source, keepDuration: .general, attemptSynchronously: true)
}
private func testAdmission() throws {
    for kind in 0 ..< 4 {
        try withBox { box, paths, directory in
            let target = directory + "/foreign"
            if kind == 0 { try FileManager.default.createDirectory(atPath: paths.complete, withIntermediateDirectories: true) }
            if kind == 1 {
                try Data([9, 9, 9, 9]).write(to: URL(fileURLWithPath: target))
                precondition(symlink(target, paths.complete) == 0)
            }
            if kind >= 2 { try Data([1, 2, 3, 4]).write(to: URL(fileURLWithPath: paths.complete)) }
            if kind == 2 { precondition(chmod(paths.complete, 0) == 0) }
            var data: [MediaResourceData] = []; var completed = 0
            let subscription = box.resourceData(id: Resource().id, attemptSynchronously: true).start(next: { data.append($0) }, completed: { completed += 1 })
            box.drain()
            expect(box.completedResourcePath(id: Resource().id) == (kind == 3 ? paths.complete : nil), "Public completedResourcePath admitted an invalid full path")
            if kind == 3 { expect(completed == 1 && data.last?.complete == true, "Valid full-cache fast path was lost") }
            else { expect(completed == 0 && data.allSatisfy { !$0.complete }, "Public resourceData claimed an invalid cache path ready") }
            subscription.dispose(); box.drain()
            if kind == 2 { precondition(chmod(paths.complete, S_IRUSR | S_IWUSR) == 0) }
            if kind == 1 { expect((try? Data(contentsOf: URL(fileURLWithPath: target))) == Data([9, 9, 9, 9]), "Invalid full symlink target was mutated") }
        }
    }
}
private func testAliases() throws {
    for kind in 0 ..< 4 {
        try withBox { box, paths, directory in
            try Data([1, 2, 3, 4]).write(to: URL(fileURLWithPath: paths.complete))
            let alias = paths.complete + ".jpg"
            if kind == 0 { try FileManager.default.createDirectory(atPath: alias, withIntermediateDirectories: true) }
            if kind == 1 { precondition(symlink(paths.complete, alias) == 0) }
            if kind == 2 { try Data([9, 9, 9, 9]).write(to: URL(fileURLWithPath: alias)) }
            let expectedPath = kind == 3 ? alias : paths.complete
            expect(box.completedResourcePath(id: Resource().id, pathExtension: "jpg") == expectedPath, "Invalid/foreign alias was reported as a verified hardlink")
            var value: MediaResourceData?
            let subscription = box.resourceData(id: Resource().id, pathExtension: "jpg", attemptSynchronously: true).start(next: { value = $0 })
            expect(value?.path == expectedPath && value?.complete == true, "Public resourceData alias fallback changed")
            if kind == 2 { expect((try? Data(contentsOf: URL(fileURLWithPath: alias))) == Data([9, 9, 9, 9]), "Foreign same-size alias was overwritten") }
            subscription.dispose()
        }
    }
}
private func testPublication() throws {
    for cached in [false, true] {
        try withBox { box, paths, _ in
            let source: Signal<CachedMediaResourceRepresentationResult, NoError> = .single(.data(Data([1, 2, 3, 4]))) |> then(.single(.done))
            box.wrappedFetchCachedResourceRepresentation.set(.single({ _, _ in source }))
            var ready: [MediaResourceData] = []; var completions = 0
            let signal = cached ? box.cachedResourceRepresentation(Resource(), representation: Representation(), complete: true, attemptSynchronously: true) : custom(box, source: { source })
            let subscription = signal.start(next: { if $0.complete { ready.append($0) } }, completed: { completions += 1 })
            box.drain()
            expect(completions == 1 && ready.count == 1 && ready[0].path == paths.complete, "Actual representation method did not publish valid data exactly once")
            expect((try? Data(contentsOf: URL(fileURLWithPath: paths.complete))) == Data([1, 2, 3, 4]), "Published representation bytes changed")
            expect(box.contextCount == 0, "Completed representation retained its context")
            subscription.dispose()
        }
    }
    try withBox { box, paths, _ in
        var values: [MediaResourceData] = []; var completed = 0
        let subscription = custom(box, source: { .single(.data(Data())) |> then(.single(.done)) }).start(next: { values.append($0) }, completed: { completed += 1 })
        box.drain()
        expect(values.last?.complete == true && values.last?.size == 0 && completed == 1, "Empty representation data regressed")
        subscription.dispose()
    }
    for cached in [false, true] {
        for temporaryPath in [false, true] {
            try withBox { box, paths, directory in
                let input = directory + "/input"
                try Data([4, 3, 2, 1]).write(to: URL(fileURLWithPath: input))
                let source: Signal<CachedMediaResourceRepresentationResult, NoError> = .single(temporaryPath ? .temporaryPath(input) : .tempFile(TempBoxFile(path: input)))
                box.wrappedFetchCachedResourceRepresentation.set(.single({ _, _ in source }))
                var ready = 0; var completed = 0
                let signal = cached ? box.cachedResourceRepresentation(Resource(), representation: Representation(), complete: true, attemptSynchronously: true) : custom(box, source: { source })
                let subscription = signal.start(next: { if $0.complete { ready += 1 } }, completed: { completed += 1 })
                box.drain()
                expect(ready == 1 && completed == 1 && box.contextCount == 0, "Valid temp/path publication did not finish exactly once")
                expect((try? Data(contentsOf: URL(fileURLWithPath: paths.complete))) == Data([4, 3, 2, 1]) && !FileManager.default.fileExists(atPath: input), "Valid temp publication changed move/cleanup ownership")
                subscription.dispose()
            }
        }
    }
}
private func testFailures() throws {
    for cached in [false, true] {
        try withBox { box, paths, _ in
            var producer: Subscriber<CachedMediaResourceRepresentationResult, NoError>?
            let source = Signal<CachedMediaResourceRepresentationResult, NoError> { producer = $0; return EmptyDisposable }
            box.wrappedFetchCachedResourceRepresentation.set(.single({ _, _ in source }))
            let signal = cached ? box.cachedResourceRepresentation(Resource(), representation: Representation(), complete: true, attemptSynchronously: true) : custom(box, source: { source })
            var completions = 0; var ready = 0
            let first = signal.start(next: { if $0.complete { ready += 1 } }, completed: { completions += 1 })
            let second = signal.start(next: { if $0.complete { ready += 1 } }, completed: { completions += 1 })
            box.drain()
            try FileManager.default.createDirectory(atPath: paths.complete, withIntermediateDirectories: true)
            producer!.putNext(.data(Data([1, 2, 3, 4]))); box.drain()
            producer!.putNext(.done); box.drain()
            expect(completions == 2 && ready == 0 && box.contextCount == 0, "Publication failure left subscribers pending or claimed ready")
            expect((try? Data(contentsOf: URL(fileURLWithPath: paths.partial))) == Data([1, 2, 3, 4]), "Publication failure discarded recoverable partial")
            expect(FileManager.default.fileExists(atPath: paths.complete), "Publication failure removed pre-existing conflict")
            first.dispose(); second.dispose()
        }
    }
    try withBox { box, paths, directory in
        let temporary = directory + "/input"
        try Data([4, 3, 2, 1]).write(to: URL(fileURLWithPath: temporary))
        try FileManager.default.createDirectory(atPath: paths.complete, withIntermediateDirectories: true)
        var complete = 0; var ready = 0
        let subscription = custom(box, source: { .single(.tempFile(TempBoxFile(path: temporary))) }).start(next: { if $0.complete { ready += 1 } }, completed: { complete += 1 })
        box.drain()
        expect(complete == 1 && ready == 0 && box.contextCount == 0, "Failed temp publication did not settle")
        expect((try? Data(contentsOf: URL(fileURLWithPath: temporary))) == Data([4, 3, 2, 1]), "Failed temp publication disposed recoverable temp")
        subscription.dispose()
    }
    for temporary in [false, true] {
        try withBox { _, paths, directory in
            let broken = ResourceStorePaths(partial: paths.partial, complete: directory + "/missing/full")
            let box = MediaBoxHarness(broken); defer { box.close() }
            let input = directory + "/input"
            try Data([4, 3, 2, 1]).write(to: URL(fileURLWithPath: input))
            var completed = 0; var ready = 0
            let source: Signal<CachedMediaResourceRepresentationResult, NoError> = temporary ? .single(.temporaryPath(input)) : .single(.data(Data([1, 2]))) |> then(.single(.done))
            let subscription = custom(box, source: { source }).start(next: { if $0.complete { ready += 1 } }, completed: { completed += 1 })
            box.drain()
            expect(completed == 1 && ready == 0 && box.contextCount == 0, "Real link/rename failure did not finish subscribers")
            expect((try? Data(contentsOf: URL(fileURLWithPath: temporary ? input : paths.partial))) == (temporary ? Data([4, 3, 2, 1]) : Data([1, 2])), "Failed link/rename discarded recoverable source")
            subscription.dispose()
        }
    }
    try withBox { box, paths, _ in
        var producer: Subscriber<CachedMediaResourceRepresentationResult, NoError>?
        var completed = 0; var ready = 0
        let subscription = custom(box, source: { Signal { producer = $0; return EmptyDisposable } }).start(next: { if $0.complete { ready += 1 } }, completed: { completed += 1 })
        box.drain()
        box.dataQueue.sync {
            var previous = rlimit(); precondition(getrlimit(RLIMIT_FSIZE, &previous) == 0)
            var restricted = rlimit(rlim_cur: 1, rlim_max: previous.rlim_max)
            let oldSignal = signal(SIGXFSZ, SIG_IGN)
            precondition(setrlimit(RLIMIT_FSIZE, &restricted) == 0)
            producer!.putNext(.data(Data([1, 2])))
            precondition(setrlimit(RLIMIT_FSIZE, &previous) == 0); signal(SIGXFSZ, oldSignal)
        }
        box.drain()
        expect(completed == 1 && ready == 0 && box.contextCount == 0 && !FileManager.default.fileExists(atPath: paths.complete), "Actual representation short write was reported ready or left pending")
        expect((try? Data(contentsOf: URL(fileURLWithPath: paths.partial))) == Data([1]), "Short write did not preserve its recoverable bytes")
        subscription.dispose()
    }
    try withBox { box, paths, directory in
        let target = directory + "/foreign"
        try Data([9, 9]).write(to: URL(fileURLWithPath: target)); precondition(symlink(target, paths.complete) == 0)
        var completed = 0
        let subscription = custom(box, source: { .single(.reset) |> then(.single(.data(Data([1, 2])))) |> then(.single(.done)) }).start(completed: { completed += 1 })
        box.drain()
        expect(completed == 1 && (try? Data(contentsOf: URL(fileURLWithPath: target))) == Data([9, 9]), "Reset/publication overwrote a foreign complete symlink target")
        var info = stat(); precondition(lstat(paths.complete, &info) == 0)
        expect(info.st_mode & S_IFMT == S_IFLNK, "Reset removed an invalid pre-existing complete alias")
        subscription.dispose()
    }
}
private func testLifecycle() throws {
    try withBox { box, paths, _ in
        var producer: Subscriber<CachedMediaResourceRepresentationResult, NoError>?
        var replacementProducer: Subscriber<CachedMediaResourceRepresentationResult, NoError>?
        var replacement: Disposable?
        var completed = 0; var replacementCompleted = 0; var ready = 0
        try FileManager.default.createDirectory(atPath: paths.complete, withIntermediateDirectories: true)
        let first = custom(box, source: { Signal { producer = $0; return EmptyDisposable } }).start(completed: {
            completed += 1
            replacement = custom(box, source: { Signal { replacementProducer = $0; return EmptyDisposable } }).start(next: { if $0.complete { ready += 1 } }, completed: { replacementCompleted += 1 })
        })
        box.drain()
        let oldContext = box.retainedContext!
        producer!.putNext(.data(Data([1, 2]))); box.drain(); producer!.putNext(.done); box.drain()
        expect(completed == 1 && replacementCompleted == 0 && box.contextCount == 1, "Old failure completion clobbered reentrant replacement")
        producer!.putNext(.reset); producer!.putCompletion(); box.drain()
        box.replayRetired(context: oldContext, next: .reset)
        expect((try? Data(contentsOf: URL(fileURLWithPath: paths.partial))) == Data([1, 2]), "Actual retired callback body mutated replacement files")
        expect(box.contextCount == 1 && replacementCompleted == 0 && ready == 0, "Late old source completed replacement or changed publication")
        replacementProducer!.putCompletion(); box.drain()
        expect(replacementCompleted == 1 && box.contextCount == 0, "Source completion without done left a context pending")
        first.dispose(); replacement?.dispose()
    }
    try withBox { box, _, _ in
        var disposed = 0; var completed = 0
        let subscription = custom(box, source: { Signal { subscriber in
            subscriber.putNext(.done)
            return ActionDisposable { disposed += 1 }
        } }).start(completed: { completed += 1 })
        box.drain()
        expect(completed == 1 && disposed == 1 && box.contextCount == 0, "Synchronous failure before disposable assignment leaked or completed twice")
        subscription.dispose()
    }
}
private func directStore(_ box: MediaBoxHarness, variant: Int, data: Data, tempPath: String, completion: @escaping (String) -> Void) {
    switch variant {
    case 0: box.storeCachedResourceRepresentation(Resource(), representation: Representation(), data: data)
    case 1: box.storeCachedResourceRepresentation(Resource(), representationId: "fixture", keepDuration: .general, data: data, completion: completion)
    case 2: box.storeCachedResourceRepresentation("synthetic", representationId: "fixture", keepDuration: .general, data: data, completion: completion)
    default: box.storeCachedResourceRepresentation("synthetic", representationId: "fixture", keepDuration: .general, tempFile: TempBoxFile(path: tempPath), completion: completion)
    }
}
private func testDirectStores() throws {
    for variant in 0 ..< 4 {
        for payload in [Data(), Data([1, 2, 3, 4])] {
            try withBox { box, paths, directory in
                let input = directory + "/input"
                try payload.write(to: URL(fileURLWithPath: input))
                var completions: [String] = []
                directStore(box, variant: variant, data: payload, tempPath: input, completion: { completions.append($0) })
                box.drain()
                expect((try? Data(contentsOf: URL(fileURLWithPath: paths.complete))) == payload, "Public direct-store changed valid/empty payload bytes")
                expect(completions == (variant == 0 ? [] : [paths.complete]), "Direct-store did not return its usable path exactly once")
                expect(box.cacheStorageBox.updatedSizes == [Int64(payload.count)], "Direct-store accounted size before verified success or lost empty accounting")
                if variant == 3 { expect(!FileManager.default.fileExists(atPath: input), "Successful temp direct-store retained its input") }
            }
        }
    }
}
private func testDirectStoreCollisions() throws {
    for variant in 0 ..< 4 {
        for collision in 0 ..< 3 {
            try withBox { box, paths, directory in
                let target = directory + "/foreign"
                let input = directory + "/input"
                let payload = Data([1, 2, 3, 4])
                try payload.write(to: URL(fileURLWithPath: input))
                if collision == 0 { try FileManager.default.createDirectory(atPath: paths.complete, withIntermediateDirectories: true) }
                if collision == 1 {
                    try Data([9, 9, 9, 9]).write(to: URL(fileURLWithPath: target))
                    precondition(symlink(target, paths.complete) == 0)
                }
                if collision == 2 {
                    try Data([8, 8, 8, 8]).write(to: URL(fileURLWithPath: paths.complete))
                    precondition(chmod(paths.complete, 0) == 0)
                }
                var completions = 0
                directStore(box, variant: variant, data: payload, tempPath: input, completion: { _ in completions += 1 })
                box.drain()
                expect(completions == 0 && box.cacheStorageBox.updatedSizes.isEmpty, "Failed direct-store called completion or accounted unusable bytes")
                var info = stat(); precondition(lstat(paths.complete, &info) == 0)
                expect(info.st_mode & S_IFMT == (collision == 0 ? S_IFDIR : collision == 1 ? S_IFLNK : S_IFREG), "Direct-store replaced an invalid pre-existing collision")
                if collision == 1 { expect((try? Data(contentsOf: URL(fileURLWithPath: target))) == Data([9, 9, 9, 9]), "Direct-store altered a foreign symlink target") }
                if collision == 2 {
                    precondition(chmod(paths.complete, S_IRUSR | S_IWUSR) == 0)
                    expect((try? Data(contentsOf: URL(fileURLWithPath: paths.complete))) == Data([8, 8, 8, 8]), "Direct-store replaced an unreadable pre-existing file")
                }
                if variant == 3 { expect((try? Data(contentsOf: URL(fileURLWithPath: input))) == payload, "Failed direct temp-store lost its recoverable input") }
            }
        }
    }
}
private func testDirectStoreWriteFailures() throws {
    for variant in 0 ..< 3 {
        try withBox { box, paths, directory in
            let original = Data([9, 9, 9, 9])
            try original.write(to: URL(fileURLWithPath: paths.complete))
            var completions = 0
            box.dataQueue.sync {
                var previous = rlimit(); precondition(getrlimit(RLIMIT_FSIZE, &previous) == 0)
                var restricted = rlimit(rlim_cur: 1, rlim_max: previous.rlim_max)
                let oldSignal = signal(SIGXFSZ, SIG_IGN)
                precondition(setrlimit(RLIMIT_FSIZE, &restricted) == 0)
                defer { precondition(setrlimit(RLIMIT_FSIZE, &previous) == 0); signal(SIGXFSZ, oldSignal) }
                // Queue.async is inline on its own queue, so the real write runs while limited.
                directStore(box, variant: variant, data: Data([1, 2, 3, 4, 5, 6]), tempPath: directory + "/unused", completion: { _ in completions += 1 })
            }
            box.drain()
            expect(completions == 0 && box.cacheStorageBox.updatedSizes.isEmpty, "Actual short direct-store write published/accounted a partial payload")
            expect((try? Data(contentsOf: URL(fileURLWithPath: paths.complete))) == original, "Failed atomic direct-store destroyed its previously complete file")
        }
    }
}
private func testDirectTempStoreFailure() throws {
    try withBox { _, paths, directory in
        let input = directory + "/input"
        try Data([1, 2, 3, 4]).write(to: URL(fileURLWithPath: input))
        let broken = ResourceStorePaths(partial: paths.partial, complete: directory + "/missing/full")
        let box = MediaBoxHarness(broken); defer { box.close() }
        var completed = 0
        directStore(box, variant: 3, data: Data(), tempPath: input, completion: { _ in completed += 1 }); box.drain()
        expect(completed == 0 && box.cacheStorageBox.updatedSizes.isEmpty, "Failed temp direct-store returned a nonexistent full path")
        expect((try? Data(contentsOf: URL(fileURLWithPath: input))) == Data([1, 2, 3, 4]), "Failed temp direct-store discarded its input")
    }
}
private func testResourceMove() throws {
    for mode in 0 ..< 5 {
        try withBox { box, source, directory in
            let destination = ResourceStorePaths(partial: directory + (mode == 3 ? "/missing/partial" : "/other-partial"), complete: directory + (mode == 3 ? "/missing/full" : "/other-full"))
            let to = MediaResourceId("other")
            box.alternatePaths[to] = destination
            let payload = Data([1, 2, 3, 4]); let foreign = Data([9, 9, 9, 9])
            try payload.write(to: URL(fileURLWithPath: source.partial)); try payload.write(to: URL(fileURLWithPath: source.complete))
            if mode == 1 {
                precondition(link(source.partial, destination.partial) == 0); precondition(link(source.complete, destination.complete) == 0)
            }
            if mode == 2 || mode == 4 { try foreign.write(to: URL(fileURLWithPath: destination.partial)) }
            if mode == 2 { try foreign.write(to: URL(fileURLWithPath: destination.complete)) }
            box.moveResourceData(from: Resource().id, to: to, synchronous: mode % 2 == 0); box.drain()
            for (index, pair) in [(source.partial, destination.partial), (source.complete, destination.complete)].enumerated() {
                let successful = mode == 0 || mode == 1 || (mode == 4 && index == 1)
                expect(FileManager.default.fileExists(atPath: pair.0) == !successful, "Resource move removed a source whose hardlink failed or retained successful source")
                if successful { expect((try? Data(contentsOf: URL(fileURLWithPath: pair.1))) == payload, "Successful hardlink move changed payload") }
                else {
                    expect((try? Data(contentsOf: URL(fileURLWithPath: pair.0))) == payload, "Failed resource move lost recoverable source bytes")
                    if mode != 3 { expect((try? Data(contentsOf: URL(fileURLWithPath: pair.1))) == foreign, "Failed move overwrote a foreign same-size destination") }
                }
            }
        }
    }
    try withBox { box, paths, _ in
        try Data([1, 2]).write(to: URL(fileURLWithPath: paths.complete))
        box.moveResourceData(from: Resource().id, to: Resource().id, synchronous: true)
        expect((try? Data(contentsOf: URL(fileURLWithPath: paths.complete))) == Data([1, 2]), "Same-id move unlinked its own resource")
    }
}
let selected = CommandLine.arguments.dropFirst().first ?? "all"
if selected == "all" || selected == "admission" { try testAdmission() }
if selected == "all" || selected == "alias" { try testAliases() }
if selected == "all" { try testPublication() }
if selected == "all" || selected == "failure" { try testFailures() }
if selected == "all" || selected == "lifecycle" { try testLifecycle() }
if selected == "all" || selected == "store" { try testDirectStores() }
if selected == "all" || selected == "store-failure" { try testDirectStoreCollisions() }
if selected == "all" || selected == "store-failure" || selected == "store-write" { try testDirectStoreWriteFailures() }
if selected == "all" || selected == "store-failure" || selected == "store-temp" { try testDirectTempStoreFailure() }
if selected == "all" || selected == "move" { try testResourceMove() }
print("PASS: \(checks) actual public MediaBox admission/alias/publication/subscriber lifecycle assertions")
