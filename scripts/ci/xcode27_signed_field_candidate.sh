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
: "${NEMBRA_FIELD_DEVICE_UDID:?Set NEMBRA_FIELD_DEVICE_UDID to the intended field iPhone UDID for verification only.}"

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

# macOS still ships an older /bin/bash. Avoid optionally empty arrays under `set -u`: Bash 3.2 can
# treat expansion of an empty array as an unbound variable before Xcode ever runs.
run_xcodebuild() {
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    xcodebuild -allowProvisioningUpdates "$@"
  else
    xcodebuild "$@"
  fi
}

# A dirty invocation checkout is never accepted. This is defense in depth only: the actual build
# below is performed from a fresh detached worktree at SOURCE_SHA so a later mutation, ignored file,
# or concurrent worker cannot silently become bytes stamped as this exact commit.
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

# These spellings are owned by the accepted V14 field-candidate/build-evidence contracts. The field
# recipe is launch routing only; its signed Info.plist bytes are evidence, never physical authority.
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

# Field-production evidence is immutable output. Resolve lexical traversal and existing symlink
# ancestors before safety decisions; never allow a root/repository target and never mix a new
# candidate into an existing directory.
if [[ -z "$ARTIFACTS_DIR" || "$ARTIFACTS_DIR" == "/" || "$ARTIFACTS_DIR" == "$ROOT" ]]; then
  echo "ARTIFACTS_DIR is not a safe field-production output path: $ARTIFACTS_DIR" >&2
  exit 9
fi
if [[ -e "$ARTIFACTS_DIR" || -L "$ARTIFACTS_DIR" ]]; then
  echo "ARTIFACTS_DIR already exists; refusing to mix or overwrite field-production evidence: $ARTIFACTS_DIR" >&2
  exit 10
fi

