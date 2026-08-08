#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TEAM_ID="${NEMBRA_DEVELOPMENT_TEAM:-}"
DEVICE_UDID="${NEMBRA_DEVICE_UDID:-}"
if [[ -z "$TEAM_ID" ]]; then
  echo "NO-GO: set NEMBRA_DEVELOPMENT_TEAM to the Apple signing team used by Xcode." >&2
  exit 2
fi
if [[ ! "$TEAM_ID" =~ ^[A-Za-z0-9]{5,64}$ ]]; then
  echo "NO-GO: NEMBRA_DEVELOPMENT_TEAM is malformed." >&2
  exit 3
fi
if [[ -z "$DEVICE_UDID" ]]; then
  echo "NO-GO: set NEMBRA_DEVICE_UDID to the exact physical iPhone intended for the field build." >&2
  exit 4
fi
if [[ ! "$DEVICE_UDID" =~ ^[A-Za-z0-9-]{8,128}$ ]]; then
  echo "NO-GO: NEMBRA_DEVICE_UDID is malformed." >&2
  exit 5
fi

for tool in git xcodebuild python3 codesign security shasum ditto; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "NO-GO: required macOS/Xcode tool is unavailable: $tool" >&2
    exit 6
  fi
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "NO-GO: signed ES80 field candidates must be produced on macOS with Xcode signing." >&2
  exit 7
fi

