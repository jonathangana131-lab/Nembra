#!/bin/bash -p
set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CANONICAL_PRODUCER="$SCRIPT_DIR/xcode27_signed_field_candidate.sh"
CAPTURE_INFO_PLIST="NembraApp/Config/NembraCaptureBuildInfo.plist"

if [[ ! -x "$CANONICAL_PRODUCER" ]]; then
  echo "Canonical signed-field producer is missing or not executable: $CANONICAL_PRODUCER" >&2
  exit 2
fi

# Do not combine caller-supplied Swift authority with the narrow TODAY capability. The delegated
# producer receives exactly the inherited project flags plus this one compile condition.
unset SWIFT_ACTIVE_COMPILATION_CONDITIONS
export OTHER_SWIFT_FLAGS='$(inherited) -DNEMBRA_ES80_TODAY_RESEARCH'

# Xcode does not synthesize arbitrary custom Info.plist keys from caller/user-defined
# INFOPLIST_KEY_* build settings. The canonical producer already owns the exact build identifier,
# build-instance, source SHA, and field-recipe values as command-line build settings; route those
# values through one tracked plist input from the detached exact-SOURCE_SHA worktree so Xcode's
# normal plist processing expands them into the signed app before hashing/signing. A caller cannot
# substitute another plist path through this TODAY wrapper.
unset INFOPLIST_FILE INFOPLIST_EXPAND_BUILD_SETTINGS
export INFOPLIST_FILE="$CAPTURE_INFO_PLIST"
export INFOPLIST_EXPAND_BUILD_SETTINGS=YES

exec "$CANONICAL_PRODUCER" "$@"