# Candidate evidence written inside the invocation checkout must already be ignored. Otherwise a
# successful producer run would silently dirty the operator checkout after admission.
if [[ "$ARTIFACTS_DIR" == "$ROOT"/* ]]; then
  RELATIVE_ARTIFACTS_DIR="${ARTIFACTS_DIR#"$ROOT"/}"
  if ! git check-ignore -q -- "$RELATIVE_ARTIFACTS_DIR"; then
    echo "ARTIFACTS_DIR inside the repository must already be ignored by Git: $RELATIVE_ARTIFACTS_DIR" >&2
    exit 11
  fi
fi

PRODUCER_EVIDENCE_DIR="$ARTIFACTS_DIR/producer-evidence"
FIELD_EVIDENCE_DIR="$ARTIFACTS_DIR/field-evidence"
LOGS_DIR="$PRODUCER_EVIDENCE_DIR/logs"
mkdir -p "$LOGS_DIR"

# The canonical inspector owns FIELD_EVIDENCE_DIR atomically and refuses preexisting output. Producer
# logs/export policy therefore live beside, never inside, the inspector-owned evidence subtree.
if [[ -e "$FIELD_EVIDENCE_DIR" || -L "$FIELD_EVIDENCE_DIR" ]]; then
  echo "Inspector evidence path unexpectedly exists before inspection: $FIELD_EVIDENCE_DIR" >&2
  exit 12
fi

EXPORT_OPTIONS_SNAPSHOT="$PRODUCER_EVIDENCE_DIR/ExportOptions.plist"
cp -p "$EXPORT_OPTIONS_PLIST" "$EXPORT_OPTIONS_SNAPSHOT"
/usr/bin/plutil -lint "$EXPORT_OPTIONS_SNAPSHOT" >/dev/null

# Export policy is an external release input, not source truth. Snapshot exactly the bytes that
# xcodebuild will consume, reject a conflicting teamID when present, and retain/hash that snapshot
# beside the signed artifact so independent acceptance can review the actual export policy used.
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
  2>&1 | tee "$LOGS_DIR/xcodebuild-archive.log"
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
  2>&1 | tee "$LOGS_DIR/xcodebuild-export.log"
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

# The detached worktree itself must still be clean after archive/export. Xcode products live under
# WORK_ROOT outside SOURCE_ROOT, so a visible source delta means the exact-commit build boundary was
# violated and no candidate evidence is allowed to be emitted.
POST_BUILD_SOURCE_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
POST_BUILD_HEAD="$(git rev-parse --verify HEAD^{commit})"
if [[ "$POST_BUILD_HEAD" != "$SOURCE_SHA" || -n "$POST_BUILD_SOURCE_STATUS" ]]; then
  echo "Archive/export changed immutable source state; refusing exact-HEAD candidate evidence." >&2
  printf '%s\n' "$POST_BUILD_SOURCE_STATUS" >&2
  exit 18
fi

# Avoid optional shell arrays under Bash 3.2 + nounset. Python performs closed-world selection of
# the final export subject and prints exactly one regular top-level .ipa path or fails the producer.
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

# Reuse the canonical post-build inspector from the same immutable source snapshot that produced
# the archive. The intended device UDID is verification-only input: the inspector requires it for
# provisioning admission but deliberately does not persist or print it.
python3 scripts/ci/es80_signed_field_artifact_evidence.py \
  --ipa "$IPA_PATH" \
  --expected-source-sha "$SOURCE_SHA" \
  --intended-device-udid "$NEMBRA_FIELD_DEVICE_UDID" \
  --output-dir "$FIELD_EVIDENCE_DIR"

EXTERNAL_RECORD="$FIELD_EVIDENCE_DIR/NembraCaptureExternalBuildRecord.json"
FIELD_BUILD_RECORD="$FIELD_EVIDENCE_DIR/NembraCaptureFieldBuildEvidenceRecord.json"
SIGNING_INSPECTION="$FIELD_EVIDENCE_DIR/NembraCaptureSignedFieldArtifactInspection.json"
RETAINED_IPA="$FIELD_EVIDENCE_DIR/build-evidence/NembraField.ipa"

# Converge the producer's own expectations against the canonical inspector without widening the
# package field-build schema. The final signed Info.plist recipe marker is checked from the exact
# retained IPA and its raw bytes must hash to the same infoPlistSHA256 already committed by field
# evidence. This proves launchability evidence without turning the marker into authority.
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
inspection_bytes = inspection_path.read_bytes()
field = json.loads(field_bytes)
inspection = json.loads(inspection_bytes)

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
    raise SystemExit(
        f"Signing inspection TeamIdentifier mismatch: {inspection.get('teamIdentifier')!r} != {expected_team!r}"
    )
if not re.fullmatch(r"[0-9a-f]{64}", inspection.get("provisioningProfileSHA256", "")):
    raise SystemExit("Signing inspection lacks exact embedded provisioning-profile digest evidence")
if not isinstance(inspection.get("provisioningProfileUUID"), str) or not inspection["provisioningProfileUUID"].strip():
    raise SystemExit("Signing inspection lacks provisioning-profile identity")

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

with zipfile.ZipFile(ipa_path) as archive:
    info_members = [
        name for name in archive.namelist()
        if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)
    ]
    if len(info_members) != 1:
        raise SystemExit(f"Retained IPA must expose exactly one top-level app Info.plist; found {len(info_members)}")
    raw_info = archive.read(info_members[0])
    info = plistlib.loads(raw_info)
if not isinstance(info, dict) or info.get("NembraCaptureFieldRecipe") != field_recipe:
    raise SystemExit("Final signed IPA does not carry the exact Capture Home-Screen launch recipe")
if hashlib.sha256(raw_info).hexdigest() != field.get("infoPlistSHA256"):
    raise SystemExit("Final signed launch-recipe Info.plist bytes disagree with canonical field-build evidence")
PY

EXTERNAL_RECORD_SHA256="$(python3 - "$EXTERNAL_RECORD" <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
)"
FIELD_BUILD_RECORD_SHA256="$(python3 - "$FIELD_BUILD_RECORD" <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
)"
SIGNING_INSPECTION_SHA256="$(python3 - "$SIGNING_INSPECTION" <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
)"
RETAINED_IPA_SHA256="$(python3 - "$RETAINED_IPA" <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
)"

{
  echo "source_commit_sha=$SOURCE_SHA"
  echo "build_identifier=$BUILD_IDENTIFIER"
  echo "build_instance_id=$BUILD_INSTANCE_ID"
  echo "field_launch_recipe_id=$FIELD_RECIPE_ID"
  echo "development_team=$NEMBRA_DEVELOPMENT_TEAM"
  echo "allow_provisioning_updates=$ALLOW_PROVISIONING_UPDATES"
  echo "intended_field_device_verified=yes"
  echo "export_options_file=producer-evidence/ExportOptions.plist"
  echo "export_options_sha256=$EXPORT_OPTIONS_SHA256"
  echo "archive_log=producer-evidence/logs/xcodebuild-archive.log"
  echo "export_log=producer-evidence/logs/xcodebuild-export.log"
  echo "field_evidence_dir=field-evidence"
  echo "external_build_record_sha256=$EXTERNAL_RECORD_SHA256"
  echo "field_build_record_sha256=$FIELD_BUILD_RECORD_SHA256"
  echo "signing_inspection_sha256=$SIGNING_INSPECTION_SHA256"
  echo "retained_ipa_sha256=$RETAINED_IPA_SHA256"
  echo "experiment_recipe_id=$FIELD_RECIPE_ID"
  echo "procedure_version=V14"
  echo "signing_inspection_authority=signed-field-artifact-inspection-not-field-authorization"
  echo "physical_authorization=not-granted"
  xcodebuild -version
} > "$PRODUCER_EVIDENCE_DIR/field-candidate-environment.txt"

echo "Signed Nembra iOS field-build CANDIDATE retained at: $ARTIFACTS_DIR"
echo "Exact ExportOptions.plist and archive/export logs were retained under producer-evidence/."
echo "Canonical signed-field evidence was atomically published under field-evidence/."
echo "The intended field-device identifier was used only for verification and was not retained."
echo "Independent acceptance has NOT occurred."
echo "PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN."
