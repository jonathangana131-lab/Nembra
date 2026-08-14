#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$ROOT"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Run this on the Mac with Xcode and the intended iPhone connected."
command -v xcodebuild >/dev/null || die "Xcode command-line tools are not available."
command -v xcrun >/dev/null || die "xcrun is not available."
command -v security >/dev/null || die "macOS security tool is not available."
command -v pod >/dev/null || die "CocoaPods is required for the official Tuya SDK field build."
[[ -x /usr/bin/python3 ]] || die "System Python 3 is required for private intended-device admission."
[[ -x /usr/bin/plutil ]] || die "System plutil is required for exact built-app provenance verification."
[[ -x /usr/bin/codesign ]] || die "System codesign is required for effective signed-entitlement verification."
[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."
[[ -x /usr/bin/sudo ]] || die "System sudo is required to create the protected signed-app install subject."
[[ -x /usr/bin/ditto ]] || die "System ditto is required to stage the exact signed-app install subject."
[[ -x /usr/bin/find ]] || die "System find is required to seal staged signed-app ownership without following symlinks."
[[ -x /usr/sbin/chown ]] || die "System chown is required to root-own the staged signed-app install subject."

EXPECTED_SOURCE_SHA="${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}"
[[ "$EXPECTED_SOURCE_SHA" =~ ^[0-9A-Fa-f]{40}$ ]] || die "Pass the exact software-accepted Capture source SHA as the first argument (40 hex characters)."
EXPECTED_SOURCE_SHA="$(printf '%s' "$EXPECTED_SOURCE_SHA" | tr '[:upper:]' '[:lower:]')"
SOURCE_SHA="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]] || die "Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA. Checkout the exact accepted SHA before building."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Working tree has local changes. Commit/stash them first."
say "Exact requested Capture source matched: $SOURCE_SHA"

# The intended-device identifier is private field-admission input, never product
# evidence. Reuse the canonical descriptor-bound reader so the private file is
# opened once with no-follow component checks and stable metadata/read custody.
# The raw identifier is captured in-process only; Nembra never prints it and
# never places it in a child process argv/environment.
unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true
: "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to an absolute private mode-0600 file containing only the intended iPhone UDID.}"
: "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256:?Final GO must provide NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 as the accepted SHA-256 of the intended-device identifier.}"
[[ "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 must be exactly 64 hex characters."
NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256="$(printf '%s' "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" | tr '[:upper:]' '[:lower:]')"
export NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256
PRIVATE_DEVICE_RUNNER_RELATIVE="scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git rev-parse "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_RELATIVE" 2>/dev/null)" || \
    die "Private intended-device reader is missing from the exact accepted Git tree."
[[ "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" =~ ^[0-9a-f]{40}$ ]] || die "Private intended-device reader Git blob identity is malformed."
PRIVATE_DEVICE_RUNNER="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git cat-file blob "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')" || \
    die "Could not capture the private intended-device reader from the accepted Git object."
[[ -n "$PRIVATE_DEVICE_RUNNER" ]] || die "Captured private intended-device reader is empty."
[[ "$(printf '%s' "$PRIVATE_DEVICE_RUNNER" | /usr/bin/base64 -D | GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git hash-object --stdin)" == "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" ]] || \
    die "Decoded private intended-device reader bytes do not match the accepted Git blob."
if ! DEVICE_UDID="$(/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
import hashlib
import hmac
import base64
import os
import re
import sys
from pathlib import Path

runner_source = base64.b64decode(sys.argv[1], validate=True)
runner_namespace = {
    "__name__": "nembra_private_device_reader",
    "__file__": "<accepted-private-device-runner>",
}
exec(
    compile(runner_source, "<accepted-private-device-runner>", "exec", dont_inherit=True),
    runner_namespace,
)
reader = runner_namespace.get("read_private_identifier")
if not callable(reader):
    raise RuntimeError("accepted private intended-device reader does not expose read_private_identifier")
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
    die "The intended-device verification file failed private custody validation."
fi
[[ -n "$DEVICE_UDID" ]] || die "The intended-device verification file produced no identifier."
unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 PRIVATE_DEVICE_RUNNER PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB PRIVATE_DEVICE_RUNNER_RELATIVE || true
say "Private intended-device admission validated against Final GO digest"

# The physical authentication candidate is the standalone Capture product with
# Tuya's app-specific security SDK and private app identity integrated through
# CocoaPods. Building the public .xcodeproj here would intentionally compile the
# fail-closed fallback and cannot authorize the ES80 experiment.
say "Validating official Tuya SDK and private app-identity provisioning"
"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"
[[ -d "$ROOT/NembraCapture.xcworkspace" ]] || die "NembraCapture.xcworkspace was not generated. Do not use NembraCapture.xcodeproj for the authenticated field build."
[[ "$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')" == "$SOURCE_SHA" ]] || die "Repository HEAD changed during private workspace bootstrap. Restart from the exact accepted source."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Private workspace bootstrap changed tracked or unignored accepted-source inputs. Review and re-accept before building."
[[ -f "$ROOT/Podfile.lock" ]] || die "Private workspace bootstrap produced no Podfile.lock; reviewed Tuya dependency provenance is unavailable."
TUYA_DEPENDENCY_LOCK_SHA256="$(shasum -a 256 "$ROOT/Podfile.lock" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$TUYA_DEPENDENCY_LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "Could not compute a valid SHA-256 fingerprint for the resolved Tuya dependency lock."
say "Resolved Tuya dependency lock fingerprint captured for compiled provenance"

TUYA_PROVENANCE_HELPER="$ROOT/Scripts/capture_tuya_private_input_provenance.py"
TUYA_BUILD_WINDOW_GUARD="$ROOT/Scripts/capture_tuya_private_input_build_guard.py"
[[ -f "$TUYA_BUILD_WINDOW_GUARD" ]] || die "Private Tuya build-window custody guard is missing from the accepted source."
TUYA_PRIVATE_SDK="$ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$ROOT/LocalSecrets/TuyaRuntime"
TUYA_DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
verify_private_tuya_inputs() {
    /usr/bin/python3 -I "$TUYA_PROVENANCE_HELPER" verify \
        --lockfile "$ROOT/Podfile.lock" \
        --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
        --security-build "$TUYA_PRIVATE_SDK/Build" \
        --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
        --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
        --record "$TUYA_DEPENDENCY_PROVENANCE" >/dev/null || \
        die "Private Tuya SDK/app-identity inputs no longer match the bootstrap fingerprint record. Restart from a freshly reviewed field-build candidate."
}

# Never accept launch-time secrets. The field workspace gets AppKey/AppSecret
# from the ignored local NembraTuyaPrivateConfig pod generated by
# Scripts/provision_capture_tuya_identity.sh. Clearing these variables here
# prevents an old caller environment from becoming accidental authority.
unset NEMBRA_TUYA_APP_KEY NEMBRA_TUYA_APP_SECRET || true

say "Verifying the intended iPhone 12 / iOS 27 baseline"
DEVICE_ROWS="$(xcrun xctrace list devices 2>/dev/null | /usr/bin/python3 -I -c '
import re,sys
section=False
for raw in sys.stdin:
    line=raw.strip()
    if line=="== Devices ==":
        section=True; continue
    if line.startswith("== "):
        section=False; continue
    if not section or "iPhone" not in line:
        continue
    m=re.search(r"\(([0-9A-Fa-f-]{20,})\)\s*$", line)
    if m:
        print(m.group(1)+"\t"+line[:m.start()].strip())
')"
[[ -n "$DEVICE_ROWS" ]] || die "No physical iPhone found. Connect the intended device by USB, unlock it, trust this Mac, and enable Developer Mode."

DEVICE_LABEL=""
DEVICE_OS_VERSION=""
MATCH_COUNT=0
INTENDED_NORMALIZED="$(printf '%s' "$DEVICE_UDID" | tr '[:upper:]' '[:lower:]')"
while IFS=$'\t' read -r ROW_UDID ROW_LABEL; do
    [[ -n "$ROW_UDID" ]] || continue
    ROW_NORMALIZED="$(printf '%s' "$ROW_UDID" | tr '[:upper:]' '[:lower:]')"
    if [[ "$ROW_NORMALIZED" == "$INTENDED_NORMALIZED" ]]; then
        MATCH_COUNT=$((MATCH_COUNT + 1))
        DEVICE_LABEL="$ROW_LABEL"
        if [[ "$ROW_LABEL" =~ \(([0-9]+(\.[0-9]+){1,2})\)$ ]]; then
            DEVICE_OS_VERSION="${BASH_REMATCH[1]}"
        fi
    fi
done <<< "$DEVICE_ROWS"
unset INTENDED_NORMALIZED ROW_NORMALIZED ROW_UDID
[[ "$MATCH_COUNT" == "1" && -n "$DEVICE_LABEL" ]] || die "The connected-device set does not contain exactly one match for the private intended iPhone. No arbitrary-device fallback is permitted."
[[ "$DEVICE_OS_VERSION" == 27.* ]] || die "The privately admitted intended iPhone is not currently reporting iOS 27 through Xcode device discovery. Do not use a different OS baseline."

# CoreDevice exposes a separate non-private selector and hardware product type.
# Correlate it to the private UDID through the device hostname, then use only the
# CoreDevice identifier for install/launch so the private UDID never enters
# devicectl argv. `--hide-headers` is an Xcode-supported textual-output option.
COREDEVICE_ROWS="$(xcrun devicectl list devices --hide-headers 2>/dev/null || true)"
[[ -n "$COREDEVICE_ROWS" ]] || die "CoreDevice did not report the intended iPhone. Keep it connected/unlocked and allow Xcode device preparation to finish."
COREDEVICE_MATCH="$(printf '%s\0%s' "$DEVICE_UDID" "$COREDEVICE_ROWS" | /usr/bin/python3 -I -c '
import re,sys
payload=sys.stdin.buffer.read()
try:
    intended_raw, rows_raw = payload.split(b"\0", 1)
    intended=intended_raw.decode("utf-8").lower()
    rows=rows_raw.decode("utf-8")
except (ValueError, UnicodeDecodeError):
    raise SystemExit(2)
matches=[]
for raw in rows.splitlines():
    line=raw.strip()
    m=re.search(r"(\S+\.coredevice\.local)\s+([0-9A-Fa-f-]{36})\s+(.+)$", line)
    if not m:
        continue
    hostname, selector, tail=m.groups()
    if hostname.lower() != intended + ".coredevice.local":
        continue
    if re.search(r"\bunavailable\b", tail, re.IGNORECASE):
        continue
    models=re.findall(r"\b(iPhone[0-9]+,[0-9]+)\b", tail)
    if len(models) != 1:
        continue
    matches.append((selector, models[0]))
if len(matches) != 1:
    raise SystemExit(3)
sys.stdout.write(matches[0][0]+"\t"+matches[0][1])
')" || die "CoreDevice could not bind exactly one available non-private selector to the intended iPhone."
COREDEVICE_ID="${COREDEVICE_MATCH%%$'\t'*}"
DEVICE_MODEL="${COREDEVICE_MATCH#*$'\t'}"
[[ "$COREDEVICE_ID" =~ ^[0-9A-Fa-f-]{36}$ ]] || die "CoreDevice returned an invalid selector for the intended iPhone."
[[ "$DEVICE_MODEL" == "iPhone13,2" ]] || die "The privately admitted intended device is not the V14 iPhone 12 hardware baseline (expected product type iPhone13,2)."
unset COREDEVICE_MATCH COREDEVICE_ROWS DEVICE_ROWS DEVICE_LABEL DEVICE_MODEL
say "Intended baseline proven: iPhone 12 / iOS $DEVICE_OS_VERSION"

say "Finding Apple Development signing team"
TEAM_IDS="$(security find-identity -v -p codesigning 2>/dev/null | /usr/bin/python3 -I -c '
import re,sys
seen=[]
for line in sys.stdin:
    if "Apple Development:" not in line:
        continue
    m=re.search(r"\(([A-Z0-9]{10})\)", line)
    if m and m.group(1) not in seen:
        seen.append(m.group(1))
print("\n".join(seen))
')"
TEAM_COUNT="$(printf '%s\n' "$TEAM_IDS" | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$TEAM_COUNT" == "1" ]]; then
    TEAM_ID="$(printf '%s\n' "$TEAM_IDS" | sed '/^$/d')"
else
    if [[ "$TEAM_COUNT" -gt 1 ]]; then
        printf '%s\n' "$TEAM_IDS" | nl -w2 -s') '
        read -r -p "Choose Apple Development team number: " PICK
        TEAM_ID="$(printf '%s\n' "$TEAM_IDS" | sed -n "${PICK}p")"
    else
        read -r -p "Enter the 10-character Apple Team ID from Xcode Signing & Capabilities: " TEAM_ID
    fi
fi
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "Could not determine a valid 10-character Team ID."

BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
APP_ID_SUFFIX=".${BUNDLE_ID}"
PROCEDURE_ID="ES80-AUTHENTICATED-STATIONARY-v1"
BUILD_LABEL="capture-v14-${SOURCE_SHA:0:12}"
DERIVED_PLACEHOLDER="__NEMBRA_PROTECTED_DERIVED__"
say "Field procedure: $PROCEDURE_ID"
verify_private_tuya_inputs

# Every privileged custody component below is transported from exact accepted Git-object
# bytes. The selected-Xcode orchestrator keeps freeze publication and compiler-output
# creation inside one root process, so the field shell never needs to regain sudo between
# those two authority transitions.
BUILD_ORIGIN_CUSTODY_HELPER_PATH="scripts/ci/capture_signed_app_build_origin_custody.py"
BUILD_ORIGIN_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse "$SOURCE_SHA:$BUILD_ORIGIN_CUSTODY_HELPER_PATH" 2>/dev/null)" || \
    die "Signed-app build-origin custody helper is missing from the exact accepted Git tree."
