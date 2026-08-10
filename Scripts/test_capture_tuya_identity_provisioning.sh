#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nembra-tuya-identity-test.XXXXXX")"
DEST="$TMP_ROOT/TuyaRuntime"
OUTPUT="$TMP_ROOT/output.txt"
DUMMY_KEY='nembra-ci-dummy-key'
DUMMY_SECRET='nembra-ci-dummy-secret'

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

printf '%s\n%s\n' "$DUMMY_KEY" "$DUMMY_SECRET" \
  | NEMBRA_TUYA_RUNTIME_DIR="$DEST" \
      bash "$ROOT/Scripts/provision_capture_tuya_identity.sh" >"$OUTPUT"

PODSPEC="$DEST/NembraTuyaPrivateConfig.podspec"
SOURCE="$DEST/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift"

test -f "$PODSPEC"
test -f "$SOURCE"
ruby -c "$PODSPEC" >/dev/null

grep -Fq 'public enum NembraTuyaPrivateIdentity' "$SOURCE"
grep -Fq 'Data(base64Encoded:' "$SOURCE"

# Dummy plaintext must never be echoed by the provisioner or written literally
# into the generated source. Encoding is representation only, not encryption.
if grep -Fq "$DUMMY_KEY" "$OUTPUT" "$SOURCE" "$PODSPEC"; then
  echo 'ERROR: dummy AppKey leaked as plaintext from provisioning' >&2
  exit 10
fi
if grep -Fq "$DUMMY_SECRET" "$OUTPUT" "$SOURCE" "$PODSPEC"; then
  echo 'ERROR: dummy AppSecret leaked as plaintext from provisioning' >&2
  exit 11
fi

# The generator must not modify tracked repository state during a dummy run.
test -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)"

# macOS field builds expect restrictive private file modes. GNU/macOS stat use
# different flags, so accept either implementation while checking the same mode.
file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}
[[ "$(file_mode "$PODSPEC")" == '600' ]]
[[ "$(file_mode "$SOURCE")" == '600' ]]

printf 'Private Tuya identity generator dummy test passed.\n'
