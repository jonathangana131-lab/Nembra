#!/bin/bash -p
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV
umask 077

say() { builtin printf '\n==> %s\n' "$*"; }
die() { builtin printf '\nERROR: %s\n' "$*" >&2; exit 1; }

APP="${1:-}"
BUILD_LABEL="${2:-}"
SOURCE_SHA="${3:-}"
TUYA_DEPENDENCY_LOCK_SHA256="${4:-}"
PROCEDURE_ID="${5:-}"
BUNDLE_ID="${6:-}"
TEAM_ID="${7:-}"
COREDEVICE_ID="${8:-}"
ROOT="${9:-}"

[[ "$APP" == /* && -d "$APP" && ! -L "$APP" ]] || die "Guarded Capture app subject must be one absolute real app directory."
[[ -n "$BUILD_LABEL" ]] || die "Guarded Capture build label is missing."
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || die "Guarded Capture source SHA is malformed."
[[ "$TUYA_DEPENDENCY_LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "Guarded Tuya dependency-lock digest is malformed."
[[ "$PROCEDURE_ID" == "ES80-AUTHENTICATED-STATIONARY-v1" ]] || die "Guarded Capture procedure is not the canonical stationary procedure."
[[ "$BUNDLE_ID" == "com.jonathangana131.nembra.capturelearn" ]] || die "Guarded Capture bundle identifier is not the standalone field product."
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "Guarded Apple Development TeamIdentifier is malformed."
[[ "$COREDEVICE_ID" =~ ^[0-9A-Fa-f-]{36}$ ]] || die "Guarded CoreDevice selector is malformed."
[[ "$ROOT" == /* && -d "$ROOT" && ! -L "$ROOT" ]] || die "Guarded repository root is unavailable."

# The raw private UDID is diagnostic-redaction input only. It arrives over stdin,
# never argv/environment, and is never passed to devicectl. CoreDevice side effects
# use only the previously correlated non-private selector.
IFS= builtin read -r PRIVATE_DEVICE_UDID || die "Private intended-device redaction token was not supplied over stdin."
[[ -n "$PRIVATE_DEVICE_UDID" ]] || die "Private intended-device redaction token is empty."

APP_INFO_PLIST="$APP/Info.plist"
[[ -f "$APP_INFO_PLIST" && ! -L "$APP_INFO_PLIST" ]] || die "Built Capture app is missing a real Info.plist provenance subject. Discard this candidate."
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

# Signature authority and installation are intentionally inside the same outer vnode
# + cryptographic custody window. No later mutable-path gap may separate the bytes
# that earned these checks from the bytes CoreDevice consumes.
if ! /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    die "Final signed Capture app failed recursive strict code-signature verification. Discard this candidate."
fi
say "Final signed Capture app passed recursive strict code-signature verification"

SIGNED_ENTITLEMENTS_OUTPUT="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml "$APP" 2>&1)" || \
    die "Could not read effective entitlements from the final signed Capture app. Discard this candidate."
BUILT_SIGNING_IDENTITY="$(builtin printf '%s' "$SIGNED_ENTITLEMENTS_OUTPUT" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '
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
APP_ID_SUFFIX=".${BUNDLE_ID}"
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
[[ -f "$BUILT_PROFILE" && ! -L "$BUILT_PROFILE" ]] || die "Final signed Capture app is missing a real embedded.mobileprovision. Discard this candidate."
PROFILE_PLIST_XML="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i "$BUILT_PROFILE" 2>/dev/null)" || \
    die "Could not decode the exact provisioning profile embedded in the final signed Capture app. Discard this candidate."
PROFILE_SIGNING_IDENTITY="$(builtin printf '%s' "$PROFILE_PLIST_XML" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '
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

INSTALL_LOG="$(/usr/bin/mktemp /tmp/nembra-authenticated-capture-install.XXXXXX)" || die "Could not create private CoreDevice install log."
/bin/chmod 600 "$INSTALL_LOG"
cleanup() {
    /bin/rm -f -- "$INSTALL_LOG"
    unset PRIVATE_DEVICE_UDID
}
trap cleanup EXIT HUP INT TERM

say "Installing the same guarded signed Capture subject on the intended iPhone"
INSTALLED=0
ATTEMPT=1
while (( ATTEMPT <= 60 )); do
    if /usr/bin/xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP" >"$INSTALL_LOG" 2>&1; then
        INSTALLED=1
        break
    fi
    if (( ATTEMPT == 1 )); then
        builtin printf '%s\n' "Xcode still appears to be preparing the intended iPhone. Keep it plugged in and unlocked; installation will retry automatically."
    fi
    ATTEMPT=$((ATTEMPT + 1))
    /bin/sleep 3
done

if [[ "$INSTALLED" != "1" ]]; then
    if [[ -s "$INSTALL_LOG" ]]; then
        INSTALL_DIAGNOSTIC="$(
            builtin printf '%s\0%s' "$PRIVATE_DEVICE_UDID" "$COREDEVICE_ID" | /usr/bin/python3 -I -c '
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
        builtin printf '%s\n' "$INSTALL_DIAGNOSTIC" >&2
        unset INSTALL_DIAGNOSTIC
    fi
    die "The app built successfully, but the intended iPhone never became ready for installation. Keep it unlocked and connected, wait for Xcode to finish Preparing/Connecting, then run this installer again."
fi

# The outer signed-app guard performs the final no-mutation proof only after this
# process exits. A successful CoreDevice transfer therefore remains provisional
# until the parent guard returns zero; the caller must not launch before then.
say "CoreDevice accepted the guarded install subject; awaiting final no-mutation custody proof"
cleanup
trap - EXIT HUP INT TERM
exit 0
