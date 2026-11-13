import Darwin
private enum AllocationProbe {
    static var enabled = true
    static var requested: Int?
}
private enum WriterBudgetHarness {
    private static let maxSerializedPayloadLength: Int64 = // ACTUAL_BUDGET
    private struct CountedRanges { let count: Int }
    static func allows(_ count: Int) -> Bool {
        let rangeView = CountedRanges(count: count)
        var allowed = false
        let run = {
            // ACTUAL_WRITER_GUARD
            allowed = true
        }
        run()
        return allowed
    }
}
private var checks = 0
private func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1; precondition(value(), message)
}
private func append<T>(_ value: T, to bytes: inout Data) {
    var value = value; withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
}
private func probe(modern: Bool, count: Int32, expectedAllocation: Int?) throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: path) }
    var header = Data()
    if modern { append(UInt32(0x7bac1487), to: &header) }
    append(UInt32(0), to: &header); append(count, to: &header)
    try header.write(to: URL(fileURLWithPath: path))
    let payloadLength = (modern ? 8 : 4) + Int64(max(0, count)) * (modern ? 16 : 8)
    let descriptor = open(path, O_RDWR)
    precondition(descriptor >= 0)
    precondition(ftruncate(descriptor, Int64(header.count) + payloadLength) == 0)
    close(descriptor)
    var metadata = stat(); precondition(stat(path, &metadata) == 0)
    expect(metadata.st_blocks * 512 < 1024 * 1024, "Probe accidentally materialized a sparse payload")
    AllocationProbe.requested = nil
    let map = try? MediaBoxFileMap.read(manager: MediaBoxFileManager(queue: nil), path: path)
    expect(map == nil && AllocationProbe.requested == expectedAllocation, "Cache-map allocation budget boundary changed")
}
if CommandLine.arguments.dropFirst().first == "huge" {
    try probe(modern: true, count: 134_217_727, expectedAllocation: nil)
    print("PASS: huge map rejected before intercepted allocation")
    exit(0)
}
for modern in [false, true] {
    let width: Int64 = modern ? 16 : 8
    let prefix: Int64 = modern ? 8 : 4
    let count = Int32((8 * 1024 * 1024 - prefix) / width)
    try probe(modern: modern, count: count, expectedAllocation: Int(prefix + Int64(count) * width))
    try probe(modern: modern, count: count + 1, expectedAllocation: nil)
    try probe(modern: modern, count: 134_217_727, expectedAllocation: nil)
    try probe(modern: modern, count: Int32.max, expectedAllocation: nil)
    try probe(modern: modern, count: -1, expectedAllocation: nil)
}
expect(WriterBudgetHarness.allows(524_287), "Writer rejected supported modern boundary")
expect(!WriterBudgetHarness.allows(524_288) && !WriterBudgetHarness.allows(Int.max), "Writer can emit an unsupported map")
AllocationProbe.enabled = false
let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
defer { try? FileManager.default.removeItem(atPath: path) }
let manager = MediaBoxFileManager(queue: nil)
let map = MediaBoxFileMap(); map.fill(0 ..< 4)
map.serialize(manager: manager, to: path)
expect(fileSize(path) != nil, "Ordinary map serialization failed")
expect((try? MediaBoxFileMap.read(manager: manager, path: path))?.sum == 4, "Ordinary map checksum/format changed")
print("PASS: \(checks) actual-source cache-map preallocation/writer-bound/format assertions (no payload allocation over 8 MiB)")
