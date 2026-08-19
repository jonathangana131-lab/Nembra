#!/bin/bash -p
set -euo pipefail

if [[ "${1:-}" == "--nembra-today-research-build" ]]; then
  printf '%s\n' \
    'SUPERSEDED: --nembra-today-research-build cannot authorize the current Capture procedure.' \
    'Use scripts/field/install_one_time_capture.command for ES80-AUTHENTICATED-STATIONARY-v1.' >&2
  exit 64
fi

# Compatibility entry point only. It cannot mint a private research compile
# capability and delegates the ordinary authenticated stationary path.
TODAY_RESEARCH_BUILD_MODE=0
RESEARCH_COMPILE_MODE="standard"
RESEARCH_COMPILE_AUTHORITY="none"
RESEARCH_COMPILE_CONDITION="none"
unset XCODE_XCCONFIG_FILE OTHER_SWIFT_FLAGS SWIFT_ACTIVE_COMPILATION_CONDITIONS
export TODAY_RESEARCH_BUILD_MODE RESEARCH_COMPILE_MODE RESEARCH_COMPILE_AUTHORITY RESEARCH_COMPILE_CONDITION

ROOT="$(cd "$(/usr/bin/dirname "$0")/../.." && /bin/pwd -P)"
exec "$ROOT/scripts/field/install_one_time_capture.command" "$@"
