#!/usr/bin/env python3
"""Test actual local FFmpeg file initialization/read/seek paths with sparse files.

Extracts size/fd initialization and callbacks for all four local-file paths.
Codec setup/decoding is excluded. Files are temporary owned, sparsely sized and
checked to allocate at most 1 MiB each; no phone or account is touched.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / "submodules/MediaPlayer/Sources/SoftwareVideoSource.swift").read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end] + "\n"


swift = r'''
import Foundation
let FFMPEG_CONSTANT_AVERROR_EOF: Int32 = -541478725
let FFMPEG_AVSEEK_SIZE: Int32 = 0x10000
'''
for name in ["SoftwareVideoSource", "SoftwareAudioSource", "SoftwareVideoReader"]:
    class_marker = f"final class {name} {{"
    class_source = block(source, class_marker)
    swift += f"final class {name} {{\n"
    for field in ["path", "fd", "size"]:
        swift += re.search(rf"^\s*(?:private|fileprivate) let {field}: .+$", class_source, re.MULTILINE).group().strip() + "\n"
    # Actual filesystem setup precedes FFmpeg openInput/findStreamInfo in each initializer.
    start = class_source.index("var s = stat()")
    end = class_source.index("let avFormatContext", start)
    swift += "init(path: String) {\n" + class_source[start:end] + "}\n"
    swift += block(class_source, "deinit {") + "}\n"
    swift += block(source, f"private func {name}_readPacketCallback(")
    swift += block(source, f"private func {name}_seekCallback(")

swift += block(source, "private final class FFMpegMediaInfoExtractContext {")
swift += block(source, "private func FFMpegMediaInfoExtractContextReadPacketCallback(")
swift += block(source, "private func FFMpegMediaInfoExtractContextSeekCallback(")
extractor = block(source, "public func extractFFMpegMediaInfo(path:")
start = extractor.index("var s = stat()")
end = extractor.index("let avFormatContext", start)
context_line = re.search(r"^\s*let context = FFMpegMediaInfoExtractContext\(.+$", extractor, re.MULTILINE).group().strip()
swift += "private func metadataFileAccess(path: String, body: (FFMpegMediaInfoExtractContext) -> Void) -> Int64? {\n"
swift += extractor[start:end] + context_line + "\nbody(context)\nreturn context.size\n}\n"
swift += r'''
var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    precondition(value(), message)
}
typealias ReadCallback = (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32
typealias SeekCallback = (UnsafeMutableRawPointer?, Int64, Int32) -> Int64
func callbacks(fd: Int32, size: Int64, userData: UnsafeMutableRawPointer, readPacket: ReadCallback, seek: SeekCallback) {
    check(seek(userData, 0, FFMPEG_AVSEEK_SIZE) == size, "size query preserves full64-bit filesystem length")
    check(seek(userData, -1, SEEK_SET) == 0, "negative absolute seek remains bounded at zero")
    check(lseek(fd, 0, SEEK_CUR) == 0, "bounded negative seek positions descriptor at zero")
    check(seek(userData, Int64.max, SEEK_SET) == size, "large absolute seek clamps without overflow")
    check(lseek(fd, 0, SEEK_CUR) == size, "large sparse offset is not narrowed")
    let markerOffset = max(0, size - 1)
    check(seek(userData, markerOffset, SEEK_SET) == markerOffset, "absolute seek reaches full-width last byte")
    check(seek(userData, 0, FFMPEG_AVSEEK_SIZE) == size && lseek(fd, 0, SEEK_CUR) == markerOffset, "size query does not move file position")
    var bytes = [UInt8](repeating: 0, count: 8)
    let readCount = bytes.withUnsafeMutableBufferPointer { readPacket(userData, $0.baseAddress, 8) }
    if size > 0 {
        check(readCount == 1 && bytes[0] == 0x5a, "read callback returns actual marker byte past2GiB")
    } else {
        check(readCount == FFMPEG_CONSTANT_AVERROR_EOF, "zero-sized file reports EOF")
    }
    let eof = bytes.withUnsafeMutableBufferPointer { readPacket(userData, $0.baseAddress, 8) }
    check(eof == FFMPEG_CONSTANT_AVERROR_EOF, "read after final byte reports EOF")
    check(readPacket(userData, nil, 8) == FFMPEG_CONSTANT_AVERROR_EOF, "nil buffer is rejected")
    check(readPacket(userData, nil, 0) == FFMPEG_CONSTANT_AVERROR_EOF, "zero buffer is rejected")
    check(readPacket(nil, nil, 8) == FFMPEG_CONSTANT_AVERROR_EOF, "missing source is rejected")
    check(seek(nil, 0, FFMPEG_AVSEEK_SIZE) == 0, "missing source seek preserves existing fallback")
}
let directory = CommandLine.arguments[1]
for size: Int64 in [0, 33, Int64(Int32.max), Int64(Int32.max) + 1, Int64(UInt32.max) + 33] {
    let path = directory + "/sparse-\(size).bin"
    let fd = open(path, O_CREAT | O_RDWR | O_EXCL, S_IRUSR | S_IWUSR)
    check(fd >= 0, "temporary sparse file opens")
    check(ftruncate(fd, off_t(size)) == 0, "temporary file sparse size is set")
    if size > 0 {
        var marker: UInt8 = 0x5a
        check(pwrite(fd, &marker, 1, off_t(size - 1)) == 1, "only final marker byte is allocated")
    }
    var info = stat()
    check(fstat(fd, &info) == 0 && Int64(info.st_size) == size, "sparse filesystem length verified")
    check(Int64(info.st_blocks) * 512 <= 1024 * 1024, "sparse test allocated storage stays below1MiB")
    close(fd)

    var sourceFd: Int32 = -1
    do {
        let context = SoftwareVideoSource(path: path)
        sourceFd = context.fd!
        callbacks(fd: sourceFd, size: size, userData: Unmanaged.passUnretained(context).toOpaque(), readPacket: SoftwareVideoSource_readPacketCallback, seek: SoftwareVideoSource_seekCallback)
    }
    check(fcntl(sourceFd, F_GETFD) == -1 && errno == EBADF, "video source descriptor closes on release")
    do {
        let context = SoftwareAudioSource(path: path)
        sourceFd = context.fd!
        callbacks(fd: sourceFd, size: size, userData: Unmanaged.passUnretained(context).toOpaque(), readPacket: SoftwareAudioSource_readPacketCallback, seek: SoftwareAudioSource_seekCallback)
    }
    check(fcntl(sourceFd, F_GETFD) == -1 && errno == EBADF, "audio source descriptor closes on release")
    do {
        let context = SoftwareVideoReader(path: path)
        sourceFd = context.fd!
        callbacks(fd: sourceFd, size: size, userData: Unmanaged.passUnretained(context).toOpaque(), readPacket: SoftwareVideoReader_readPacketCallback, seek: SoftwareVideoReader_seekCallback)
    }
    check(fcntl(sourceFd, F_GETFD) == -1 && errno == EBADF, "video reader descriptor closes on release")
    let metadataSize = metadataFileAccess(path: path) { context in
        sourceFd = context.fd
        callbacks(fd: sourceFd, size: size, userData: Unmanaged.passUnretained(context).toOpaque(), readPacket: FFMpegMediaInfoExtractContextReadPacketCallback, seek: FFMpegMediaInfoExtractContextSeekCallback)
    }
    check(metadataSize == size, "metadata initialization preserves full64-bit file size")
    check(fcntl(sourceFd, F_GETFD) == -1 && errno == EBADF, "metadata descriptor closes after callback")
}
let missing = directory + "/missing-file.bin"
check(SoftwareVideoSource(path: missing).fd == nil, "video missing-file handling is preserved")
check(SoftwareAudioSource(path: missing).fd == nil, "audio missing-file handling is preserved")
check(SoftwareVideoReader(path: missing).fd == nil, "video reader missing-file handling is preserved")
check(metadataFileAccess(path: missing) { _ in preconditionFailure("missing metadata file opened") } == nil, "metadata missing-file handling is preserved")
print("PASS: \(assertions) actual-source local media size/read/seek assertions; sparse allocated bytes <=1MiB per file")
'''

with tempfile.TemporaryDirectory(prefix="supergram-media-file-size-") as temporary:
    swift_source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    swift_source.write_text(swift)
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(swift_source), "-o", str(executable)], check=True)
    subprocess.run([str(executable), temporary], check=True)