SOURCE_COMMIT_SHA="$(git rev-parse --verify HEAD^{commit})"
if [[ ! "$SOURCE_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "NO-GO: exact source identity requires one canonical 40-hex commit." >&2
  exit 8
fi

# Refuse all tracked and non-ignored untracked inputs before creating output. SwiftPM/Xcode can
# discover new source files, so a clean index alone is not enough to establish exact source truth.
REPOSITORY_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$REPOSITORY_STATUS" ]]; then
  echo "NO-GO: field candidate refuses tracked changes or non-ignored untracked build inputs." >&2
  printf '%s\n' "$REPOSITORY_STATUS" >&2
  exit 9
fi

XCODE_VERSION="$(xcodebuild -version)"
if ! grep -Eq '^Xcode 27([. ]|$)' <<<"$XCODE_VERSION"; then
  echo "NO-GO: V14 field candidate requires Xcode 27; found:" >&2
  printf '%s\n' "$XCODE_VERSION" >&2
  exit 10
fi

BUILD_IDENTIFIER="Capture Build V14-${SOURCE_COMMIT_SHA:0:12}"
BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
if [[ ! "$BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "NO-GO: generated build-instance identifier is not a canonical lowercase UUID." >&2
  exit 11
fi
RECIPE_ID="ES80-FINGERPRINT-v1"
PROCEDURE_VERSION="V14"

DEFAULT_ARTIFACTS="$ROOT/Artifacts/ES80FieldCandidate/${SOURCE_COMMIT_SHA:0:12}-$BUILD_INSTANCE_ID"
ARTIFACTS_DIR="${FIELD_ARTIFACTS_DIR:-$DEFAULT_ARTIFACTS}"
ARCHIVE_PATH="$ARTIFACTS_DIR/NembraField.xcarchive"
STAGING_DIR="$ARTIFACTS_DIR/ipa-staging"
IPA_PATH="$ARTIFACTS_DIR/Nembra.ipa"
EXTERNAL_RECORD="$ARTIFACTS_DIR/NembraCaptureExternalBuildRecord.json"
FIELD_EVIDENCE="$ARTIFACTS_DIR/NembraCaptureFieldBuildEvidenceRecord.json"
VERIFICATION_METADATA="$ARTIFACTS_DIR/NembraCaptureFieldVerificationMetadata.json"
MANIFEST="$ARTIFACTS_DIR/SHA256SUMS.txt"
ENVIRONMENT="$ARTIFACTS_DIR/environment.txt"
BUILD_LOG="$ARTIFACTS_DIR/xcodebuild-archive.log"

mkdir -p "$ARTIFACTS_DIR"
rm -rf "$ARCHIVE_PATH" "$STAGING_DIR" "$IPA_PATH"

{
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "authority=candidate-evidence-only-not-field-authorization"
  echo "source_commit_sha=$SOURCE_COMMIT_SHA"
  echo "build_identifier=$BUILD_IDENTIFIER"
  echo "build_instance_id=$BUILD_INSTANCE_ID"
  echo "recipe_id=$RECIPE_ID"
  echo "procedure_version=$PROCEDURE_VERSION"
  echo "bundle_identifier=com.jonathangana131.nembra"
  echo "target_device_udid_retained=false"
  printf '%s\n' "$XCODE_VERSION"
  sw_vers
} > "$ENVIRONMENT"

# The repository intentionally does not carry a DEVELOPMENT_TEAM. The operator supplies the actual
# Xcode team at execution time so GitHub/Simulator state cannot impersonate physical signing.
# Automatic signing may update/register provisioning only through the user's authenticated Xcode
# account. The produced candidate is still evidence only; this script never changes the package GO
# gate or the physical runbook.
set +e
set -o pipefail
xcodebuild \
  -project Nembra.xcodeproj \
  -scheme Nembra \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  "INFOPLIST_KEY_NembraCaptureBuildIdentifier=$BUILD_IDENTIFIER" \
  "INFOPLIST_KEY_NembraCaptureBuildInstanceID=$BUILD_INSTANCE_ID" \
  "INFOPLIST_KEY_NembraCaptureBuildCommitSHA=$SOURCE_COMMIT_SHA" \
  archive \
  | tee "$BUILD_LOG"
ARCHIVE_STATUS=${PIPESTATUS[0]}
set -e
if [[ "$ARCHIVE_STATUS" -ne 0 ]]; then
  echo "NO-GO: Xcode failed to produce the signed field archive; see $BUILD_LOG" >&2
  exit "$ARCHIVE_STATUS"
fi

APP_PATH="$ARCHIVE_PATH/Products/Applications/Nembra.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "NO-GO: archive does not contain Products/Applications/Nembra.app" >&2
  exit 12
fi

INFO_PLIST="$APP_PATH/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "NO-GO: archived app has no root Info.plist" >&2
  exit 13
fi
for key in NembraCaptureBuildIdentifier NembraCaptureBuildInstanceID NembraCaptureBuildCommitSHA; do
  if ! /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" >/dev/null 2>&1; then
    echo "NO-GO: archived app is missing required provenance key: $key" >&2
    exit 14
  fi
done
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildIdentifier' "$INFO_PLIST")" != "$BUILD_IDENTIFIER" ]]; then
  echo "NO-GO: archived app build identifier differs from the field candidate tuple." >&2
  exit 15
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildInstanceID' "$INFO_PLIST")" != "$BUILD_INSTANCE_ID" ]]; then
  echo "NO-GO: archived app build-instance ID differs from the field candidate tuple." >&2
  exit 16
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildCommitSHA' "$INFO_PLIST")" != "$SOURCE_COMMIT_SHA" ]]; then
  echo "NO-GO: archived app source commit differs from the field candidate tuple." >&2
  exit 17
fi

codesign --verify --strict --all-architectures --verbose=4 "$APP_PATH"
if [[ ! -f "$APP_PATH/embedded.mobileprovision" ]]; then
  echo "NO-GO: signed field archive has no embedded provisioning profile." >&2
  exit 18
fi

# Package the already-signed archive app without rewriting its bundle. The verifier below extracts
# this exact IPA, re-hashes its executable/Info.plist, checks code signing, decodes the embedded
# provisioning profile, and requires that profile to cover NEMBRA_DEVICE_UDID.
mkdir -p "$STAGING_DIR/Payload"
ditto "$APP_PATH" "$STAGING_DIR/Payload/Nembra.app"
(
  cd "$STAGING_DIR"
  /usr/bin/zip -qry --symlinks "$IPA_PATH" Payload
)
if [[ ! -f "$IPA_PATH" ]]; then
  echo "NO-GO: failed to package the exact signed Nembra.app as an IPA." >&2
  exit 19
fi

python3 - \
  "$IPA_PATH" \
  "$EXTERNAL_RECORD" \
  "$BUILD_IDENTIFIER" \
  "$BUILD_INSTANCE_ID" \
  "$SOURCE_COMMIT_SHA" \
  "$RECIPE_ID" \
  "$PROCEDURE_VERSION" <<'PY'
import hashlib
import json
import plistlib
import sys
import zipfile
from pathlib import PurePosixPath

(
    ipa_path,
    record_path,
    build_identifier,
    build_instance_id,
    source_commit_sha,
    recipe_id,
    procedure_version,
) = sys.argv[1:]

with zipfile.ZipFile(ipa_path, "r") as archive:
    names = archive.namelist()
    app_roots = {
        f"Payload/{parts[1]}"
        for name in names
        for parts in [PurePosixPath(name).parts]
        if len(parts) >= 2 and parts[0] == "Payload" and parts[1].endswith(".app")
    }
    if len(app_roots) != 1:
        raise SystemExit(f"field IPA must contain exactly one app root; found {sorted(app_roots)}")
    app_root = next(iter(app_roots))
    info_bytes = archive.read(f"{app_root}/Info.plist")
    info = plistlib.loads(info_bytes)
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name:
        raise SystemExit("field IPA Info.plist has no CFBundleExecutable")
    executable_bytes = archive.read(f"{app_root}/{executable_name}")

if info.get("NembraCaptureBuildIdentifier") != build_identifier:
    raise SystemExit("packaged IPA changed the embedded Capture build identifier")
if info.get("NembraCaptureBuildInstanceID") != build_instance_id:
    raise SystemExit("packaged IPA changed the embedded Capture build-instance ID")
if info.get("NembraCaptureBuildCommitSHA") != source_commit_sha:
    raise SystemExit("packaged IPA changed the embedded Capture source commit")

record = {
    "schemaVersion": 3,
    "buildIdentifier": build_identifier,
    "buildInstanceID": build_instance_id,
    "sourceCommitSHA": source_commit_sha,
    "executableSHA256": hashlib.sha256(executable_bytes).hexdigest(),
    "infoPlistSHA256": hashlib.sha256(info_bytes).hexdigest(),
    "experimentRecipeID": recipe_id,
    "procedureVersion": procedure_version,
}
with open(record_path, "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

python3 scripts/ci/verify_es80_field_artifact.py \
  --ipa "$IPA_PATH" \
  --external-build-record "$EXTERNAL_RECORD" \
  --expected-source-commit "$SOURCE_COMMIT_SHA" \
  --expected-device-udid "$DEVICE_UDID" \
  --output "$FIELD_EVIDENCE" \
  --metadata-output "$VERIFICATION_METADATA"

(
  cd "$ARTIFACTS_DIR"
  shasum -a 256 \
    "$(basename "$IPA_PATH")" \
    "$(basename "$EXTERNAL_RECORD")" \
    "$(basename "$FIELD_EVIDENCE")" \
    "$(basename "$VERIFICATION_METADATA")" \
    > "$(basename "$MANIFEST")"
)

{
  echo "ipa_sha256=$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"
  echo "external_build_record_sha256=$(shasum -a 256 "$EXTERNAL_RECORD" | awk '{print $1}')"
  echo "field_build_evidence_sha256=$(shasum -a 256 "$FIELD_EVIDENCE" | awk '{print $1}')"
  echo "target_device_provisioning_matched=true"
  echo "physical_authorization=NO-GO"
} >> "$ENVIRONMENT"

rm -rf "$STAGING_DIR"

cat <<EOF
FIELD CANDIDATE VERIFIED — EVIDENCE ONLY / PHYSICAL EXPERIMENT REMAINS NO-GO

Exact source:        $SOURCE_COMMIT_SHA
Build instance:      $BUILD_INSTANCE_ID
Signed IPA:          $IPA_PATH
External build record: $EXTERNAL_RECORD
Field evidence:      $FIELD_EVIDENCE
Verification metadata: $VERIFICATION_METADATA
SHA-256 manifest:    $MANIFEST
Archive retained:    $ARCHIVE_PATH

The target device UDID was used only for local provisioning verification and is not written into
these evidence records. Independent exact-artifact acceptance plus the package field gate and V14
runbook must still deliberately become GO before the ES80 physical procedure can run.
EOF
