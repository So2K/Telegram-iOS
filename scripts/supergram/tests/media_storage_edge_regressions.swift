import Darwin

private func withFileLimit(_ limit: rlim_t, _ f: () -> Void) {
    var previous = rlimit()
    precondition(getrlimit(RLIMIT_FSIZE, &previous) == 0)
    var restricted = rlimit(rlim_cur: limit, rlim_max: previous.rlim_max)
    let oldSignal = signal(SIGXFSZ, SIG_IGN)
    precondition(setrlimit(RLIMIT_FSIZE, &restricted) == 0)
    defer {
        precondition(setrlimit(RLIMIT_FSIZE, &previous) == 0)
        signal(SIGXFSZ, oldSignal)
    }
    f()
}

private func testFinalLinkFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fullDirectory = directory.appendingPathComponent("missing-final-directory")
    let full = fullDirectory.appendingPathComponent("resource").path
    let partial = directory.appendingPathComponent("partial").path
    let queue = Queue(name: "Link failure regression")
    let manager = MediaBoxFileManager(queue: queue)
    var context: MediaBoxFileContextV2Impl?
    queue.sync {
        context = MediaBoxFileContextV2Impl(queue: queue, manager: manager, storageBox: nil, resourceId: Data(), path: full, partialPath: partial, metaPath: partial + ".meta")!
        var errors = 0
        var completions = 0
        let request = context!.fetchedFullRange(fetch: { _ in .single(.dataPart(resourceOffset: 0, data: Data([1, 2, 3, 4]), range: 0 ..< 4, complete: true)) }, error: { _ in errors += 1 }, completed: { completions += 1 })
        expect(errors == 1 && completions == 0, "Failed final link was reported as successful fetch")
        expect(!FileManager.default.fileExists(atPath: full), "Failed link created a final resource")
        expect((try? Data(contentsOf: URL(fileURLWithPath: partial))) == Data([1, 2, 3, 4]), "Link error discarded recoverable partial data")
        request.dispose()
        try! FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        var fetchCalls = 0
        let retry = context!.fetchedFullRange(fetch: { _ in fetchCalls += 1; return .never() }, error: { _ in errors += 1 }, completed: { completions += 1 })
        expect(errors == 1 && completions == 1 && fetchCalls == 0, "Link retry should finalize existing data without another download")
        expect((try? Data(contentsOf: URL(fileURLWithPath: full))) == Data([1, 2, 3, 4]), "Retry final resource bytes changed")
        retry.dispose()
        context = nil
    }
}

private func testInvalidFetchResults() throws {
    let invalid: [MediaResourceDataFetchResult] = [
        .dataPart(resourceOffset: Int64.max, data: Data([2]), range: 0 ..< 1, complete: true),
        .dataPart(resourceOffset: -1, data: Data([2]), range: 0 ..< 1, complete: true),
        .dataPart(resourceOffset: 0, data: Data([2]), range: Int64.min ..< Int64.max, complete: true),
        .resourceSizeUpdated(-1)
    ]
    for result in invalid {
        try withContext { context, queue, prefix in
            queue.sync {
                var subscriber: Subscriber<MediaResourceDataFetchResult, MediaResourceDataFetchError>?
                var errors = 0; var completions = 0
                let request = context.fetchedFullRange(fetch: { _ in Signal { subscriber = $0; return EmptyDisposable } }, error: { _ in errors += 1 }, completed: { completions += 1 })
                subscriber!.putNext(.dataPart(resourceOffset: 0, data: Data([1]), range: 0 ..< 1, complete: false))
                subscriber!.putNext(result)
                expect(errors == 1 && completions == 0, "Invalid fetched offsets/size must terminate with an error")
                expect(!FileManager.default.fileExists(atPath: prefix), "Invalid result published a final resource")
                expect((try? Data(contentsOf: URL(fileURLWithPath: prefix + "_partial"))) == Data([1]), "Invalid result changed previously valid bytes")
                request.dispose()
            }
        }
    }
}

