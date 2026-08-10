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
script again. Do not copy private Tuya provisioning material into git.
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

TUYA_SECURITY_DIR="$REPO_ROOT/LocalSecrets/TuyaSecuritySDK"
if [[ ! -f "$TUYA_SECURITY_DIR/ThingSmartCryption.podspec" ]]; then
  cat >&2 <<EOF
ERROR: Tuya's app-specific iOS security SDK is not provisioned.

Expected:
  $TUYA_SECURITY_DIR/ThingSmartCryption.podspec
  $TUYA_SECURITY_DIR/Build/   (from the Tuya SDK security package for this app)

Download the security package for Nembra Capture's exact iOS bundle identifier
from the Tuya Developer Platform and place its ThingSmartCryption.podspec plus
Build directory at that ignored local path. Do not commit those files.
EOF
  exit 5
fi

if [[ ! -d "$TUYA_SECURITY_DIR/Build" ]]; then
  echo "ERROR: Tuya security SDK Build directory is missing at $TUYA_SECURITY_DIR/Build" >&2
  exit 6
fi

printf 'Installing the official Tuya SmartLife iOS SDK for Nembra Capture...\n'
pod install

if [[ ! -d NembraCapture.xcworkspace ]]; then
  echo "ERROR: CocoaPods did not create NembraCapture.xcworkspace." >&2
  exit 7
fi

cat <<'EOF'

Tuya SDK integration is installed locally with the app-specific security pod.

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.

This bootstrap does NOT authorize a Tuya SDK user session and does not authorize
the physical experiment. Nembra Capture must continue to fail closed until its
in-app preflight reports every required gate as satisfied.
EOF
