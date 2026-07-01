#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep is required for crash-risk scan" >&2
  exit 127
fi

mode="${1:-changed}"

collect_changed_files() {
  {
    git diff --name-only --diff-filter=ACMRT -- '*.swift'
    git ls-files --others --exclude-standard -- '*.swift'
  } | sort -u
}

collect_all_files() {
  git ls-files -- '*.swift'
}

collect_path_files() {
  for file in "$@"; do
    case "$file" in
      *.swift)
        [ -f "$file" ] && printf '%s\n' "$file"
        ;;
    esac
  done
}

case "$mode" in
  changed)
    files="$(collect_changed_files)"
    ;;
  --all)
    files="$(collect_all_files)"
    ;;
  --path)
    shift
    if [ "$#" -eq 0 ]; then
      echo "usage: $0 --path file.swift [file2.swift ...]" >&2
      exit 2
    fi
    files="$(collect_path_files "$@")"
    ;;
  *)
    echo "usage: $0 [changed|--all|--path file.swift ...]" >&2
    exit 2
    ;;
esac

if [ -z "$files" ]; then
  echo "No Swift files to scan."
  exit 0
fi

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT
printf '%s\n' "$files" > "$tmp_file"

patterns='try!|cgImage!|baseAddress!|userData!|imageBuffer!|sampleBuffer!|cachedTexture!|as! NSString|as! NSMutableDictionary|malloc\([^)]*\)!|frame\.data\[[0-3]\]!|CVPixelBufferGetBaseAddress[^)]*\)!|attachments\[0\]|touches\.first!|CGGradient\([^)]*\)!|UIGraphicsGetCurrentContext\(\)!|UIGraphicsGetImageFromCurrentImageContext\(\)!'

matches="$(
  while IFS= read -r file; do
    rg -n --with-filename --no-heading "$patterns" "$file" || true
  done < "$tmp_file"
)"

if [ -n "$matches" ]; then
  echo "Crash-risk scan found force-unwrap patterns at C/media/payload/error boundaries:" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

echo "Crash-risk scan passed."
