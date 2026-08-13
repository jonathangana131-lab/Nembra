#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$ROOT"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

EXPECTED_SOURCE_SHA="${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}"
[[ "$EXPECTED_SOURCE_SHA" =~ ^[0-9A-Fa-f]{40}$ ]] || die "Pass the exact software-accepted Capture source SHA (40 hex characters)."
EXPECTED_SOURCE_SHA="$(printf '%s' "$EXPECTED_SOURCE_SHA" | tr '[:upper:]' '[:lower:]')"

SOURCE_SHA="$(GIT_NO_REPLACE_OBJECTS=1 git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]] || die "Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Working tree has local changes. Commit or stash them before field admission."

# Resolve critical field-admission inputs from the accepted Git tree itself.
# This catches a missing/replaced script before CocoaPods, signing, device
# discovery, or any private field material is touched.
REQUIRED_PATHS=(
  "scripts/field/install_one_time_capture.command"
  "scripts/ci/es80_signed_field_artifact_private_runner.py"
  "Scripts/bootstrap_capture_tuya_sdk.sh"
  "Scripts/capture_tuya_private_input_provenance.py"
  "Scripts/capture_tuya_private_input_build_guard.py"
  "NembraCapture.xcodeproj/project.pbxproj"
)

for path in "${REQUIRED_PATHS[@]}"; do
  blob="$(GIT_NO_REPLACE_OBJECTS=1 git rev-parse "$SOURCE_SHA:$path" 2>/dev/null)" || die "Accepted Capture source is missing required field input: $path"
  [[ "$blob" =~ ^[0-9a-f]{40}$ ]] || die "Accepted Git object identity is malformed for: $path"
  type="$(GIT_NO_REPLACE_OBJECTS=1 git cat-file -t "$blob" 2>/dev/null)" || die "Could not inspect accepted Git object for: $path"
  [[ "$type" == "blob" ]] || die "Required field input is not an accepted Git blob: $path"
done

say "Capture field source preflight passed"
printf 'Accepted source: %s\n' "$SOURCE_SHA"
printf 'Critical field inputs: %s\n' "${#REQUIRED_PATHS[@]} accepted Git blobs"
printf 'Private inputs touched: no\n'
printf 'Device/signing state touched: no\n'
