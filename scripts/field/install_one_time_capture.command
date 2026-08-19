#!/bin/bash -p
set -euo pipefail

if [[ $- != *p* ]]; then
  builtin printf '%s\n' 'ERROR: open scripts/field/install_one_time_capture.command directly; imported Bash startup state must remain disabled.' >&2
  exit 2
fi

set +x
PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV CDPATH GLOBIGNORE XCODE_XCCONFIG_FILE OTHER_SWIFT_FLAGS SWIFT_ACTIVE_COMPILATION_CONDITIONS || true

ROOT="$(cd "$(/usr/bin/dirname "$0")/../.." && /bin/pwd -P)"
cd "$ROOT"
umask 077

say() { builtin printf '\n==> %s\n' "$*"; }
die() { builtin printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "Run this on the Mac with Xcode and the intended iPhone connected."
for tool in xcodebuild xcrun security pod git shasum; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required for the one-time Capture field build."
done
[[ -x /usr/bin/python3 ]] || die "System Python 3 is required."
[[ -x /usr/bin/plutil ]] || die "System plutil is required for exact app provenance readback."
[[ -x /usr/bin/codesign ]] || die "System codesign is required for signed-bundle verification."
[[ -x /usr/bin/security ]] || die "System security is required for embedded-profile verification."

# The only positional input is a public Git commit. Private values are read
# from narrow local files or hidden prompts and never accepted on argv.
EXPECTED_SOURCE_SHA="${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}"
[[ "$EXPECTED_SOURCE_SHA" =~ ^[0-9A-Fa-f]{40}$ ]] || die "Pass the exact accepted Capture source SHA as the first argument (40 hex characters)."
EXPECTED_SOURCE_SHA="$(printf '%s' "$EXPECTED_SOURCE_SHA" | tr '[:upper:]' '[:lower:]')"
SOURCE_SHA="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]] || die "Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA. Checkout the exact accepted SHA before building."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Working tree has local changes. Commit or stash them before the field build."
say "Exact requested Capture source matched: $SOURCE_SHA"

# Capture nested repository-authored executables from the accepted Git object,
# never from a mutable checkout pathname after a check. A same-UID pathname swap
# after this point therefore cannot replace the bytes that the installer runs.
capture_accepted_git_source_base64() {
  local path="$1"
  local blob encoded decoded_blob
  blob="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$ROOT" rev-parse "$SOURCE_SHA:$path" 2>/dev/null)" || die "Accepted nested field tool is missing from the exact Git tree: $path"
  [[ "$blob" =~ ^[0-9a-f]{40}$ ]] || die "Accepted nested field tool Git identity is malformed: $path"
  encoded="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$ROOT" cat-file blob "$blob" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')" || die "Could not capture accepted Git bytes for nested field tool: $path"
  [[ -n "$encoded" ]] || die "Accepted nested field tool has no captured execution bytes: $path"
  decoded_blob="$(printf '%s' "$encoded" | /usr/bin/base64 -D | GIT_NO_REPLACE_OBJECTS=1 git -C "$ROOT" hash-object --stdin 2>/dev/null)" || die "Could not authenticate captured nested field-tool bytes: $path"
  [[ "$decoded_blob" == "$blob" ]] || die "Captured nested field-tool bytes do not match the exact accepted Git object: $path"
  printf '%s' "$encoded"
}

CAPTURE_BOOTSTRAP_PATH="Scripts/bootstrap_capture_tuya_sdk.sh"
TUYA_PROVENANCE_PATH="Scripts/capture_tuya_private_input_provenance.py"
CAPTURE_BOOTSTRAP_SOURCE_B64="$(capture_accepted_git_source_base64 "$CAPTURE_BOOTSTRAP_PATH")"
TUYA_PROVENANCE_SOURCE_B64="$(capture_accepted_git_source_base64 "$TUYA_PROVENANCE_PATH")"

