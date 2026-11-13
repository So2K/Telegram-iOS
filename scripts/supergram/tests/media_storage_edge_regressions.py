#!/usr/bin/env python3
"""Exercise new storage failures using actual Postbox and real local file I/O.

The optional baseline directory contains saved pre-fix sources. File-size limits
are changed only inside the test child and restored before teardown. No device,
account, download, build target, or host filesystem limit is changed.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--baseline-dir", type=Path)
parser.add_argument("--case", default="all", choices=["all", "link", "admission", "invalid", "write", "map", "coverage", "tail"])
parser.add_argument("--expect-failure", action="store_true")
args = parser.parse_args()

def path(name):
    candidate = args.baseline_dir / name if args.baseline_dir else None
    return candidate if candidate and candidate.exists() else ROOT / name

def read(name):
    return path(name).read_text()

def between(source, first, last):
    return source.split(first, 1)[1].split(last, 1)[0]

def strip_imports(source):
    return re.sub(r"^import (SwiftSignalKit|ManagedFile|RangeSet|Crc32)\n", "", source, flags=re.M)

fetch = read("submodules/TelegramCore/Sources/Network/FetchV2.swift")
manager = read("submodules/FetchManagerImpl/Sources/FetchManagerImpl.swift")
media_box = read("submodules/Postbox/Sources/MediaBox.swift")
# Reuse existing service doubles and fixture utilities, but execute only new cases.
fixture = (HERE / "media_fetch_regressions.swift").read_text().rsplit("try testFileMaps()", 1)[0]
fixture += (HERE / "media_storage_edge_regressions.swift").read_text()
fixture = fixture.replace("// PRODUCTION_MEDIA_TYPES", "public struct MediaResourceData" + between(media_box, "public struct MediaResourceData", "public enum CachedMediaResourceRepresentationResult"))
fixture = fixture.replace("// PRODUCTION_ATTEMPT_TYPES", "private final class FetchManagerFetchAttempt" + between(manager, "private final class FetchManagerFetchAttempt", "// SuperGram: how many entries"))
fixture = fixture.replace("// PRODUCTION_ATTEMPT_CHECK", "func isCurrentFetchAttempt" + between(manager, "func isCurrentFetchAttempt", "    func handleEntryFetchFailed"))
fixture = fixture.replace("// PRODUCTION_DATA_BRANCH", between(fetch, "case let .data(data, verifyPartHashData):", "case let .cdnRedirect(cdnData):"))
fixture = fixture.replace("// PRODUCTION_RETRY\n", "private func scheduleRetryAfterFailure()" + between(fetch, "private func scheduleRetryAfterFailure()", "        private func update()"))
fixture = fixture.replace("// PRODUCTION_COMMIT", "private func commitPendingReadyPart" + between(fetch, "private func commitPendingReadyPart", "        private func processFloodWaitError"))
fixture = fixture.replace("// PRODUCTION_RETRY_LIMIT", re.search(r"private static let maxConsecutiveFailures: Int = (\d+)", fetch).group(1))
paths = sorted((ROOT / "submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"))
paths += sorted((ROOT / "submodules/Utils/RangeSet/Sources").glob("*.swift"))
paths += [path(name) for name in ["submodules/ManagedFile/Sources/ManagedFile.swift", "submodules/Postbox/Sources/MediaBoxFileManager.swift", "submodules/Postbox/Sources/FileSize.swift", "submodules/Postbox/Sources/MediaResourceStatus.swift", "submodules/Postbox/Sources/MediaBoxFileContext.swift", "submodules/Postbox/Sources/MediaBoxFileMap.swift", "submodules/Postbox/Sources/MediaBoxFileContextV2Impl.swift"]]
with tempfile.TemporaryDirectory(prefix="supergram-storage-edge-") as temporary:
    source = Path(temporary) / "main.swift"
    binary = Path(temporary) / "regressions"
    source.write_text("\n\n".join(strip_imports(p.read_text()) for p in paths) + "\n" + fixture)
    compiled = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-lz", str(source), "-o", str(binary)], capture_output=True, text=True)
    if compiled.returncode:
        print(compiled.stderr)
        raise SystemExit(compiled.returncode)
    result = subprocess.run([str(binary), args.case], capture_output=True, text=True, timeout=30)
    if args.expect_failure:
        if not result.returncode:
            raise SystemExit("Expected pre-fix failure was not reproduced")
        failure = next((line for line in result.stderr.splitlines() if "failed" in line or "Failure" in line), "child terminated")
        print(f"PASS: pre-fix {args.case} reproduced (exit {result.returncode}): {failure}")
    else:
        print(result.stdout, end="")
        if result.returncode:
            print(result.stderr)
        raise SystemExit(result.returncode)
