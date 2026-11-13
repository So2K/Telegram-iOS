#!/usr/bin/env python3
"""Run deterministic media regressions against the current Swift production sources.

This is a standalone regression executable, not a selective application build. It
uses the real file map/context, managed file, RangeSet and SwiftSignalKit sources.
Only StorageBox, TempBox and logging are replaced; disk I/O is real. The FetchV2
data classification/retry/commit bodies are extracted unchanged and exercised
with a deterministic retry clock, without a Telegram server or an iOS device.
"""

from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def read(path):
    return (ROOT / path).read_text()


def strip_imports(source):
    return re.sub(r"^import (SwiftSignalKit|ManagedFile|RangeSet|Crc32)\n", "", source, flags=re.M)


def between(source, first, last):
    return source.split(first, 1)[1].split(last, 1)[0]


def main():
    fetch = read("submodules/TelegramCore/Sources/Network/FetchV2.swift")
    manager = read("submodules/FetchManagerImpl/Sources/FetchManagerImpl.swift")
    media_box = read("submodules/Postbox/Sources/MediaBox.swift")
    fixture = (HERE / "media_fetch_regressions.swift").read_text()
    fixture = fixture.replace("// PRODUCTION_MEDIA_TYPES", "public struct MediaResourceData" + between(media_box, "public struct MediaResourceData", "public enum CachedMediaResourceRepresentationResult"))
    fixture = fixture.replace("// PRODUCTION_ATTEMPT_TYPES", "private final class FetchManagerFetchAttempt" + between(manager, "private final class FetchManagerFetchAttempt", "// SuperGram: how many entries"))
    fixture = fixture.replace("// PRODUCTION_ATTEMPT_CHECK", "func isCurrentFetchAttempt" + between(manager, "func isCurrentFetchAttempt", "    func handleEntryFetchFailed"))
    fixture = fixture.replace("// PRODUCTION_DATA_BRANCH", between(fetch, "case let .data(data, verifyPartHashData):", "case let .cdnRedirect(cdnData):"))
    fixture = fixture.replace("// PRODUCTION_RETRY\n", "private func scheduleRetryAfterFailure()" + between(fetch, "private func scheduleRetryAfterFailure()", "        private func update()"))
    fixture = fixture.replace("// PRODUCTION_COMMIT", "private func commitPendingReadyPart" + between(fetch, "private func commitPendingReadyPart", "        private func processFloodWaitError"))
    fixture = fixture.replace("// PRODUCTION_RETRY_LIMIT", re.search(r"private static let maxConsecutiveFailures: Int = (\d+)", fetch).group(1))

    paths = sorted((ROOT / "submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"))
    paths += sorted((ROOT / "submodules/Utils/RangeSet/Sources").glob("*.swift"))
    paths += [ROOT / path for path in (
        "submodules/ManagedFile/Sources/ManagedFile.swift",
        "submodules/Postbox/Sources/MediaBoxFileManager.swift",
        "submodules/Postbox/Sources/FileSize.swift",
        "submodules/Postbox/Sources/MediaResourceStatus.swift",
        "submodules/Postbox/Sources/MediaBoxFileContext.swift",
        "submodules/Postbox/Sources/MediaBoxFileMap.swift",
        "submodules/Postbox/Sources/MediaBoxFileContextV2Impl.swift",
    )]
    with tempfile.TemporaryDirectory(prefix="supergram-media-regression-") as directory:
        directory = Path(directory)
        source = directory / "main.swift"
        source.write_text("\n\n".join(strip_imports(path.read_text()) for path in paths) + "\n\n" + fixture)
        binary = directory / "media-regressions"
        result = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-lz", str(source), "-o", str(binary)], capture_output=True, text=True)
        if result.returncode:
            print(result.stdout)
            print(result.stderr)
            raise SystemExit(result.returncode)
        subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    main()
