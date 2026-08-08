#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Create and retain a signed iPhone Capture build candidate without authorizing a physical experiment.

Required:
  NEMBRA_DEVELOPMENT_TEAM       Apple development-team ID used by Xcode signing.
  NEMBRA_EXPORT_OPTIONS_PLIST   Path to an ExportOptions.plist produced/reviewed for the intended
                                device distribution path. You may also pass this path as argument 1.

Optional:
  NEMBRA_ALLOW_PROVISIONING_UPDATES=1       Allow Xcode to update signing assets.
  NEMBRA_ALLOW_DEVICE_REGISTRATION=1        Also allow device registration (requires the option above).
  ARTIFACTS_DIR=/path                         Defaults to ignored artifacts/Xcode27SignedDevice.
  DERIVED_DATA=/path                          Defaults to a temporary DerivedData directory.

This script archives and exports; it never installs or launches the app on a phone and it never
changes PassiveBluetoothExperimentOneFieldExecutionGate. Its output is signed-build evidence only,
not independent acceptance, field authorization, or physical ES80 truth.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

TEAM_ID="${NEMBRA_DEVELOPMENT_TEAM:-}"
EXPORT_OPTIONS_INPUT="${NEMBRA_EXPORT_OPTIONS_PLIST:-${1:-}}"
if [[ -z "$TEAM_ID" || -z "$EXPORT_OPTIONS_INPUT" ]]; then
  usage >&2
  exit 2
