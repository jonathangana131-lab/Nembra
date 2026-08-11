#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROVISIONER="$SCRIPT_DIR/provision_capture_tuya_identity.py"
MODE="${1:-}"

if [[ "$#" -gt 1 || ( -n "$MODE" && "$MODE" != "--self-test" ) ]]; then
  printf 'Usage: %s [--self-test]\n' "$0" >&2
  exit 2
fi
[[ -f "$PROVISIONER" ]] || {
  echo 'ERROR: Private Tuya identity provisioner core is missing from this accepted checkout.' >&2
  exit 3
}
[[ -x /usr/bin/python3 ]] || {
  echo 'ERROR: System Python 3 is required for private Tuya identity provisioning.' >&2
  exit 4
}

if [[ "$MODE" == "--self-test" ]]; then
  exec /usr/bin/python3 -B -I "$PROVISIONER" --self-test
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'ERROR: Run private Tuya identity provisioning on the Mac used for the reviewed Capture field workspace.' >&2
  exit 5
fi

# AppKey/AppSecret are read by Python getpass directly from the terminal. They
# are never accepted through this command's argv or environment.
unset NEMBRA_TUYA_APP_KEY NEMBRA_TUYA_APP_SECRET || true
exec /usr/bin/python3 -B -I "$PROVISIONER"