[[ "$BUILD_ORIGIN_CUSTODY_HELPER_BLOB" =~ ^[0-9a-f]{40}$ ]] || die "Signed-app build-origin custody helper Git blob identity is malformed."
BUILD_ORIGIN_CUSTODY_HELPER_BASE64="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git cat-file blob "$BUILD_ORIGIN_CUSTODY_HELPER_BLOB" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')" || \
    die "Could not capture signed-app build-origin custody helper from the accepted Git object."
[[ -n "$BUILD_ORIGIN_CUSTODY_HELPER_BASE64" ]] || die "Captured signed-app build-origin custody helper is empty."
[[ "$(printf '%s' "$BUILD_ORIGIN_CUSTODY_HELPER_BASE64" | /usr/bin/base64 -D | GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git hash-object --stdin)" == "$BUILD_ORIGIN_CUSTODY_HELPER_BLOB" ]] || \
    die "Decoded signed-app build-origin custody helper bytes do not match the accepted Git blob."

SIGNED_APP_CUSTODY_HELPER_PATH="scripts/ci/capture_signed_app_install_custody.py"
SIGNED_APP_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse "$SOURCE_SHA:$SIGNED_APP_CUSTODY_HELPER_PATH" 2>/dev/null)" || \
    die "Signed-app custody helper is missing from the exact accepted Git tree."
