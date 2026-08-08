#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Signed Capture IPA production requires macOS with Xcode 27." >&2
  exit 2
fi

for tool in git xcodebuild python3 shasum find cp tee; do
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
  echo "This producer deliberately does not guess or synthesize an export method." >&2
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

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/artifacts/Xcode27FieldIPA}"
DERIVED_DATA="${DERIVED_DATA:-${TMPDIR:-/tmp}/NembraFieldIPADerivedData}"
ARCHIVE_PATH="$ARTIFACTS_DIR/NembraField.xcarchive"
EXPORT_PATH="$ARTIFACTS_DIR/export"
EVIDENCE_DIR="$ARTIFACTS_DIR/evidence"
LOGS_DIR="$ARTIFACTS_DIR/logs"
RETAINED_EXPORT_OPTIONS="$ARTIFACTS_DIR/ExportOptions.plist"
BUNDLE_ID="com.jonathangana131.nembra"
CAPTURE_BUILD_IDENTIFIER="Capture Build V14-${CAPTURE_BUILD_COMMIT_SHA:0:12}"
CAPTURE_BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"

require_safe_generated_path() {
  local path="$1"
  local label="$2"
  if [[ "$path" == "$ROOT"/* ]]; then
    local relative_path="${path#"$ROOT"/}"
    if ! git check-ignore -q -- "$relative_path"; then
      echo "$label inside the repository must already be ignored by Git: $relative_path" >&2
      exit 8
    fi
  fi
}
require_safe_generated_path "$ARTIFACTS_DIR" "ARTIFACTS_DIR"
require_safe_generated_path "$DERIVED_DATA" "DERIVED_DATA"

if [[ ! "$CAPTURE_BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Capture build instance must be one canonical lowercase UUID." >&2
  exit 9
fi

# Export settings are an explicit external production input. Retain their exact bytes and reject a
# conflicting team declaration without guessing what export methods Xcode 27 supports.
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

rm -rf "$ARTIFACTS_DIR" "$DERIVED_DATA"
mkdir -p "$EXPORT_PATH" "$LOGS_DIR"
cp -p "$EXPORT_OPTIONS_PLIST" "$RETAINED_EXPORT_OPTIONS"
EXPORT_OPTIONS_SHA256="$(shasum -a 256 "$RETAINED_EXPORT_OPTIONS" | awk '{print $1}')"
if [[ ! "$EXPORT_OPTIONS_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not derive canonical export-options SHA-256." >&2
  exit 10
fi

{
  echo "status=PRODUCER_EVIDENCE_ONLY_NOT_FIELD_AUTHORIZATION"
  echo "capture_build_identifier=$CAPTURE_BUILD_IDENTIFIER"
  echo "capture_build_instance_id=$CAPTURE_BUILD_INSTANCE_ID"
  echo "capture_build_commit_sha=$CAPTURE_BUILD_COMMIT_SHA"
  echo "requested_development_team=$DEVELOPMENT_TEAM"
  echo "export_options_sha256=$EXPORT_OPTIONS_SHA256"
  echo "bundle_identifier=$BUNDLE_ID"
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
  exit 11
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
  exit 12
fi

IPA_FILES=()
while IFS= read -r ipa_path; do
  IPA_FILES+=("$ipa_path")
done < <(find "$EXPORT_PATH" -maxdepth 1 -type f -name '*.ipa' -print | LC_ALL=C sort)

if [[ "${#IPA_FILES[@]}" -ne 1 ]]; then
  echo "Expected exactly one exported IPA; found ${#IPA_FILES[@]}." >&2
  printf 'candidate: %s\n' "${IPA_FILES[@]:-<none>}" >&2
  exit 13
fi
EXPORTED_IPA="${IPA_FILES[0]}"

# The flagship owns one canonical signed-IPA verifier/evidence format. Feed the exported IPA into it
# instead of minting a second candidate schema here.
python3 scripts/ci/es80_signed_field_artifact_evidence.py \
  --ipa "$EXPORTED_IPA" \
  --output-dir "$EVIDENCE_DIR" \
  --expected-source-sha "$CAPTURE_BUILD_COMMIT_SHA" \
  > "$LOGS_DIR/canonical-field-evidence.log"

FIELD_EVIDENCE="$EVIDENCE_DIR/NembraCaptureSignedFieldArtifactEvidence.json"
EXTERNAL_RECORD="$EVIDENCE_DIR/NembraCaptureExternalBuildRecord.json"
RETAINED_IPA="$EVIDENCE_DIR/build-evidence/NembraField.ipa"

# Producer-side consistency only: the canonical verifier must have measured the same requested team,
# exact source/build tuple and evidence-only authority class. This is not independent acceptance.
python3 - \
  "$FIELD_EVIDENCE" \
  "$EXTERNAL_RECORD" \
  "$RETAINED_IPA" \
  "$DEVELOPMENT_TEAM" \
  "$CAPTURE_BUILD_IDENTIFIER" \
  "$CAPTURE_BUILD_INSTANCE_ID" \
  "$CAPTURE_BUILD_COMMIT_SHA" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

field_path = Path(sys.argv[1])
external_path = Path(sys.argv[2])
retained_ipa = Path(sys.argv[3])
expected_team = sys.argv[4]
expected_build = sys.argv[5]
expected_instance = sys.argv[6]
expected_source = sys.argv[7]

field = json.loads(field_path.read_text(encoding="utf-8"))
external = json.loads(external_path.read_text(encoding="utf-8"))
if field.get("authority") != "signed-field-artifact-evidence-not-field-authorization":
    raise SystemExit("canonical field evidence authority class changed or is not evidence-only")
if field.get("teamIdentifier") != expected_team:
    raise SystemExit("final exported IPA TeamIdentifier does not match requested development team")
for key, expected in (
    ("buildIdentifier", expected_build),
    ("buildInstanceID", expected_instance),
    ("sourceCommitSHA", expected_source),
):
    if field.get(key) != expected or external.get(key) != expected:
        raise SystemExit(f"canonical evidence build tuple mismatch for {key}")

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

if sha256(retained_ipa) != field.get("ipaSHA256"):
    raise SystemExit("retained canonical IPA does not match canonical field evidence")
if hashlib.sha256(external_path.read_bytes()).hexdigest() != field.get("externalBuildRecordSHA256"):
    raise SystemExit("canonical external build-record bytes do not match field evidence")
PY

IPA_SHA256="$(shasum -a 256 "$RETAINED_IPA" | awk '{print $1}')"
EXTERNAL_RECORD_SHA256="$(shasum -a 256 "$EXTERNAL_RECORD" | awk '{print $1}')"
FIELD_EVIDENCE_SHA256="$(shasum -a 256 "$FIELD_EVIDENCE" | awk '{print $1}')"

printf '%s\n' \
  "canonical_retained_ipa=$RETAINED_IPA" \
  "canonical_retained_ipa_sha256=$IPA_SHA256" \
  "canonical_external_build_record=$EXTERNAL_RECORD" \
  "canonical_external_build_record_sha256=$EXTERNAL_RECORD_SHA256" \
  "canonical_signed_field_evidence=$FIELD_EVIDENCE" \
  "canonical_signed_field_evidence_sha256=$FIELD_EVIDENCE_SHA256" \
  >> "$ARTIFACTS_DIR/producer-environment.txt"

cat <<EOF
SIGNED CAPTURE IPA CANDIDATE PRODUCED
source: $CAPTURE_BUILD_COMMIT_SHA
build instance: $CAPTURE_BUILD_INSTANCE_ID
requested/verified team: $DEVELOPMENT_TEAM
retained IPA: $RETAINED_IPA
retained IPA sha256: $IPA_SHA256
external schema-v3 record: $EXTERNAL_RECORD
canonical signed-field evidence: $FIELD_EVIDENCE

THIS IS PRODUCER + EVIDENCE OUTPUT ONLY, NOT PHYSICAL FIELD AUTHORIZATION.
Experiment One remains NO-GO until these exact retained bytes receive independent acceptance,
the externally controlled authorization trust root is deliberately configured, the package gate
accepts that exact authorization, and the final runbook is changed to GO for that exact build.
EOF
