#!/bin/bash -p
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV

# TODAY-only private-research wrapper for the first stationary passive ES80 artifact.
#
# The canonical producer now owns the private Research compile setting itself. This wrapper makes
# that signing-operator choice explicit with one source-controlled producer mode instead of passing
# caller-visible Xcode settings through the environment.
#
# This script does not authorize the physical run. Its output still requires terminal exact-head
# Xcode acceptance, independent signed-IPA inspection, intended-device installation, and an exact
# recipe/runbook GO record before Experiment One may begin.

# Close executable discovery before resolving this wrapper's own directory. Otherwise caller PATH
# could substitute `dirname` and redirect CANONICAL_PRODUCER before the canonical producer gets a
# chance to establish its stronger root-custodied process boundary.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CANONICAL_PRODUCER="$SCRIPT_DIR/xcode27_signed_field_candidate.sh"

if [[ ! -x "$CANONICAL_PRODUCER" ]]; then
  echo "Canonical signed-field producer is missing or not executable: $CANONICAL_PRODUCER" >&2
  exit 2
fi

# Ambient compiler/Xcode state can never become Research authority. The canonical producer repeats
# this scrub before starting any child process; doing it here prevents even the delegation boundary
# from carrying ambiguous build-setting state.
unset SWIFT_ACTIVE_COMPILATION_CONDITIONS OTHER_SWIFT_FLAGS XCODE_XCCONFIG_FILE

exec "$CANONICAL_PRODUCER" --nembra-today-research-build "$@"
