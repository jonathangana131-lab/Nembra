#!/bin/bash -p
set -euo pipefail

if [[ $- != *p* ]]; then
  builtin printf '%s\n' 'ERROR: execute Scripts/provision_capture_tuya_identity.sh directly; do not invoke it through bash/sh because the privileged startup fence is required.' >&2
  exit 5
fi

# A direct operator invocation enters privileged Bash mode from the shebang,
# which suppresses BASH_ENV/imported startup state. Close xtrace and executable
# lookup before resolving or admitting the checkout-owned private destination.
set +x
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
ROOT="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && /bin/pwd -P)"
LOCAL_SECRETS="$ROOT/LocalSecrets"
# NEMBRA_TUYA_RUNTIME_DIR is deliberately not honored: private field identity
# output is fixed to the checkout-owned ignored LocalSecrets tree.
DEST="$LOCAL_SECRETS/TuyaRuntime"
WRITER="$ROOT/Scripts/provision_capture_tuya_identity_writer.py"
WRITER_SHA256="6a27f9f0640a00dfe5f74a1cc4a65a0faf76994fe584efe23afb8f7ee1638fc2"
AUTHORITY_HELPER="$ROOT/Scripts/capture_tuya_private_identity_authority.py"
AUTHORITY_HELPER_SHA256="40f5aee5c5e39c0a6146ba2ca7bc6bad7cf6abd6576fff8835d02f714589ae71"
ROOT_FD=9

umask 077

# Admit the exact checkout directory before any credential input. FD 9 remains
# inherited by the Python publication helper; the pathname is used only for a
# later identity-drift comparison and for non-authoritative operator output.
if ! exec 9<"$ROOT"; then
  builtin printf '%s\n' 'ERROR: could not admit the checkout root before private credential input.' >&2
  exit 4
fi
close_root_fd() {
  exec 9<&- 2>/dev/null || true
}
trap close_root_fd EXIT

