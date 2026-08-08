#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Signed Capture field-candidate production requires macOS with Xcode 27." >&2
  exit 2
fi

for tool in git xcodebuild xcrun python3 shasum codesign ditto; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool is unavailable: $tool" >&2
    exit 3
  fi
done

PLIST_BUDDY="/usr/libexec/PlistBuddy"
if [[ ! -x "$PLIST_BUDDY" ]]; then
  echo "Required plist reader is unavailable at $PLIST_BUDDY" >&2
  exit 4
fi

DEVELOPMENT_TEAM="${NEMBRA_DEVELOPMENT_TEAM:-}"
if [[ ! "$DEVELOPMENT_TEAM" =~ ^[A-Za-z0-9]{10}$ ]]; then
  echo "Set NEMBRA_DEVELOPMENT_TEAM to the exact 10-character Apple Developer Team ID used to sign the candidate." >&2
  exit 5
fi

CAPTURE_BUILD_COMMIT_SHA="$(git rev-parse --verify HEAD^{commit})"
if [[ ! "$CAPTURE_BUILD_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Capture build identity requires an exact 40-hex Git commit; got: $CAPTURE_BUILD_COMMIT_SHA" >&2
  exit 6
fi

# Run source admission before creating any output. Xcode/SwiftPM may discover non-ignored untracked
# files under source roots, so a clean tracked index alone is insufficient evidence for exact HEAD.
REPOSITORY_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$REPOSITORY_STATUS" ]]; then
  echo "Signed Capture candidate refuses tracked changes or non-ignored untracked files." >&2
  printf '%s\n' "$REPOSITORY_STATUS" >&2
  exit 7
fi

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/Artifacts/Xcode27FieldCandidate}"
DERIVED_DATA="${DERIVED_DATA:-${TMPDIR:-/tmp}/NembraFieldDerivedData}"
ARCHIVE_PATH="$ARTIFACTS_DIR/NembraFieldCandidate.xcarchive"
BUILD_EVIDENCE_DIR="$ARTIFACTS_DIR/build-evidence"
LOGS_DIR="$ARTIFACTS_DIR/logs"
BUNDLE_ID="com.jonathangana131.nembra"
CAPTURE_RECIPE_IDENTIFIER="ES80-FINGERPRINT-v1"
CAPTURE_PROCEDURE_VERSION="V14"
CAPTURE_BUILD_IDENTIFIER="Capture Build V14-${CAPTURE_BUILD_COMMIT_SHA:0:12}"
CAPTURE_BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"

if [[ ! "$CAPTURE_BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Capture build instance must be one canonical lowercase UUID; got: $CAPTURE_BUILD_INSTANCE_ID" >&2
  exit 8
fi

rm -rf "$ARTIFACTS_DIR" "$DERIVED_DATA"
mkdir -p "$BUILD_EVIDENCE_DIR" "$LOGS_DIR"

{
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "capture_build_identifier=$CAPTURE_BUILD_IDENTIFIER"
  echo "capture_build_instance_id=$CAPTURE_BUILD_INSTANCE_ID"
  echo "capture_build_commit_sha=$CAPTURE_BUILD_COMMIT_SHA"
  echo "capture_recipe_identifier=$CAPTURE_RECIPE_IDENTIFIER"
  echo "capture_procedure_version=$CAPTURE_PROCEDURE_VERSION"
  echo "development_team=$DEVELOPMENT_TEAM"
  sw_vers
  xcodebuild -version
} > "$ARTIFACTS_DIR/environment.txt"

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
  echo "Signed Capture candidate archive failed with status $ARCHIVE_STATUS." >&2
  echo "No field authorization was produced." >&2
  exit "$ARCHIVE_STATUS"
fi

APP_PATH="$ARCHIVE_PATH/Products/Applications/Nembra.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected signed app was not found at $APP_PATH" >&2
  exit 9
fi

INFO_PLIST="$APP_PATH/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Expected signed app Info.plist was not found." >&2
  exit 10
fi

EMBEDDED_BUILD_IDENTIFIER="$($PLIST_BUDDY -c 'Print :NembraCaptureBuildIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
EMBEDDED_BUILD_INSTANCE_ID="$($PLIST_BUDDY -c 'Print :NembraCaptureBuildInstanceID' "$INFO_PLIST" 2>/dev/null || true)"
EMBEDDED_BUILD_COMMIT_SHA="$($PLIST_BUDDY -c 'Print :NembraCaptureBuildCommitSHA' "$INFO_PLIST" 2>/dev/null || true)"
EMBEDDED_BUNDLE_ID="$($PLIST_BUDDY -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)"

if [[ "$EMBEDDED_BUILD_IDENTIFIER" != "$CAPTURE_BUILD_IDENTIFIER" ]]; then
  echo "Signed app did not preserve the exact Capture build identifier." >&2
  exit 11
fi
if [[ "$EMBEDDED_BUILD_INSTANCE_ID" != "$CAPTURE_BUILD_INSTANCE_ID" ]]; then
  echo "Signed app did not preserve the exact Capture build-instance identifier." >&2
  exit 12
fi
if [[ "$EMBEDDED_BUILD_COMMIT_SHA" != "$CAPTURE_BUILD_COMMIT_SHA" ]]; then
  echo "Signed app did not preserve the exact Capture source commit SHA." >&2
  exit 13
fi
if [[ "$EMBEDDED_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
  echo "Signed app bundle identifier changed unexpectedly: $EMBEDDED_BUNDLE_ID" >&2
  exit 14
fi

# Final digest-bearing provenance must remain external. Embedding a digest of the final signed
# executable inside the same signed bundle creates a code-signing self-reference and is forbidden.
if [[ -e "$APP_PATH/NembraCaptureTrustedBuildRecord.json" || -e "$APP_PATH/NembraCaptureExternalBuildRecord.json" ]]; then
  echo "Executable-digest provenance record must remain external to the signed app bundle." >&2
  exit 15
fi

if ! codesign --verify --deep --strict --verbose=2 "$APP_PATH" > "$LOGS_DIR/codesign-verify.log" 2>&1; then
  cat "$LOGS_DIR/codesign-verify.log" >&2 || true
  echo "Signed Capture candidate failed strict code-signature verification." >&2
  exit 16
fi
codesign -d --verbose=4 "$APP_PATH" > "$LOGS_DIR/codesign-details.log" 2>&1 || true

EXECUTABLE_NAME="$($PLIST_BUDDY -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
EXECUTABLE_PATH="$APP_PATH/$EXECUTABLE_NAME"
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Expected signed executable was not found at $EXECUTABLE_PATH" >&2
  exit 17
fi

EXECUTABLE_SHA256="$(shasum -a 256 "$EXECUTABLE_PATH" | awk '{print $1}')"
INFO_PLIST_SHA256="$(shasum -a 256 "$INFO_PLIST" | awk '{print $1}')"
if [[ ! "$EXECUTABLE_SHA256" =~ ^[0-9a-f]{64}$ || ! "$INFO_PLIST_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not derive canonical SHA-256 digests for the signed executable/build metadata." >&2
  exit 18
fi

RETAINED_EXECUTABLE="$BUILD_EVIDENCE_DIR/Nembra"
RETAINED_INFO_PLIST="$BUILD_EVIDENCE_DIR/Info.plist"
SIGNED_APP_ARCHIVE="$BUILD_EVIDENCE_DIR/Nembra.signed-app.zip"
cp -p "$EXECUTABLE_PATH" "$RETAINED_EXECUTABLE"
cp -p "$INFO_PLIST" "$RETAINED_INFO_PLIST"

if ! cmp -s "$EXECUTABLE_PATH" "$RETAINED_EXECUTABLE" || ! cmp -s "$INFO_PLIST" "$RETAINED_INFO_PLIST"; then
  echo "Retained signed build evidence diverged from the exact archived app." >&2
  exit 19
fi
if [[ "$(shasum -a 256 "$RETAINED_EXECUTABLE" | awk '{print $1}')" != "$EXECUTABLE_SHA256" ]]; then
  echo "Retained signed executable digest mismatch." >&2
  exit 20
fi
if [[ "$(shasum -a 256 "$RETAINED_INFO_PLIST" | awk '{print $1}')" != "$INFO_PLIST_SHA256" ]]; then
  echo "Retained signed Info.plist digest mismatch." >&2
  exit 21
fi

# Preserve the exact signed .app as one transferable file without pretending that the zip itself is
# an App Store/exported IPA. Re-extract it immediately and prove that its critical bytes/signature
# still match before retaining the archive as candidate evidence.
ditto -c -k --keepParent "$APP_PATH" "$SIGNED_APP_ARCHIVE"
SIGNED_APP_ARCHIVE_SHA256="$(shasum -a 256 "$SIGNED_APP_ARCHIVE" | awk '{print $1}')"
if [[ ! "$SIGNED_APP_ARCHIVE_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not derive signed app archive SHA-256." >&2
  exit 22
fi

REHYDRATED_DIR="$ARTIFACTS_DIR/.signed-app-verification"
rm -rf "$REHYDRATED_DIR"
mkdir -p "$REHYDRATED_DIR"
ditto -x -k "$SIGNED_APP_ARCHIVE" "$REHYDRATED_DIR"
REHYDRATED_APP="$REHYDRATED_DIR/Nembra.app"
if [[ ! -d "$REHYDRATED_APP" ]]; then
  echo "Transfer archive did not rehydrate the expected Nembra.app." >&2
  exit 23
fi
if ! cmp -s "$EXECUTABLE_PATH" "$REHYDRATED_APP/$EXECUTABLE_NAME" || ! cmp -s "$INFO_PLIST" "$REHYDRATED_APP/Info.plist"; then
  echo "Transfer archive did not preserve the exact signed executable/build metadata bytes." >&2
  exit 24
fi
if ! codesign --verify --deep --strict --verbose=2 "$REHYDRATED_APP" > "$LOGS_DIR/codesign-rehydrated-verify.log" 2>&1; then
  cat "$LOGS_DIR/codesign-rehydrated-verify.log" >&2 || true
  echo "Rehydrated signed app failed strict code-signature verification." >&2
  exit 25
fi
rm -rf "$REHYDRATED_DIR"

EXTERNAL_BUILD_RECORD="$ARTIFACTS_DIR/NembraCaptureExternalBuildRecord.json"
FIELD_CANDIDATE_EVIDENCE="$ARTIFACTS_DIR/NembraCaptureSignedFieldCandidateEvidence.json"
python3 - \
  "$EXTERNAL_BUILD_RECORD" \
  "$FIELD_CANDIDATE_EVIDENCE" \
  "$CAPTURE_BUILD_IDENTIFIER" \
  "$CAPTURE_BUILD_INSTANCE_ID" \
  "$CAPTURE_BUILD_COMMIT_SHA" \
  "$EXECUTABLE_SHA256" \
  "$INFO_PLIST_SHA256" \
  "$SIGNED_APP_ARCHIVE_SHA256" \
  "$BUNDLE_ID" \
  "$DEVELOPMENT_TEAM" \
  "$CAPTURE_RECIPE_IDENTIFIER" \
  "$CAPTURE_PROCEDURE_VERSION" <<'PY'
import json
import sys

(
    external_record_path,
    field_candidate_path,
    build_identifier,
    build_instance_id,
    source_commit_sha,
    executable_sha256,
    info_plist_sha256,
    signed_app_archive_sha256,
    bundle_identifier,
    development_team,
    recipe_identifier,
    procedure_version,
) = sys.argv[1:]

external_record = {
    "schemaVersion": 3,
    "buildIdentifier": build_identifier,
    "buildInstanceID": build_instance_id,
    "sourceCommitSHA": source_commit_sha,
    "executableSHA256": executable_sha256,
    "infoPlistSHA256": info_plist_sha256,
    "experimentRecipeID": recipe_identifier,
    "procedureVersion": procedure_version,
}
with open(external_record_path, "w", encoding="utf-8") as handle:
    json.dump(external_record, handle, indent=2, sort_keys=True)
    handle.write("\n")

field_candidate = {
    "schemaVersion": 1,
    "evidenceClass": "signed-field-candidate-not-field-authorization",
    "buildIdentifier": build_identifier,
    "buildInstanceID": build_instance_id,
    "sourceCommitSHA": source_commit_sha,
    "executableSHA256": executable_sha256,
    "infoPlistSHA256": info_plist_sha256,
    "signedAppArchiveSHA256": signed_app_archive_sha256,
    "bundleIdentifier": bundle_identifier,
    "developmentTeam": development_team,
    "experimentRecipeID": recipe_identifier,
    "procedureVersion": procedure_version,
}
with open(field_candidate_path, "w", encoding="utf-8") as handle:
    json.dump(field_candidate, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

EXTERNAL_BUILD_RECORD_SHA256="$(shasum -a 256 "$EXTERNAL_BUILD_RECORD" | awk '{print $1}')"
FIELD_CANDIDATE_EVIDENCE_SHA256="$(shasum -a 256 "$FIELD_CANDIDATE_EVIDENCE" | awk '{print $1}')"

printf '%s\n' \
  "capture_executable_sha256=$EXECUTABLE_SHA256" \
  "capture_info_plist_sha256=$INFO_PLIST_SHA256" \
  "capture_signed_app_archive=$SIGNED_APP_ARCHIVE" \
  "capture_signed_app_archive_sha256=$SIGNED_APP_ARCHIVE_SHA256" \
  "capture_external_build_record=$EXTERNAL_BUILD_RECORD" \
  "capture_external_build_record_sha256=$EXTERNAL_BUILD_RECORD_SHA256" \
  "capture_field_candidate_evidence=$FIELD_CANDIDATE_EVIDENCE" \
  "capture_field_candidate_evidence_sha256=$FIELD_CANDIDATE_EVIDENCE_SHA256" \
  >> "$ARTIFACTS_DIR/environment.txt"

# Optional installability proof. The caller-supplied device identifier and raw devicectl output are
# intentionally not retained in the evidence bundle. Installation still does not authorize the
# experiment; the package field gate and runbook remain independently NO-GO.
if [[ -n "${NEMBRA_INSTALL_DEVICE_ID:-}" ]]; then
  INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-devicectl-install.XXXXXX")"
  if ! xcrun devicectl device install app \
    --device "$NEMBRA_INSTALL_DEVICE_ID" \
    "$APP_PATH" \
    > "$INSTALL_LOG" 2>&1; then
    cat "$INSTALL_LOG" >&2 || true
    rm -f "$INSTALL_LOG"
    echo "The exact signed candidate did not install successfully on the requested device." >&2
    exit 26
  fi
  rm -f "$INSTALL_LOG"
  echo "device_install_requested=true" >> "$ARTIFACTS_DIR/environment.txt"
  echo "device_install_result=success" >> "$ARTIFACTS_DIR/environment.txt"
else
  echo "device_install_requested=false" >> "$ARTIFACTS_DIR/environment.txt"
fi

cat <<EOF
SIGNED CAPTURE FIELD CANDIDATE PRODUCED
source: $CAPTURE_BUILD_COMMIT_SHA
build instance: $CAPTURE_BUILD_INSTANCE_ID
signed executable sha256: $EXECUTABLE_SHA256
signed app archive sha256: $SIGNED_APP_ARCHIVE_SHA256
external schema-v3 record: $EXTERNAL_BUILD_RECORD
candidate evidence: $FIELD_CANDIDATE_EVIDENCE

THIS IS NOT PHYSICAL FIELD AUTHORIZATION.
The package field gate and V14 physical runbook remain NO-GO until this exact signed candidate receives independent acceptance and a deliberate final GO change.
EOF
