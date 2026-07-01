#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

CONFIG_PATH="${SWIFTLINT_CONFIG:-.swiftlint.yml}"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint is not installed. Install it with: brew install swiftlint" >&2
  exit 127
fi

if [ ! -f "$CONFIG_PATH" ]; then
  echo "missing SwiftLint config: $CONFIG_PATH" >&2
  exit 2
fi

run_path() {
  file="$1"
  [ -f "$file" ] || return 0
  case "$file" in
    *.swift)
      echo "swiftlint: $file"
      swiftlint lint --config "$CONFIG_PATH" --quiet "$file"
      ;;
  esac
}

mode="${1:-changed}"

case "$mode" in
  changed)
    files="$(
      {
        git diff --name-only --diff-filter=ACMRT -- '*.swift'
        git ls-files --others --exclude-standard -- '*.swift'
      } | sort -u
    )"
    if [ -z "$files" ]; then
      echo "No changed Swift files to lint."
      exit 0
    fi
    echo "$files" | while IFS= read -r file; do
      run_path "$file"
    done
    ;;
  --all)
    swiftlint lint --config "$CONFIG_PATH" --quiet
    ;;
  --path)
    shift
    if [ "$#" -eq 0 ]; then
      echo "usage: $0 --path file.swift [file2.swift ...]" >&2
      exit 2
    fi
    for file in "$@"; do
      run_path "$file"
    done
    ;;
  *)
    echo "usage: $0 [changed|--all|--path file.swift ...]" >&2
    exit 2
    ;;
esac
