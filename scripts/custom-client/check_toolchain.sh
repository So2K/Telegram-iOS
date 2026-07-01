#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."

python3 - <<'PY'
import json
import hashlib
import os
import platform
import shutil
import subprocess
from pathlib import Path

required = json.loads(Path("versions.json").read_text())
bazel_requirement = required.get("bazel") or ""
bazel_version, _, bazel_sha256 = bazel_requirement.partition(":")
bazel_arch = "darwin-arm64" if platform.machine() == "arm64" else "darwin-x86_64"
local_bazel_path = Path("build-input") / f"bazel-{bazel_version}-{bazel_arch}"

def run(cmd):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True).strip()
    except FileNotFoundError:
        return None
    except subprocess.CalledProcessError as error:
        return error.output.strip()

xcode_output = run(["xcodebuild", "-version"])
bazel_output = run(["bazel", "--version"])
bazel_source = "PATH"
local_bazel_valid = False
if not bazel_output and local_bazel_path.exists() and os.access(local_bazel_path, os.X_OK):
    if bazel_sha256:
        digest = hashlib.sha256(local_bazel_path.read_bytes()).hexdigest()
        if digest == bazel_sha256:
            bazel_output = run([str(local_bazel_path), "--version"])
            bazel_source = str(local_bazel_path)
            local_bazel_valid = True
        else:
            bazel_output = f"sha256 mismatch for {local_bazel_path}: {digest}"
            bazel_source = "invalid local build-input"
    else:
        bazel_output = run([str(local_bazel_path), "--version"])
        bazel_source = str(local_bazel_path)
        local_bazel_valid = True
xcode_version = None
if xcode_output:
    for line in xcode_output.splitlines():
        if line.startswith("Xcode "):
            xcode_version = line.split(" ", 1)[1].strip()
            break

print("# Toolchain Check")
print(f"required_xcode={required.get('xcode')}")
print(f"required_bazel={required.get('bazel')}")
print(f"required_macos={required.get('macos')}")
print()

if xcode_output:
    print("xcodebuild:")
    print(xcode_output)
else:
    print("xcodebuild: missing")

print()
if bazel_output:
    print(f"bazel ({bazel_source}):")
    print(bazel_output)
else:
    print("bazel: missing")

print()
print("git:")
print(run(["git", "status", "--short", "--branch"]) or "")

missing = []
if not xcode_output:
    missing.append("xcodebuild")
elif xcode_version != required.get("xcode"):
    missing.append(f"xcode:{xcode_version}")
if not shutil.which("bazel") and not local_bazel_valid:
    missing.append("bazel")

if missing:
    print()
    print("blocked_by=" + ",".join(missing))
    raise SystemExit(1)
PY
