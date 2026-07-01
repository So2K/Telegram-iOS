#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_PATH="${1:-docs/custom-client/full-static-audit.md}"
TMP_OUTPUT="$(mktemp "${OUTPUT_PATH}.XXXXXX")"
TMP_COMMAND="$(mktemp)"
trap 'rm -f "$TMP_OUTPUT" "$TMP_COMMAND"' EXIT

append() {
  printf '%s\n' "$*" >> "$TMP_OUTPUT"
}

append_command() {
  title="$1"
  shift
  append "## $title"
  append
  append '```'
  set +e
  "$@" > "$TMP_COMMAND" 2>&1
  status="$?"
  set -e
  sed -n '1,260p' "$TMP_COMMAND" >> "$TMP_OUTPUT"
  total_lines="$(wc -l < "$TMP_COMMAND" | tr -d ' ')"
  if [ "$total_lines" -gt 260 ]; then
    append "... output truncated; total lines: $total_lines"
  fi
  append "exit_status=$status"
  append '```'
  append
}

swift_files="$(git ls-files '*.swift' | wc -l | tr -d ' ')"
changed_swift_files="$(
  {
    git diff --name-only --diff-filter=ACMRT -- '*.swift'
    git ls-files --others --exclude-standard -- '*.swift'
  } | sort -u | wc -l | tr -d ' '
)"

append "# Full Static Audit"
append
append "Generated UTC: \`$(date -u '+%Y-%m-%dT%H:%M:%SZ')\`"
append "Branch: \`$(git rev-parse --abbrev-ref HEAD)\`"
append "Commit: \`$(git rev-parse --short HEAD)\`"
append "Tracked Swift files: \`$swift_files\`"
append "Changed/untracked Swift files: \`$changed_swift_files\`"
append

append_command "Toolchain" scripts/custom-client/check_toolchain.sh
append_command "Changed-File Crash-Risk Gate" scripts/custom-client/run_crash_risk_scan.sh
append_command "Repository-Wide Crash-Risk Inventory" scripts/custom-client/run_crash_risk_scan.sh --all
append_command "Changed-File SwiftLint Gate" scripts/custom-client/run_static_analysis.sh
append_command "Configured SwiftLint Module Pass" scripts/custom-client/run_static_analysis.sh --all
append_command "Whitespace Check" git diff --check

mv "$TMP_OUTPUT" "$OUTPUT_PATH"
trap - EXIT
rm -f "$TMP_COMMAND"