private func testFinalPathCollisions() throws {
    for collision in 0 ..< 4 {
        try withContext { context, queue, prefix in
            queue.sync {
                var subscriber: Subscriber<MediaResourceDataFetchResult, MediaResourceDataFetchError>?
                var errors = 0; var completions = 0
                let request = context.fetchedFullRange(fetch: { _ in Signal { subscriber = $0; return EmptyDisposable } }, error: { _ in errors += 1 }, completed: { completions += 1 })
                if collision == 0 { try! FileManager.default.createDirectory(atPath: prefix, withIntermediateDirectories: true) }
                if collision == 1 { precondition(symlink(prefix + "_partial", prefix) == 0) }
                if collision == 2 { try! Data([9]).write(to: URL(fileURLWithPath: prefix)) }
                if collision == 3 { try! Data([9, 9, 9, 9]).write(to: URL(fileURLWithPath: prefix)) }
                subscriber!.putNext(.dataPart(resourceOffset: 0, data: Data([1, 2, 3, 4]), range: 0 ..< 4, complete: true))
                expect(errors == 1 && completions == 0, "A conflicting directory/symlink/wrong-size final path was accepted")
                expect((try? Data(contentsOf: URL(fileURLWithPath: prefix + "_partial"))) == Data([1, 2, 3, 4]), "Final-path conflict destroyed recoverable bytes")
                if collision == 3 { expect((try? Data(contentsOf: URL(fileURLWithPath: prefix))) == Data([9, 9, 9, 9]), "Foreign in-flight final bytes were overwritten") }
                request.dispose()
            }
        }
    }
}

private func testExistingMatchingFinalLink() throws {
    try withContext { context, queue, prefix in
        queue.sync {
            var subscriber: Subscriber<MediaResourceDataFetchResult, MediaResourceDataFetchError>?
            var errors = 0; var completions = 0
            let request = context.fetchedFullRange(fetch: { _ in Signal { subscriber = $0; return EmptyDisposable } }, error: { _ in errors += 1 }, completed: { completions += 1 })
            subscriber!.putNext(.dataPart(resourceOffset: 0, data: Data([1, 2, 3, 4]), range: 0 ..< 4, complete: false))
            precondition(link(prefix + "_partial", prefix) == 0)
            subscriber!.putNext(.resourceSizeUpdated(4))
            expect(errors == 0 && completions == 1, "Existing same-inode final hardlink was rejected")
            expect((try? Data(contentsOf: URL(fileURLWithPath: prefix))) == Data([1, 2, 3, 4]), "Same-inode EEXIST finalization changed bytes")
            request.dispose()
        }
    }
}

