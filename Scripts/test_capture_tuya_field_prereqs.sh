#!/bin/bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_VALIDATOR="$SOURCE_ROOT/Scripts/validate_capture_tuya_field_prereqs.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nembra-tuya-prereq-test.XXXXXX")"
FIXTURE="$TMP_ROOT/repo"
OUT="$TMP_ROOT/out.txt"
ERR="$TMP_ROOT/err.txt"
EXPECTED_BUNDLE_ID='com.jonathangana131.nembra.capturelearn'

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p \
  "$FIXTURE/Scripts" \
  "$FIXTURE/NembraCapture.xcodeproj" \
  "$FIXTURE/LocalSecrets/TuyaSDK/Build" \
  "$FIXTURE/LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"

cp "$SOURCE_VALIDATOR" "$FIXTURE/Scripts/validate_capture_tuya_field_prereqs.sh"
chmod +x "$FIXTURE/Scripts/validate_capture_tuya_field_prereqs.sh"

git -C "$FIXTURE" init -q
printf 'LocalSecrets/\n' > "$FIXTURE/.gitignore"

cat > "$FIXTURE/Podfile" <<'EOF'
pod 'ThingSmartCryption', :path => './LocalSecrets/TuyaSDK'
pod 'NembraTuyaPrivateConfig', :path => './LocalSecrets/TuyaRuntime'
pod 'ThingSmartHomeKit', '7.8.0'
pod 'ThingSmartBusinessExtensionKit', '7.8.0'
EOF

: > "$FIXTURE/LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"
: > "$FIXTURE/LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"
: > "$FIXTURE/LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift"

write_project() {
  local first_bundle="$1"
  local second_bundle="$2"
  cat > "$FIXTURE/NembraCapture.xcodeproj/project.pbxproj" <<EOF
PRODUCT_BUNDLE_IDENTIFIER = $first_bundle;
PRODUCT_BUNDLE_IDENTIFIER = $second_bundle;
EOF
}

write_project "$EXPECTED_BUNDLE_ID" "$EXPECTED_BUNDLE_ID"
bash "$FIXTURE/Scripts/validate_capture_tuya_field_prereqs.sh" >"$OUT" 2>"$ERR"
grep -Fq "READY: Tuya field prerequisites are present for bundle $EXPECTED_BUNDLE_ID." "$OUT"
test ! -s "$ERR"

# Regression: grep exits 1 for zero matches. The validator must still reach its
# explicit fail-closed diagnostic instead of being terminated early by
# `set -euo pipefail` inside the count command substitution.
write_project 'com.example.wrong.one' 'com.example.wrong.two'
set +e
bash "$FIXTURE/Scripts/validate_capture_tuya_field_prereqs.sh" >"$OUT" 2>"$ERR"
status=$?
set -e
[[ "$status" -eq 4 ]]
grep -Fxq 'NOT_READY: capture-bundle-id-does-not-match-tuya-field-identity' "$ERR"

# An accidental duplicate/third matching configuration must fail through the
# same deterministic authority boundary rather than silently widening identity.
cat >> "$FIXTURE/NembraCapture.xcodeproj/project.pbxproj" <<EOF
PRODUCT_BUNDLE_IDENTIFIER = $EXPECTED_BUNDLE_ID;
PRODUCT_BUNDLE_IDENTIFIER = $EXPECTED_BUNDLE_ID;
PRODUCT_BUNDLE_IDENTIFIER = $EXPECTED_BUNDLE_ID;
EOF
set +e
bash "$FIXTURE/Scripts/validate_capture_tuya_field_prereqs.sh" >"$OUT" 2>"$ERR"
status=$?
set -e
[[ "$status" -eq 4 ]]
grep -Fxq 'NOT_READY: capture-bundle-id-does-not-match-tuya-field-identity' "$ERR"

printf 'Tuya field prerequisite validator regression test passed.\n'
