#!/bin/bash
set -euo pipefail

# Produce one exact signed iOS Nembra Capture field-build CANDIDATE.
# This script cannot authorize physical ES80 Experiment One.

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Signed iOS field-candidate production requires macOS." >&2
  exit 2
fi

: "${NEMBRA_DEVELOPMENT_TEAM:?Set NEMBRA_DEVELOPMENT_TEAM to the Apple signing TeamIdentifier.}"
: "${NEMBRA_EXPORT_OPTIONS_PLIST:?Set NEMBRA_EXPORT_OPTIONS_PLIST to an existing Xcode export-options plist.}"
: "${NEMBRA_INTENDED_DEVICE_UDID:?Set NEMBRA_INTENDED_DEVICE_UDID to the intended field iPhone for verification only.}"

if [[ ! "$NEMBRA_DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "NEMBRA_DEVELOPMENT_TEAM must be one canonical 10-character Apple TeamIdentifier." >&2
  exit 3
fi
if [[ ! -f "$NEMBRA_EXPORT_OPTIONS_PLIST" ]]; then
  echo "NEMBRA_EXPORT_OPTIONS_PLIST does not name an existing file." >&2
  exit 4
fi
/usr/bin/plutil -lint "$NEMBRA_EXPORT_OPTIONS_PLIST" >/dev/null
EXPORT_OPTIONS_PLIST="$(cd "$(dirname "$NEMBRA_EXPORT_OPTIONS_PLIST")" && pwd -P)/$(basename "$NEMBRA_EXPORT_OPTIONS_PLIST")"

ALLOW_PROVISIONING_UPDATES="${NEMBRA_ALLOW_PROVISIONING_UPDATES:-0}"
case "$ALLOW_PROVISIONING_UPDATES" in
  0|1) ;;
  *)
    echo "NEMBRA_ALLOW_PROVISIONING_UPDATES must be exactly 0 or 1." >&2
    exit 5
    ;;
esac

# macOS still ships Bash 3.2. Avoid optionally-empty arrays under nounset.
run_xcodebuild() {
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    xcodebuild -allowProvisioningUpdates "$@"
  else
    xcodebuild "$@"
  fi
}

REPOSITORY_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$REPOSITORY_STATUS" ]]; then
  echo "Signed field-candidate production refuses tracked changes or non-ignored untracked files." >&2
  printf '%s\n' "$REPOSITORY_STATUS" >&2
  exit 6
fi

