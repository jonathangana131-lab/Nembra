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
: "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to a private mode-0600 file containing the intended field iPhone UDID for verification only.}"

if [[ ! "$NEMBRA_DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "NEMBRA_DEVELOPMENT_TEAM must be one canonical 10-character Apple TeamIdentifier." >&2
  exit 3
fi
if ! python3 scripts/ci/es80_signed_field_artifact_private_runner.py \
  --intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" \
  --check-private-input
then
  echo "NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE is not a valid private verification input." >&2
  exit 4
fi
if [[ ! -f "$NEMBRA_EXPORT_OPTIONS_PLIST" ]]; then
  echo "NEMBRA_EXPORT_OPTIONS_PLIST does not name an existing file." >&2
  exit 5
fi
/usr/bin/plutil -lint "$NEMBRA_EXPORT_OPTIONS_PLIST" >/dev/null
EXPORT_OPTIONS_PLIST="$(cd "$(dirname "$NEMBRA_EXPORT_OPTIONS_PLIST")" && pwd -P)/$(basename "$NEMBRA_EXPORT_OPTIONS_PLIST")"

ALLOW_PROVISIONING_UPDATES="${NEMBRA_ALLOW_PROVISIONING_UPDATES:-0}"
case "$ALLOW_PROVISIONING_UPDATES" in
  0|1) ;;
  *)
    echo "NEMBRA_ALLOW_PROVISIONING_UPDATES must be exactly 0 or 1." >&2
    exit 6
    ;;
esac

# Keep the producer compatible with the Bash 3.2 still shipped by macOS. Avoid optionally empty
# arrays under nounset; pass provisioning updates through one explicit wrapper instead.
run_xcodebuild() {
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    xcodebuild -allowProvisioningUpdates "$@"
  else
    xcodebuild "$@"
  fi
}

# A dirty invocation checkout is never accepted. The real build below is additionally produced from
# a fresh detached worktree at SOURCE_SHA, preventing ignored/local/concurrent source mutation from
# silently becoming bytes stamped as this exact commit.
REPOSITORY_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$REPOSITORY_STATUS" ]]; then
  echo "Signed field-candidate production refuses tracked changes or non-ignored untracked files." >&2
  printf '%s\n' "$REPOSITORY_STATUS" >&2
  exit 7
fi

