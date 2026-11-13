#!/usr/bin/env python3
"""Run FetchV2 CDN verification and callback bodies with real SHA-256.

Time/network responses are deterministic doubles. Verification, hash response
classification, retry scheduling and range commit bodies are actual source.
No application build target, device or account is used.
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
parser.add_argument("--case", default="all", choices=["all", "tail", "mismatch", "offtarget", "late", "bounds"])
parser.add_argument("--expect-failure", action="store_true")
args = parser.parse_args()
relative = "submodules/TelegramCore/Sources/Network/FetchV2.swift"
source = ((args.baseline_dir / relative) if args.baseline_dir else ROOT / relative).read_text()

def block(marker, text=source):
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        if text[end] == "{": depth += 1
        elif text[end] == "}": depth -= 1
        end += 1
    return text[start:end]

def between(first, last, text=source):
    return text.split(first, 1)[1].split(last, 1)[0]

fixture = (HERE / "cdn_integrity_regressions.swift").read_text()
fixture = fixture.replace("// READY_TYPE", block("private final class PendingReadyPart").replace("private ", ""))
fixture = fixture.replace("// HASH_TYPE", block("private final class HashRangeData").replace("private ", ""))
fixture = fixture.replace("// RETRY_LIMIT", re.search(r"maxConsecutiveFailures: Int = (\d+)", source).group(1))
fixture = fixture.replace("// VERIFY", block("do {\n                    var removedPendingReadyPartIndices"))
fixture = fixture.replace("// REQUIRED_HASH_RANGES", "var requiredHashRanges = RangeSet<Int64>()" + between("var requiredHashRanges = RangeSet<Int64>()", "let expectedHashRangeLength"))
fixture = fixture.replace("// RETRY", block("private func scheduleRetryAfterFailure()"))
fixture = fixture.replace("// COMMIT", block("private func commitPendingReadyPart"))
hash_function = block("private func fetchHashRange")
hash_callback = block("queue.async {", hash_function)
fixture = fixture.replace("// HASH_CALLBACK", hash_callback[len("queue.async {"):-1])
validator = block("private func validatedHashRanges") if "private func validatedHashRanges" in source else "private func validatedHashRanges(_ result: [Api.FileHash]?, requiredOffset: Int64) -> [HashRangeData]? { return nil }"
fixture = fixture.replace("// HASH_VALIDATOR", validator)
part_function = block("private func fetchPart")
part_callback = between(".startStrict(next: { [weak self, weak state, weak part] result in", "// SuperGram: only a response", part_function)
fixture = fixture.replace("// PART_IDENTITY", part_callback)
fixture = fixture.replace("// DATA_CLASSIFICATION", between("case let .data(data, verifyPartHashData):", "case let .cdnRedirect(cdnData):"))
range_sources = sorted((ROOT / "submodules/Utils/RangeSet/Sources").glob("*.swift"))
with tempfile.TemporaryDirectory(prefix="supergram-cdn-integrity-") as temporary:
    main = Path(temporary) / "main.swift"
    binary = Path(temporary) / "regressions"
    main.write_text("\n".join(p.read_text() for p in range_sources) + "\n" + fixture)
    compiled = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(main), "-o", str(binary)], capture_output=True, text=True)
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
        if result.returncode: print(result.stderr)
        raise SystemExit(result.returncode)
