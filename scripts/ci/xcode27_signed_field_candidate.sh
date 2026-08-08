#!/bin/bash
set -euo pipefail

# Produce one exact signed iOS Nembra Capture field-build CANDIDATE and the canonical
# non-authorizing evidence consumed by NembraBluetoothCapture.
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

# Exact source identity is captured before any build output exists. Non-ignored untracked source
# cannot silently participate in a field candidate whose record claims only HEAD.
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

# Match the already-accepted runtime/Simulator build-label contract. Field-vs-Simulator identity is
# distinguished by build-instance + exact artifact evidence, not by inventing a second label grammar.
BUILD_IDENTIFIER="Capture Build V14-${SOURCE_SHA:0:12}"
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

# The verifier independently reopens the exact IPA, validates device platform, exact embedded build
# provenance, Apple code signature + provisioning identity, retains exact bytes, emits the existing
# schema-v3 external record and the package-owned closed-world field evidence record, and keeps all
# signing metadata in a separate supporting NO-GO record.
python3 scripts/ci/es80_field_candidate_verify.py \
  --ipa "$IPA_PATH" \
  --output-dir "$ARTIFACTS_DIR"

FIELD_RECORD="$ARTIFACTS_DIR/NembraCaptureFieldBuildEvidenceRecord.json"
EXTERNAL_RECORD="$ARTIFACTS_DIR/NembraCaptureExternalBuildRecord.json"
SIGNING_RECORD="$ARTIFACTS_DIR/NembraCaptureFieldSigningEvidence.json"
RETAINED_IPA="$ARTIFACTS_DIR/build-evidence/NembraField.ipa"

python3 - \
  "$FIELD_RECORD" \
  "$EXTERNAL_RECORD" \
  "$SIGNING_RECORD" \
  "$RETAINED_IPA" \
  "$SOURCE_SHA" \
  "$BUILD_IDENTIFIER" \
  "$BUILD_INSTANCE_ID" \
  "$NEMBRA_DEVELOPMENT_TEAM" <<'PY'
import hashlib
import json
import pathlib
import sys

field_path, external_path, signing_path, ipa_path = map(pathlib.Path, sys.argv[1:5])
source_sha, build_id, instance_id, expected_team = sys.argv[5:9]

def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

field = json.loads(field_path.read_text(encoding="utf-8"))
external = json.loads(external_path.read_text(encoding="utf-8"))
signing = json.loads(signing_path.read_text(encoding="utf-8"))

field_keys = {
    "schemaVersion",
    "externalBuildRecordSHA256",
    "signedInstallableSHA256",
    "signedInstallableKind",
    "buildIdentifier",
    "buildInstanceID",
    "sourceCommitSHA",
    "executableSHA256",
    "infoPlistSHA256",
    "experimentRecipeID",
    "procedureVersion",
}
external_keys = {
    "schemaVersion",
    "buildIdentifier",
    "buildInstanceID",
    "sourceCommitSHA",
    "executableSHA256",
    "infoPlistSHA256",
    "experimentRecipeID",
    "procedureVersion",
}
if set(field) != field_keys or field.get("schemaVersion") != 1:
    raise SystemExit("Field evidence is not the exact package-owned closed-world schema v1 shape")
if set(external) != external_keys or external.get("schemaVersion") != 3:
    raise SystemExit("External build record is not the exact closed-world schema v3 shape")

expected = {
    "buildIdentifier": build_id,
    "buildInstanceID": instance_id,
    "sourceCommitSHA": source_sha,
    "experimentRecipeID": "ES80-FINGERPRINT-v1",
    "procedureVersion": "V14",
}
for key, value in expected.items():
    if field.get(key) != value or external.get(key) != value:
        raise SystemExit(f"Field/external record mismatch for {key}")
if field.get("signedInstallableKind") != "ipa":
    raise SystemExit("Field evidence installable kind is not ipa")
if field.get("externalBuildRecordSHA256") != sha256(external_path):
    raise SystemExit("Field evidence does not bind the exact external-record bytes")
if field.get("signedInstallableSHA256") != sha256(ipa_path):
    raise SystemExit("Field evidence does not bind the exact retained IPA bytes")
if signing.get("status") != "signing-evidence-only-no-go":
    raise SystemExit("Signing evidence lost its explicit non-authorizing status")
if signing.get("teamIdentifier") != expected_team:
    raise SystemExit("Observed signing TeamIdentifier differs from requested NEMBRA_DEVELOPMENT_TEAM")
for forbidden in ("physicalGO", "authorized", "accepted"):
    if forbidden in field or forbidden in external or forbidden in signing:
        raise SystemExit(f"Evidence illegally contains authority-looking field: {forbidden}")
PY

{
  echo "source_commit_sha=$SOURCE_SHA"
  echo "build_identifier=$BUILD_IDENTIFIER"
  echo "build_instance_id=$BUILD_INSTANCE_ID"
  echo "development_team=$NEMBRA_DEVELOPMENT_TEAM"
  echo "experiment_recipe_id=ES80-FINGERPRINT-v1"
  echo "procedure_version=V14"
  echo "status=evidence-only-not-field-authorization"
  xcodebuild -version
} > "$ARTIFACTS_DIR/field-candidate-environment.txt"

echo "Signed Nembra iOS field-build evidence retained at: $ARTIFACTS_DIR"
echo "PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN."
