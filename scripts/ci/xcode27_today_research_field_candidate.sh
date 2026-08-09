#!/bin/bash -p
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV

# TODAY-only private-research wrapper for the first stationary passive ES80 artifact.
#
# The normal signed-field producer remains release-grade/fail-closed. This wrapper supplies one
# exact Xcode build-setting overlay that compiles the package-owned private Research capability into
# every target participating in the Release archive, then delegates every signing, exact-source,
# intended-device, recipe, hashing, and retained-evidence responsibility to the canonical producer.
#
# `xcodebuild` does not define arbitrary inherited shell variables as build-setting overrides. Its
# documented all-target environment hook is XCODE_XCCONFIG_FILE, so the TODAY capability must travel
# through that explicit build-settings channel rather than a bare exported OTHER_SWIFT_FLAGS value.
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
OTHER_SWIFT_FLAGS = $(inherited) -DNEMBRA_ES80_TODAY_RESEARCH
XCCONFIG
/bin/chmod 0400 "$TODAY_XCCONFIG"

export XCODE_XCCONFIG_FILE="$TODAY_XCCONFIG"

# The active TODAY directive requires this exact wrapper to produce the private candidate from the
# already accepted Nembra source. Preserve the real signing/Xcode/keychain environment, but do not
# allow caller Git repository/config/object redirection to change which repository, commit, tools,
# or detached worktree the canonical producer treats as SOURCE_SHA authority. Repository-local Git
# semantics remain the canonical producer's responsibility; this boundary closes inherited process
# authority for the only producer entry point authorized by the first private Research procedure.
/usr/bin/env \
  -u GIT_DIR \
  -u GIT_WORK_TREE \
  -u GIT_COMMON_DIR \
  -u GIT_INDEX_FILE \
  -u GIT_OBJECT_DIRECTORY \
  -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
  -u GIT_NAMESPACE \
  -u GIT_SHALLOW_FILE \
  -u GIT_GRAFT_FILE \
  -u GIT_CEILING_DIRECTORIES \
  -u GIT_DISCOVERY_ACROSS_FILESYSTEM \
  -u GIT_CONFIG \
  -u GIT_CONFIG_SYSTEM \
  -u GIT_CONFIG_COUNT \
  -u GIT_CONFIG_PARAMETERS \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_NO_REPLACE_OBJECTS=1 \
  GIT_ATTR_NOSYSTEM=1 \
  "$CANONICAL_PRODUCER" "$@"