: "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 to the reviewed Podfile.lock SHA-256 printed by the bootstrap review command.}"
[[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 must be exactly 64 hex characters."
NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
export NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256

unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true
: "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to an absolute mode-0600 file outside the repo containing only the intended iPhone UDID.}"
: "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 to the reviewed SHA-256 of that exact identifier.}"
[[ "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 must be exactly 64 hex characters."
NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256="$(printf '%s' "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" | tr '[:upper:]' '[:lower:]')"
export NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256

PRIVATE_DEVICE_RUNNER_PATH="scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_DEVICE_RUNNER="$(capture_accepted_git_source_base64 "$PRIVATE_DEVICE_RUNNER_PATH")"
# Base64 is only a transport encoding for these already-public, Git-authenticated
# helper source bytes. It is not encryption and must never be treated as secret
# protection for a UDID, credential, token, AppKey, or AppSecret.

if ! DEVICE_UDID="$(/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
import base64
import hashlib
import hmac
import os
import re
import sys
from pathlib import Path

source = base64.b64decode(sys.argv[1], validate=True)
namespace = {"__name__": "nembra_private_device_reader", "__file__": "<accepted-private-device-reader>"}
exec(compile(source, namespace["__file__"], "exec", dont_inherit=True), namespace)
reader = namespace.get("read_private_identifier")
if not callable(reader):
    raise RuntimeError("accepted private reader does not expose read_private_identifier")
value = reader(Path(sys.argv[2]), Path(sys.argv[3]))
expected_digest = os.environ.get("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256", "")
if re.fullmatch(r"[0-9a-f]{64}", expected_digest) is None:
    raise RuntimeError("expected intended-device digest is unavailable or malformed")
actual_digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
if not hmac.compare_digest(actual_digest, expected_digest):
    raise RuntimeError("private intended-device identifier does not match Final GO authority")
sys.stdout.write(value)
PY
)"; then
  die "The intended-device file failed private custody or digest validation."
fi
[[ -n "$DEVICE_UDID" ]] || die "The intended-device file produced no identifier."
unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 PRIVATE_DEVICE_RUNNER PRIVATE_DEVICE_RUNNER_PATH || true
say "Private intended-device admission validated"

say "Preparing the official Tuya SDK workspace from captured accepted Git bytes"
if ! printf '%s' "$CAPTURE_BOOTSTRAP_SOURCE_B64" | /usr/bin/base64 -D | /bin/bash -p -s -- \
  --field-repo-root "$ROOT" \
  --field-source-sha "$SOURCE_SHA" \
  --field-provenance-helper-base64 "$TUYA_PROVENANCE_SOURCE_B64"
then
  die "The accepted Tuya SDK bootstrap failed. No mutable checkout bootstrap was executed."
fi
[[ -d "$ROOT/NembraCapture.xcworkspace" ]] || die "NembraCapture.xcworkspace was not generated. Do not use NembraCapture.xcodeproj for the authenticated field build."
[[ "$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')" == "$SOURCE_SHA" ]] || die "Repository HEAD changed during private workspace bootstrap. Restart from the exact accepted source."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Private workspace bootstrap changed tracked or unignored accepted-source inputs. Review and re-accept before building."
[[ -f "$ROOT/Podfile.lock" ]] || die "Private workspace bootstrap produced no Podfile.lock."
TUYA_DEPENDENCY_LOCK_SHA256="$(shasum -a 256 "$ROOT/Podfile.lock" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$TUYA_DEPENDENCY_LOCK_SHA256" == "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" ]] || die "Resolved Tuya dependency lock no longer matches the reviewed fingerprint."
unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 CAPTURE_BOOTSTRAP_SOURCE_B64 CAPTURE_BOOTSTRAP_PATH || true

TUYA_PRIVATE_SDK="$ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$ROOT/LocalSecrets/TuyaRuntime"
TUYA_DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
run_accepted_private_tuya_provenance() {
  local operation="$1"
  /usr/bin/python3 -I -B - "$TUYA_PROVENANCE_SOURCE_B64" "$operation" \
    --lockfile "$ROOT/Podfile.lock" \
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
    --security-build "$TUYA_PRIVATE_SDK/Build" \
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
    --record "$TUYA_DEPENDENCY_PROVENANCE" <<'PY'
import base64
import sys

source = base64.b64decode(sys.argv[1], validate=True)
sys.argv = ["<accepted-tuya-private-input-provenance>"] + sys.argv[2:]
namespace = {
    "__name__": "__main__",
    "__file__": "<accepted-tuya-private-input-provenance>",
}
exec(compile(source, namespace["__file__"], "exec", dont_inherit=True), namespace)
PY
}
verify_private_tuya_inputs() {
  if ! run_accepted_private_tuya_provenance verify >/dev/null; then
    die "Private Tuya SDK/app-identity inputs no longer match the bootstrap fingerprint record. Restart from a freshly reviewed field-build candidate."
  fi
}

unset NEMBRA_TUYA_APP_KEY NEMBRA_TUYA_APP_SECRET || true

say "Verifying the intended iPhone 12 / iOS 27 baseline"
DEVICE_ROWS="$(xcrun xctrace list devices 2>/dev/null | /usr/bin/python3 -I -c '
import re, sys
section = False
for raw in sys.stdin:
    line = raw.strip()
    if line == "== Devices ==":
        section = True
        continue
    if line.startswith("== "):
        section = False
        continue
    if not section or "iPhone" not in line:
        continue
    match = re.search(r"\(([0-9A-Fa-f-]{20,})\)\s*$", line)
    if match:
        print(match.group(1) + "\t" + line[:match.start()].strip())
')"
[[ -n "$DEVICE_ROWS" ]] || die "No physical iPhone found. Connect the intended device by USB, unlock it, trust this Mac, and enable Developer Mode."

DEVICE_OS_VERSION=""
MATCH_COUNT=0
INTENDED_NORMALIZED="$(printf '%s' "$DEVICE_UDID" | /usr/bin/tr '[:upper:]' '[:lower:]')"
while IFS=$'\t' read -r ROW_UDID ROW_LABEL; do
  [[ -n "$ROW_UDID" ]] || continue
  ROW_NORMALIZED="$(printf '%s' "$ROW_UDID" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  if [[ "$ROW_NORMALIZED" == "$INTENDED_NORMALIZED" ]]; then
    MATCH_COUNT=$((MATCH_COUNT + 1))
    if [[ "$ROW_LABEL" =~ \(([0-9]+(\.[0-9]+){1,2})\)$ ]]; then
      DEVICE_OS_VERSION="${BASH_REMATCH[1]}"
    fi
  fi
done <<< "$DEVICE_ROWS"
unset INTENDED_NORMALIZED ROW_NORMALIZED ROW_UDID ROW_LABEL
[[ "$MATCH_COUNT" == "1" ]] || die "The connected-device set does not contain exactly one match for the private intended iPhone. No arbitrary-device fallback is permitted."
[[ "$DEVICE_OS_VERSION" == 27.* ]] || die "The intended iPhone is not reporting iOS 27."

COREDEVICE_ROWS="$(xcrun devicectl list devices --hide-headers 2>/dev/null || true)"
[[ -n "$COREDEVICE_ROWS" ]] || die "CoreDevice did not report the intended iPhone. Keep it connected and unlocked."
COREDEVICE_MATCH="$(printf '%s\0%s' "$DEVICE_UDID" "$COREDEVICE_ROWS" | /usr/bin/python3 -I -c '
import re, sys
payload = sys.stdin.buffer.read()
try:
    intended_raw, rows_raw = payload.split(b"\0", 1)
    intended = intended_raw.decode("utf-8").lower()
    rows = rows_raw.decode("utf-8")
except (ValueError, UnicodeDecodeError):
    raise SystemExit(2)
matches = []
for raw in rows.splitlines():
    match = re.search(r"(\S+\.coredevice\.local)\s+([0-9A-Fa-f-]{36})\s+(.+)$", raw.strip())
    if not match or match.group(1).lower() != intended + ".coredevice.local":
        continue
    if re.search(r"\bunavailable\b", match.group(3), re.IGNORECASE):
        continue
    models = re.findall(r"\b(iPhone[0-9]+,[0-9]+)\b", match.group(3))
    if len(models) == 1:
        matches.append((match.group(2), models[0]))
if len(matches) != 1:
    raise SystemExit(3)
sys.stdout.write(matches[0][0] + "\t" + matches[0][1])
')" || die "CoreDevice could not bind one non-private selector to the intended iPhone."
COREDEVICE_ID="${COREDEVICE_MATCH%%$'\t'*}"
DEVICE_MODEL="${COREDEVICE_MATCH#*$'\t'}"
[[ "$COREDEVICE_ID" =~ ^[0-9A-Fa-f-]{36}$ ]] || die "CoreDevice returned an invalid selector."
[[ "$DEVICE_MODEL" == "iPhone13,2" ]] || die "The intended device is not the V14 iPhone 12 hardware baseline (iPhone13,2)."
unset COREDEVICE_MATCH COREDEVICE_ROWS DEVICE_ROWS DEVICE_MODEL
say "Intended baseline proven: iPhone 12 / iOS $DEVICE_OS_VERSION"
say "The raw private UDID was correlated locally and is not placed in devicectl argv"

TEAM_ID="${NEMBRA_CAPTURE_TEAM_ID:-}"
if [[ -z "$TEAM_ID" ]]; then
  TEAM_IDS="$(security find-identity -v -p codesigning 2>/dev/null | /usr/bin/python3 -I -c '
import re, sys
seen = []
for line in sys.stdin:
    if "Apple Development:" not in line:
        continue
    match = re.search(r"\(([A-Z0-9]{10})\)", line)
    if match and match.group(1) not in seen:
        seen.append(match.group(1))
sys.stdout.write(chr(10).join(seen))
')"
  TEAM_COUNT="$(printf '%s\n' "$TEAM_IDS" | /usr/bin/sed '/^$/d' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  if [[ "$TEAM_COUNT" == "1" ]]; then
    TEAM_ID="$(printf '%s\n' "$TEAM_IDS" | /usr/bin/sed '/^$/d')"
  elif [[ "$TEAM_COUNT" -gt 1 ]]; then
    printf '%s\n' "$TEAM_IDS" | /usr/bin/nl -w2 -s') '
    builtin read -r -p "Choose the Apple Development team number: " TEAM_PICK
    TEAM_ID="$(printf '%s\n' "$TEAM_IDS" | /usr/bin/sed -n "${TEAM_PICK}p")"
  else
    builtin read -r -p "Enter the 10-character Apple Team ID shown in Xcode: " TEAM_ID
  fi
fi
unset NEMBRA_CAPTURE_TEAM_ID TEAM_IDS TEAM_COUNT TEAM_PICK || true
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "Could not determine a valid Apple Development Team ID."

BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
APP_ID_SUFFIX=".${BUNDLE_ID}"
PROCEDURE_ID="ES80-AUTHENTICATED-STATIONARY-v1"
BUILD_LABEL="capture-v14-${SOURCE_SHA:0:12}"
say "Field procedure: $PROCEDURE_ID"
verify_private_tuya_inputs

BUILD_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nembra-capture-field.XXXXXX")"
[[ "$BUILD_ROOT" == "${TMPDIR:-/tmp}/nembra-capture-field."* ]] || die "Could not create a narrow private build directory."
/bin/chmod 700 "$BUILD_ROOT"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
BUILD_LOG="$BUILD_ROOT/xcodebuild.log"
: > "$BUILD_LOG"
/bin/chmod 600 "$BUILD_LOG"
cleanup_build_root() {
  if [[ -n "${BUILD_ROOT:-}" && "$BUILD_ROOT" == "${TMPDIR:-/tmp}/nembra-capture-field."* ]]; then
    /bin/rm -rf -- "$BUILD_ROOT"
  fi
}
trap cleanup_build_root EXIT HUP INT TERM

say "Building SDK-integrated Nembra Capture for the intended iPhone"
if ! xcodebuild \
  -workspace NembraCapture.xcworkspace \
  -scheme "Nembra Capture" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  "NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL" \
  "NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA" \
  "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \
  "NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID" \
  "INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$PROCEDURE_ID" \
  build >"$BUILD_LOG" 2>&1
then
  /usr/bin/tail -n 80 "$BUILD_LOG" >&2 || true
  die "The signed Capture build failed. No app was installed and no physical attempt is authorized."
fi

verify_private_tuya_inputs
[[ "$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')" == "$SOURCE_SHA" ]] || die "Repository HEAD changed while the accepted field build was compiling. Discard this candidate."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart."

APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/Nembra Capture.app"
APP_INFO_PLIST="$APP/Info.plist"
[[ -d "$APP" && -f "$APP_INFO_PLIST" ]] || die "The device build produced no standalone Nembra Capture app."
BUILT_BUILD_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureBuildIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_SOURCE_SHA="$(/usr/bin/plutil -extract NembraCaptureSourceCommitSHA raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_PROCEDURE_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
[[ "$BUILT_BUILD_IDENTIFIER" == "$BUILD_LABEL" ]] || die "Built app identifier does not match the requested field build."
[[ "$BUILT_SOURCE_SHA" == "$SOURCE_SHA" ]] || die "Built app source does not match the exact accepted source."
[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built app lock fingerprint does not match the reviewed Tuya dependency lock."
[[ "$BUILT_PROCEDURE_IDENTIFIER" == "$PROCEDURE_ID" ]] || die "Built app procedure does not match the canonical stationary procedure."
[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "Built app bundle identifier does not match the standalone Capture product."
say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, canonical stationary procedure, and field product"

if ! /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  die "Final signed Capture app failed recursive strict code-signature verification."
fi
say "Final signed Capture app passed recursive strict code-signature verification"

SIGNED_ENTITLEMENTS_OUTPUT="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml "$APP" 2>&1)" || die "Could not read final signed app entitlements."
BUILT_SIGNING_IDENTITY="$(printf '%s' "$SIGNED_ENTITLEMENTS_OUTPUT" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '
import plistlib, sys
payload = sys.stdin.buffer.read()
start, end = payload.find(b"<?xml"), payload.rfind(b"</plist>")
if start < 0 or end < start:
    raise SystemExit(2)
root = plistlib.loads(payload[start:end + len(b"</plist>")])
apple = root.get("com.apple.developer.applesignin")
application = root.get("application-identifier")
team = root.get("com.apple.developer.team-identifier")
if apple == ["Default"] and isinstance(application, str) and isinstance(team, str):
    sys.stdout.write(application + "\t" + team)
')" || die "Final signed app lacks its required Apple sign-in/application identity."
BUILT_APPLICATION_IDENTIFIER="${BUILT_SIGNING_IDENTITY%%$'\t'*}"
BUILT_TEAM_IDENTIFIER="${BUILT_SIGNING_IDENTITY#*$'\t'}"
[[ "$BUILT_APPLICATION_IDENTIFIER" == *"$APP_ID_SUFFIX" ]] || die "Signed application identifier does not end in the exact Capture bundle ID."
[[ "$BUILT_APPLICATION_IDENTIFIER" != *"*"* ]] || die "Signed application identifier is wildcard/ambiguous."
BUILT_APP_ID_PREFIX="${BUILT_APPLICATION_IDENTIFIER%$APP_ID_SUFFIX}"
[[ -n "$BUILT_APP_ID_PREFIX" && "$BUILT_APP_ID_PREFIX" != "$BUILT_APPLICATION_IDENTIFIER" ]] || die "Signed application identifier has no concrete App ID prefix."
[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || die "Signed app team does not match the selected Apple Development team."

BUILT_PROFILE="$APP/embedded.mobileprovision"
[[ -f "$BUILT_PROFILE" ]] || die "Final signed app has no embedded provisioning profile."
PROFILE_XML="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i "$BUILT_PROFILE" 2>/dev/null)" || die "Could not decode the embedded provisioning profile."
PROFILE_SIGNING_IDENTITY="$(printf '%s' "$PROFILE_XML" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '
import plistlib, sys
root = plistlib.loads(sys.stdin.buffer.read())
entitlements = root.get("Entitlements", {})
application = entitlements.get("application-identifier")
entitlement_team = entitlements.get("com.apple.developer.team-identifier")
team_identifiers = root.get("TeamIdentifier")
apple = entitlements.get("com.apple.developer.applesignin")
if (apple == ["Default"] and isinstance(application, str) and isinstance(entitlement_team, str)
        and isinstance(team_identifiers, list) and len(team_identifiers) == 1
        and isinstance(team_identifiers[0], str)):
    sys.stdout.write(application + "\t" + entitlement_team + "\t" + team_identifiers[0])
')" || die "Embedded profile lacks the exact required app/team/Apple entitlement identity."
PROFILE_APPLICATION_IDENTIFIER="${PROFILE_SIGNING_IDENTITY%%$'\t'*}"
PROFILE_TEAM_FIELDS="${PROFILE_SIGNING_IDENTITY#*$'\t'}"
PROFILE_TEAM_IDENTIFIER="${PROFILE_TEAM_FIELDS%%$'\t'*}"
PROFILE_ROOT_TEAM_IDENTIFIER="${PROFILE_TEAM_FIELDS#*$'\t'}"
[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]] || die "Embedded profile application identifier does not match the signed app."
[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || die "Embedded profile entitlement team does not match the selected team."
[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || die "Embedded profile root TeamIdentifier does not match the selected team."

# A generic device build keeps the private UDID out of xcodebuild argv and logs.
# It therefore may not register an arbitrary connected device. Instead, fail
# closed before install unless the final embedded development profile already
# names the exact intended device admitted above.
PROFILE_DEVICE_ADMISSION="$(printf '%s\0%s' "$DEVICE_UDID" "$PROFILE_XML" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '
import hmac, plistlib, re, sys
payload = sys.stdin.buffer.read()
try:
    intended_raw, profile_raw = payload.split(b"\0", 1)
    intended = intended_raw.decode("utf-8")
    profile = plistlib.loads(profile_raw)
except (ValueError, UnicodeDecodeError, plistlib.InvalidFileException):
    raise SystemExit(2)
if re.fullmatch(r"(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})", intended) is None:
    raise SystemExit(3)
devices = profile.get("ProvisionedDevices")
if profile.get("ProvisionsAllDevices") is True or not isinstance(devices, list):
    raise SystemExit(4)
matches = [
    candidate for candidate in devices
    if isinstance(candidate, str)
    and hmac.compare_digest(candidate.lower(), intended.lower())
]
if len(matches) != 1:
    raise SystemExit(5)
sys.stdout.write("authorized")
')" || die "Embedded development profile does not include the exact intended iPhone. Register only that device through Apple/Xcode, then rerun the installer."
[[ "$PROFILE_DEVICE_ADMISSION" == "authorized" ]] || die "Embedded profile intended-device admission returned an invalid result."
unset PROFILE_DEVICE_ADMISSION PROFILE_XML
say "Signed app and embedded profile match one exact Capture App ID, selected team, and intended iPhone"

install_on_intended_device() (
  INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-authenticated-capture-install.XXXXXX")"
  chmod 600 "$INSTALL_LOG"
  trap 'rm -f -- "$INSTALL_LOG"' EXIT
  if ! xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP" >"$INSTALL_LOG" 2>&1; then
    if [[ -s "$INSTALL_LOG" ]]; then
      printf '%s\0%s' "$DEVICE_UDID" "$COREDEVICE_ID" | /usr/bin/python3 -I -c '
import re, sys
from pathlib import Path
payload = sys.stdin.buffer.read()
private_udid_raw, selector_raw = payload.split(b"\0", 1)
private_udid = private_udid_raw.decode("utf-8")
selector = selector_raw.decode("utf-8")
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
for secret, replacement in ((private_udid, "<redacted-device>"), (selector, "<redacted-device-selector>")):
    for variant in sorted({secret, secret.replace("-", "")}, key=len, reverse=True):
        if variant:
            text = re.sub(re.escape(variant), replacement, text, flags=re.IGNORECASE)
sys.stderr.write(text)
' "$INSTALL_LOG"
    fi
    die "The intended iPhone was not ready for installation. Keep it unlocked and connected, then rerun this installer."
  fi
  rm -f -- "$INSTALL_LOG"
  trap - EXIT
)

say "Installing SDK-integrated Capture on the intended iPhone"
install_on_intended_device
say "Launching privately provisioned Capture on the intended iPhone"
if ! xcrun devicectl device process launch \
  --device "$COREDEVICE_ID" \
  --activate \
  "$BUNDLE_ID" >/dev/null 2>&1
then
  die "Capture installed, but could not launch on the intended iPhone. Do not start a physical attempt."
fi
unset DEVICE_UDID COREDEVICE_ID DEVICE_OS_VERSION TUYA_PROVENANCE_SOURCE_B64 TUYA_PROVENANCE_PATH

cleanup_build_root
BUILD_ROOT=""
trap - EXIT HUP INT TERM

say "CAPTURE IS INSTALLED AND OPEN"
printf '%s\n' \
  "Capture will now give one short instruction at a time." \
  "Link the owning Tuya account, choose the intended scooter, and complete the fresh stationary safety check in the app." \
  "The scooter must remain stationary, initially OFF, and physically charger-disconnected. No riding is authorized." \
  "Use the OFF1 -> ON1 -> OFF2 -> ON2 prompts; wait for each fresh-manager scanner to report Live." \
  "After the four windows, explicitly confirm the single repeatable correlated target." \
  "That target is current-session evidence only; it is not permanent scooter identity, and name/RSSI/FD50/Tuya-company/historical UUID hints never substitute." \
  "PASS requires at least two genuine non-empty same-generation dpsUpdate callbacks, the latest at least 30 seconds after SDK authentication, canonical continuity of at least 45 seconds, and a sealed accepted prefix." \
  "If field-build provenance is not proven, STOP. Share only the sealed sanitized artifact or diagnostic offered by Capture." \
  "No outdoor ride is authorized by this installer."
