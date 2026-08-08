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
: "${NEMBRA_FIELD_DEVICE_UDID:?Set NEMBRA_FIELD_DEVICE_UDID to the intended field iPhone identifier for verification only.}"

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

# The intended-device identifier is verification-only input. Treat it as an opaque bounded token:
# do not invent Apple-format semantics here, and never print, hash, persist, or place it in a path.
NEMBRA_FIELD_DEVICE_UDID="$NEMBRA_FIELD_DEVICE_UDID" python3 - <<'PY'
import os

value = os.environ.get("NEMBRA_FIELD_DEVICE_UDID", "")
encoded = value.encode("utf-8")
if not value or value != value.strip() or len(encoded) > 128:
    raise SystemExit("NEMBRA_FIELD_DEVICE_UDID must be one bounded nonblank opaque identifier")
if any(ord(character) < 0x21 or ord(character) == 0x7F for character in value):
    raise SystemExit("NEMBRA_FIELD_DEVICE_UDID must not contain whitespace or control characters")
PY

ALLOW_PROVISIONING_UPDATES="${NEMBRA_ALLOW_PROVISIONING_UPDATES:-0}"
case "$ALLOW_PROVISIONING_UPDATES" in
  0|1) ;;
  *)
    echo "NEMBRA_ALLOW_PROVISIONING_UPDATES must be exactly 0 or 1." >&2
    exit 5
    ;;
esac

# macOS ships Bash 3.2. Avoid optionally empty arrays under `set -u`.
run_xcodebuild() {
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    xcodebuild -allowProvisioningUpdates "$@"
  else
    xcodebuild "$@"
  fi
}