[[ -f "$WRITER" && ! -L "$WRITER" ]] || {
  builtin printf '%s\n' 'ERROR: descriptor-bound private Tuya identity writer is missing or symlinked.' >&2
  exit 4
}
[[ -x /usr/bin/python3 && -x /usr/bin/shasum && -x /usr/bin/awk ]] || {
  builtin printf '%s\n' 'ERROR: system Python 3 and SHA-256 tooling are required for private identity publication.' >&2
  exit 4
}
[[ -f "$AUTHORITY_HELPER" && ! -L "$AUTHORITY_HELPER" ]] || {
  builtin printf '%s\n' 'ERROR: private identity authority helper is missing or symlinked.' >&2
  exit 4
}
[[ -x /usr/bin/sudo ]] || {
  builtin printf '%s\n' 'ERROR: system sudo is required to seal private identity transaction authority.' >&2
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

# Capture and digest-pin the non-secret authority helper before privilege or
# credential input. Root executes only these captured accepted bytes, never a
# mutable checkout pathname.
AUTHORITY_CAPTURE="$({ /bin/cat -- "$AUTHORITY_HELPER"; builtin printf '\001'; })"
[[ "$AUTHORITY_CAPTURE" == *$'\001' ]] || {
  unset WRITER_SOURCE AUTHORITY_CAPTURE
  builtin printf '%s\n' 'ERROR: could not capture private identity authority helper bytes.' >&2
  exit 4
}
AUTHORITY_SOURCE="${AUTHORITY_CAPTURE%$'\001'}"
unset AUTHORITY_CAPTURE
CAPTURED_AUTHORITY_SHA256="$(builtin printf '%s' "$AUTHORITY_SOURCE" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
[[ "$CAPTURED_AUTHORITY_SHA256" == "$AUTHORITY_HELPER_SHA256" ]] || {
  unset WRITER_SOURCE AUTHORITY_SOURCE CAPTURED_AUTHORITY_SHA256
  builtin printf '%s\n' 'ERROR: private identity authority helper bytes do not match the accepted digest.' >&2
  exit 4
}
unset CAPTURED_AUTHORITY_SHA256

# A new attempt must revoke any older successful transaction before secrets are
# requested. If this attempt later fails, bootstrap remains mechanically blocked
# rather than silently falling back to stale authority.
if ! /usr/bin/sudo /usr/bin/python3 -I -c "$AUTHORITY_SOURCE" invalidate "$ROOT"; then
  unset WRITER_SOURCE AUTHORITY_SOURCE
  builtin printf '%s\n' 'ERROR: prior private identity transaction authority could not be revoked.' >&2
  exit 4
fi

builtin read -r -s -p "Tuya SmartLife SDK AppKey (input hidden): " APP_KEY
builtin printf '\n'
builtin read -r -s -p "Tuya SmartLife SDK AppSecret (input hidden): " APP_SECRET
builtin printf '\n'

[[ -n "$APP_KEY" ]] || { unset WRITER_SOURCE; echo "ERROR: AppKey is empty." >&2; exit 2; }
[[ -n "$APP_SECRET" ]] || { unset WRITER_SOURCE; echo "ERROR: AppSecret is empty." >&2; exit 3; }

APP_KEY_B64="$(builtin printf '%s' "$APP_KEY" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')"
APP_SECRET_B64="$(builtin printf '%s' "$APP_SECRET" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')"
unset APP_KEY APP_SECRET

if ! WRITER_RECEIPT="$(builtin printf '%s\0%s' "$APP_KEY_B64" "$APP_SECRET_B64" | /usr/bin/python3 -I -c "$WRITER_SOURCE" "$ROOT_FD" "$ROOT")"; then
  unset APP_KEY_B64 APP_SECRET_B64 WRITER_SOURCE AUTHORITY_SOURCE
  builtin printf '%s\n' 'ERROR: private Tuya identity publication failed closed; transaction authority remains revoked.' >&2
  exit 4
fi
unset APP_KEY_B64 APP_SECRET_B64 WRITER_SOURCE
[[ "$WRITER_RECEIPT" != *$'\n'* ]] || {
  unset WRITER_RECEIPT AUTHORITY_SOURCE
  builtin printf '%s\n' 'ERROR: private identity writer returned a malformed transaction receipt.' >&2
  exit 4
}
IFS=$'\t' builtin read -r RECEIPT_SCHEMA PODSPEC_SHA256 IDENTITY_SHA256 RECEIPT_EXTRA <<< "$WRITER_RECEIPT"
unset WRITER_RECEIPT
[[ "$RECEIPT_SCHEMA" == "NEMBRA_PRIVATE_IDENTITY_RECEIPT_V1" &&
   "$PODSPEC_SHA256" =~ ^[0-9a-f]{64}$ &&
   "$IDENTITY_SHA256" =~ ^[0-9a-f]{64}$ &&
   -z "${RECEIPT_EXTRA:-}" ]] || {
  unset RECEIPT_SCHEMA PODSPEC_SHA256 IDENTITY_SHA256 RECEIPT_EXTRA AUTHORITY_SOURCE
  builtin printf '%s\n' 'ERROR: private identity writer returned an invalid transaction fingerprint.' >&2
  exit 4
}
unset RECEIPT_SCHEMA RECEIPT_EXTRA

# Seal only non-secret hashes of the exact successful held output inodes into a
# root-owned receipt outside the user-writable checkout. The privileged helper
# independently re-opens and fingerprints current outputs before sealing.
if ! /usr/bin/sudo /usr/bin/python3 -I -c "$AUTHORITY_SOURCE" seal "$ROOT" "$WRITER_SHA256" "$PODSPEC_SHA256" "$IDENTITY_SHA256" >/dev/null; then
  unset PODSPEC_SHA256 IDENTITY_SHA256 AUTHORITY_SOURCE
  builtin printf '%s\n' 'ERROR: private identity transaction could not be sealed; bootstrap remains blocked.' >&2
  exit 4
fi
unset PODSPEC_SHA256 IDENTITY_SHA256
if ! /usr/bin/python3 -I -c "$AUTHORITY_SOURCE" verify "$ROOT" "$WRITER_SHA256" >/dev/null; then
  unset AUTHORITY_SOURCE
  builtin printf '%s\n' 'ERROR: freshly sealed private identity transaction failed local verification.' >&2
  exit 4
fi
unset AUTHORITY_SOURCE

close_root_fd
trap - EXIT

/bin/cat <<EOF

Private Tuya app identity provisioned locally at:
  $DEST

No plaintext credential was written to Git, shell history, host process argv, or stdout.
The generated source is compiled only by the SDK-integrated Capture workspace.
The writer source and checkout directory are pinned before credential input; filesystem publication is descriptor-bound and no-follow under that admitted checkout.
Next: run Scripts/bootstrap_capture_tuya_sdk.sh.
EOF
