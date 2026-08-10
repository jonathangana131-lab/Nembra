#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v pod >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ERROR: CocoaPods is not installed.

Nembra Capture's authenticated Tuya BLE path intentionally uses Tuya's official
SmartLife App SDK. Install CocoaPods on the development Mac, then run this
script again. Do not copy SDK binaries or private Tuya credentials into git.
EOF
  exit 2
fi

if [[ ! -f Podfile ]]; then
  echo "ERROR: Podfile is missing at $REPO_ROOT/Podfile" >&2
  exit 3
fi

if [[ ! -d NembraCapture.xcodeproj ]]; then
  echo "ERROR: NembraCapture.xcodeproj is missing." >&2
  exit 4
fi

TUYA_SECURITY_ROOT="$REPO_ROOT/LocalSecrets/TuyaSDK"
if [[ ! -f "$TUYA_SECURITY_ROOT/ThingSmartCryption.podspec" || ! -e "$TUYA_SECURITY_ROOT/Build" ]]; then
  cat >&2 <<EOF
ERROR: Tuya's app-specific iOS security SDK is not provisioned.

For the Tuya Developer Platform SmartLife SDK app whose iOS Bundle ID exactly
matches Nembra Capture, download and extract ios_core_sdk.tar.gz, then keep the
following private files only on this Mac under:

  $TUYA_SECURITY_ROOT/

Required:
  ThingSmartCryption.podspec
  Build

LocalSecrets/ is git-ignored. Do not commit, upload, paste, or attach this
security package. A public ThingSmartHomeKit pod by itself is not a complete
SmartLife App SDK v5+ integration.
EOF
  exit 5
fi

printf 'Installing the official Tuya SmartLife iOS SDK for Nembra Capture...\n'
pod install

if [[ ! -d NembraCapture.xcworkspace ]]; then
  echo "ERROR: CocoaPods did not create NembraCapture.xcworkspace." >&2
  exit 6
fi

cat <<'EOF'

Tuya SDK dependencies and the app-specific security component are installed locally.

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.

This bootstrap does NOT provision AppKey/AppSecret, authorize a Tuya SDK user
session, or authorize the physical experiment. Nembra Capture must continue to
fail closed until its in-app preflight reports all of those gates as satisfied.
EOF
