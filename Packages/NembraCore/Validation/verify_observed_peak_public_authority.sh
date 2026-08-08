#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_PATH="$(swift build --package-path "$PACKAGE_ROOT" --show-bin-path)"
MODULES_DIR="$BIN_PATH/Modules"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

compile_must_fail_for_access_control() {
  local name="$1"
  local source="$2"
  local file="$TMP_DIR/$name.swift"
  local output="$TMP_DIR/$name.log"

  printf '%s\n' "$source" > "$file"

  set +e
  swiftc -typecheck -I "$MODULES_DIR" "$file" >"$output" 2>&1
  local status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    echo "ERROR: external probe '$name' unexpectedly compiled; durable observed-peak authority leaked into public API." >&2
    cat "$output" >&2
    exit 1
  fi

  if ! grep -Eq "inaccessible|internal|protection level" "$output"; then
    echo "ERROR: external probe '$name' failed for an unexpected reason; this does not prove the intended access boundary." >&2
    cat "$output" >&2
    exit 1
  fi

  echo "PASS: external probe '$name' is denied by Swift access control."
}

compile_must_fail_for_access_control \
  evidence_assessment \
  $'import NembraCore\n\nfunc attempt(_ evidence: RideObservedPeakHistoryEvidence) {\n    _ = try? evidence.assessment()\n}'

compile_must_fail_for_access_control \
  joined_assessment \
  $'import NembraCore\n\nfunc attempt(_ joined: RideHistoryObservedPeakJoinedRecord) {\n    _ = try? joined.assessment()\n}'

compile_must_fail_for_access_control \
  assessment_type \
  $'import NembraCore\n\nfunc attempt() {\n    _ = RideObservedPeakHistoryAssessment.self\n}'

echo "Observed-peak durable eligibility remains module-owned; public Codable evidence is descriptive only."