[[ "$SIGNED_APP_CUSTODY_HELPER_BLOB" =~ ^[0-9a-f]{40}$ ]] || die "Signed-app custody helper Git blob identity is malformed."
SIGNED_APP_CUSTODY_HELPER_BASE64="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git cat-file blob "$SIGNED_APP_CUSTODY_HELPER_BLOB" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')" || \
    die "Could not capture signed-app custody helper from the accepted Git object."
[[ -n "$SIGNED_APP_CUSTODY_HELPER_BASE64" ]] || die "Captured signed-app custody helper is empty."
[[ "$(printf '%s' "$SIGNED_APP_CUSTODY_HELPER_BASE64" | /usr/bin/base64 -D | GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git hash-object --stdin)" == "$SIGNED_APP_CUSTODY_HELPER_BLOB" ]] || \
    die "Decoded signed-app custody helper bytes do not match the accepted Git blob."

SELECTED_XCODE_FREEZE_HELPER_PATH="scripts/ci/capture_selected_xcode_freeze.py"
SELECTED_XCODE_FREEZE_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse "$SOURCE_SHA:$SELECTED_XCODE_FREEZE_HELPER_PATH" 2>/dev/null)" || \
    die "Selected-Xcode freeze helper is missing from the exact accepted Git tree."
[[ "$SELECTED_XCODE_FREEZE_HELPER_BLOB" =~ ^[0-9a-f]{40}$ ]] || die "Selected-Xcode freeze helper Git blob identity is malformed."
SELECTED_XCODE_FREEZE_HELPER_BASE64="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git cat-file blob "$SELECTED_XCODE_FREEZE_HELPER_BLOB" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')" || \
    die "Could not capture selected-Xcode freeze helper from the accepted Git object."
