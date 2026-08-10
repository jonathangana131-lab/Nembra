#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TUYA_PRIVATE_SDK="$REPO_ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$REPO_ROOT/LocalSecrets/TuyaRuntime"
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

# Tuya's SmartLife iOS SDK requires the app-specific security package generated
# for the exact Developer Platform app/bundle identity. It must never be
# replaced with a public placeholder or omitted just to make CocoaPods resolve.
if [[ ! -f "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" || ! -d "$TUYA_PRIVATE_SDK/Build" ]]; then
  cat >&2 <<EOF
ERROR: Tuya's app-specific iOS security SDK is not provisioned.

Expected private files:
  $TUYA_PRIVATE_SDK/ThingSmartCryption.podspec
  $TUYA_PRIVATE_SDK/Build/

On the Tuya Developer Platform, build/download the SmartLife iOS SDK for the
EXACT Nembra Capture Bundle ID, extract ios_core_sdk.tar.gz, and place its
ThingSmartCryption.podspec plus Build directory in:
  $TUYA_PRIVATE_SDK

LocalSecrets/ is git-ignored. Do not commit, paste, upload, or export this SDK,
AppKey/AppSecret, account tokens, device keys, or session material.
EOF
  exit 5
fi

if [[ ! -f "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" ||
      ! -f "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift" ]]; then
  cat >&2 <<EOF
ERROR: Tuya's private app identity is not provisioned for the field workspace.

Run:
  Scripts/provision_capture_tuya_identity.sh

That script reads AppKey/AppSecret with terminal echo disabled and writes them
only beneath ignored LocalSecrets/TuyaRuntime as a local Swift pod. The values
must not be passed through xcodebuild/devicectl arguments or committed to Git.
EOF
  exit 6
fi

printf 'Resolving the official Tuya SmartLife iOS SDK and private field identity for Nembra Capture...\n'
# Tuya's integration guide uses `pod update` after the app-specific Cryption
# package is present. Explicit Podfile version constraints keep the public SDK
# line bounded while both private packages remain local.
pod update

if [[ ! -d NembraCapture.xcworkspace ]]; then
  echo "ERROR: CocoaPods did not create NembraCapture.xcworkspace." >&2
  exit 7
fi

cat <<'EOF'

Tuya SDK dependencies are integrated locally, including the app-specific
ThingSmartCryption package and local-only app identity pod.

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.

This bootstrap still does NOT authorize the physical experiment. The exact app
must consume the private identity pod, authorize the user's own SDK session,
prove exact scooter membership, receive a genuine structured application
update, and survive the canonical authenticated 45-second gate before
stationary mapping can unlock.
EOF
