#!/bin/bash -p
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV

# TODAY-only private-research wrapper for the first stationary passive ES80 artifact.
#
# The normal signed-field producer remains release-grade/fail-closed. This wrapper adds one
# compile-time capability that cannot be created by editing Info.plist after compilation, then
# delegates every signing, exact-source, intended-device, recipe, hashing, and retained-evidence
# responsibility to the canonical producer.
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

# Do not combine caller-supplied Swift authority with the narrow TODAY capability. The delegated
# producer receives exactly the inherited project flags plus this one compile condition.
unset SWIFT_ACTIVE_COMPILATION_CONDITIONS
export OTHER_SWIFT_FLAGS='$(inherited) -DNEMBRA_ES80_TODAY_RESEARCH'

exec "$CANONICAL_PRODUCER" "$@"