[[ "$(printf '%s' "$SELECTED_XCODE_FREEZE_HELPER_BASE64" | /usr/bin/base64 -D | GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git hash-object --stdin)" == "$SELECTED_XCODE_FREEZE_HELPER_BLOB" ]] || \
    die "Decoded selected-Xcode freeze helper bytes do not match the accepted Git blob."

SELECTED_XCODE_FREEZE_LAUNCHER_PATH="scripts/ci/capture_selected_xcode_freeze_launcher.py"
SELECTED_XCODE_FREEZE_LAUNCHER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse "$SOURCE_SHA:$SELECTED_XCODE_FREEZE_LAUNCHER_PATH" 2>/dev/null)" || \
    die "Selected-Xcode freeze launcher is missing from the exact accepted Git tree."
[[ "$SELECTED_XCODE_FREEZE_LAUNCHER_BLOB" =~ ^[0-9a-f]{40}$ ]] || die "Selected-Xcode freeze launcher Git blob identity is malformed."
SELECTED_XCODE_FREEZE_LAUNCHER_BASE64="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git cat-file blob "$SELECTED_XCODE_FREEZE_LAUNCHER_BLOB" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')" || \
    die "Could not capture selected-Xcode freeze launcher from the accepted Git object."
[[ "$(printf '%s' "$SELECTED_XCODE_FREEZE_LAUNCHER_BASE64" | /usr/bin/base64 -D | GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git hash-object --stdin)" == "$SELECTED_XCODE_FREEZE_LAUNCHER_BLOB" ]] || \
    die "Decoded selected-Xcode freeze launcher bytes do not match the accepted Git blob."

SELECTED_XCODE_BUILD_ORCHESTRATOR_PATH="scripts/ci/capture_selected_xcode_build_orchestrator.py"
SELECTED_XCODE_BUILD_ORCHESTRATOR_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse "$SOURCE_SHA:$SELECTED_XCODE_BUILD_ORCHESTRATOR_PATH" 2>/dev/null)" || \
    die "Selected-Xcode build orchestrator is missing from the exact accepted Git tree."
[[ "$SELECTED_XCODE_BUILD_ORCHESTRATOR_BLOB" =~ ^[0-9a-f]{40}$ ]] || die "Selected-Xcode build orchestrator Git blob identity is malformed."
SELECTED_XCODE_BUILD_ORCHESTRATOR_BASE64="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git cat-file blob "$SELECTED_XCODE_BUILD_ORCHESTRATOR_BLOB" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')" || \
    die "Could not capture selected-Xcode build orchestrator from the accepted Git object."
[[ "$(printf '%s' "$SELECTED_XCODE_BUILD_ORCHESTRATOR_BASE64" | /usr/bin/base64 -D | GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git hash-object --stdin)" == "$SELECTED_XCODE_BUILD_ORCHESTRATOR_BLOB" ]] || \
    die "Decoded selected-Xcode build orchestrator bytes do not match the accepted Git blob."

