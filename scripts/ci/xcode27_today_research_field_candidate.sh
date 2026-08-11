#!/bin/bash -p
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV

echo "SUPERSEDED: the private TODAY ES80-FINGERPRINT-v1 Research candidate path is retired." >&2
echo "Current Capture field procedure is ES80-AUTHENTICATED-STATIONARY-v1." >&2
echo "Use scripts/field/install_one_time_capture.command only from the final exact software-accepted Capture source and only after its current field gates are satisfied." >&2
echo "PHYSICAL NO-GO: this legacy wrapper cannot authorize scanning or an ES80 experiment." >&2
exit 64