SOURCE_SHA="$(git rev-parse --verify HEAD^{commit})"
if [[ ! "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Could not derive one exact lowercase 40-hex Git HEAD." >&2
  exit 7
fi

BUILD_IDENTIFIER="Capture Build V14-${SOURCE_SHA:0:12}"
BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
FIELD_RECIPE_ID="ES80-FINGERPRINT-v1"
if [[ ! "$BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Generated build-instance ID is not canonical lowercase UUID text." >&2
  exit 8
fi

WORK_ROOT="${RUNNER_TEMP:-/tmp}/NembraES80FieldCandidate-${SOURCE_SHA:0:12}-${BUILD_INSTANCE_ID}"
SOURCE_ROOT="$WORK_ROOT/source"
ARCHIVE_PATH="$WORK_ROOT/Nembra.xcarchive"
EXPORT_DIR="$WORK_ROOT/export"
RAW_ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/artifacts/Xcode27FieldCandidate-${SOURCE_SHA:0:12}-$BUILD_INSTANCE_ID}"
if [[ "$RAW_ARTIFACTS_DIR" != /* ]]; then
  RAW_ARTIFACTS_DIR="$ROOT/$RAW_ARTIFACTS_DIR"
fi
ARTIFACTS_DIR="$(python3 - "$RAW_ARTIFACTS_DIR" <<'PY'
import sys
from pathlib import Path
print(Path(sys.argv[1]).resolve(strict=False))
PY
)"
PRODUCER_AUDIT_DIR="${ARTIFACTS_DIR}.producer-audit"

# The canonical inspector owns ARTIFACTS_DIR and publishes that exact evidence directory
# failure-atomically/no-replace. Producer-only logs and export-policy provenance live in a separate
# sidecar so they can never make a partial directory look like canonical field evidence.
if [[ -z "$ARTIFACTS_DIR" || "$ARTIFACTS_DIR" == "/" || "$ARTIFACTS_DIR" == "$ROOT" ]]; then
  echo "ARTIFACTS_DIR is not a safe field-production output path: $ARTIFACTS_DIR" >&2
  exit 9
fi
if [[ -e "$ARTIFACTS_DIR" || -L "$ARTIFACTS_DIR" ]]; then
  echo "ARTIFACTS_DIR already exists; refusing to mix or overwrite field evidence: $ARTIFACTS_DIR" >&2
  exit 10
fi
if [[ -e "$PRODUCER_AUDIT_DIR" || -L "$PRODUCER_AUDIT_DIR" ]]; then
  echo "Producer audit sidecar already exists; refusing to mix field-production provenance: $PRODUCER_AUDIT_DIR" >&2
  exit 11
fi
if [[ "$ARTIFACTS_DIR" == "$ROOT"/* ]]; then
  RELATIVE_ARTIFACTS_DIR="${ARTIFACTS_DIR#"$ROOT"/}"
  if ! git check-ignore -q -- "$RELATIVE_ARTIFACTS_DIR"; then
    echo "ARTIFACTS_DIR inside the repository must already be ignored by Git: $RELATIVE_ARTIFACTS_DIR" >&2
    exit 12
  fi
fi

mkdir -p "$PRODUCER_AUDIT_DIR/logs"
printf '%s\n' \
  'status=INCOMPLETE_NON_AUTHORIZING_PRODUCER_AUDIT' \
  'physical_authorization=not-granted' \
  > "$PRODUCER_AUDIT_DIR/status.txt"

EXPORT_OPTIONS_SNAPSHOT="$PRODUCER_AUDIT_DIR/ExportOptions.plist"
cp -p "$EXPORT_OPTIONS_PLIST" "$EXPORT_OPTIONS_SNAPSHOT"
/usr/bin/plutil -lint "$EXPORT_OPTIONS_SNAPSHOT" >/dev/null

EXPORT_OPTIONS_SHA256="$(python3 - "$EXPORT_OPTIONS_SNAPSHOT" "$NEMBRA_DEVELOPMENT_TEAM" <<'PY'
import hashlib
import plistlib
import sys
from pathlib import Path
path = Path(sys.argv[1])
expected_team = sys.argv[2]
raw = path.read_bytes()
options = plistlib.loads(raw)
if not isinstance(options, dict):
    raise SystemExit("Export options plist root must be a dictionary")
team = options.get("teamID")
if team is not None and team != expected_team:
    raise SystemExit("Export options teamID does not match NEMBRA_DEVELOPMENT_TEAM")
method = options.get("method")
if method is not None and (not isinstance(method, str) or not method.strip()):
    raise SystemExit("Export options method, when present, must be a non-empty string")
print(hashlib.sha256(raw).hexdigest())
PY
)"
if [[ ! "$EXPORT_OPTIONS_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not derive one canonical SHA-256 for retained ExportOptions.plist." >&2
  exit 13
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
  exit 14
fi
mkdir -p "$EXPORT_DIR"

set +e
set -o pipefail
run_xcodebuild \
  -project Nembra.xcodeproj \
  -scheme Nembra \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  "DEVELOPMENT_TEAM=$NEMBRA_DEVELOPMENT_TEAM" \
  "INFOPLIST_KEY_NembraCaptureBuildIdentifier=$BUILD_IDENTIFIER" \
  "INFOPLIST_KEY_NembraCaptureBuildInstanceID=$BUILD_INSTANCE_ID" \
  "INFOPLIST_KEY_NembraCaptureBuildCommitSHA=$SOURCE_SHA" \
  "INFOPLIST_KEY_NembraCaptureFieldRecipe=$FIELD_RECIPE_ID" \
  archive \
  2>&1 | tee "$PRODUCER_AUDIT_DIR/logs/xcodebuild-archive.log"
# This array is always non-empty because the immediately preceding pipeline has exactly two commands.
# Snapshot PIPESTATUS in one assignment: any later shell command would replace PIPESTATUS.
ARCHIVE_PIPESTATUS=("${PIPESTATUS[@]}")
set -e
if [[ "${ARCHIVE_PIPESTATUS[0]}" -ne 0 || "${ARCHIVE_PIPESTATUS[1]}" -ne 0 ]]; then
  echo "Signed field-candidate archive/log capture failed: xcodebuild=${ARCHIVE_PIPESTATUS[0]} tee=${ARCHIVE_PIPESTATUS[1]}." >&2
  exit 15
fi

set +e
set -o pipefail
run_xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_SNAPSHOT" \
  2>&1 | tee "$PRODUCER_AUDIT_DIR/logs/xcodebuild-export.log"
EXPORT_PIPESTATUS=("${PIPESTATUS[@]}")
set -e
if [[ "${EXPORT_PIPESTATUS[0]}" -ne 0 || "${EXPORT_PIPESTATUS[1]}" -ne 0 ]]; then
  echo "Signed field-candidate export/log capture failed: xcodebuild=${EXPORT_PIPESTATUS[0]} tee=${EXPORT_PIPESTATUS[1]}." >&2
  exit 16
fi

POST_EXPORT_OPTIONS_SHA256="$(python3 - "$EXPORT_OPTIONS_SNAPSHOT" <<'PY'
import hashlib
import sys
from pathlib import Path
print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"
if [[ "$POST_EXPORT_OPTIONS_SHA256" != "$EXPORT_OPTIONS_SHA256" ]]; then
  echo "Retained ExportOptions.plist changed during archive/export; refusing candidate evidence." >&2
  exit 17
fi

POST_BUILD_SOURCE_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
POST_BUILD_HEAD="$(git rev-parse --verify HEAD^{commit})"
if [[ "$POST_BUILD_HEAD" != "$SOURCE_SHA" || -n "$POST_BUILD_SOURCE_STATUS" ]]; then
  echo "Archive/export changed immutable source state; refusing exact-HEAD candidate evidence." >&2
  printf '%s\n' "$POST_BUILD_SOURCE_STATUS" >&2
  exit 18
fi

IPA_PATH="$(python3 - "$EXPORT_DIR" <<'PY'
import sys
from pathlib import Path
export_dir = Path(sys.argv[1])
candidates = sorted(
    path for path in export_dir.iterdir()
    if path.is_file() and path.suffix.lower() == ".ipa"
)
if len(candidates) != 1:
    rendered = ", ".join(path.name for path in candidates) or "<none>"
    raise SystemExit(f"Expected exactly one exported .ipa; found {len(candidates)}: {rendered}")
print(candidates[0])
PY
)"

# The canonical inspector owns exact IPA/provisioning/installability truth. The UDID is supplied only
# for verification against the embedded profile; the inspector does not persist, print, or hash it.
# ARTIFACTS_DIR must still not exist here so the inspector can publish its evidence atomically.
python3 scripts/ci/es80_signed_field_artifact_evidence.py \
  --ipa "$IPA_PATH" \
  --expected-source-sha "$SOURCE_SHA" \
  --intended-device-udid "$NEMBRA_INTENDED_DEVICE_UDID" \
  --output-dir "$ARTIFACTS_DIR"

EXTERNAL_RECORD="$ARTIFACTS_DIR/NembraCaptureExternalBuildRecord.json"
FIELD_BUILD_RECORD="$ARTIFACTS_DIR/NembraCaptureFieldBuildEvidenceRecord.json"
SIGNING_INSPECTION="$ARTIFACTS_DIR/NembraCaptureSignedFieldArtifactInspection.json"
RETAINED_IPA="$ARTIFACTS_DIR/build-evidence/NembraField.ipa"

python3 - \
  "$EXTERNAL_RECORD" \
  "$FIELD_BUILD_RECORD" \
  "$SIGNING_INSPECTION" \
  "$RETAINED_IPA" \
  "$SOURCE_SHA" \
  "$BUILD_IDENTIFIER" \
  "$BUILD_INSTANCE_ID" \
  "$NEMBRA_DEVELOPMENT_TEAM" \
  "$FIELD_RECIPE_ID" <<'PY'
import hashlib
import json
import pathlib
import re
import sys
external_path = pathlib.Path(sys.argv[1])
field_path = pathlib.Path(sys.argv[2])
inspection_path = pathlib.Path(sys.argv[3])
ipa_path = pathlib.Path(sys.argv[4])
source_sha, build_identifier, build_instance_id, expected_team, field_recipe = sys.argv[5:10]
external_bytes = external_path.read_bytes()
field_bytes = field_path.read_bytes()
field = json.loads(field_bytes)
inspection = json.loads(inspection_path.read_bytes())
expected_field_keys = {
    "schemaVersion", "externalBuildRecordSHA256", "signedInstallableSHA256",
    "signedInstallableKind", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "executableSHA256", "infoPlistSHA256", "experimentRecipeID", "procedureVersion",
}
if set(field) != expected_field_keys:
    raise SystemExit(f"Canonical field-build evidence shape drifted: {sorted(field)!r}")
shared_expected = {
    "sourceCommitSHA": source_sha,
    "buildIdentifier": build_identifier,
    "buildInstanceID": build_instance_id,
    "experimentRecipeID": field_recipe,
    "procedureVersion": "V14",
}
for record_name, record in (("field-build evidence", field), ("signing inspection", inspection)):
    for key, value in shared_expected.items():
        if record.get(key) != value:
            raise SystemExit(f"{record_name} mismatch for {key}: {record.get(key)!r} != {value!r}")
if field.get("signedInstallableKind") != "ipa":
    raise SystemExit("Canonical field-build evidence no longer describes an IPA installable")
if inspection.get("authority") != "signed-field-artifact-inspection-not-field-authorization":
    raise SystemExit("Signing inspection authority boundary changed unexpectedly")
if inspection.get("teamIdentifier") != expected_team:
    raise SystemExit("Signing inspection TeamIdentifier does not match requested signing team")
if inspection.get("provisioningApplicationIdentifier") != f"{expected_team}.com.jonathangana131.nembra":
    raise SystemExit("Provisioning application identifier does not match exact Nembra app identity")
if not re.fullmatch(r"[0-9a-f]{64}", inspection.get("provisioningProfileSHA256", "")):
    raise SystemExit("Signed field candidate lacks exact embedded provisioning-profile digest evidence")
external_sha = hashlib.sha256(external_bytes).hexdigest()
field_sha = hashlib.sha256(field_bytes).hexdigest()
if field.get("externalBuildRecordSHA256") != external_sha:
    raise SystemExit("Field-build evidence is not bound to exact external build-record bytes")
if inspection.get("externalBuildRecordSHA256") != external_sha:
    raise SystemExit("Signing inspection is not bound to exact external build-record bytes")
if inspection.get("fieldBuildEvidenceRecordSHA256") != field_sha:
    raise SystemExit("Signing inspection is not bound to exact field-build evidence bytes")
if inspection.get("signedInstallableSHA256") != field.get("signedInstallableSHA256"):
    raise SystemExit("Signing inspection and field-build evidence disagree on exact IPA digest")
ipa_digest = hashlib.sha256()
with ipa_path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        ipa_digest.update(chunk)
if ipa_digest.hexdigest() != field.get("signedInstallableSHA256"):
    raise SystemExit("Retained IPA bytes do not match canonical field-build evidence")
PY

{
  echo "source_commit_sha=$SOURCE_SHA"
  echo "build_identifier=$BUILD_IDENTIFIER"
  echo "build_instance_id=$BUILD_INSTANCE_ID"
  echo "field_recipe_id=$FIELD_RECIPE_ID"
  echo "development_team=$NEMBRA_DEVELOPMENT_TEAM"
  echo "experiment_recipe_id=ES80-FINGERPRINT-v1"
  echo "procedure_version=V14"
  echo "export_options_sha256=$EXPORT_OPTIONS_SHA256"
  echo "canonical_evidence_dir=$ARTIFACTS_DIR"
  echo "archive_log=$PRODUCER_AUDIT_DIR/logs/xcodebuild-archive.log"
  echo "export_log=$PRODUCER_AUDIT_DIR/logs/xcodebuild-export.log"
  echo "signing_inspection_authority=signed-field-artifact-inspection-not-field-authorization"
  echo "physical_authorization=not-granted"
  xcodebuild -version
} > "$PRODUCER_AUDIT_DIR/field-candidate-environment.txt"

printf '%s\n' \
  'status=COMPLETE_NON_AUTHORIZING_PRODUCER_AUDIT' \
  'physical_authorization=not-granted' \
  > "$PRODUCER_AUDIT_DIR/status.txt.tmp"
mv "$PRODUCER_AUDIT_DIR/status.txt.tmp" "$PRODUCER_AUDIT_DIR/status.txt"

echo "Signed Nembra iOS field-build CANDIDATE evidence retained at: $ARTIFACTS_DIR"
echo "Producer-only audit retained separately at: $PRODUCER_AUDIT_DIR"
echo "Independent acceptance has NOT occurred."
echo "PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN."