SOURCE_SHA="$(git rev-parse --verify HEAD^{commit})"
if [[ ! "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Could not derive one exact lowercase 40-hex Git HEAD." >&2
  exit 8
fi

BUILD_IDENTIFIER="Capture Build V14-${SOURCE_SHA:0:12}"
FIELD_RECIPE_ID="ES80-FINGERPRINT-v1"
BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
if [[ ! "$BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Generated build-instance ID is not canonical lowercase UUID text." >&2
  exit 9
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
INSPECTION_DIR="$ARTIFACTS_DIR/inspection"

# Candidate output is immutable. Resolve lexical traversal/symlink ancestors before safety checks;
# never mix a new field candidate into an old or repository-root evidence directory.
if [[ -z "$ARTIFACTS_DIR" || "$ARTIFACTS_DIR" == "/" || "$ARTIFACTS_DIR" == "$ROOT" ]]; then
  echo "ARTIFACTS_DIR is not a safe field-production output path: $ARTIFACTS_DIR" >&2
  exit 10
fi
if [[ -e "$ARTIFACTS_DIR" || -L "$ARTIFACTS_DIR" ]]; then
  echo "ARTIFACTS_DIR already exists; refusing to mix or overwrite field-production evidence: $ARTIFACTS_DIR" >&2
  exit 11
fi
if [[ "$ARTIFACTS_DIR" == "$ROOT"/* ]]; then
  RELATIVE_ARTIFACTS_DIR="${ARTIFACTS_DIR#"$ROOT"/}"
  if ! git check-ignore -q -- "$RELATIVE_ARTIFACTS_DIR"; then
    echo "ARTIFACTS_DIR inside the repository must already be ignored by Git: $RELATIVE_ARTIFACTS_DIR" >&2
    exit 12
  fi
fi

# Producer-owned provenance is a sibling of the inspector-owned evidence directory. The inspector's
# failure-atomic/no-replace contract requires INSPECTION_DIR not to exist before invocation.
mkdir -p "$ARTIFACTS_DIR/logs"
EXPORT_OPTIONS_SNAPSHOT="$ARTIFACTS_DIR/ExportOptions.plist"
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

set -o pipefail
if ! run_xcodebuild \
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
  2>&1 | tee "$ARTIFACTS_DIR/logs/xcodebuild-archive.log"
then
  echo "Signed field-candidate archive or archive-log capture failed." >&2
  exit 15
fi

if ! run_xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_SNAPSHOT" \
  2>&1 | tee "$ARTIFACTS_DIR/logs/xcodebuild-export.log"
then
  echo "Signed field-candidate export or export-log capture failed." >&2
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

# Closed-world top-level IPA selection without nullglob/empty arrays under Bash 3.2 + nounset.
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

# The intended-device UDID is verification-only input. The shell and OS process table see only the
# path to its private file; the private runner reads the value in-process and calls the canonical
# es80_signed_field_artifact_evidence.py inspector with an in-memory argv list. The raw identifier is
# deliberately never exported, persisted, echoed, hashed, embedded into filenames, or copied into
# candidate evidence. INSPECTION_DIR remains absent until the failure-atomic inspector publishes.
python3 scripts/ci/es80_signed_field_artifact_private_runner.py \
  --ipa "$IPA_PATH" \
  --expected-source-sha "$SOURCE_SHA" \
  --intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" \
  --output-dir "$INSPECTION_DIR"

EXTERNAL_RECORD="$INSPECTION_DIR/NembraCaptureExternalBuildRecord.json"
FIELD_BUILD_RECORD="$INSPECTION_DIR/NembraCaptureFieldBuildEvidenceRecord.json"
SIGNING_INSPECTION="$INSPECTION_DIR/NembraCaptureSignedFieldArtifactInspection.json"
RETAINED_IPA="$INSPECTION_DIR/build-evidence/NembraField.ipa"

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
import plistlib
import re
import sys
import zipfile

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
if set(field) != expected_field_keys:
    raise SystemExit(f"Canonical field-build evidence shape drifted: {sorted(field)!r}")

expected_inspection_keys = {
    "schemaVersion",
    "authority",
    "fieldBuildEvidenceRecordSHA256",
    "externalBuildRecordSHA256",
    "signedInstallableSHA256",
    "signedInstallableKind",
    "ipaByteCount",
    "buildIdentifier",
    "buildInstanceID",
    "sourceCommitSHA",
    "bundleIdentifier",
    "platformName",
    "supportedPlatforms",
    "teamIdentifier",
    "signingAuthorities",
    "codeDirectoryHash",
    "provisioningProfileSHA256",
    "provisioningProfileUUID",
    "provisioningProfileExpirationUTC",
    "provisioningApplicationIdentifier",
    "executableSHA256",
    "infoPlistSHA256",
    "experimentRecipeID",
    "procedureVersion",
}
if set(inspection) != expected_inspection_keys:
    raise SystemExit(f"Signing inspection shape drifted: {sorted(inspection)!r}")

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

if field.get("signedInstallableKind") != "ipa" or inspection.get("signedInstallableKind") != "ipa":
    raise SystemExit("Signed field evidence no longer describes one IPA installable")
if inspection.get("authority") != "signed-field-artifact-inspection-not-field-authorization":
    raise SystemExit("Signing inspection authority boundary changed unexpectedly")
if inspection.get("teamIdentifier") != expected_team:
    raise SystemExit("Signing inspection TeamIdentifier does not match requested development team")
if inspection.get("bundleIdentifier") != "com.jonathangana131.nembra":
    raise SystemExit("Signing inspection bundle identifier drifted")
if inspection.get("platformName") != "iphoneos" or "iPhoneOS" not in inspection.get("supportedPlatforms", []):
    raise SystemExit("Signing inspection no longer describes a physical iPhone build")
if inspection.get("provisioningApplicationIdentifier") != f"{expected_team}.com.jonathangana131.nembra":
    raise SystemExit("Provisioning application identifier does not match the requested signed Nembra app")
if not re.fullmatch(r"[0-9a-f]{64}", inspection.get("provisioningProfileSHA256", "")):
    raise SystemExit("Signed field candidate lacks exact embedded provisioning-profile digest evidence")
if not isinstance(inspection.get("provisioningProfileUUID"), str) or not inspection["provisioningProfileUUID"].strip():
    raise SystemExit("Signed field candidate lacks provisioning-profile identity")
if not isinstance(inspection.get("provisioningProfileExpirationUTC"), str) or not inspection["provisioningProfileExpirationUTC"].endswith("Z"):
    raise SystemExit("Signed field candidate lacks normalized provisioning-profile expiration")

external_sha = hashlib.sha256(external_bytes).hexdigest()
field_sha = hashlib.sha256(field_bytes).hexdigest()
if field.get("externalBuildRecordSHA256") != external_sha:
    raise SystemExit("Field-build evidence is not bound to the exact external build-record bytes")
if inspection.get("externalBuildRecordSHA256") != external_sha:
    raise SystemExit("Signing inspection is not bound to the exact external build-record bytes")
if inspection.get("fieldBuildEvidenceRecordSHA256") != field_sha:
    raise SystemExit("Signing inspection is not bound to the exact field-build evidence bytes")
if inspection.get("signedInstallableSHA256") != field.get("signedInstallableSHA256"):
    raise SystemExit("Signing inspection and field-build evidence disagree on the exact IPA digest")
if inspection.get("executableSHA256") != field.get("executableSHA256"):
    raise SystemExit("Signing inspection and field-build evidence disagree on executable bytes")
if inspection.get("infoPlistSHA256") != field.get("infoPlistSHA256"):
    raise SystemExit("Signing inspection and field-build evidence disagree on raw Info.plist bytes")

ipa_digest = hashlib.sha256()
with ipa_path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        ipa_digest.update(chunk)
if ipa_digest.hexdigest() != field.get("signedInstallableSHA256"):
    raise SystemExit("Retained IPA bytes do not match canonical field-build evidence")

# The canonical inspector has already rejected duplicate/colliding archive members. Re-open the exact
# retained IPA only to prove the launch-routing marker in the signed Info.plist and bind those same
# raw plist bytes to the field evidence digest.
with zipfile.ZipFile(ipa_path) as archive:
    plist_members = [
        info for info in archive.infolist()
        if len(pathlib.PurePosixPath(info.filename).parts) == 3
        and pathlib.PurePosixPath(info.filename).parts[0] == "Payload"
        and pathlib.PurePosixPath(info.filename).parts[1].endswith(".app")
        and pathlib.PurePosixPath(info.filename).parts[2] == "Info.plist"
    ]
    if len(plist_members) != 1:
        raise SystemExit("Retained IPA does not contain exactly one top-level signed Info.plist")
    raw_info_plist = archive.read(plist_members[0])
    info = plistlib.loads(raw_info_plist)
if not isinstance(info, dict) or info.get("NembraCaptureFieldRecipe") != field_recipe:
    raise SystemExit("Signed IPA does not contain the exact Nembra Capture field-launch recipe")
if hashlib.sha256(raw_info_plist).hexdigest() != field.get("infoPlistSHA256"):
    raise SystemExit("Signed field-launch recipe was not verified on the exact Info.plist evidence bytes")
PY

# Never persist the intended-device UDID. Candidate provenance records only non-sensitive build and
# export-policy facts plus paths to the failure-atomic inspector evidence directory.
{
  echo "source_commit_sha=$SOURCE_SHA"
  echo "build_identifier=$BUILD_IDENTIFIER"
  echo "build_instance_id=$BUILD_INSTANCE_ID"
  echo "development_team=$NEMBRA_DEVELOPMENT_TEAM"
  echo "allow_provisioning_updates=$ALLOW_PROVISIONING_UPDATES"
  echo "field_launch_recipe_id=$FIELD_RECIPE_ID"
  echo "experiment_recipe_id=$FIELD_RECIPE_ID"
  echo "export_options_file=ExportOptions.plist"
  echo "export_options_sha256=$EXPORT_OPTIONS_SHA256"
  echo "archive_log=logs/xcodebuild-archive.log"
  echo "export_log=logs/xcodebuild-export.log"
  echo "inspection_directory=inspection"
  echo "procedure_version=V14"
  echo "signing_inspection_authority=signed-field-artifact-inspection-not-field-authorization"
  echo "physical_authorization=not-granted"
  xcodebuild -version
} > "$ARTIFACTS_DIR/field-candidate-environment.txt"

echo "Signed Nembra iOS field-build CANDIDATE retained at: $ARTIFACTS_DIR"
echo "Exact ExportOptions.plist, archive/export logs, and failure-atomic signed evidence were retained."
echo "Independent acceptance has NOT occurred."
echo "PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN."
