#!/bin/bash -p
set -euo pipefail

if [[ $- != *p* ]]; then
  builtin printf '%s\n' 'ERROR: execute Scripts/provision_capture_tuya_identity.sh directly; do not invoke it through bash/sh because the privileged startup fence is required.' >&2
  exit 5
fi

# A direct operator invocation enters privileged Bash mode from the shebang,
# which suppresses BASH_ENV/imported startup state. Close xtrace and executable
# lookup before even resolving the checkout-owned private destination.
set +x
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
ROOT="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && /bin/pwd -P)"
LOCAL_SECRETS="$ROOT/LocalSecrets"
# NEMBRA_TUYA_RUNTIME_DIR is deliberately not honored: private field identity
# output is fixed to the checkout-owned ignored LocalSecrets tree.
DEST="$LOCAL_SECRETS/TuyaRuntime"
SOURCE_DIR="$DEST/Sources/NembraTuyaPrivateConfig"
PODSPEC="$DEST/NembraTuyaPrivateConfig.podspec"
IDENTITY_SWIFT="$SOURCE_DIR/NembraTuyaPrivateIdentity.swift"
PRIVATE_REVIEW_KEY="$DEST/PrivateReviewAuthority.key"

umask 077

# Credential output is intentionally pinned under the ignored checkout-owned
# LocalSecrets tree. Refuse symlinked/non-directory components instead of
# following caller-controlled filesystem redirections.
for directory in "$LOCAL_SECRETS" "$DEST" "$DEST/Sources" "$SOURCE_DIR"; do
  if [[ -L "$directory" ]]; then
    echo "ERROR: refusing symlinked private Tuya destination: $directory" >&2
    exit 4
  fi
  if [[ -e "$directory" && ! -d "$directory" ]]; then
    echo "ERROR: private Tuya destination component is not a directory: $directory" >&2
    exit 4
  fi
  /bin/mkdir -p "$directory"
  /bin/chmod 700 "$directory"
done

for output in "$PODSPEC" "$IDENTITY_SWIFT" "$PRIVATE_REVIEW_KEY"; do
  if [[ -L "$output" ]]; then
    echo "ERROR: refusing symlinked private Tuya identity output: $output" >&2
    exit 4
  fi
  if [[ -e "$output" && ! -f "$output" ]]; then
    echo "ERROR: private Tuya identity output is not a regular file: $output" >&2
    exit 4
  fi
done

builtin read -r -s -p "Tuya SmartLife SDK AppKey (input hidden): " APP_KEY
builtin printf '\n'
builtin read -r -s -p "Tuya SmartLife SDK AppSecret (input hidden): " APP_SECRET
builtin printf '\n'

[[ -n "$APP_KEY" ]] || { echo "ERROR: AppKey is empty." >&2; exit 2; }
[[ -n "$APP_SECRET" ]] || { echo "ERROR: AppSecret is empty." >&2; exit 3; }

APP_KEY_B64="$(builtin printf '%s' "$APP_KEY" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')"
APP_SECRET_B64="$(builtin printf '%s' "$APP_SECRET" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')"
unset APP_KEY APP_SECRET

PODSPEC_TMP=""
IDENTITY_TMP=""
PRIVATE_REVIEW_KEY_TMP=""
cleanup_private_identity_temps() {
  [[ -z "$PODSPEC_TMP" ]] || /bin/rm -f -- "$PODSPEC_TMP"
  [[ -z "$IDENTITY_TMP" ]] || /bin/rm -f -- "$IDENTITY_TMP"
  [[ -z "$PRIVATE_REVIEW_KEY_TMP" ]] || /bin/rm -f -- "$PRIVATE_REVIEW_KEY_TMP"
}
trap cleanup_private_identity_temps EXIT HUP INT TERM

validate_private_temp() {
  local candidate="$1"
  local expected_prefix="$2"
  local expected_parent="$3"
  local actual_parent
  actual_parent="$(cd "$(/usr/bin/dirname "$candidate")" && /bin/pwd -P)"
  if [[ "$candidate" != "$expected_prefix"* || "$candidate" == "$expected_prefix" || -L "$candidate" || ! -f "$candidate" || "$actual_parent" != "$expected_parent" ]]; then
    echo "ERROR: refusing unexpected private Tuya temporary output: $candidate" >&2
    exit 4
  fi
}

