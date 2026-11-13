#!/usr/bin/env python3
"""Probe actual cache-map allocation guards without making large allocations.

The only inserted reader seam records and throws immediately before Data(count:).
Files are sparse; their headers occupy a few bytes. The writer count guard is
executed unchanged with a count double, avoiding a half-million-range fixture.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--baseline-dir", type=Path)
parser.add_argument("--expect-failure", action="store_true")
parser.add_argument("--case", choices=["all", "huge"], default="all")
args = parser.parse_args()
map_source = ((args.baseline_dir if args.baseline_dir else ROOT) / "submodules/Postbox/Sources/MediaBoxFileMap.swift").read_text()
allocation = "var data = Data(count: Int(payloadLength))"
assert map_source.count(allocation) == 2
map_source = map_source.replace(allocation, "if AllocationProbe.enabled { AllocationProbe.requested = Int(payloadLength); throw FileMapError.generic }\n                " + allocation)
writer_guard_match = re.search(r"guard rangeView.count <= .*?\n\s*}", map_source, re.S)
writer_guard = writer_guard_match.group(0) if writer_guard_match else ""
budget_match = re.search(r"maxSerializedPayloadLength: Int64 = ([^\n]+)", map_source)
budget = budget_match.group(1) if budget_match else "8 * 1024 * 1024"
fixture = (HERE / "media_fetch_regressions.swift").read_text().split("// PRODUCTION_MEDIA_TYPES", 1)[0]
fixture += (HERE / "cache_map_budget_regression.swift").read_text().replace("// ACTUAL_WRITER_GUARD", writer_guard).replace("// ACTUAL_BUDGET", budget)
paths = sorted((ROOT / "submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"))
paths += sorted((ROOT / "submodules/Utils/RangeSet/Sources").glob("*.swift"))
paths += [ROOT / p for p in ["submodules/ManagedFile/Sources/ManagedFile.swift", "submodules/Postbox/Sources/MediaBoxFileManager.swift", "submodules/Postbox/Sources/FileSize.swift"]]
def strip(source):
    return re.sub(r"^import (SwiftSignalKit|ManagedFile|RangeSet|Crc32)\n", "", source, flags=re.M)
with tempfile.TemporaryDirectory(prefix="supergram-map-budget-") as temporary:
    source = Path(temporary) / "main.swift"
    binary = Path(temporary) / "regressions"
    source.write_text("\n".join(strip(p.read_text()) for p in paths) + "\n" + strip(map_source) + "\n" + fixture)
    result = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-lz", str(source), "-o", str(binary)], capture_output=True, text=True)
    if result.returncode:
        print(result.stderr)
        raise SystemExit(result.returncode)
    result = subprocess.run([str(binary), args.case], capture_output=True, text=True, timeout=30)
    if args.expect_failure:
        if not result.returncode: raise SystemExit("Expected pre-fix allocation reachability was not reproduced")
        failure = next((line for line in result.stderr.splitlines() if "failed" in line or "Failure" in line), "child terminated")
        print(f"PASS: pre-fix map allocation reached intercepted allocation (exit {result.returncode}): {failure}")
    else:
        print(result.stdout, end="")
        if result.returncode: print(result.stderr)
        raise SystemExit(result.returncode)
