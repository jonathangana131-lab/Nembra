#!/bin/bash
set -euo pipefail

# Produce one exact signed iOS Nembra Capture field-build CANDIDATE.
# This script cannot authorize physical ES80 Experiment One.

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
if [[ ! -f "$NEMBRA_EXPORT_OPTIONS_PLIST" ]]; then
  echo "NEMBRA_EXPORT_OPTIONS_PLIST does not name an existing file." >&2
  exit 4
fi
/usr/bin/plutil -lint "$NEMBRA_EXPORT_OPTIONS_PLIST" >/dev/null

# Exact source identity is captured before any build output exists.
REPOSITORY_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$REPOSITORY_STATUS" ]]; then
  echo "Signed field-candidate production refuses tracked changes or non-ignored untracked files." >&2
  printf '%s\n' "$REPOSITORY_STATUS" >&2
  exit 5
fi

SOURCE_SHA="$(git rev-parse --verify HEAD^{commit})"
if [[ ! "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Could not derive one exact lowercase 40-hex Git HEAD." >&2
  exit 6
fi

BUILD_IDENTIFIER="Capture Field V14-${SOURCE_SHA:0:12}"
BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
if [[ ! "$BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Generated build-instance ID is not canonical lowercase UUID text." >&2
  exit 7
fi

WORK_ROOT="${RUNNER_TEMP:-/tmp}/NembraES80FieldCandidate-${SOURCE_SHA:0:12}-${BUILD_INSTANCE_ID}"
ARCHIVE_PATH="$WORK_ROOT/Nembra.xcarchive"
EXPORT_DIR="$WORK_ROOT/export"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/Artifacts/ES80FieldCandidate}"
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
  -exportOptionsPlist "$NEMBRA_EXPORT_OPTIONS_PLIST" \
  "${PROVISIONING_ARGS[@]}"

shopt -s nullglob
IPA_FILES=("$EXPORT_DIR"/*.ipa)
shopt -u nullglob
if [[ "${#IPA_FILES[@]}" -ne 1 ]]; then
  echo "Expected exactly one exported .ipa; found ${#IPA_FILES[@]}." >&2
  printf '%s\n' "${IPA_FILES[@]:-}" >&2
  exit 8
fi
IPA_PATH="${IPA_FILES[0]}"

# The verifier independently reopens the exact IPA, validates signing/profile identity,
# verifies embedded build provenance against the still-pristine exact Git HEAD, retains
# exact bytes, and emits candidate-only/no-GO evidence.
python3 scripts/ci/es80_field_candidate_verify.py \
  --ipa "$IPA_PATH" \
  --output-dir "$ARTIFACTS_DIR"

RECORD_PATH="$ARTIFACTS_DIR/NembraCaptureFieldBuildCandidateRecord.json"
python3 - "$RECORD_PATH" "$SOURCE_SHA" "$BUILD_IDENTIFIER" "$BUILD_INSTANCE_ID" "$NEMBRA_DEVELOPMENT_TEAM" <<'PY'
import json, pathlib, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = {
    "status": "candidate-only-no-go",
    "sourceCommitSHA": sys.argv[2],
    "buildIdentifier": sys.argv[3],
    "buildInstanceID": sys.argv[4],
    "teamIdentifier": sys.argv[5],
    "experimentRecipeID": "ES80-FINGERPRINT-v1",
    "procedureVersion": "V14",
}
for key, value in expected.items():
    if record.get(key) != value:
        raise SystemExit(f"Field-candidate record mismatch for {key}: {record.get(key)!r} != {value!r}")
if "physicalGO" in record or "authorized" in record:
    raise SystemExit("Candidate record illegally contains a physical authorization field")
PY

{
  echo "source_commit_sha=$SOURCE_SHA"
  echo "build_identifier=$BUILD_IDENTIFIER"
  echo "build_instance_id=$BUILD_INSTANCE_ID"
  echo "development_team=$NEMBRA_DEVELOPMENT_TEAM"
  echo "experiment_recipe_id=ES80-FINGERPRINT-v1"
  echo "procedure_version=V14"
  echo "status=candidate-only-no-go"
  xcodebuild -version
} > "$ARTIFACTS_DIR/field-candidate-environment.txt"

echo "Signed Nembra iOS field-build CANDIDATE retained at: $ARTIFACTS_DIR"
echo "PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN."
