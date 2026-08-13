#!/bin/bash -p
set -euo pipefail
set +x

if [[ $- != *p* ]]; then
    printf '%s\n' 'ERROR: execute this file directly; privileged Bash startup mode is required.' >&2
    exit 2
fi

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
export PATH
unset BASH_ENV ENV CDPATH XCODE_XCCONFIG_FILE OTHER_SWIFT_FLAGS SWIFT_ACTIVE_COMPILATION_CONDITIONS SDKROOT TOOLCHAINS DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH || true

ROOT="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/../.." && /bin/pwd -P)"
cd "$ROOT"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "Signed Capture candidate production requires macOS."
[[ -x /usr/bin/git ]] || die "System Git is unavailable."
[[ -x /usr/bin/xcodebuild ]] || die "Xcode command-line tools are unavailable."
[[ -x /usr/bin/codesign ]] || die "System codesign is unavailable."
[[ -x /usr/bin/plutil ]] || die "System plutil is unavailable."
[[ -x /usr/bin/python3 ]] || die "System Python 3 is unavailable."
[[ -x /usr/bin/shasum ]] || die "System shasum is unavailable."
[[ -x /usr/bin/ditto ]] || die "System ditto is unavailable."
command -v pod >/dev/null 2>&1 || die "CocoaPods is required for the authenticated Tuya workspace."

EXPECTED_SOURCE_SHA="${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}"
[[ "$EXPECTED_SOURCE_SHA" =~ ^[0-9A-Fa-f]{40}$ ]] || die "Pass the exact accepted standalone Capture source SHA as the first argument."
EXPECTED_SOURCE_SHA="$(printf '%s' "$EXPECTED_SOURCE_SHA" | /usr/bin/tr '[:upper:]' '[:lower:]')"
SOURCE_SHA="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse --verify HEAD^{commit} | /usr/bin/tr '[:upper:]' '[:lower:]')"
[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]] || die "Checkout HEAD $SOURCE_SHA does not match accepted source $EXPECTED_SOURCE_SHA."
[[ -z "$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git status --porcelain=v1 --untracked-files=all)" ]] || die "Accepted source checkout is dirty."

