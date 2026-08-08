#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Signed Capture IPA production requires macOS with Xcode 27." >&2
  exit 2
fi

for tool in git xcodebuild python3 shasum awk cp tee sw_vers; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool is unavailable: $tool" >&2
    exit 3
  fi
done

DEVELOPMENT_TEAM="${NEMBRA_DEVELOPMENT_TEAM:-}"
if [[ ! "$DEVELOPMENT_TEAM" =~ ^[A-Za-z0-9]{10}$ ]]; then
  echo "Set NEMBRA_DEVELOPMENT_TEAM to the intended exact 10-character Apple Developer Team ID." >&2
  exit 4
fi

EXPORT_OPTIONS_PLIST="${NEMBRA_EXPORT_OPTIONS_PLIST:-}"
if [[ -z "$EXPORT_OPTIONS_PLIST" || ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  echo "Set NEMBRA_EXPORT_OPTIONS_PLIST to an existing Xcode export-options plist for the intended field distribution." >&2
  echo "This producer deliberately does not guess or synthesize an Xcode export method." >&2
  exit 5
fi
EXPORT_OPTIONS_PLIST="$(cd "$(dirname "$EXPORT_OPTIONS_PLIST")" && pwd)/$(basename "$EXPORT_OPTIONS_PLIST")"

CAPTURE_BUILD_COMMIT_SHA="$(git rev-parse --verify HEAD^{commit})"
if [[ ! "$CAPTURE_BUILD_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Capture build identity requires one canonical lowercase 40-hex Git commit." >&2
  exit 6
fi

REPOSITORY_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$REPOSITORY_STATUS" ]]; then
  echo "Signed Capture IPA production refuses tracked changes or non-ignored untracked files." >&2
  printf '%s\n' "$REPOSITORY_STATUS" >&2
  exit 7
fi

CAPTURE_BUILD_IDENTIFIER="Capture Build V14-${CAPTURE_BUILD_COMMIT_SHA:0:12}"
CAPTURE_BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
if [[ ! "$CAPTURE_BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Capture build instance must be one canonical lowercase UUID." >&2
  exit 8
fi

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/artifacts/Xcode27FieldIPA-${CAPTURE_BUILD_COMMIT_SHA:0:12}-$CAPTURE_BUILD_INSTANCE_ID}"
DERIVED_DATA="${DERIVED_DATA:-${TMPDIR:-/tmp}/NembraFieldIPADerivedData-$CAPTURE_BUILD_INSTANCE_ID}"
ARCHIVE_PATH="$ARTIFACTS_DIR/NembraField.xcarchive"
EXPORT_PATH="$ARTIFACTS_DIR/export"
EVIDENCE_DIR="$ARTIFACTS_DIR/evidence"
LOGS_DIR="$ARTIFACTS_DIR/logs"
RETAINED_EXPORT_OPTIONS="$ARTIFACTS_DIR/ExportOptions.plist"

require_safe_generated_path() {
  local path="$1"
  local label="$2"
  if [[ -z "$path" || "$path" == "/" || "$path" == "$ROOT" ]]; then
    echo "$label is not a safe generated-output path: $path" >&2
    exit 9
  fi
  if [[ "$path" == "$ROOT"/* ]]; then
    local relative_path="${path#"$ROOT"/}"
    if ! git check-ignore -q -- "$relative_path"; then
      echo "$label inside the repository must already be ignored by Git: $relative_path" >&2
      exit 10
    fi
  fi
  if [[ -e "$path" ]]; then
    echo "$label already exists; refusing to delete or overwrite field-production state: $path" >&2
    exit 11
  fi
}
require_safe_generated_path "$ARTIFACTS_DIR" "ARTIFACTS_DIR"
require_safe_generated_path "$DERIVED_DATA" "DERIVED_DATA"

# Export settings are an explicit external release input. Retain their exact bytes and reject a
# conflicting team declaration without guessing Xcode 27's current export-method vocabulary.
python3 - "$EXPORT_OPTIONS_PLIST" "$DEVELOPMENT_TEAM" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected_team = sys.argv[2]
try:
    with path.open("rb") as handle:
        options = plistlib.load(handle)
except (OSError, plistlib.InvalidFileException) as exc:
    raise SystemExit(f"Export options plist is unreadable: {exc}")
if not isinstance(options, dict):
    raise SystemExit("Export options plist root must be a dictionary")
team = options.get("teamID")
if team is not None and team != expected_team:
    raise SystemExit("Export options teamID does not match NEMBRA_DEVELOPMENT_TEAM")
method = options.get("method")
if method is not None and (not isinstance(method, str) or not method.strip()):
    raise SystemExit("Export options method, when present, must be a non-empty string")
PY

mkdir -p "$EXPORT_PATH" "$LOGS_DIR" "$DERIVED_DATA"
cp -p "$EXPORT_OPTIONS_PLIST" "$RETAINED_EXPORT_OPTIONS"
EXPORT_OPTIONS_SHA256="$(shasum -a 256 "$RETAINED_EXPORT_OPTIONS" | awk '{print $1}')"
if [[ ! "$EXPORT_OPTIONS_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not derive canonical export-options SHA-256." >&2
  exit 12
fi

{
  echo "status=PRODUCER_EVIDENCE_ONLY_NOT_FIELD_AUTHORIZATION"
  echo "capture_build_identifier=$CAPTURE_BUILD_IDENTIFIER"
  echo "capture_build_instance_id=$CAPTURE_BUILD_INSTANCE_ID"
  echo "capture_build_commit_sha=$CAPTURE_BUILD_COMMIT_SHA"
  echo "requested_development_team=$DEVELOPMENT_TEAM"
  echo "export_options_sha256=$EXPORT_OPTIONS_SHA256"
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sw_vers
  xcodebuild -version
} > "$ARTIFACTS_DIR/producer-environment.txt"

set +e
set -o pipefail
xcodebuild \
  -project Nembra.xcodeproj \
  -scheme Nembra \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  "INFOPLIST_KEY_NembraCaptureBuildIdentifier=$CAPTURE_BUILD_IDENTIFIER" \
  "INFOPLIST_KEY_NembraCaptureBuildInstanceID=$CAPTURE_BUILD_INSTANCE_ID" \
  "INFOPLIST_KEY_NembraCaptureBuildCommitSHA=$CAPTURE_BUILD_COMMIT_SHA" \
  archive \
  | tee "$LOGS_DIR/xcodebuild-archive.log"
ARCHIVE_STATUS=${PIPESTATUS[0]}
set -e
if [[ "$ARCHIVE_STATUS" -ne 0 ]]; then
  echo "Signed Capture archive failed with status $ARCHIVE_STATUS." >&2
  echo "No field authorization was produced." >&2
  exit "$ARCHIVE_STATUS"
fi

POST_ARCHIVE_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$POST_ARCHIVE_STATUS" ]]; then
  echo "Archive changed non-ignored repository state; refusing exact-HEAD production evidence." >&2
  printf '%s\n' "$POST_ARCHIVE_STATUS" >&2
  exit 13
fi

set +e
set -o pipefail
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$RETAINED_EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  | tee "$LOGS_DIR/xcodebuild-export.log"
EXPORT_STATUS=${PIPESTATUS[0]}
set -e
if [[ "$EXPORT_STATUS" -ne 0 ]]; then
  echo "Signed Capture IPA export failed with status $EXPORT_STATUS." >&2
  echo "No field authorization was produced." >&2
  exit "$EXPORT_STATUS"
fi

POST_EXPORT_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$POST_EXPORT_STATUS" ]]; then
  echo "Export changed non-ignored repository state; refusing exact-HEAD production evidence." >&2
  printf '%s\n' "$POST_EXPORT_STATUS" >&2
  exit 14
fi

EXPORTED_IPA="$(python3 - "$EXPORT_PATH" <<'PY'
import sys
from pathlib import Path

export_path = Path(sys.argv[1])
candidates = sorted(path for path in export_path.iterdir() if path.is_file() and path.suffix.lower() == ".ipa")
if len(candidates) != 1:
    rendered = ", ".join(str(path) for path in candidates) or "<none>"
    raise SystemExit(f"Expected exactly one exported IPA; found {len(candidates)}: {rendered}")
print(candidates[0])
PY
)"

# There is one machine-readable field-build contract on the flagship. The producer feeds its exact
# exported IPA into that verifier instead of creating a second candidate/evidence schema.
python3 scripts/ci/es80_signed_field_artifact_evidence.py \
  --ipa "$EXPORTED_IPA" \
  --output-dir "$EVIDENCE_DIR" \
  --expected-source-sha "$CAPTURE_BUILD_COMMIT_SHA" \
  > "$LOGS_DIR/canonical-field-evidence.log"

EXTERNAL_RECORD="$EVIDENCE_DIR/NembraCaptureExternalBuildRecord.json"
FIELD_BUILD_RECORD="$EVIDENCE_DIR/NembraCaptureFieldBuildEvidenceRecord.json"
SIGNING_INSPECTION="$EVIDENCE_DIR/NembraCaptureSignedFieldArtifactInspection.json"
RETAINED_IPA="$EVIDENCE_DIR/build-evidence/NembraField.ipa"

# Producer-side consistency only. The canonical inspector must have measured the exact requested
# signing team and the same build/IPA subjects carried by the package rendezvous record. None of
# these checks is independent acceptance or field authorization.
python3 - \
  "$EXTERNAL_RECORD" \
  "$FIELD_BUILD_RECORD" \
  "$SIGNING_INSPECTION" \
  "$RETAINED_IPA" \
  "$DEVELOPMENT_TEAM" \
  "$CAPTURE_BUILD_IDENTIFIER" \
  "$CAPTURE_BUILD_INSTANCE_ID" \
  "$CAPTURE_BUILD_COMMIT_SHA" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

external_path = Path(sys.argv[1])
field_build_path = Path(sys.argv[2])
inspection_path = Path(sys.argv[3])
retained_ipa = Path(sys.argv[4])
expected_team = sys.argv[5]
expected_build = sys.argv[6]
expected_instance = sys.argv[7]
expected_source = sys.argv[8]

external = json.loads(external_path.read_text(encoding="utf-8"))
field_build = json.loads(field_build_path.read_text(encoding="utf-8"))
inspection = json.loads(inspection_path.read_text(encoding="utf-8"))

if inspection.get("authority") != "signed-field-artifact-inspection-not-field-authorization":
    raise SystemExit("canonical signing inspection authority class changed or is not evidence-only")
if inspection.get("teamIdentifier") != expected_team:
    raise SystemExit("final exported IPA TeamIdentifier does not match requested development team")
if field_build.get("signedInstallableKind") != "ipa" or inspection.get("signedInstallableKind") != "ipa":
    raise SystemExit("canonical field evidence no longer identifies the retained signed installable as IPA")

for key, expected in (
    ("buildIdentifier", expected_build),
    ("buildInstanceID", expected_instance),
    ("sourceCommitSHA", expected_source),
):
    if external.get(key) != expected or field_build.get(key) != expected or inspection.get(key) != expected:
        raise SystemExit(f"canonical field evidence build tuple mismatch for {key}")

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

retained_ipa_sha = sha256(retained_ipa)
external_sha = hashlib.sha256(external_path.read_bytes()).hexdigest()
field_build_sha = hashlib.sha256(field_build_path.read_bytes()).hexdigest()

if retained_ipa_sha != field_build.get("signedInstallableSHA256"):
    raise SystemExit("retained canonical IPA does not match field-build evidence")
if inspection.get("signedInstallableSHA256") != retained_ipa_sha:
    raise SystemExit("signing inspection does not bind the retained canonical IPA")
if field_build.get("externalBuildRecordSHA256") != external_sha:
    raise SystemExit("field-build evidence does not bind exact external build-record bytes")
if inspection.get("externalBuildRecordSHA256") != external_sha:
    raise SystemExit("signing inspection does not bind exact external build-record bytes")
if inspection.get("fieldBuildEvidenceRecordSHA256") != field_build_sha:
    raise SystemExit("signing inspection does not bind exact field-build evidence bytes")
PY

IPA_SHA256="$(shasum -a 256 "$RETAINED_IPA" | awk '{print $1}')"
EXTERNAL_RECORD_SHA256="$(shasum -a 256 "$EXTERNAL_RECORD" | awk '{print $1}')"
FIELD_BUILD_RECORD_SHA256="$(shasum -a 256 "$FIELD_BUILD_RECORD" | awk '{print $1}')"
SIGNING_INSPECTION_SHA256="$(shasum -a 256 "$SIGNING_INSPECTION" | awk '{print $1}')"

printf '%s\n' \
  "canonical_retained_ipa=$RETAINED_IPA" \
  "canonical_retained_ipa_sha256=$IPA_SHA256" \
  "canonical_external_build_record=$EXTERNAL_RECORD" \
  "canonical_external_build_record_sha256=$EXTERNAL_RECORD_SHA256" \
  "canonical_field_build_record=$FIELD_BUILD_RECORD" \
  "canonical_field_build_record_sha256=$FIELD_BUILD_RECORD_SHA256" \
  "canonical_signing_inspection=$SIGNING_INSPECTION" \
  "canonical_signing_inspection_sha256=$SIGNING_INSPECTION_SHA256" \
  >> "$ARTIFACTS_DIR/producer-environment.txt"

cat <<EOF
SIGNED CAPTURE IPA CANDIDATE PRODUCED
source: $CAPTURE_BUILD_COMMIT_SHA
build instance: $CAPTURE_BUILD_INSTANCE_ID
requested/verified team: $DEVELOPMENT_TEAM
retained IPA: $RETAINED_IPA
retained IPA sha256: $IPA_SHA256
external schema-v3 record: $EXTERNAL_RECORD
canonical field-build record: $FIELD_BUILD_RECORD
canonical signing inspection: $SIGNING_INSPECTION

THIS IS PRODUCER + EVIDENCE OUTPUT ONLY, NOT PHYSICAL FIELD AUTHORIZATION.
Experiment One remains NO-GO until these exact retained bytes receive independent acceptance,
the externally controlled authorization trust root is deliberately configured, the package gate
accepts that exact authorization, and the final runbook is changed to GO for that exact build.
EOF
