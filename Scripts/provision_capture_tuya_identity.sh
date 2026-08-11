#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEST="${NEMBRA_TUYA_RUNTIME_DIR:-$ROOT/LocalSecrets/TuyaRuntime}"
WRITER="$ROOT/Scripts/provision_capture_tuya_identity_writer.py"

[[ -x /usr/bin/python3 ]] || { echo "ERROR: System Python 3 is required for private Tuya identity provisioning." >&2; exit 2; }
[[ -f "$WRITER" ]] || { echo "ERROR: descriptor-bound private identity writer is missing from accepted source." >&2; exit 3; }

umask 077
read -r -s -p "Tuya SmartLife SDK AppKey (input hidden): " APP_KEY
printf '\n'
read -r -s -p "Tuya SmartLife SDK AppSecret (input hidden): " APP_SECRET
printf '\n'

[[ -n "$APP_KEY" ]] || { echo "ERROR: AppKey is empty." >&2; exit 4; }
[[ -n "$APP_SECRET" ]] || { echo "ERROR: AppSecret is empty." >&2; exit 5; }

APP_KEY_B64="$(printf '%s' "$APP_KEY" | base64 | tr -d '\r\n')"
APP_SECRET_B64="$(printf '%s' "$APP_SECRET" | base64 | tr -d '\r\n')"
unset APP_KEY APP_SECRET

if ! printf '%s\0%s' "$APP_KEY_B64" "$APP_SECRET_B64" | /usr/bin/python3 -I "$WRITER" "$DEST"; then
    unset APP_KEY_B64 APP_SECRET_B64
    echo "ERROR: private Tuya identity was not provisioned; no existing runtime is overwritten or followed." >&2
    exit 6
fi
unset APP_KEY_B64 APP_SECRET_B64

cat <<EOF

Private Tuya app identity provisioned locally at:
  $DEST

Nothing was written to Git, shell history, host process argv, or stdout.
The generated source is compiled only by the SDK-integrated Capture workspace.
Reprovisioning is fail-closed: remove the old local TuyaRuntime directory deliberately before creating a replacement.
Next: run Scripts/bootstrap_capture_tuya_sdk.sh.
EOF