PODSPEC_TMP_PREFIX="$DEST/.NembraTuyaPrivateConfig.podspec."
IDENTITY_TMP_PREFIX="$SOURCE_DIR/.NembraTuyaPrivateIdentity.swift."
PRIVATE_REVIEW_KEY_TMP_PREFIX="$DEST/.PrivateReviewAuthority.key."
PODSPEC_TMP="$(/usr/bin/mktemp "${PODSPEC_TMP_PREFIX}XXXXXX")"
validate_private_temp "$PODSPEC_TMP" "$PODSPEC_TMP_PREFIX" "$DEST"
IDENTITY_TMP="$(/usr/bin/mktemp "${IDENTITY_TMP_PREFIX}XXXXXX")"
validate_private_temp "$IDENTITY_TMP" "$IDENTITY_TMP_PREFIX" "$SOURCE_DIR"
PRIVATE_REVIEW_KEY_TMP="$(/usr/bin/mktemp "${PRIVATE_REVIEW_KEY_TMP_PREFIX}XXXXXX")"
validate_private_temp "$PRIVATE_REVIEW_KEY_TMP" "$PRIVATE_REVIEW_KEY_TMP_PREFIX" "$DEST"

/bin/cat > "$PODSPEC_TMP" <<'RUBY'
Pod::Spec.new do |s|
  s.name = 'NembraTuyaPrivateConfig'
  s.version = '1.0.0'
  s.summary = 'Local-only Nembra Capture Tuya app identity.'
  s.description = 'Generated private field-build configuration. Never commit this pod.'
  s.homepage = 'https://localhost.invalid/nembra-private-config'
  s.license = { :type => 'Private' }
  s.author = { 'Nembra' => 'local-only' }
  s.source = { :git => 'https://localhost.invalid/nembra-private-config.git', :tag => s.version.to_s }
  s.platform = :ios, '17.0'
  s.swift_version = '6.0'
  s.source_files = 'Sources/NembraTuyaPrivateConfig/**/*.swift'
end
RUBY

/bin/cat > "$IDENTITY_TMP" <<SWIFT
import Foundation

public enum NembraTuyaPrivateIdentity {
    private static let encodedAppKey = "$APP_KEY_B64"
    private static let encodedAppSecret = "$APP_SECRET_B64"

    public static var appKey: String { decode(encodedAppKey) }
    public static var appSecret: String { decode(encodedAppSecret) }

    private static func decode(_ value: String) -> String {
        guard let data = Data(base64Encoded: value),
              let decoded = String(data: data, encoding: .utf8) else {
            preconditionFailure("Invalid local Tuya identity encoding")
        }
        return decoded
    }
}
SWIFT
unset APP_KEY_B64 APP_SECRET_B64

# Generate a fresh 256-bit review-commitment key without placing its bytes in
# shell variables, argv, stdout, or Git. A public HMAC can later bind this exact
# private generation without publishing a raw digest of credential-bearing
# source. Re-provisioning intentionally rotates the key together with identity.
/usr/bin/python3 -I - "$PRIVATE_REVIEW_KEY_TMP" <<'PY'
import os
import secrets
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])
flags = os.O_WRONLY | os.O_TRUNC | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
fd = os.open(path, flags)
try:
    before = os.fstat(fd)
    if not stat.S_ISREG(before.st_mode):
        raise RuntimeError("private review key temporary is not regular")
    payload = secrets.token_bytes(32)
    view = memoryview(payload)
    while view:
        written = os.write(fd, view)
        if written <= 0:
            raise RuntimeError("private review key write made no progress")
        view = view[written:]
    os.fsync(fd)
    after = os.fstat(fd)
    if after.st_size != 32 or after.st_ino != before.st_ino or after.st_dev != before.st_dev:
        raise RuntimeError("private review key temporary changed while written")
finally:
    os.close(fd)
PY

/bin/chmod 600 "$PODSPEC_TMP" "$IDENTITY_TMP" "$PRIVATE_REVIEW_KEY_TMP"

# Recheck directory custody immediately before publication. `mv` replaces a
# final-path symlink rather than following it, while the parent checks keep the
# publication rooted in the checkout-owned private tree.
for directory in "$LOCAL_SECRETS" "$DEST" "$DEST/Sources" "$SOURCE_DIR"; do
  [[ ! -L "$directory" && -d "$directory" ]] || {
    echo "ERROR: private Tuya destination changed during provisioning: $directory" >&2
    exit 4
  }
done
/bin/mv -f "$PODSPEC_TMP" "$PODSPEC"
PODSPEC_TMP=""
/bin/mv -f "$IDENTITY_TMP" "$IDENTITY_SWIFT"
IDENTITY_TMP=""
/bin/mv -f "$PRIVATE_REVIEW_KEY_TMP" "$PRIVATE_REVIEW_KEY"
PRIVATE_REVIEW_KEY_TMP=""
trap - EXIT HUP INT TERM
/bin/chmod 600 "$PODSPEC" "$IDENTITY_SWIFT" "$PRIVATE_REVIEW_KEY"

/bin/cat <<EOF

Private Tuya app identity and review-authority key provisioned locally at:
  $DEST

No plaintext credential or private review key was written to Git, shell history,
host process argv, or stdout. The generated source is compiled only by the
SDK-integrated Capture workspace.
Next: run Scripts/bootstrap_capture_tuya_sdk.sh --resolve-lock-for-review.
EOF