private func testExistingFinalAdmission() throws {
    for kind in 0 ..< 4 {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefix = directory.appendingPathComponent("resource").path
        let target = directory.appendingPathComponent("target").path
        if kind == 0 { try FileManager.default.createDirectory(atPath: prefix, withIntermediateDirectories: true) }
        if kind == 1 {
            try Data([9]).write(to: URL(fileURLWithPath: target))
            precondition(symlink(target, prefix) == 0)
        }
        if kind >= 2 { try Data([1, 2, 3, 4]).write(to: URL(fileURLWithPath: prefix)) }
        if kind == 2 { precondition(chmod(prefix, 0) == 0) }
        let queue = Queue(name: "Existing final admission regression")
        let manager = MediaBoxFileManager(queue: queue)
        var context: MediaBoxFileContextV2Impl?
        queue.sync {
            context = MediaBoxFileContextV2Impl(queue: queue, manager: manager, storageBox: nil, resourceId: Data(), path: prefix, partialPath: prefix + "_partial", metaPath: prefix + "_partial.meta")!
            var local = false
            let status = context!.status(next: { if case .Local = $0 { local = true } }, completed: {}, size: nil)
            var latest: MediaResourceData?
            let data = context!.data(range: 0 ..< 4, waitUntilAfterInitialFetch: false, next: { latest = $0 })
            let initiallyComplete = latest?.complete == true
            var fetchCalls = 0; var errors = 0; var completed = 0
            let request = context!.fetchedFullRange(fetch: { _ in fetchCalls += 1; return .single(.dataPart(resourceOffset: 0, data: Data([1, 2, 3, 4]), range: 0 ..< 4, complete: true)) }, error: { _ in errors += 1 }, completed: { completed += 1 })
            if kind == 3 {
                expect(local && latest?.complete == true && latest?.size == 4 && completed == 1 && fetchCalls == 0, "Valid existing final resource lost its cache fast path")
            } else {
                expect(!local && !initiallyComplete && completed == 0 && errors == 1 && fetchCalls == 1, "Pre-existing directory/symlink/unreadable file bypassed final admission")
                expect(FileManager.default.fileExists(atPath: prefix), "Invalid pre-existing path was deleted")
                expect((try? Data(contentsOf: URL(fileURLWithPath: prefix + "_partial"))) == Data([1, 2, 3, 4]), "Admission error discarded recoverable partial bytes")
            }
            request.dispose(); status.dispose(); data.dispose(); context = nil
        }
        if kind == 2 { precondition(chmod(prefix, S_IRUSR | S_IWUSR) == 0) }
        if kind == 1 { expect((try? Data(contentsOf: URL(fileURLWithPath: target))) == Data([9]), "Invalid symlink target was overwritten") }
    }
}

private func testShortWriteFailure() throws {
    try withContext { context, queue, prefix in
        queue.sync {
            // Initialize the partial context and metadata before restricting this child process.
            let reader = context.data(range: 0 ..< 2, waitUntilAfterInitialFetch: false, next: { _ in })
            var errors = 0; var completions = 0
            withFileLimit(1) {
                let request = context.fetchedFullRange(fetch: { _ in .single(.dataPart(resourceOffset: 0, data: Data([1, 2]), range: 0 ..< 2, complete: false)) }, error: { _ in errors += 1 }, completed: { completions += 1 })
                expect(errors == 1 && completions == 0, "A real short write must fail fetch instead of asserting")
                expect(!FileManager.default.fileExists(atPath: prefix), "Short write published a final resource")
                request.dispose()
            }
            var ranges = RangeSet<Int64>()
            let status = context.rangeStatus(next: { ranges = $0 }, completed: {})
            expect(ranges.isEmpty, "Short write marked unwritten bytes as available")
            status.dispose(); reader.dispose()
        }
    }
}

private func testMapWriteFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = MediaBoxFileManager(queue: nil)
    let map = MediaBoxFileMap()
    map.fill(0 ..< 4)
    let path = directory.appendingPathComponent("map").path
    withFileLimit(1) { map.serialize(manager: manager, to: path) }
    expect((try? MediaBoxFileMap.read(manager: manager, path: path)) == nil, "Truncated map must not decode as valid coverage")
    map.serialize(manager: manager, to: path)
    expect((try? MediaBoxFileMap.read(manager: manager, path: path))?.sum == 4, "Map persistence did not recover after write restriction lifted")
}

private func testDirtyMapRetry() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let prefix = directory.appendingPathComponent("resource").path
    let queue = Queue(name: "Map retry regression")
    let manager = MediaBoxFileManager(queue: queue)
    var context: MediaBoxFileContextV2Impl?
    queue.sync {
        context = MediaBoxFileContextV2Impl(queue: queue, manager: manager, storageBox: nil, resourceId: Data(), path: prefix, partialPath: prefix + "_partial", metaPath: prefix + "_partial.meta")!
        var subscriber: Subscriber<MediaResourceDataFetchResult, MediaResourceDataFetchError>?
        var completed = 0
        let request = context!.fetchedFullRange(fetch: { _ in Signal { subscriber = $0; return EmptyDisposable } }, error: { _ in preconditionFailure("Usable payload should survive metadata retry") }, completed: { completed += 1 })
        subscriber!.putNext(.dataPart(resourceOffset: 0, data: Data([1, 2, 3, 4]), range: 0 ..< 4, complete: false))
        withFileLimit(1) { subscriber!.putNext(.resourceSizeUpdated(4)) }
        expect(completed == 1 && (try? Data(contentsOf: URL(fileURLWithPath: prefix))) == Data([1, 2, 3, 4]), "Metadata failure erased a valid full payload")
        request.dispose(); context = nil
        let map = try? MediaBoxFileMap.read(manager: manager, path: prefix + "_partial.meta")
        expect(map?.sum == 4 && map?.truncationSize == 4, "Failed metadata flush cleared dirty state before a successful retry")
    }
}

