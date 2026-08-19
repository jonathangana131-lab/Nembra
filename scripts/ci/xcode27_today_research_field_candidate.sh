#!/bin/bash
set -euo pipefail

printf '%s\n' \
  'SUPERSEDED: the private TODAY ES80-FINGERPRINT-v1 Research candidate path is retired.' \
  'Current Capture field procedure is ES80-AUTHENTICATED-STATIONARY-v1.' \
  'PHYSICAL NO-GO: this legacy wrapper cannot authorize scanning or an ES80 experiment.' \
  'Use scripts/field/install_one_time_capture.command only after its exact private prerequisites are accepted.' >&2
exit 64
