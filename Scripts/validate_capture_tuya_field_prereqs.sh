#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT="$ROOT/NembraCapture.xcodeproj/project.pbxproj"
PODFILE="$ROOT/Podfile"
TUYA_PRIVATE_SDK="$ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$ROOT/LocalSecrets/TuyaRuntime"
EXPECTED_BUNDLE_ID='com.jonathangana131.nembra.capturelearn'

fail() {
  printf 'NOT_READY: %s\n' "$1" >&2
  exit "${2:-1}"
}

[[ -f "$PROJECT" ]] || fail 'capture-project-missing' 2
[[ -f "$PODFILE" ]] || fail 'podfile-missing' 3

# Tuya requires the SDK app identity and iOS Bundle ID registered in the
# Developer Platform to stay coherent. Refuse to prepare a private field build
# if the standalone Capture target drifts away from the identity for which the
# private security component must be generated.
#
# grep returns 1 when there are zero matches. Under set -e + pipefail that must
# not bypass the explicit NOT_READY diagnostic below, so normalize the expected
# zero-match status while still preserving the exact fixed-string count.
BUNDLE_COUNT="$(grep -Fc "PRODUCT_BUNDLE_IDENTIFIER = $EXPECTED_BUNDLE_ID;" "$PROJECT" || true)"
[[ "$BUNDLE_COUNT" == '2' ]] || fail 'capture-bundle-id-does-not-match-tuya-field-identity' 4

# The security component is app-specific private material downloaded from the
# user's own Tuya Developer Platform app. Presence is necessary before CocoaPods
# is allowed to resolve the authenticated field workspace.
[[ -f "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" ]] || fail 'tuya-security-podspec-missing' 5
[[ -d "$TUYA_PRIVATE_SDK/Build" ]] || fail 'tuya-security-build-missing' 6

# AppKey/AppSecret are generated into an ignored local pod by the provisioner.
# Never print, source, grep, hash, or otherwise expose those values here.
PRIVATE_PODSPEC="$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec"
PRIVATE_SOURCE="$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift"
[[ -f "$PRIVATE_PODSPEC" ]] || fail 'tuya-private-config-podspec-missing' 7
[[ -f "$PRIVATE_SOURCE" ]] || fail 'tuya-private-config-source-missing' 8

# Lock the public SDK line and both private local pods. A field build that drops
# any of these dependencies is not allowed to claim official Tuya auth support.
grep -Fq "pod 'ThingSmartCryption', :path => './LocalSecrets/TuyaSDK'" "$PODFILE" \
  || fail 'tuya-security-pod-not-wired' 9
grep -Fq "pod 'NembraTuyaPrivateConfig', :path => './LocalSecrets/TuyaRuntime'" "$PODFILE" \
  || fail 'tuya-private-config-pod-not-wired' 10
grep -Fq "pod 'ThingSmartHomeKit', '7.8.0'" "$PODFILE" \
  || fail 'tuya-homekit-version-not-pinned' 11
grep -Fq "pod 'ThingSmartBusinessExtensionKit', '7.8.0'" "$PODFILE" \
  || fail 'tuya-extension-version-not-pinned' 12

# LocalSecrets must remain outside version control. This checks repository
# policy without enumerating or printing any secret-bearing file contents.
git -C "$ROOT" check-ignore -q LocalSecrets/ \
  || fail 'local-secrets-not-git-ignored' 13

printf 'READY: Tuya field prerequisites are present for bundle %s.\n' "$EXPECTED_BUNDLE_ID"
printf 'NEXT: resolve NembraCapture.xcworkspace and use only the stationary authenticated read-only preflight.\n'
