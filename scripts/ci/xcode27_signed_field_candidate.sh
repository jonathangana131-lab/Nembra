#!/bin/bash
set -euo pipefail

# Produce one exact signed iOS Nembra Capture field-build CANDIDATE.
# This script can measure and retain a signed installable, but it cannot authorize physical ES80
# Experiment One. Final field authority remains a separate independently signed acceptance step.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Signed iOS field-candidate production requires macOS." >&2
  exit 2
fi

: "${NEMBRA_DEVELOPMENT_TEAM:?Set NEMBRA_DEVELOPMENT_TEAM to the Apple signing TeamIdentifier.}"
: "${NEMBRA_EXPORT_OPTIONS_PLIST:?Set NEMBRA_EXPORT_OPTIONS_PLIST to an existing Xcode export-options plist.}"

if [[ ! "$NEMBRA_DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "NEMBRA_DEVELOPMENT_TEAM must be one canonical 10-character Apple TeamIdentifier." >&2
  exit 3
fi

resolve_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
}

EXPORT_OPTIONS_PLIST="$(resolve_path "$NEMBRA_EXPORT_OPTIONS_PLIST")"
if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  echo "NEMBRA_EXPORT_OPTIONS_PLIST does not name an existing file." >&2
  exit 4
fi
/usr/bin/plutil -lint "$EXPORT_OPTIONS_PLIST" >/dev/null

SOURCE_SHA="$(git rev-parse --verify HEAD^{commit})"
if [[ ! "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Could not derive one exact lowercase 40-hex Git HEAD." >&2
  exit 5
fi

# A clean worktree is not enough if another process moves HEAD during a long archive/sign/export.
# Every admission samples HEAD on both sides of the status check and requires the exact source SHA
# captured before the build. This prevents a clean concurrent checkout from changing either source
# inputs or the verifier implementation while still appearing pristine.
require_exact_clean_source() {
  local phase="$1"
  local head_before
  local head_after
  local status

  head_before="$(git rev-parse --verify HEAD^{commit})"
  status="$(git status --porcelain=v1 --untracked-files=all)"
  head_after="$(git rev-parse --verify HEAD^{commit})"

  if [[ "$head_before" != "$SOURCE_SHA" || "$head_after" != "$SOURCE_SHA" ]]; then
    echo "Signed field-candidate source HEAD changed during $phase." >&2
    printf 'expected=%s before=%s after=%s\n' "$SOURCE_SHA" "$head_before" "$head_after" >&2
    exit 6
  fi
  if [[ -n "$status" ]]; then
    echo "Signed field-candidate production requires a pristine exact checkout during $phase." >&2
    printf '%s\n' "$status" >&2
    exit 7
  fi
}

require_exact_clean_source "initial source admission"

BUILD_IDENTIFIER="Capture Build V14-${SOURCE_SHA:0:12}"
BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
if [[ ! "$BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Generated build-instance ID is not canonical lowercase UUID text." >&2
  exit 8
fi

WORK_ROOT="$(resolve_path "${RUNNER_TEMP:-/tmp}/NembraES80FieldCandidate-${SOURCE_SHA:0:12}-${BUILD_INSTANCE_ID}")"
ARCHIVE_PATH="$WORK_ROOT/Nembra.xcarchive"
EXPORT_DIR="$WORK_ROOT/export"
ARTIFACTS_DIR="$(resolve_path "${ARTIFACTS_DIR:-$ROOT/artifacts/Xcode27FieldCandidate}")"

# Generated state may live outside the checkout, or under a path that Git already ignores. Never
# allow the repository root itself as an output target. That would let evidence generation dirty the
# exact source checkout after preflight and make later source admission ambiguous.
require_safe_generated_path() {
  local path="$1"
  local label="$2"

  if [[ "$path" == "$ROOT" ]]; then
    echo "$label must not be the repository root." >&2
    exit 9
  fi
  if [[ "$path" == "$ROOT"/* ]]; then
    local relative_path="${path#"$ROOT"/}"
    if ! git check-ignore -q -- "$relative_path"; then
      echo "$label inside the repository must already be ignored by Git: $relative_path" >&2
      exit 10
    fi
  fi
}

require_safe_generated_path "$WORK_ROOT" "WORK_ROOT"
require_safe_generated_path "$ARTIFACTS_DIR" "ARTIFACTS_DIR"

rm -rf "$WORK_ROOT"
mkdir -p "$EXPORT_DIR"

PROVISIONING_ARGS=()
if [[ "${NEMBRA_ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
  PROVISIONING_ARGS+=("-allowProvisioningUpdates")
fi

xcodebuild \
  -project Nembra.xcodeproj \
  -scheme Nembra \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  "${PROVISIONING_ARGS[@]}" \
  "DEVELOPMENT_TEAM=$NEMBRA_DEVELOPMENT_TEAM" \
  "INFOPLIST_KEY_NembraCaptureBuildIdentifier=$BUILD_IDENTIFIER" \
  "INFOPLIST_KEY_NembraCaptureBuildInstanceID=$BUILD_INSTANCE_ID" \
  "INFOPLIST_KEY_NembraCaptureBuildCommitSHA=$SOURCE_SHA" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  "${PROVISIONING_ARGS[@]}"

# Re-prove both immutable source identity and cleanliness before the post-build evidence owner runs.
# In particular, do not let a different clean checkout supply the verifier for bytes built earlier.
require_exact_clean_source "post archive/export admission"

shopt -s nullglob
IPA_FILES=("$EXPORT_DIR"/*.ipa)
shopt -u nullglob
if [[ "${#IPA_FILES[@]}" -ne 1 ]]; then
  echo "Expected exactly one exported .ipa; found ${#IPA_FILES[@]}." >&2
  printf '%s\n' "${IPA_FILES[@]:-}" >&2
  exit 11
fi
IPA_PATH="${IPA_FILES[0]}"

# Reuse the flagship's single canonical post-build evidence owner. It opens the exact final IPA,
# rejects ambiguous/unsafe archive topology, requires real iphoneos metadata, verifies code signing,
# hashes and retains the final IPA/executable/Info.plist bytes, and emits schema-v3 + companion
# evidence. It still does not mint GO authority.
python3 scripts/ci/es80_signed_field_artifact_evidence.py \
  --ipa "$IPA_PATH" \
  --expected-source-sha "$SOURCE_SHA" \
  --output-dir "$ARTIFACTS_DIR"

FIELD_RECORD="$ARTIFACTS_DIR/NembraCaptureSignedFieldArtifactEvidence.json"
python3 - "$FIELD_RECORD" "$SOURCE_SHA" "$BUILD_IDENTIFIER" "$BUILD_INSTANCE_ID" "$NEMBRA_DEVELOPMENT_TEAM" <<'PY'
import json
from pathlib import Path
import sys

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected = {
    "authority": "signed-field-artifact-evidence-not-field-authorization",
    "sourceCommitSHA": sys.argv[2],
    "buildIdentifier": sys.argv[3],
    "buildInstanceID": sys.argv[4],
    "teamIdentifier": sys.argv[5],
    "experimentRecipeID": "ES80-FINGERPRINT-v1",
    "procedureVersion": "V14",
}
for key, value in expected.items():
    if record.get(key) != value:
        raise SystemExit(
            f"Signed-field evidence mismatch for {key}: {record.get(key)!r} != {value!r}"
        )
PY

{
  echo "source_commit_sha=$SOURCE_SHA"
  echo "build_identifier=$BUILD_IDENTIFIER"
  echo "build_instance_id=$BUILD_INSTANCE_ID"
  echo "development_team=$NEMBRA_DEVELOPMENT_TEAM"
  echo "experiment_recipe_id=ES80-FINGERPRINT-v1"
  echo "procedure_version=V14"
  echo "authority=signed-field-artifact-evidence-not-field-authorization"
  xcodebuild -version
} > "$ARTIFACTS_DIR/field-candidate-environment.txt"

# The evidence producer may write only to the admitted ignored/external target. Re-check exact HEAD
# after all post-build evidence work so a concurrent clean checkout cannot escape detection at the
# last authority boundary either.
require_exact_clean_source "post evidence admission"

echo "Signed Nembra iOS field-build CANDIDATE retained at: $ARTIFACTS_DIR"
echo "Independent acceptance has NOT occurred."
echo "PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN."