APP_INSTALL_STAGE_ROOT=""
INSTALL_LOG=""
cleanup_install_subject() {
    if [[ -n "${INSTALL_LOG:-}" ]]; then
        /bin/rm -f -- "$INSTALL_LOG" || true
    fi
    if [[ -n "${APP_INSTALL_STAGE_ROOT:-}" ]]; then
        if ! /usr/bin/sudo -n /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" >/dev/null 2>&1; then
            printf '%s\n' "Protected signed-app stage retained at $APP_INSTALL_STAGE_ROOT; remove it later with sudo after this run is no longer authoritative." >&2
        fi
    fi
}
trap cleanup_install_subject EXIT

say "Building SDK-integrated Nembra Capture with frozen Xcode inside protected compiler-output custody"
# The exact accepted orchestrator remains in one privileged process. Its accepted freeze
# launcher invalidates reusable field-user sudo before publishing a root/no-write COW Xcode,
# then the orchestrator replaces the one canonical xcodebuild marker with that frozen tool
# and calls the dedicated-UID/APFS build-origin helper directly. No return-to-shell/re-sudo
# window exists between selected-toolchain publication and compiler-output custody.
if ! BUILD_ORIGIN_CUSTODY_RESULT="$(
    /usr/bin/sudo /usr/bin/python3 -I -c '
import base64
import hashlib
import re
import sys
encoded = sys.argv[1]
expected = sys.argv[2]
if re.fullmatch(r"[0-9a-f]{40}", expected) is None:
    raise SystemExit("selected-Xcode orchestrator expected blob is malformed")
source = base64.b64decode(encoded, validate=True)
actual = hashlib.sha1(b"blob " + str(len(source)).encode("ascii") + b"\0" + source).hexdigest()
if actual != expected:
    raise SystemExit("selected-Xcode orchestrator bytes do not match the accepted Git blob")
sys.argv = ["<accepted-selected-xcode-build-orchestrator>"] + sys.argv[3:]
namespace = {
    "__name__": "__main__",
    "__file__": "<accepted-selected-xcode-build-orchestrator>",
}
exec(
    compile(source, "<accepted-selected-xcode-build-orchestrator>", "exec", dont_inherit=True),
    namespace,
)
' \
        "$SELECTED_XCODE_BUILD_ORCHESTRATOR_BASE64" \
        "$SELECTED_XCODE_BUILD_ORCHESTRATOR_BLOB" \
        --field-pid "$$" \
        --source-sha "$SOURCE_SHA" \
        --freeze-launcher-base64 "$SELECTED_XCODE_FREEZE_LAUNCHER_BASE64" \
        --freeze-launcher-blob "$SELECTED_XCODE_FREEZE_LAUNCHER_BLOB" \
        --freeze-helper-base64 "$SELECTED_XCODE_FREEZE_HELPER_BASE64" \
        --freeze-helper-blob "$SELECTED_XCODE_FREEZE_HELPER_BLOB" \
        --build-origin-base64 "$BUILD_ORIGIN_CUSTODY_HELPER_BASE64" \
        --build-origin-blob "$BUILD_ORIGIN_CUSTODY_HELPER_BLOB" \
        --install-custody-base64 "$SIGNED_APP_CUSTODY_HELPER_BASE64" \
        --install-custody-blob "$SIGNED_APP_CUSTODY_HELPER_BLOB" \
        -- \
        /usr/bin/python3 -I "$TUYA_BUILD_WINDOW_GUARD" \
        --lockfile "$ROOT/Podfile.lock" \
        --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
        --security-build "$TUYA_PRIVATE_SDK/Build" \
        --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
        --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
        -- /usr/bin/xcodebuild \
        -workspace NembraCapture.xcworkspace \
        -scheme "Nembra Capture" \
        -configuration Debug \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$DERIVED_PLACEHOLDER" \
        -allowProvisioningUpdates \
        -allowProvisioningDeviceRegistration \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE=Automatic \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
        "NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL" \
        "NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA" \
        "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \
        "INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$PROCEDURE_ID"
)"; then
    die "The signed build could not bind frozen selected-Xcode execution to isolated compiler output and protected install custody. No field artifact was admitted."
fi

[[ "$BUILD_ORIGIN_CUSTODY_RESULT" == *$'\t'* ]] || die "Build-origin custody returned no canonical stage/fingerprint record."
[[ "${BUILD_ORIGIN_CUSTODY_RESULT#*$'\t'}" != *$'\t'* ]] || die "Build-origin custody returned an ambiguous stage/fingerprint record."
APP_INSTALL_STAGE_ROOT="${BUILD_ORIGIN_CUSTODY_RESULT%%$'\t'*}"
STAGED_APP_TREE_SHA256="${BUILD_ORIGIN_CUSTODY_RESULT#*$'\t'}"
[[ "$APP_INSTALL_STAGE_ROOT" == /private/tmp/nembra-authenticated-capture-install.* ]] || \
    die "Build-origin custody returned a stage outside the canonical private temporary root."