fi
if [[ ! "$TEAM_ID" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "NEMBRA_DEVELOPMENT_TEAM must be a non-empty alphanumeric Apple team identifier." >&2
  exit 3
fi
if [[ ! -f "$EXPORT_OPTIONS_INPUT" ]]; then
  echo "Export options plist not found: $EXPORT_OPTIONS_INPUT" >&2
  exit 4
fi
EXPORT_OPTIONS_INPUT="$(cd "$(dirname "$EXPORT_OPTIONS_INPUT")" && pwd -P)/$(basename "$EXPORT_OPTIONS_INPUT")"

for tool in xcodebuild python3 shasum unzip codesign security plutil git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool is unavailable: $tool" >&2
    exit 5
  fi
done
if [[ ! -x /usr/libexec/PlistBuddy ]]; then
  echo "Required tool is unavailable: /usr/libexec/PlistBuddy" >&2
  exit 5
fi
if ! plutil -lint "$EXPORT_OPTIONS_INPUT" >/dev/null; then
  echo "Export options plist is malformed: $EXPORT_OPTIONS_INPUT" >&2
  exit 6
fi

CAPTURE_BUILD_COMMIT_SHA="$(git rev-parse --verify HEAD^{commit})"
if [[ ! "$CAPTURE_BUILD_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Capture field build requires an exact 40-hex Git commit; got: $CAPTURE_BUILD_COMMIT_SHA" >&2
  exit 7
fi

# A field artifact must be attributable to exactly the checked-in source at HEAD. Ignored local
# build artifacts are permitted; every tracked modification and every non-ignored untracked file is
# rejected before Xcode is invoked.
REPOSITORY_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$REPOSITORY_STATUS" ]]; then
  echo "Signed Capture build refuses tracked changes or non-ignored untracked files." >&2
  printf '%s\n' "$REPOSITORY_STATUS" >&2
  exit 8
fi

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/artifacts/Xcode27SignedDevice}"
DERIVED_DATA="${DERIVED_DATA:-${TMPDIR:-/tmp}/NembraSignedDeviceDerivedData}"
ARCHIVE_PATH="$ARTIFACTS_DIR/Nembra.xcarchive"
EXPORT_DIR="$ARTIFACTS_DIR/export"
EVIDENCE_DIR="$ARTIFACTS_DIR/build-evidence"
INSPECTION_DIR="$ARTIFACTS_DIR/inspection"
LOGS_DIR="$ARTIFACTS_DIR/logs"
BUNDLE_ID="com.jonathangana131.nembra"
CAPTURE_RECIPE_IDENTIFIER="ES80-FINGERPRINT-v1"
CAPTURE_PROCEDURE_VERSION="V14"

rm -rf "$ARTIFACTS_DIR" "$DERIVED_DATA"
mkdir -p "$EXPORT_DIR" "$EVIDENCE_DIR" "$INSPECTION_DIR" "$LOGS_DIR"

CAPTURE_BUILD_IDENTIFIER="Capture Build V14-${CAPTURE_BUILD_COMMIT_SHA:0:12}"
CAPTURE_BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
if [[ ! "$CAPTURE_BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Capture build instance must be one canonical lowercase UUID; got: $CAPTURE_BUILD_INSTANCE_ID" >&2
  exit 9
fi

PROVISIONING_ARGS=()
if [[ "${NEMBRA_ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
  PROVISIONING_ARGS+=("-allowProvisioningUpdates")
fi
if [[ "${NEMBRA_ALLOW_DEVICE_REGISTRATION:-0}" == "1" ]]; then
  if [[ "${NEMBRA_ALLOW_PROVISIONING_UPDATES:-0}" != "1" ]]; then
    echo "Device registration requires NEMBRA_ALLOW_PROVISIONING_UPDATES=1." >&2
    exit 10
  fi
  PROVISIONING_ARGS+=("-allowProvisioningDeviceRegistration")
fi

RETAINED_EXPORT_OPTIONS="$EVIDENCE_DIR/ExportOptions.plist"
cp -p "$EXPORT_OPTIONS_INPUT" "$RETAINED_EXPORT_OPTIONS"
if ! cmp -s "$EXPORT_OPTIONS_INPUT" "$RETAINED_EXPORT_OPTIONS"; then
  echo "Retained ExportOptions.plist bytes diverged from the supplied file." >&2
  exit 11
fi

{
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "capture_build_identifier=$CAPTURE_BUILD_IDENTIFIER"
  echo "capture_build_instance_id=$CAPTURE_BUILD_INSTANCE_ID"
  echo "capture_build_commit_sha=$CAPTURE_BUILD_COMMIT_SHA"
  echo "capture_recipe_identifier=$CAPTURE_RECIPE_IDENTIFIER"
  echo "capture_procedure_version=$CAPTURE_PROCEDURE_VERSION"
  echo "development_team=$TEAM_ID"
  echo "platform=iphoneos"
  echo "configuration=Release"
  sw_vers
  xcodebuild -version
} > "$ARTIFACTS_DIR/environment.txt"

set +e
set -o pipefail
xcodebuild \
  -project Nembra.xcodeproj \
  -scheme Nembra \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  "${PROVISIONING_ARGS[@]}" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED=YES \
  "INFOPLIST_KEY_NembraCaptureBuildIdentifier=$CAPTURE_BUILD_IDENTIFIER" \
  "INFOPLIST_KEY_NembraCaptureBuildInstanceID=$CAPTURE_BUILD_INSTANCE_ID" \
  "INFOPLIST_KEY_NembraCaptureBuildCommitSHA=$CAPTURE_BUILD_COMMIT_SHA" \
  archive \
  | tee "$LOGS_DIR/xcodebuild-archive.log"
ARCHIVE_STATUS=${PIPESTATUS[0]}
set -e
if [[ "$ARCHIVE_STATUS" -ne 0 ]]; then
  echo "Signed Capture archive failed with status $ARCHIVE_STATUS." >&2
  exit "$ARCHIVE_STATUS"
fi

ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/Nembra.app"
if [[ ! -d "$ARCHIVE_APP" ]]; then
  echo "Expected signed archive app was not found at $ARCHIVE_APP" >&2
  exit 12
fi
ARCHIVE_INFO_PLIST="$ARCHIVE_APP/Info.plist"
ARCHIVE_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$ARCHIVE_INFO_PLIST" 2>/dev/null || true)"
ARCHIVE_EXECUTABLE="$ARCHIVE_APP/$ARCHIVE_EXECUTABLE_NAME"
if [[ -z "$ARCHIVE_EXECUTABLE_NAME" || ! -f "$ARCHIVE_EXECUTABLE" ]]; then
  echo "Could not resolve the archived Nembra executable." >&2
  exit 13
fi
if ! codesign --verify --deep --strict --verbose=2 "$ARCHIVE_APP" 2> "$LOGS_DIR/codesign-archive-verify.log"; then
  echo "Archived Nembra.app failed strict code-signature verification." >&2
  exit 14
fi

set +e
set -o pipefail
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$RETAINED_EXPORT_OPTIONS" \
  "${PROVISIONING_ARGS[@]}" \
  | tee "$LOGS_DIR/xcodebuild-export.log"
EXPORT_STATUS=${PIPESTATUS[0]}
set -e
if [[ "$EXPORT_STATUS" -ne 0 ]]; then
  echo "Signed Capture export failed with status $EXPORT_STATUS." >&2
  exit "$EXPORT_STATUS"
fi

IPA_COUNT="$(find "$EXPORT_DIR" -maxdepth 1 -type f -name '*.ipa' -print | wc -l | tr -d '[:space:]')"
if [[ "$IPA_COUNT" != "1" ]]; then
  echo "Expected exactly one exported IPA; found $IPA_COUNT." >&2
  find "$EXPORT_DIR" -maxdepth 1 -type f -print >&2 || true
  exit 15
fi
EXPORTED_IPA="$(find "$EXPORT_DIR" -maxdepth 1 -type f -name '*.ipa' -print | head -n 1)"
RETAINED_IPA="$EVIDENCE_DIR/Nembra.ipa"
cp -p "$EXPORTED_IPA" "$RETAINED_IPA"
if ! cmp -s "$EXPORTED_IPA" "$RETAINED_IPA"; then
  echo "Retained IPA bytes diverged from the exact Xcode export." >&2
  exit 16
fi

unzip -q "$RETAINED_IPA" -d "$INSPECTION_DIR"
FINAL_APP="$INSPECTION_DIR/Payload/Nembra.app"
if [[ ! -d "$FINAL_APP" ]]; then
  echo "Exported IPA does not contain the expected Payload/Nembra.app." >&2
  exit 17
fi
FINAL_INFO_PLIST="$FINAL_APP/Info.plist"
FINAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$FINAL_INFO_PLIST" 2>/dev/null || true)"
FINAL_BUILD_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildIdentifier' "$FINAL_INFO_PLIST" 2>/dev/null || true)"
FINAL_BUILD_INSTANCE_ID="$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildInstanceID' "$FINAL_INFO_PLIST" 2>/dev/null || true)"
FINAL_BUILD_COMMIT_SHA="$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildCommitSHA' "$FINAL_INFO_PLIST" 2>/dev/null || true)"
if [[ "$FINAL_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
  echo "Exported app bundle ID mismatch: $FINAL_BUNDLE_ID" >&2
  exit 18
fi
if [[ "$FINAL_BUILD_IDENTIFIER" != "$CAPTURE_BUILD_IDENTIFIER" ]]; then
  echo "Exported app lost the exact Capture build identifier." >&2
  exit 19
fi
if [[ "$FINAL_BUILD_INSTANCE_ID" != "$CAPTURE_BUILD_INSTANCE_ID" ]]; then
  echo "Exported app lost the exact Capture build-instance identifier." >&2
  exit 20
fi
if [[ "$FINAL_BUILD_COMMIT_SHA" != "$CAPTURE_BUILD_COMMIT_SHA" ]]; then
  echo "Exported app lost the exact Capture source commit SHA." >&2
  exit 21
fi

FINAL_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$FINAL_INFO_PLIST" 2>/dev/null || true)"
FINAL_EXECUTABLE="$FINAL_APP/$FINAL_EXECUTABLE_NAME"
if [[ -z "$FINAL_EXECUTABLE_NAME" || ! -f "$FINAL_EXECUTABLE" ]]; then
  echo "Could not resolve the exported Nembra executable." >&2
  exit 22
fi
if ! codesign --verify --deep --strict --verbose=2 "$FINAL_APP" 2> "$LOGS_DIR/codesign-export-verify.log"; then
  echo "Exported Nembra.app failed strict code-signature verification." >&2
  exit 23
fi
codesign -d --verbose=4 "$FINAL_APP" > /dev/null 2> "$EVIDENCE_DIR/codesign-display.txt"

FINAL_MOBILEPROVISION="$FINAL_APP/embedded.mobileprovision"
if [[ ! -f "$FINAL_MOBILEPROVISION" ]]; then
  echo "Exported device app has no embedded.mobileprovision; refusing field evidence promotion." >&2
  exit 24
fi
RETAINED_MOBILEPROVISION="$EVIDENCE_DIR/embedded.mobileprovision"
cp -p "$FINAL_MOBILEPROVISION" "$RETAINED_MOBILEPROVISION"
if ! cmp -s "$FINAL_MOBILEPROVISION" "$RETAINED_MOBILEPROVISION"; then
  echo "Retained provisioning-profile bytes diverged from the exported app." >&2
  exit 25
fi
PROVISIONING_PLIST="$EVIDENCE_DIR/embedded.mobileprovision.plist"
if ! security cms -D -i "$RETAINED_MOBILEPROVISION" > "$PROVISIONING_PLIST" 2> "$LOGS_DIR/security-cms.log"; then
  echo "Could not decode the exported app provisioning profile." >&2
  exit 26
fi

PROFILE_TEAM_ID="$(python3 - "$PROVISIONING_PLIST" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as handle:
    profile = plistlib.load(handle)
teams = profile.get("TeamIdentifier") or []
print(teams[0] if len(teams) == 1 else "")
PY
)"
PROFILE_APPLICATION_ID="$(python3 - "$PROVISIONING_PLIST" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as handle:
    profile = plistlib.load(handle)
print((profile.get("Entitlements") or {}).get("application-identifier", ""))
PY
)"
if [[ -z "$PROFILE_TEAM_ID" || "$PROFILE_TEAM_ID" != "$TEAM_ID" ]]; then
  echo "Provisioning profile team '$PROFILE_TEAM_ID' does not match requested team '$TEAM_ID'." >&2
  exit 27
fi
if [[ "$PROFILE_APPLICATION_ID" != *".$BUNDLE_ID" ]]; then
  echo "Provisioning application identifier does not bind the Nembra bundle ID: $PROFILE_APPLICATION_ID" >&2
  exit 28
fi

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

ARCHIVE_EXECUTABLE_SHA256="$(sha256 "$ARCHIVE_EXECUTABLE")"
ARCHIVE_INFO_PLIST_SHA256="$(sha256 "$ARCHIVE_INFO_PLIST")"
EXPORTED_EXECUTABLE_SHA256="$(sha256 "$FINAL_EXECUTABLE")"
EXPORTED_INFO_PLIST_SHA256="$(sha256 "$FINAL_INFO_PLIST")"
IPA_SHA256="$(sha256 "$RETAINED_IPA")"
MOBILEPROVISION_SHA256="$(sha256 "$RETAINED_MOBILEPROVISION")"
EXPORT_OPTIONS_SHA256="$(sha256 "$RETAINED_EXPORT_OPTIONS")"

for digest in \
  "$ARCHIVE_EXECUTABLE_SHA256" \
  "$ARCHIVE_INFO_PLIST_SHA256" \
  "$EXPORTED_EXECUTABLE_SHA256" \
  "$EXPORTED_INFO_PLIST_SHA256" \
  "$IPA_SHA256" \
  "$MOBILEPROVISION_SHA256" \
  "$EXPORT_OPTIONS_SHA256"; do
  if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Could not derive one canonical SHA-256 build-evidence digest." >&2
    exit 29
  fi
done

# Preserve the same strict schema-v3 rendezvous shape already understood by the Capture package,
# but derive it from the final exported/signed app bytes rather than the unsigned Simulator app.
# Parsing/matching this record remains non-authoritative; the independent field acceptance layer is
# deliberately separate.
EXTERNAL_BUILD_RECORD="$EVIDENCE_DIR/NembraCaptureExternalBuildRecord.json"
python3 - \
  "$EXTERNAL_BUILD_RECORD" \
  "$CAPTURE_BUILD_IDENTIFIER" \
  "$CAPTURE_BUILD_INSTANCE_ID" \
  "$CAPTURE_BUILD_COMMIT_SHA" \
  "$EXPORTED_EXECUTABLE_SHA256" \
  "$EXPORTED_INFO_PLIST_SHA256" \
  "$CAPTURE_RECIPE_IDENTIFIER" \
  "$CAPTURE_PROCEDURE_VERSION" <<'PY'
import json, sys
(
    path,
    build_identifier,
    build_instance_id,
    source_commit_sha,
    executable_sha256,
    info_plist_sha256,
    recipe_identifier,
    procedure_version,
) = sys.argv[1:]
record = {
    "schemaVersion": 3,
    "buildIdentifier": build_identifier,
    "buildInstanceID": build_instance_id,
    "sourceCommitSHA": source_commit_sha,
    "executableSHA256": executable_sha256,
    "infoPlistSHA256": info_plist_sha256,
    "experimentRecipeID": recipe_identifier,
    "procedureVersion": procedure_version,
}
with open(path, "wb") as handle:
    handle.write(json.dumps(record, indent=2, sort_keys=True).encode("utf-8") + b"\n")
PY
EXTERNAL_BUILD_RECORD_SHA256="$(sha256 "$EXTERNAL_BUILD_RECORD")"

FIELD_BUILD_EVIDENCE="$EVIDENCE_DIR/NembraCaptureSignedDeviceBuildEvidence.json"
python3 - \
  "$FIELD_BUILD_EVIDENCE" \
  "$CAPTURE_BUILD_IDENTIFIER" \
  "$CAPTURE_BUILD_INSTANCE_ID" \
  "$CAPTURE_BUILD_COMMIT_SHA" \
  "$BUNDLE_ID" \
  "$CAPTURE_RECIPE_IDENTIFIER" \
  "$CAPTURE_PROCEDURE_VERSION" \
  "$TEAM_ID" \
  "$PROFILE_TEAM_ID" \
  "$PROFILE_APPLICATION_ID" \
  "$ARCHIVE_EXECUTABLE_SHA256" \
  "$ARCHIVE_INFO_PLIST_SHA256" \
  "$EXPORTED_EXECUTABLE_SHA256" \
  "$EXPORTED_INFO_PLIST_SHA256" \
  "$IPA_SHA256" \
  "$MOBILEPROVISION_SHA256" \
  "$EXPORT_OPTIONS_SHA256" \
  "$EXTERNAL_BUILD_RECORD_SHA256" <<'PY'
import json, sys
(
    path,
    build_identifier,
    build_instance_id,
    source_commit_sha,
    bundle_identifier,
    recipe_identifier,
    procedure_version,
    requested_team_id,
    provisioning_team_id,
    provisioning_application_id,
    archive_executable_sha256,
    archive_info_plist_sha256,
    exported_executable_sha256,
    exported_info_plist_sha256,
    ipa_sha256,
    mobileprovision_sha256,
    export_options_sha256,
    external_build_record_sha256,
) = sys.argv[1:]
record = {
    "schemaVersion": 1,
    "authority": "signed-device-build-evidence-not-field-authorization",
    "platform": "iphoneos",
    "configuration": "Release",
    "bundleIdentifier": bundle_identifier,
    "buildIdentifier": build_identifier,
    "buildInstanceID": build_instance_id,
    "sourceCommitSHA": source_commit_sha,
    "experimentRecipeID": recipe_identifier,
    "procedureVersion": procedure_version,
    "requestedDevelopmentTeamID": requested_team_id,
    "provisioningTeamID": provisioning_team_id,
    "provisioningApplicationIdentifier": provisioning_application_id,
    "archiveExecutableSHA256": archive_executable_sha256,
    "archiveInfoPlistSHA256": archive_info_plist_sha256,
    "exportedExecutableSHA256": exported_executable_sha256,
    "exportedInfoPlistSHA256": exported_info_plist_sha256,
    "ipaSHA256": ipa_sha256,
    "embeddedMobileProvisionSHA256": mobileprovision_sha256,
    "exportOptionsSHA256": export_options_sha256,
    "externalBuildRecordSHA256": external_build_record_sha256,
    "codeSignatureVerified": True,
}
with open(path, "wb") as handle:
    handle.write(json.dumps(record, indent=2, sort_keys=True).encode("utf-8") + b"\n")
PY
FIELD_BUILD_EVIDENCE_SHA256="$(sha256 "$FIELD_BUILD_EVIDENCE")"

(
  cd "$EVIDENCE_DIR"
  shasum -a 256 \
    Nembra.ipa \
    NembraCaptureExternalBuildRecord.json \
    NembraCaptureSignedDeviceBuildEvidence.json \
    ExportOptions.plist \
    embedded.mobileprovision \
    embedded.mobileprovision.plist \
    codesign-display.txt \
    > SHA256SUMS.txt
)

cat <<EOF
SIGNED DEVICE BUILD EVIDENCE COMPLETE — NOT FIELD AUTHORIZATION

Build:        $CAPTURE_BUILD_IDENTIFIER
Commit:       $CAPTURE_BUILD_COMMIT_SHA
Build life:   $CAPTURE_BUILD_INSTANCE_ID
IPA SHA-256:  $IPA_SHA256
Record SHA:   $EXTERNAL_BUILD_RECORD_SHA256
Evidence SHA: $FIELD_BUILD_EVIDENCE_SHA256
Evidence dir: $EVIDENCE_DIR

The script did not install this IPA, did not independently accept it, did not change the package
field gate, and did not authorize OFF1/ON1/OFF2/ON2. The next authority rung is independent review
or attestation of these exact retained bytes, followed by deliberate package + runbook GO binding.
EOF
