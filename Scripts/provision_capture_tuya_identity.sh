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
WRITER="$ROOT/Scripts/provision_capture_tuya_identity_writer.py"
WRITER_SHA256="3575ccc3aea7a493e4972c780852f3da5434fb323e9fa728c612d14ea605ed71"

umask 077

[[ -f "$WRITER" && ! -L "$WRITER" ]] || {
  builtin printf '%s\n' 'ERROR: descriptor-bound private Tuya identity writer is missing or symlinked.' >&2
  exit 4
}
[[ -x /usr/bin/python3 && -x /usr/bin/shasum && -x /usr/bin/awk ]] || {
  builtin printf '%s\n' 'ERROR: system Python 3 and SHA-256 tooling are required for private identity publication.' >&2
  exit 4
}

# Capture the helper exactly once before credential input. Appending a non-newline
# sentinel prevents command substitution from stripping the helper's trailing
# newline; Python later executes these captured bytes with -c rather than
# reopening the mutable worktree pathname.
WRITER_CAPTURE="$({ /bin/cat -- "$WRITER"; builtin printf '\001'; })"
[[ "$WRITER_CAPTURE" == *$'\001' ]] || {
  builtin printf '%s\n' 'ERROR: could not capture private identity writer bytes.' >&2
  exit 4
}
WRITER_SOURCE="${WRITER_CAPTURE%$'\001'}"
unset WRITER_CAPTURE
CAPTURED_WRITER_SHA256="$(builtin printf '%s' "$WRITER_SOURCE" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
[[ "$CAPTURED_WRITER_SHA256" == "$WRITER_SHA256" ]] || {
  unset WRITER_SOURCE CAPTURED_WRITER_SHA256
  builtin printf '%s\n' 'ERROR: private identity writer bytes do not match the accepted digest.' >&2
  exit 4
}
unset CAPTURED_WRITER_SHA256

# Bind the checkout root itself before asking for credentials. Descendant
# descriptor custody is insufficient if the checkout pathname can be replaced
# while the operator is blocked on hidden input. The writer must later open the
# root and prove that descriptor has this exact device/inode identity before it
# creates LocalSecrets or consumes the credential-derived publication payload.
if ! ROOT_IDENTITY_CAPTURE="$(/usr/bin/python3 -I - "$ROOT" <<'PY'
import os
import stat
import sys

path = sys.argv[1]
metadata = os.stat(path, follow_symlinks=False)
if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.geteuid():
    raise SystemExit(2)
print(f"{metadata.st_dev}\t{metadata.st_ino}")
PY
)"; then
  unset WRITER_SOURCE
  builtin printf '%s\n' 'ERROR: checkout root could not be admitted before private credential input.' >&2
  exit 4
fi
ROOT_DEVICE="${ROOT_IDENTITY_CAPTURE%%$'\t'*}"
ROOT_INODE="${ROOT_IDENTITY_CAPTURE#*$'\t'}"
unset ROOT_IDENTITY_CAPTURE
[[ "$ROOT_DEVICE" =~ ^[0-9]+$ && "$ROOT_INODE" =~ ^[0-9]+$ ]] || {
  unset WRITER_SOURCE ROOT_DEVICE ROOT_INODE
  builtin printf '%s\n' 'ERROR: checkout root identity admission returned malformed metadata.' >&2
  exit 4
}

builtin read -r -s -p "Tuya SmartLife SDK AppKey (input hidden): " APP_KEY
builtin printf '\n'
builtin read -r -s -p "Tuya SmartLife SDK AppSecret (input hidden): " APP_SECRET
builtin printf '\n'

[[ -n "$APP_KEY" ]] || { unset WRITER_SOURCE ROOT_DEVICE ROOT_INODE; echo "ERROR: AppKey is empty." >&2; exit 2; }
[[ -n "$APP_SECRET" ]] || { unset WRITER_SOURCE ROOT_DEVICE ROOT_INODE; echo "ERROR: AppSecret is empty." >&2; exit 3; }

APP_KEY_B64="$(builtin printf '%s' "$APP_KEY" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')"
APP_SECRET_B64="$(builtin printf '%s' "$APP_SECRET" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')"
unset APP_KEY APP_SECRET

if ! builtin printf '%s\0%s' "$APP_KEY_B64" "$APP_SECRET_B64" | /usr/bin/python3 -I -c "$WRITER_SOURCE" "$ROOT" "$ROOT_DEVICE" "$ROOT_INODE"; then
  unset APP_KEY_B64 APP_SECRET_B64 WRITER_SOURCE ROOT_DEVICE ROOT_INODE
  builtin printf '%s\n' 'ERROR: private Tuya identity publication failed closed.' >&2
  exit 4
fi
unset APP_KEY_B64 APP_SECRET_B64 WRITER_SOURCE ROOT_DEVICE ROOT_INODE

/bin/cat <<EOF

Private Tuya app identity provisioned locally at:
  $DEST

No plaintext credential was written to Git, shell history, host process argv, or stdout.
The generated source is compiled only by the SDK-integrated Capture workspace.
The writer source is SHA-256 pinned before credential input; checkout-root identity is bound before input; filesystem publication is descriptor-bound and no-follow under that exact admitted root.
Next: run Scripts/bootstrap_capture_tuya_sdk.sh.
EOF