[[ "$STAGED_APP_TREE_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "Build-origin custody returned a malformed signed-app tree fingerprint."
APP_INSTALL_STAGE="$APP_INSTALL_STAGE_ROOT/Nembra Capture.app"
APP="$APP_INSTALL_STAGE"

# Both privileged layers revoke caller-side cached sudo before selected toolchain
# publication/compiler output. Reprove command and policy-listing noninteractive
# elevation are unavailable before the staged app can be promoted.
if /usr/bin/sudo -n /usr/bin/true >/dev/null 2>&1; then
    die "Noninteractive sudo authority remained after selected-Xcode/build-origin custody; do not install from this stage."
fi
if /usr/bin/sudo -n -l >/dev/null 2>&1; then
    die "Noninteractive sudo policy listing remained after selected-Xcode/build-origin custody; do not install from this stage."
fi

VERIFIED_STAGE_TREE_SHA256="$(printf '%s' "$SIGNED_APP_CUSTODY_HELPER_BASE64" | /usr/bin/base64 -D | /usr/bin/python3 -I - verify-stage \
    --stage-root "$APP_INSTALL_STAGE_ROOT" \
    --app "$APP_INSTALL_STAGE" \
    --expected "$STAGED_APP_TREE_SHA256")" || \
    die "Protected signed-app install subject failed root-owned custody or exact build-origin tree verification."
[[ "$VERIFIED_STAGE_TREE_SHA256" == "$STAGED_APP_TREE_SHA256" ]] || \
    die "Protected signed-app install subject differs from the exact isolated xcodebuild output."
unset BUILD_ORIGIN_CUSTODY_RESULT VERIFIED_STAGE_TREE_SHA256

verify_private_tuya_inputs
[[ "$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')" == "$SOURCE_SHA" ]] || die "Repository HEAD changed while the accepted field build was compiling. Discard this candidate."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart."

APP_INFO_PLIST="$APP/Info.plist"
[[ -f "$APP_INFO_PLIST" ]] || die "Built Capture app is missing its Info.plist provenance subject. Discard this candidate."
BUILT_BUILD_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureBuildIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_SOURCE_SHA="$(/usr/bin/plutil -extract NembraCaptureSourceCommitSHA raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_PROCEDURE_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
[[ "$BUILT_BUILD_IDENTIFIER" == "$BUILD_LABEL" ]] || die "Built Capture app identifier does not match the exact requested field-build label. Discard this candidate."
[[ "$BUILT_SOURCE_SHA" == "$SOURCE_SHA" ]] || die "Built Capture app source SHA does not match the exact requested source. Discard this candidate."
[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."
[[ "$BUILT_PROCEDURE_IDENTIFIER" == "$PROCEDURE_ID" ]] || die "Built Capture app procedure identity does not match the canonical stationary procedure. Discard this candidate."
[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "Built Capture app bundle identifier does not match the intended standalone field product. Discard this candidate."
say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, canonical stationary procedure, and field product"

# Entitlement/profile readback proves identity values, but it does not prove the app bundle's
# recursive signature/seal is valid. Fail closed on the exact signed bytes before those values
# are allowed to participate in field authority or before any device installation is attempted.
if ! /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    die "Final signed Capture app failed recursive strict code-signature verification. Discard this candidate."
fi
say "Final signed Capture app passed recursive strict code-signature verification"

# Apple-backed Smart Life account entry is now part of field preflight. A source entitlement file
# is not enough: prove the final signed executable and the exact embedded provisioning profile both
# authorize Sign in with Apple before this build can be installed as the field candidate. Run the
# Apple verifiers with a closed startup environment and parse an XML plist from either display stream.
SIGNED_ENTITLEMENTS_OUTPUT="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml "$APP" 2>&1)" || \
    die "Could not read effective entitlements from the final signed Capture app. Discard this candidate."
BUILT_SIGNING_IDENTITY="$(printf '%s' "$SIGNED_ENTITLEMENTS_OUTPUT" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '
import plistlib, sys
payload = sys.stdin.buffer.read()
start = payload.find(b"<?xml")
end = payload.rfind(b"</plist>")
if start < 0 or end < start:
    raise SystemExit(2)
try:
    entitlements = plistlib.loads(payload[start:end + len(b"</plist>")])
    apple = entitlements.get("com.apple.developer.applesignin")
    application = entitlements.get("application-identifier")
    team = entitlements.get("com.apple.developer.team-identifier")
except Exception:
    raise SystemExit(2)
if apple == ["Default"] and isinstance(application, str) and isinstance(team, str):
    sys.stdout.write(application + "\t" + team)
' || true)"
[[ "$BUILT_SIGNING_IDENTITY" == *$'\t'* ]] || \
    die "Final signed Capture app is missing required Sign in with Apple or exact application/team identity entitlements. Discard this candidate."
BUILT_APPLICATION_IDENTIFIER="${BUILT_SIGNING_IDENTITY%%$'\t'*}"
BUILT_TEAM_IDENTIFIER="${BUILT_SIGNING_IDENTITY#*$'\t'}"
[[ "$BUILT_APPLICATION_IDENTIFIER" == *"$APP_ID_SUFFIX" ]] || \
    die "Final signed Capture app application-identifier does not end in the exact Capture bundle identifier. Discard this candidate."
[[ "$BUILT_APPLICATION_IDENTIFIER" != *"*"* ]] || \
    die "Final signed Capture app application-identifier is wildcard/ambiguous. Discard this candidate."
BUILT_APP_ID_PREFIX="${BUILT_APPLICATION_IDENTIFIER%$APP_ID_SUFFIX}"
[[ -n "$BUILT_APP_ID_PREFIX" && "$BUILT_APP_ID_PREFIX" != "$BUILT_APPLICATION_IDENTIFIER" ]] || \
    die "Final signed Capture app application-identifier is missing a concrete App ID prefix. Discard this candidate."
[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \
    die "Final signed Capture app team identifier does not match the selected Apple Development team. Discard this candidate."

BUILT_PROFILE="$APP/embedded.mobileprovision"
[[ -f "$BUILT_PROFILE" ]] || die "Final signed Capture app is missing embedded.mobileprovision. Discard this candidate."
PROFILE_PLIST_XML="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i "$BUILT_PROFILE" 2>/dev/null)" || \
    die "Could not decode the exact provisioning profile embedded in the final signed Capture app. Discard this candidate."
PROFILE_SIGNING_IDENTITY="$(printf '%s' "$PROFILE_PLIST_XML" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '
import plistlib, sys
try:
    root = plistlib.loads(sys.stdin.buffer.read())
    entitlements = root.get("Entitlements", {})
    apple = entitlements.get("com.apple.developer.applesignin")
    application = entitlements.get("application-identifier")
    entitlement_team = entitlements.get("com.apple.developer.team-identifier")
    team_identifiers = root.get("TeamIdentifier")
except Exception:
    raise SystemExit(2)
if (apple == ["Default"] and isinstance(application, str) and isinstance(entitlement_team, str)
        and isinstance(team_identifiers, list) and len(team_identifiers) == 1
        and isinstance(team_identifiers[0], str)):
    sys.stdout.write(application + "\t" + entitlement_team + "\t" + team_identifiers[0])
' || true)"
[[ "$PROFILE_SIGNING_IDENTITY" == *$'\t'*$'\t'* ]] || \
    die "Embedded provisioning profile is missing required Sign in with Apple or exact application/team identity custody. Discard this candidate."
PROFILE_APPLICATION_IDENTIFIER="${PROFILE_SIGNING_IDENTITY%%$'\t'*}"
PROFILE_TEAM_FIELDS="${PROFILE_SIGNING_IDENTITY#*$'\t'}"
PROFILE_TEAM_IDENTIFIER="${PROFILE_TEAM_FIELDS%%$'\t'*}"
PROFILE_ROOT_TEAM_IDENTIFIER="${PROFILE_TEAM_FIELDS#*$'\t'}"
[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]] || \
    die "Embedded provisioning profile application identifier does not exactly match the final signed Capture app. Discard this candidate."
[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \
    die "Embedded provisioning profile entitlement team identity does not match the selected Apple Development team. Discard this candidate."
[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \
    die "Embedded provisioning profile root TeamIdentifier does not match the selected Apple Development team. Discard this candidate."
say "Final signed app and embedded provisioning profile authorize Sign in with Apple for one exact App ID and the selected team"
unset SIGNED_ENTITLEMENTS_OUTPUT BUILT_SIGNING_IDENTITY BUILT_APPLICATION_IDENTIFIER BUILT_TEAM_IDENTIFIER BUILT_APP_ID_PREFIX PROFILE_PLIST_XML PROFILE_SIGNING_IDENTITY PROFILE_APPLICATION_IDENTIFIER PROFILE_TEAM_FIELDS PROFILE_TEAM_IDENTIFIER PROFILE_ROOT_TEAM_IDENTIFIER BUILT_PROFILE APP_ID_SUFFIX
unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_PROCEDURE_IDENTIFIER BUILT_BUNDLE_ID APP_INFO_PLIST

say "Installing SDK-integrated Capture on the intended iPhone"
open -a Xcode "$ROOT/NembraCapture.xcworkspace" >/dev/null 2>&1 || true
INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-authenticated-capture-install-log.XXXXXX")"
chmod 600 "$INSTALL_LOG"
INSTALLED=0
for ATTEMPT in $(seq 1 60); do
    if xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP" >"$INSTALL_LOG" 2>&1; then
        INSTALLED=1
        break
    fi
    if [[ "$ATTEMPT" == "1" ]]; then
        printf '%s\n' "Xcode still appears to be preparing the intended iPhone. Keep it plugged in and unlocked; installation will retry automatically."
    fi
    sleep 3
done

if [[ "$INSTALLED" != "1" ]]; then
    if [[ -s "$INSTALL_LOG" ]]; then
        INSTALL_DIAGNOSTIC="$(
            printf '%s\0%s' "$DEVICE_UDID" "$COREDEVICE_ID" | /usr/bin/python3 -I -c '
import re
import sys
from pathlib import Path
payload = sys.stdin.buffer.read()
try:
    private_udid_raw, selector_raw = payload.split(b"\0", 1)
    private_udid = private_udid_raw.decode("utf-8")
    selector = selector_raw.decode("utf-8")
except (ValueError, UnicodeDecodeError):
    raise SystemExit(2)
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
secrets = (
    (private_udid, "<redacted-device>"),
    (selector, "<redacted-device-selector>"),
)
for secret, replacement in secrets:
    for variant in sorted({secret, secret.replace("-", "")}, key=len, reverse=True):
        if variant:
            text = re.sub(re.escape(variant), replacement, text, flags=re.IGNORECASE)
sys.stdout.write(text)
' "$INSTALL_LOG"
        )"
        printf '%s\n' "$INSTALL_DIAGNOSTIC" >&2
        unset INSTALL_DIAGNOSTIC
    fi
    die "The app built successfully, but the intended iPhone never became ready for installation. Keep it unlocked and connected, wait for Xcode to finish Preparing/Connecting, then run this installer again."
fi

say "Launching privately provisioned Capture on the intended iPhone"
if ! xcrun devicectl device process launch \
    --device "$COREDEVICE_ID" \
    --activate \
    "$BUNDLE_ID" >/dev/null 2>&1; then
    die "Capture installed, but devicectl could not launch it on the intended iPhone. Do not promote the physical test; relaunch through this installer after the device is ready."
fi
unset DEVICE_UDID COREDEVICE_ID DEVICE_OS_VERSION
rm -f -- "$INSTALL_LOG"
INSTALL_LOG=""
if /usr/bin/sudo -n /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" >/dev/null 2>&1; then
    APP_INSTALL_STAGE_ROOT=""
else
    printf '%s\n' "Protected signed-app stage retained at $APP_INSTALL_STAGE_ROOT; remove it later with sudo after this run is no longer authoritative." >&2
fi
trap - EXIT
unset STAGED_APP_TREE_SHA256 SIGNED_APP_CUSTODY_HELPER_PATH SIGNED_APP_CUSTODY_HELPER_BLOB SIGNED_APP_CUSTODY_HELPER_BASE64 BUILD_ORIGIN_CUSTODY_HELPER_PATH BUILD_ORIGIN_CUSTODY_HELPER_BLOB BUILD_ORIGIN_CUSTODY_HELPER_BASE64 APP_INSTALL_STAGE
unset SELECTED_XCODE_FREEZE_HELPER_PATH SELECTED_XCODE_FREEZE_HELPER_BLOB SELECTED_XCODE_FREEZE_HELPER_BASE64 SELECTED_XCODE_FREEZE_LAUNCHER_PATH SELECTED_XCODE_FREEZE_LAUNCHER_BLOB SELECTED_XCODE_FREEZE_LAUNCHER_BASE64 SELECTED_XCODE_BUILD_ORCHESTRATOR_PATH SELECTED_XCODE_BUILD_ORCHESTRATOR_BLOB SELECTED_XCODE_BUILD_ORCHESTRATOR_BASE64

say "SDK-INTEGRATED CAPTURE LAUNCHED"
printf '%s\n' \
    "This launch used no Tuya secret in host argv, environment, Git, or the diagnostic export." \
    "The private intended-device UDID was used only for local correlation and was not placed in devicectl argv." \
    "The exact private Tuya security SDK, resolved lockfile, and generated private app identity matched the bootstrap fingerprint before and after the signed build." \
    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, canonical stationary procedure, and standalone bundle identifier." \
    "Field procedure: $PROCEDURE_ID. The same identifier is compiled into the immutable accepted export and shown in Capture." \
    "Do NOT repeat the old 17-step ride capture." \
    "Keep the scooter stationary for this first preflight." \
    "If Capture says SDK compiled/configured, account logged in, exact scooter membership, or field-build provenance is not proven, STOP and do not start Bluetooth correlation." \
    "Only after every app authority gate is green: complete the package-owned OFF1 -> ON1 -> OFF2 -> ON2 correlation in order, wait for each fresh-manager scanner to report Live and satisfy the receipt-bounded window before sealing it, then explicitly confirm the single repeatable correlated target for this attempt before starting the secure read-only test." \
    "A correlated target is current-session evidence only; it is not permanent scooter identity, and name/RSSI/FD50/Tuya-company/historical UUID hints never substitute for the four-window result." \
    "PASS requires exact SDK scooter membership, same-account source authority, Tuya local BLE online, a genuine same-generation dpsUpdate, canonical continuity of at least 45 seconds, a sealed accepted prefix, and no command/pair/reset/unbind action." \
    "If any gate fails, correlation is ambiguous, the app reports source/continuity/lifecycle failure, or the package cannot seal the accepted prefix, share the sanitized diagnostic JSON and stop. No outdoor ride is authorized by this installer."
