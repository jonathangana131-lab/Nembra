#!/bin/bash -p
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV

# TODAY-only private-research wrapper for the first stationary passive ES80 artifact.
#
# The normal signed-field producer remains release-grade/fail-closed. This wrapper supplies one
# exact Xcode build-setting overlay that compiles the app's private Research entrypoint call into the
# Release app target, then delegates every signing, exact-source, intended-device, recipe, hashing,
# and retained-evidence responsibility to the canonical producer.
#
# The ResearchAdmission itself remains package-owned. The app-side condition exists because Xcode
# target build settings are authoritative for the app target but are not a reliable way to configure
# Swift Package dependency compilation. An ordinary exact-source Release therefore compiles no call
# to the package's private-research SPI even if bundle metadata is later edited.
#
# `xcodebuild` does not define arbitrary inherited shell variables as build-setting overrides. Its
# documented all-target environment hook is XCODE_XCCONFIG_FILE, so the TODAY app entrypoint must
# travel through that explicit build-settings channel rather than a bare exported compiler variable.
#
# This script does not authorize the physical run. Its output still requires terminal exact-head
# Xcode acceptance, independent signed-IPA inspection, intended-device installation, the package-owned
# runtime ResearchAdmission rendezvous, and an exact recipe/runbook GO record before Experiment One.

# Close executable discovery before resolving this wrapper's own directory. Otherwise caller PATH
# could substitute `dirname` and redirect CANONICAL_PRODUCER before the canonical producer gets a
# chance to establish its stronger root-custodied process boundary.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CANONICAL_PRODUCER="$SCRIPT_DIR/xcode27_signed_field_candidate.sh"

if [[ ! -x "$CANONICAL_PRODUCER" ]]; then
  echo "Canonical signed-field producer is missing or not executable: $CANONICAL_PRODUCER" >&2
  exit 2
fi

# Retire ambiguous caller-controlled spellings of the same compiler authority. The canonical
# producer receives exactly one TODAY overlay through Xcode's documented all-target settings file.
unset SWIFT_ACTIVE_COMPILATION_CONDITIONS OTHER_SWIFT_FLAGS XCODE_XCCONFIG_FILE

TODAY_SETTINGS_ROOT="$(/usr/bin/mktemp -d "${RUNNER_TEMP:-/tmp}/NembraES80TodayResearch.XXXXXX")"
TODAY_XCCONFIG="$TODAY_SETTINGS_ROOT/NembraES80TodayResearch.xcconfig"
cleanup() {
  /bin/rm -rf "$TODAY_SETTINGS_ROOT"
}
trap cleanup EXIT

umask 077
cat > "$TODAY_XCCONFIG" <<'XCCONFIG'
OTHER_SWIFT_FLAGS = $(inherited) -DNEMBRA_ES80_TODAY_RESEARCH_APP
XCCONFIG
/bin/chmod 0400 "$TODAY_XCCONFIG"

export XCODE_XCCONFIG_FILE="$TODAY_XCCONFIG"

"$CANONICAL_PRODUCER" "$@"
