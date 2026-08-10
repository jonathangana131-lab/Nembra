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
PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"
[[ -f "$PRIVATE_DEVICE_RUNNER" ]] || die "Private intended-device reader is missing from the accepted source."
if ! DEVICE_UDID="$(/usr/bin/python3 -I - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
import importlib.util
import sys
from pathlib import Path

runner_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("nembra_private_device_reader", runner_path)
if spec is None or spec.loader is None:
    raise RuntimeError("private intended-device reader could not be loaded")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
value = module.read_private_identifier(Path(sys.argv[2]), Path(sys.argv[3]))
sys.stdout.write(value)
PY
)"; then
    die "The intended-device verification file failed private custody validation."
fi
[[ -n "$DEVICE_UDID" ]] || die "The intended-device verification file produced no identifier."
say "Private intended-device admission validated"

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
TUYA_PRIVATE_SDK="$ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$ROOT/LocalSecrets/TuyaRuntime"
TUYA_DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
verify_private_tuya_inputs() {
    /usr/bin/python3 "$TUYA_PROVENANCE_HELPER" verify \
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
DEVICE_ROWS="$(xcrun xctrace list devices 2>/dev/null | /usr/bin/python3 -c '
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
COREDEVICE_MATCH="$(printf '%s\0%s' "$DEVICE_UDID" "$COREDEVICE_ROWS" | /usr/bin/python3 -c '
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
TEAM_IDS="$(security find-identity -v -p codesigning 2>/dev/null | /usr/bin/python3 -c '
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

DERIVED="${TMPDIR:-/tmp}/NembraAuthenticatedCaptureDerived"
rm -rf "$DERIVED"
BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
PROCEDURE_ID="ES80-AUTHENTICATED-STATIONARY-v1"
BUILD_LABEL="capture-v14-${SOURCE_SHA:0:12}"
verify_private_tuya_inputs

say "Building SDK-integrated Nembra Capture for the intended iPhone"
xcodebuild \
    -workspace NembraCapture.xcworkspace \
    -scheme "Nembra Capture" \
    -configuration Debug \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    "NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL" \
    "NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA" \
    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \
    build

verify_private_tuya_inputs
[[ "$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')" == "$SOURCE_SHA" ]] || die "Repository HEAD changed while the accepted field build was compiling. Discard this candidate."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart."
APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"
[[ -d "$APP" ]] || die "Build finished but the standalone Nembra Capture.app was not found at $APP"
APP_INFO_PLIST="$APP/Info.plist"
[[ -f "$APP_INFO_PLIST" ]] || die "Built Capture app is missing its Info.plist provenance subject. Discard this candidate."
BUILT_BUILD_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureBuildIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_SOURCE_SHA="$(/usr/bin/plutil -extract NembraCaptureSourceCommitSHA raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
[[ "$BUILT_BUILD_IDENTIFIER" == "$BUILD_LABEL" ]] || die "Built Capture app identifier does not match the exact requested field-build label. Discard this candidate."
[[ "$BUILT_SOURCE_SHA" == "$SOURCE_SHA" ]] || die "Built Capture app source SHA does not match the exact requested source. Discard this candidate."
[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."
[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "Built Capture app bundle identifier does not match the intended standalone field product. Discard this candidate."
say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, and field product"
unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_BUNDLE_ID APP_INFO_PLIST

say "Installing SDK-integrated Capture on the intended iPhone"
open -a Xcode "$ROOT/NembraCapture.xcworkspace" >/dev/null 2>&1 || true
INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-authenticated-capture-install.XXXXXX")"
trap 'rm -f -- "$INSTALL_LOG"' EXIT
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
trap - EXIT

say "SDK-INTEGRATED CAPTURE LAUNCHED"
printf '%s\n' \
    "This launch used no Tuya secret in host argv, environment, Git, or the diagnostic export." \
    "The private intended-device UDID was used only for local correlation and was not placed in devicectl argv." \
    "The exact private Tuya security SDK, resolved lockfile, and generated private app identity matched the bootstrap fingerprint before and after the signed build." \
    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, and standalone bundle identifier." \
    "Field procedure: $PROCEDURE_ID. The same identifier is compiled into the immutable accepted export." \
    "Do NOT repeat the old 17-step ride capture." \
    "Keep the scooter stationary for this first preflight." \
    "If Capture says SDK compiled/configured, account logged in, exact scooter membership, or field-build provenance is not proven, STOP and do not start Bluetooth correlation." \
    "Only after every app authority gate is green: complete the package-owned OFF1 -> ON1 -> OFF2 -> ON2 correlation in order, wait for each fresh-manager scanner to report Live and satisfy the receipt-bounded window before sealing it, then explicitly confirm the single repeatable correlated target for this attempt before starting the secure read-only test." \
    "A correlated target is current-session evidence only; it is not permanent scooter identity, and name/RSSI/FD50/Tuya-company/historical UUID hints never substitute for the four-window result." \
    "PASS requires exact SDK scooter membership, same-account source authority, Tuya local BLE online, a genuine same-generation dpsUpdate, canonical continuity of at least 45 seconds, a sealed accepted prefix, and no command/pair/reset/unbind action." \
    "If any gate fails, correlation is ambiguous, the app reports source/continuity/lifecycle failure, or the package cannot seal the accepted prefix, share the sanitized diagnostic JSON and stop. No outdoor ride is authorized by this installer."
