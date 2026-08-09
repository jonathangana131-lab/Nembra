#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$ROOT"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Run this on the Mac with Xcode and the iPhone connected."
command -v xcodebuild >/dev/null || die "Xcode command-line tools are not available."
command -v xcrun >/dev/null || die "xcrun is not available."
command -v security >/dev/null || die "macOS security tool is not available."

CURRENT_BRANCH="$(git branch --show-current)"
[[ "$CURRENT_BRANCH" == "capture/one-time-ble-dump-gpt56" ]] || die "Switch to capture/one-time-ble-dump-gpt56 first. Current branch: ${CURRENT_BRANCH:-detached}"
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Working tree has local changes. Commit/stash them first."

say "Finding connected iPhone"
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
[[ -n "$DEVICE_ROWS" ]] || die "No physical iPhone found. Connect it by USB, unlock it, trust this Mac, and enable Developer Mode."

DEVICE_COUNT="$(printf '%s\n' "$DEVICE_ROWS" | wc -l | tr -d ' ')"
if [[ "$DEVICE_COUNT" == "1" ]]; then
    DEVICE_UDID="$(printf '%s\n' "$DEVICE_ROWS" | cut -f1)"
    DEVICE_NAME="$(printf '%s\n' "$DEVICE_ROWS" | cut -f2-)"
else
    printf '%s\n' "$DEVICE_ROWS" | nl -w2 -s') '
    read -r -p "Choose iPhone number: " PICK
    DEVICE_UDID="$(printf '%s\n' "$DEVICE_ROWS" | sed -n "${PICK}p" | cut -f1)"
    DEVICE_NAME="$(printf '%s\n' "$DEVICE_ROWS" | sed -n "${PICK}p" | cut -f2-)"
    [[ -n "$DEVICE_UDID" ]] || die "Invalid device selection."
fi
say "Using $DEVICE_NAME"

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

DERIVED="${TMPDIR:-/tmp}/NembraGuidedCaptureDerived"
rm -rf "$DERIVED"
BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
SOURCE_SHA="$(git rev-parse HEAD)"
BUILD_LABEL="Guided scooter learning ${SOURCE_SHA:0:12}"

say "Building guided Nembra Capture for the connected iPhone"
xcodebuild \
    -project Nembra.xcodeproj \
    -scheme Nembra \
    -configuration Debug \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    "NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL" \
    "NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA" \
    build

APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra.app"
[[ -d "$APP" ]] || die "Build finished but Nembra.app was not found at $APP"

say "Installing on iPhone"
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"

say "GUIDED CAPTURE INSTALLED"
printf '%s\n' \
    "Open Nembra Capture on the iPhone." \
    "Follow the app itself; it now guides the whole learning session." \
    "It first compares scooter-OFF vs scooter-ON Bluetooth scans so the likely scooter is easy to find." \
    "After connection it records GATT topology, readable values, notifications, descriptors, RSSI and optional GPS reference speed." \
    "It guides stationary mode/light/brake tests, walking-wheel motion, an optional safely-supported unloaded-wheel test, and ride segments." \
    "For every moving step: press Start while fully stopped, secure the phone, ride, stop completely, then press Complete." \
    "At the end tap Finish capture & prepare JSON, then Share learning dataset back into ChatGPT." \
    "" \
    "The guided Capture source contains no CoreBluetooth application-characteristic writeValue(...) call."
