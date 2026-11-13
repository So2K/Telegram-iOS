#!/usr/bin/env python3
"""Execute actual public MediaBox cache/representation methods with real I/O.

Filesystem, SwiftSignalKit and file contexts are production sources. Only path
layout, unrelated account/cache services and representation producers are
controlled fixtures. Saved pre-pass MediaBox sources can be replayed safely.
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
parser.add_argument("--expect-failure", action="store_true")
parser.add_argument("--case", choices=["all", "admission", "alias", "failure", "lifecycle", "store", "store-failure", "store-write", "store-temp", "move"], default="all")
args = parser.parse_args()
base = args.baseline_dir or ROOT
media = (base / "submodules/Postbox/Sources/MediaBox.swift").read_text()

def block(marker, text=media):
    start = text.index(marker)
    if marker.startswith("public func ") or marker.startswith("private func "):
        # Default closure arguments are inside the parameter list, not the body.
        opening = text.index("(", start)
        position, parameter_depth = opening + 1, 1
        while parameter_depth:
            parameter_depth += (text[position] == "(") - (text[position] == ")")
            position += 1
        opening = text.index("{", position)
    else:
        opening = text.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]

def strip(source):
    return re.sub(r"^import (SwiftSignalKit|ManagedFile|RangeSet|Crc32)\n", "", source, flags=re.M)

fixture = (HERE / "media_fetch_regressions.swift").read_text().split("// PRODUCTION_MEDIA_TYPES", 1)[0]
fixture = fixture.replace("func update(id: Data, size: Int64) {}", "var updatedSizes: [Int64] = []; func update(id: Data, size: Int64) { updatedSizes.append(size) }")
fixture += "public struct ResourceStorePaths" + media.split("public struct ResourceStorePaths", 1)[1].split("private final class MediaBoxKeepResourceContext", 1)[0]
fixture += (HERE / "media_box_publication_regression.swift").read_text()
methods = ["public func completedResourcePath(id:", "public func resourceData(id: MediaResourceId, pathExtension:", "public func cachedResourceRepresentation(", "public func customResourceData(",
    "public func storeCachedResourceRepresentation(_ resource: MediaResource, representation:",
    "public func storeCachedResourceRepresentation(_ resource: MediaResource, representationId:",
    "public func storeCachedResourceRepresentation(_ resourceId: String, representationId: String, keepDuration: CachedMediaRepresentationKeepDuration, data:",
    "public func storeCachedResourceRepresentation(_ resourceId: String, representationId: String, keepDuration: CachedMediaRepresentationKeepDuration, tempFile:",
    "public func moveResourceData(from:"]
production = "\n".join(block(marker) for marker in methods)
if "private func finishFailedRepresentation" in media:
    production += "\n" + block("private func finishFailedRepresentation")
fixture = fixture.replace("// ACTUAL_PUBLIC_METHODS", production)
callback = block("context.disposable.set(signal.startStrict(next:", block("public func customResourceData("))
callback_body = callback.split(" next in", 1)[1].rsplit("}", 1)[0]
fixture = fixture.replace("// ACTUAL_RETIRED_CALLBACK", callback_body)
paths = sorted((ROOT / "submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"))
paths += sorted((ROOT / "submodules/Utils/RangeSet/Sources").glob("*.swift"))
paths += [ROOT / p for p in ["submodules/ManagedFile/Sources/ManagedFile.swift", "submodules/Postbox/Sources/MediaBoxFileManager.swift", "submodules/Postbox/Sources/FileSize.swift", "submodules/Postbox/Sources/MediaResourceStatus.swift", "submodules/Postbox/Sources/MediaBoxFileContext.swift", "submodules/Postbox/Sources/MediaBoxFileMap.swift", "submodules/Postbox/Sources/MediaBoxFileContextV2Impl.swift"]]
with tempfile.TemporaryDirectory(prefix="supergram-publication-") as temporary:
    main = Path(temporary) / "main.swift"
    binary = Path(temporary) / "regressions"
    main.write_text("\n".join(strip(p.read_text()) for p in paths) + "\n" + fixture)
    compiled = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-lz", str(main), "-o", str(binary)], capture_output=True, text=True)
    if compiled.returncode:
        print(compiled.stderr)
        raise SystemExit(compiled.returncode)
    result = subprocess.run([str(binary), args.case], capture_output=True, text=True, timeout=45)
    if args.expect_failure:
        if not result.returncode: raise SystemExit("Expected pre-fix public cache failure was not reproduced")
        failure = next((line for line in result.stderr.splitlines() if "failed" in line or "Failure" in line), "child terminated")
        print(f"PASS: pre-fix public {args.case} reproduced (exit {result.returncode}): {failure}")
    else:
        print(result.stdout, end="")
        if result.returncode: print(result.stderr)
        raise SystemExit(result.returncode)
