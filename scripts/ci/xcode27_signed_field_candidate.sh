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
EXPORT_OPTIONS_PLIST="$(cd "$(dirname "$NEMBRA_EXPORT_OPTIONS_PLIST")" && pwd)/$(basename "$NEMBRA_EXPORT_OPTIONS_PLIST")"

# A dirty invocation checkout is never accepted. This is defense in depth only: the actual build
# below is performed from a fresh detached worktree at SOURCE_SHA so a later mutation, ignored file,
# or concurrent worker cannot silently become bytes stamped as this exact commit.
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

# This spelling is owned by the accepted schema-v3/current field-artifact evidence contract.
BUILD_IDENTIFIER="Capture Build V14-${SOURCE_SHA:0:12}"
BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
if [[ ! "$BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Generated build-instance ID is not canonical lowercase UUID text." >&2
  exit 7
fi

WORK_ROOT="${RUNNER_TEMP:-/tmp}/NembraES80FieldCandidate-${SOURCE_SHA:0:12}-${BUILD_INSTANCE_ID}"
SOURCE_ROOT="$WORK_ROOT/source"
ARCHIVE_PATH="$WORK_ROOT/Nembra.xcarchive"
EXPORT_DIR="$WORK_ROOT/export"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/artifacts/Xcode27FieldCandidate}"
if [[ "$ARTIFACTS_DIR" != /* ]]; then
  ARTIFACTS_DIR="$ROOT/$ARTIFACTS_DIR"
fi

# Candidate evidence written inside the invocation checkout must already be ignored. Otherwise a
# successful producer run would silently dirty the operator checkout after admission.
if [[ "$ARTIFACTS_DIR" == "$ROOT"/* ]]; then
  RELATIVE_ARTIFACTS_DIR="${ARTIFACTS_DIR#"$ROOT"/}"
  if ! git check-ignore -q -- "$RELATIVE_ARTIFACTS_DIR"; then
    echo "ARTIFACTS_DIR inside the repository must already be ignored by Git: $RELATIVE_ARTIFACTS_DIR" >&2
    exit 8
  fi
fi

rm -rf "$WORK_ROOT"
mkdir -p "$WORK_ROOT"
git worktree add --detach "$SOURCE_ROOT" "$SOURCE_SHA"

cleanup() {
  cd "$ROOT" >/dev/null 2>&1 || true
  git worktree remove --force "$SOURCE_ROOT" >/dev/null 2>&1 || true
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

cd "$SOURCE_ROOT"
IMMUTABLE_HEAD="$(git rev-parse --verify HEAD^{commit})"
IMMUTABLE_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ "$IMMUTABLE_HEAD" != "$SOURCE_SHA" || -n "$IMMUTABLE_STATUS" ]]; then
  echo "Detached source worktree is not an exact clean checkout of SOURCE_SHA." >&2
  exit 9
fi
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

# The detached worktree itself must still be clean after archive/export. Xcode products live under
# WORK_ROOT outside SOURCE_ROOT, so a visible source delta means the exact-commit build boundary was
# violated and no candidate evidence is allowed to be emitted.
POST_BUILD_SOURCE_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
POST_BUILD_HEAD="$(git rev-parse --verify HEAD^{commit})"
if [[ "$POST_BUILD_HEAD" != "$SOURCE_SHA" || -n "$POST_BUILD_SOURCE_STATUS" ]]; then
  echo "Archive/export changed immutable source state; refusing exact-HEAD candidate evidence." >&2
  printf '%s\n' "$POST_BUILD_SOURCE_STATUS" >&2
  exit 10
fi

shopt -s nullglob
IPA_FILES=("$EXPORT_DIR"/*.ipa)
shopt -u nullglob
if [[ "${#IPA_FILES[@]}" -ne 1 ]]; then
  echo "Expected exactly one exported .ipa; found ${#IPA_FILES[@]}." >&2
  printf '%s\n' "${IPA_FILES[@]:-}" >&2
  exit 11
fi
IPA_PATH="${IPA_FILES[0]}"

# Reuse the exact canonical post-build evidence implementation from the same immutable source
# snapshot that produced the archive. It reopens the final IPA, verifies iphoneos/codesign, hashes
# exact final bytes, retains the IPA, and emits schema-v3 + field companion evidence without GO.
python3 scripts/ci/es80_signed_field_artifact_evidence.py \
  --ipa "$IPA_PATH" \
  --expected-source-sha "$SOURCE_SHA" \
  --output-dir "$ARTIFACTS_DIR"

FIELD_RECORD="$ARTIFACTS_DIR/NembraCaptureSignedFieldArtifactEvidence.json"
python3 - "$FIELD_RECORD" "$SOURCE_SHA" "$BUILD_IDENTIFIER" "$BUILD_INSTANCE_ID" "$NEMBRA_DEVELOPMENT_TEAM" <<'PY'
import json, pathlib, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_text())
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
        raise SystemExit(f"Signed-field evidence mismatch for {key}: {record.get(key)!r} != {value!r}")
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

echo "Signed Nembra iOS field-build CANDIDATE retained at: $ARTIFACTS_DIR"
echo "Independent acceptance has NOT occurred."
echo "PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN."