: "${NEMBRA_DEVELOPMENT_TEAM:?Set NEMBRA_DEVELOPMENT_TEAM to the 10-character Apple Development TeamIdentifier.}"
[[ "$NEMBRA_DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]] || die "NEMBRA_DEVELOPMENT_TEAM must be exactly 10 uppercase alphanumeric characters."
: "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 to the reviewed Podfile.lock SHA-256.}"
[[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 must be exactly 64 hex characters."

ALLOW_PROVISIONING_UPDATES="${NEMBRA_ALLOW_PROVISIONING_UPDATES:-1}"
case "$ALLOW_PROVISIONING_UPDATES" in
    0|1) ;;
    *) die "NEMBRA_ALLOW_PROVISIONING_UPDATES must be exactly 0 or 1." ;;
esac

BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
PROCEDURE_ID="ES80-AUTHENTICATED-STATIONARY-v1"
BUILD_LABEL="capture-v14-${SOURCE_SHA:0:12}"

say "Preparing exact authenticated Tuya workspace for signed-build candidate"
"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"
[[ -d "$ROOT/NembraCapture.xcworkspace" ]] || die "CocoaPods did not create NembraCapture.xcworkspace."
[[ -f "$ROOT/Podfile.lock" ]] || die "Authenticated workspace has no Podfile.lock."
[[ "$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse --verify HEAD^{commit})" == "$SOURCE_SHA" ]] || die "Repository HEAD moved during workspace preparation."
[[ -z "$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git status --porcelain=v1 --untracked-files=all)" ]] || die "Tracked or unignored source changed during workspace preparation."

TUYA_LOCK_SHA256="$(/usr/bin/shasum -a 256 "$ROOT/Podfile.lock" | /usr/bin/awk '{print $1}' | /usr/bin/tr '[:upper:]' '[:lower:]')"
ACCEPTED_TUYA_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | /usr/bin/tr '[:upper:]' '[:lower:]')"
[[ "$TUYA_LOCK_SHA256" == "$ACCEPTED_TUYA_LOCK_SHA256" ]] || die "Resolved Tuya dependency lock no longer matches the reviewed digest."
unset ACCEPTED_TUYA_LOCK_SHA256

BUILD_INSTANCE_ID="$(/usr/bin/python3 -I -c 'import uuid; print(uuid.uuid4())')"
[[ "$BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || die "Could not create a canonical candidate instance ID."
WORK_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/NembraV16SignedCapture.XXXXXX")"
ARCHIVE_PATH="$WORK_ROOT/NembraCapture.xcarchive"
cleanup() { /bin/rm -rf "$WORK_ROOT"; }
trap cleanup EXIT INT TERM

say "Building signed standalone Nembra Capture archive"
XCODE_ARGS=(
    -workspace "$ROOT/NembraCapture.xcworkspace"
    -scheme "Nembra Capture"
    -configuration Release
    -destination "generic/platform=iOS"
    -archivePath "$ARCHIVE_PATH"
    DEVELOPMENT_TEAM="$NEMBRA_DEVELOPMENT_TEAM"
    CODE_SIGN_STYLE=Automatic
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
    "NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL"
    "NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA"
    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_LOCK_SHA256"
    "NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID"
    archive
)
if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    /usr/bin/xcodebuild -allowProvisioningUpdates "${XCODE_ARGS[@]}"
else
    /usr/bin/xcodebuild "${XCODE_ARGS[@]}"
fi

[[ "$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse --verify HEAD^{commit})" == "$SOURCE_SHA" ]] || die "Repository HEAD moved while signed candidate was compiling."
[[ -z "$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git status --porcelain=v1 --untracked-files=all)" ]] || die "Tracked or unignored source changed while signed candidate was compiling."

APP="$ARCHIVE_PATH/Products/Applications/Nembra Capture.app"
INFO_PLIST="$APP/Info.plist"
[[ -d "$APP" && -f "$INFO_PLIST" ]] || die "Archive did not contain the standalone Nembra Capture app."
/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || die "Signed Capture app failed strict recursive code-signature verification."

read_plist() { /usr/bin/plutil -extract "$1" raw -o - "$INFO_PLIST" 2>/dev/null || true; }
[[ "$(read_plist CFBundleIdentifier)" == "$BUNDLE_ID" ]] || die "Signed app bundle identifier does not match the standalone Capture product."
[[ "$(read_plist NembraCaptureBuildIdentifier)" == "$BUILD_LABEL" ]] || die "Signed app build identifier does not match exact source."
[[ "$(read_plist NembraCaptureSourceCommitSHA)" == "$SOURCE_SHA" ]] || die "Signed app source provenance does not match exact source."
[[ "$(read_plist NembraCaptureTuyaDependencyLockSHA256)" == "$TUYA_LOCK_SHA256" ]] || die "Signed app Tuya dependency provenance does not match reviewed lock."
[[ "$(read_plist NembraCaptureProcedureIdentifier)" == "$PROCEDURE_ID" ]] || die "Signed app procedure provenance does not match the canonical stationary procedure."

TEAM_IDENTIFIER="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | /usr/bin/awk -F= '$1 == "TeamIdentifier" {print $2; exit}')"
[[ "$TEAM_IDENTIFIER" == "$NEMBRA_DEVELOPMENT_TEAM" ]] || die "Signed app TeamIdentifier does not match NEMBRA_DEVELOPMENT_TEAM."

EXECUTABLE_NAME="$(read_plist CFBundleExecutable)"
[[ -n "$EXECUTABLE_NAME" && -f "$APP/$EXECUTABLE_NAME" ]] || die "Signed app executable is unavailable for candidate fingerprinting."
EXECUTABLE_SHA256="$(/usr/bin/shasum -a 256 "$APP/$EXECUTABLE_NAME" | /usr/bin/awk '{print $1}')"
INFO_PLIST_SHA256="$(/usr/bin/shasum -a 256 "$INFO_PLIST" | /usr/bin/awk '{print $1}')"

DEFAULT_ARTIFACTS_DIR="$ROOT/artifacts/V16SignedCapture-${SOURCE_SHA:0:12}-${BUILD_INSTANCE_ID}"
FINAL_ARTIFACTS_DIR="${ARTIFACTS_DIR:-$DEFAULT_ARTIFACTS_DIR}"
[[ "$FINAL_ARTIFACTS_DIR" == /* ]] || FINAL_ARTIFACTS_DIR="$ROOT/$FINAL_ARTIFACTS_DIR"
[[ ! -e "$FINAL_ARTIFACTS_DIR" && ! -L "$FINAL_ARTIFACTS_DIR" ]] || die "Candidate artifact destination already exists: $FINAL_ARTIFACTS_DIR"
/bin/mkdir -p "$(/usr/bin/dirname "$FINAL_ARTIFACTS_DIR")"
STAGING_DIR="${FINAL_ARTIFACTS_DIR}.staging-$BUILD_INSTANCE_ID"
[[ ! -e "$STAGING_DIR" && ! -L "$STAGING_DIR" ]] || die "Candidate staging destination already exists."
/bin/mkdir -m 700 "$STAGING_DIR"
/usr/bin/ditto "$ARCHIVE_PATH" "$STAGING_DIR/NembraCapture.xcarchive"

/usr/bin/python3 -I - \
    "$STAGING_DIR/candidate-manifest.json" \
    "$SOURCE_SHA" "$BUILD_LABEL" "$BUILD_INSTANCE_ID" "$TUYA_LOCK_SHA256" \
    "$PROCEDURE_ID" "$BUNDLE_ID" "$TEAM_IDENTIFIER" "$EXECUTABLE_SHA256" "$INFO_PLIST_SHA256" <<'PY'
import datetime as dt
import json
import os
import sys

(path, source, build, instance, lock, procedure, bundle, team, executable_sha, plist_sha) = sys.argv[1:]
record = {
    "schema": "nembra-v16-signed-build-candidate-v1",
    "createdAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "candidateKind": "signed-xcarchive",
    "sourceCommitSHA": source,
    "buildIdentifier": build,
    "buildInstanceID": instance,
    "tuyaDependencyLockSHA256": lock,
    "procedureIdentifier": procedure,
    "bundleIdentifier": bundle,
    "teamIdentifier": team,
    "executableSHA256": executable_sha,
    "infoPlistSHA256": plist_sha,
    "installationExecuted": False,
    "bluetoothExecuted": False,
    "physicalAuthorityCreated": False,
}
with open(path, "x", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.chmod(path, 0o600)
PY

/bin/mv "$STAGING_DIR" "$FINAL_ARTIFACTS_DIR"
trap - EXIT INT TERM
cleanup

say "SIGNED BUILD CANDIDATE COMPLETE"
printf 'Source: %s\nBuild: %s\nCandidate: %s\n' "$SOURCE_SHA" "$BUILD_LABEL" "$FINAL_ARTIFACTS_DIR"
printf '%s\n' 'SIGNED BUILD CANDIDATE ONLY — NOT INSTALLED — PHYSICAL NO-GO.'