private func testActualCoverage() throws {
    try withContext { context, queue, prefix in
        queue.sync {
            var subscriber: Subscriber<MediaResourceDataFetchResult, MediaResourceDataFetchError>?
            var completions = 0
            let request = context.fetchedFullRange(fetch: { _ in Signal { subscriber = $0; return EmptyDisposable } }, error: { _ in preconditionFailure("Unexpected coverage error") }, completed: { completions += 1 })
            subscriber!.putNext(.dataPart(resourceOffset: 4, data: Data([5, 6, 7, 8]), range: 0 ..< 4, complete: false))
            subscriber!.putNext(.resourceSizeUpdated(4))
            expect(completions == 0 && !FileManager.default.fileExists(atPath: prefix), "Equal byte count with a hole before EOF was finalized")
            subscriber!.putNext(.dataPart(resourceOffset: 0, data: Data([1, 2, 3, 4]), range: 0 ..< 4, complete: false))
            expect(completions == 1, "Actual contiguous coverage should finalize despite discarded trailing ranges")
            expect((try? Data(contentsOf: URL(fileURLWithPath: prefix))) == Data([1, 2, 3, 4]), "Final resource retained stale bytes beyond advertised EOF")
            request.dispose()
        }
    }
}

private func testResetTail() throws {
    try withContext { context, queue, prefix in
        queue.sync {
            var subscriber: Subscriber<MediaResourceDataFetchResult, MediaResourceDataFetchError>?
            var completions = 0
            let request = context.fetchedFullRange(fetch: { _ in Signal { subscriber = $0; return EmptyDisposable } }, error: { _ in preconditionFailure("Unexpected tail error") }, completed: { completions += 1 })
            subscriber!.putNext(.dataPart(resourceOffset: 0, data: Data([1, 2, 3, 4, 9, 9, 9, 9]), range: 0 ..< 8, complete: false))
            subscriber!.putNext(.reset)
            subscriber!.putNext(.dataPart(resourceOffset: 0, data: Data([1, 2, 3, 4]), range: 0 ..< 4, complete: true))
            expect(completions == 1 && (try? Data(contentsOf: URL(fileURLWithPath: prefix))) == Data([1, 2, 3, 4]), "Reset followed by smaller EOF retained an old physical tail")
            request.dispose()
        }
    }
}

let selected = CommandLine.arguments.dropFirst().first ?? "all"
if selected == "all" || selected == "link" { try testFinalLinkFailure() }
if selected == "all" || selected == "link" { try testFinalPathCollisions() }
if selected == "all" || selected == "link" { try testExistingMatchingFinalLink() }
if selected == "all" || selected == "link" || selected == "admission" { try testExistingFinalAdmission() }
if selected == "all" || selected == "invalid" { try testInvalidFetchResults() }
if selected == "all" || selected == "write" { try testShortWriteFailure() }
if selected == "all" || selected == "map" { try testMapWriteFailure() }
if selected == "all" || selected == "map" { try testDirtyMapRetry() }
if selected == "all" || selected == "coverage" { try testActualCoverage() }
if selected == "all" || selected == "tail" { try testResetTail() }
print("PASS: \(assertionCount) new actual-source storage failure/range/finalization assertions")
