#!/usr/bin/env python3
"""Group compiler errors from a Bazel build log by module.

Usage: scripts/supergram/build_errors.py <log> [max-errors-per-group]
Prints JSON: {"logPath": ..., "groups": [{"name": ..., "errors": [...]}]}
"""
import json
import re
import sys

log_path = sys.argv[1]
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 60
repo = "/Users/fackeuser/Documents/Telegram/"

error_re = re.compile(r"^(?P<path>[^\s:]+\.(?:swift|m|mm|h|c|cc|cpp)):(?P<line>\d+):(?P<col>\d+): error: (?P<msg>.*)$")
target_re = re.compile(r"^ERROR: (?P<path>\S+?/BUILD(?:\.bazel)?):\d+:\d+: (?P<msg>.*)$")

groups = {}
seen = set()


def module_of(path):
    path = path.replace(repo, "")
    for marker in ("/Sources/", "/Source/", "/PublicHeaders/"):
        if marker in path:
            return path.split(marker)[0]
    return "/".join(path.split("/")[:3])


with open(log_path, errors="replace") as log:
    for raw in log:
        line = raw.rstrip("\n")
        match = error_re.match(line.replace(repo, ""))
        if match:
            path = match.group("path")
            key = (path, match.group("line"), match.group("msg"))
            if key in seen:
                continue
            seen.add(key)
            groups.setdefault(module_of(path), []).append(f"{path}:{match.group('line')}:{match.group('col')}: {match.group('msg')}")
            continue
        match = target_re.match(line.replace(repo, ""))
        if match and "Build did NOT complete" not in line:
            msg = match.group("msg")
            if "Compiling Swift module" in msg or "error executing" in msg:
                continue
            key = (match.group("path"), msg)
            if key in seen:
                continue
            seen.add(key)
            groups.setdefault(match.group("path").rsplit("/", 1)[0], []).append(f"{match.group('path')}: {msg}")

result = {
    "logPath": log_path,
    "groups": [{"name": name, "errors": errors[:limit]} for name, errors in sorted(groups.items())],
}
print(json.dumps(result, ensure_ascii=False, indent=1))