# A dirty invocation checkout is never accepted. The actual build below is performed from a fresh
# detached worktree at SOURCE_SHA so later invocation-checkout mutations cannot enter exact bytes.
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
FIELD_RECIPE_ID="ES80-FINGERPRINT-v1"
BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
if [[ ! "$BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Generated build-instance ID is not canonical lowercase UUID text." >&2
  exit 8
fi

WORK_ROOT="${RUNNER_TEMP:-/tmp}/NembraES80FieldCandidate-${SOURCE_SHA:0:12}-${BUILD_INSTANCE_ID}"
SOURCE_ROOT="$WORK_ROOT/source"
ARCHIVE_PATH="$WORK_ROOT/Nembra.xcarchive"
EXPORT_DIR="$WORK_ROOT/export"
RAW_CANDIDATE_ROOT="${ARTIFACTS_DIR:-$ROOT/artifacts/Xcode27FieldCandidate-${SOURCE_SHA:0:12}-${BUILD_INSTANCE_ID}}"
if [[ "$RAW_CANDIDATE_ROOT" != /* ]]; then
  RAW_CANDIDATE_ROOT="$ROOT/$RAW_CANDIDATE_ROOT"
fi
CANDIDATE_ROOT="$(python3 - "$RAW_CANDIDATE_ROOT" <<'PY'
import sys
from pathlib import Path
print(Path(sys.argv[1]).resolve(strict=False))
PY
)"
PRODUCER_DIR="$CANDIDATE_ROOT/producer"
PRODUCER_LOG_DIR="$PRODUCER_DIR/logs"
EVIDENCE_DIR="$CANDIDATE_ROOT/capture-evidence"

# Resolve lexical traversal and existing symlink ancestors before safety decisions. Candidate roots
# are one-shot outputs: never target filesystem root, repository root, or an existing path.
if [[ -z "$CANDIDATE_ROOT" || "$CANDIDATE_ROOT" == "/" || "$CANDIDATE_ROOT" == "$ROOT" ]]; then
  echo "ARTIFACTS_DIR is not a safe field-production output path." >&2
  exit 9
fi
if [[ -e "$CANDIDATE_ROOT" || -L "$CANDIDATE_ROOT" ]]; then
  echo "Field-candidate output already exists; refusing to mix or overwrite evidence." >&2
  exit 10
fi
if [[ "$CANDIDATE_ROOT" == "$ROOT"/* ]]; then
  RELATIVE_CANDIDATE_ROOT="${CANDIDATE_ROOT#"$ROOT"/}"
  if ! git check-ignore -q -- "$RELATIVE_CANDIDATE_ROOT"; then
    echo "ARTIFACTS_DIR inside the repository must already be ignored by Git." >&2
    exit 11
  fi
fi

# Producer provenance is a sibling of inspector evidence. The inspector receives a nonexistent child
# so its own failure-atomic/no-replace directory publication remains authoritative.
mkdir -p "$PRODUCER_LOG_DIR"
EXPORT_OPTIONS_SNAPSHOT="$PRODUCER_DIR/ExportOptions.plist"
ARCHIVE_LOG="$PRODUCER_LOG_DIR/xcodebuild-archive.log"
EXPORT_LOG="$PRODUCER_LOG_DIR/xcodebuild-export.log"
ENVIRONMENT_RECORD="$PRODUCER_DIR/field-candidate-environment.txt"
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
  exit 12
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
  exit 13
fi
mkdir -p "$EXPORT_DIR"

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
  archive >"$ARCHIVE_LOG" 2>&1; then
  echo "Signed field-candidate archive failed; retained log contains exact xcodebuild output." >&2
  exit 14
fi

if ! run_xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_SNAPSHOT" \
  >"$EXPORT_LOG" 2>&1; then
  echo "Signed field-candidate export failed; retained log contains exact xcodebuild output." >&2
  exit 15
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
  exit 16
fi

POST_BUILD_SOURCE_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
POST_BUILD_HEAD="$(git rev-parse --verify HEAD^{commit})"
if [[ "$POST_BUILD_HEAD" != "$SOURCE_SHA" || -n "$POST_BUILD_SOURCE_STATUS" ]]; then
  echo "Archive/export changed immutable source state; refusing exact-HEAD candidate evidence." >&2
  printf '%s\n' "$POST_BUILD_SOURCE_STATUS" >&2
  exit 17
fi

# Python performs closed-world selection and returns exactly one regular top-level IPA. No nullglob
# or optional shell arrays are used under Bash 3.2 + nounset.
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

# EVIDENCE_DIR deliberately does not exist before this call. The intended device is verification-only
# input and is not retained by the inspector. Neither inspector success nor these records grant GO.
python3 scripts/ci/es80_signed_field_artifact_evidence.py \
  --ipa "$IPA_PATH" \
  --expected-source-sha "$SOURCE_SHA" \
  --intended-device-udid "$NEMBRA_FIELD_DEVICE_UDID" \
  --output-dir "$EVIDENCE_DIR"

EXTERNAL_RECORD="$EVIDENCE_DIR/NembraCaptureExternalBuildRecord.json"
FIELD_BUILD_RECORD="$EVIDENCE_DIR/NembraCaptureFieldBuildEvidenceRecord.json"
SIGNING_INSPECTION="$EVIDENCE_DIR/NembraCaptureSignedFieldArtifactInspection.json"
RETAINED_IPA="$EVIDENCE_DIR/build-evidence/NembraField.ipa"

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
from pathlib import PurePosixPath
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
    raise SystemExit("Signing inspection TeamIdentifier does not match requested development team")
if inspection.get("provisioningApplicationIdentifier") != f"{expected_team}.com.jonathangana131.nembra":
    raise SystemExit("Provisioning application identifier does not match requested team + Nembra bundle")

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

ipa_digest = hashlib.sha256()
with ipa_path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        ipa_digest.update(chunk)
if ipa_digest.hexdigest() != field.get("signedInstallableSHA256"):
    raise SystemExit("Retained IPA bytes do not match canonical field-build evidence")

# The canonical inspector has already fail-closed validated this exact IPA archive and retained these
# exact bytes. Reopen that immutable subject only to verify the app-visible Release launch marker that
# routes Home-Screen launch into Capture; this value remains routing, never physical authority.
with zipfile.ZipFile(ipa_path) as archive:
    info_members = []
    for info in archive.infolist():
        member = PurePosixPath(info.filename.rstrip("/"))
        parts = member.parts
        if (
            len(parts) == 3
            and parts[0] == "Payload"
            and parts[1].endswith(".app")
            and parts[2] == "Info.plist"
            and not info.is_dir()
        ):
            info_members.append(info)
    if len(info_members) != 1:
        raise SystemExit("Retained IPA does not contain exactly one top-level app Info.plist")
    try:
        info_plist = plistlib.loads(archive.read(info_members[0]))
    except Exception as error:
        raise SystemExit("Retained IPA app Info.plist is not a readable plist") from error
if not isinstance(info_plist, dict) or info_plist.get("NembraCaptureFieldRecipe") != field_recipe:
    raise SystemExit("Retained signed IPA does not contain the exact Capture Home-Screen launch recipe")

# Verification-only device identity must never become a retained evidence field.
def contains_udid_key(value):
    if isinstance(value, dict):
        return any("udid" in str(key).lower() or contains_udid_key(child) for key, child in value.items())
    if isinstance(value, list):
        return any(contains_udid_key(child) for child in value)
    return False

for record in (field, inspection):
    if contains_udid_key(record):
        raise SystemExit("Verification-only field-device identifier leaked into retained evidence schema")
PY

{
  echo "source_commit_sha=$SOURCE_SHA"
  echo "build_identifier=$BUILD_IDENTIFIER"
  echo "build_instance_id=$BUILD_INSTANCE_ID"
  echo "field_recipe_id=$FIELD_RECIPE_ID"
  echo "development_team=$NEMBRA_DEVELOPMENT_TEAM"
  echo "allow_provisioning_updates=$ALLOW_PROVISIONING_UPDATES"
  echo "export_options_file=producer/ExportOptions.plist"
  echo "export_options_sha256=$EXPORT_OPTIONS_SHA256"
  echo "archive_log=producer/logs/xcodebuild-archive.log"
  echo "export_log=producer/logs/xcodebuild-export.log"
  echo "capture_evidence_dir=capture-evidence"
  echo "experiment_recipe_id=ES80-FINGERPRINT-v1"
  echo "procedure_version=V14"
  echo "signing_inspection_authority=signed-field-artifact-inspection-not-field-authorization"
  echo "physical_authorization=not-granted"
  xcodebuild -version
} > "$ENVIRONMENT_RECORD"

echo "Signed Nembra iOS field-build CANDIDATE retained at: $CANDIDATE_ROOT"
echo "Independent acceptance has NOT occurred."
echo "PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN."
