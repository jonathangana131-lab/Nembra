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
  # FD 6 is wrapper-owned. It may already be closed if setup failed before admission.
  exec 6<&- 2>/dev/null || true
  /bin/rm -rf "$TODAY_SETTINGS_ROOT"
}
trap cleanup EXIT

umask 077
cat > "$TODAY_XCCONFIG" <<'XCCONFIG'
OTHER_SWIFT_FLAGS = $(inherited) -DNEMBRA_ES80_TODAY_RESEARCH
XCCONFIG
/bin/chmod 0400 "$TODAY_XCCONFIG"

# Open first, then immediately retire every mutable pathname. A same-UID process can replace a
# mode-0400 pathname before this open, so the open descriptor is not trusted merely because it is
# readable. The descriptor itself is re-proven below against the one canonical overlay byte string
# before any signed-field producer or xcodebuild process is admitted.
exec 6< "$TODAY_XCCONFIG"
/bin/rm -f "$TODAY_XCCONFIG"
/bin/rmdir "$TODAY_SETTINGS_ROOT"

if ! /usr/bin/python3 -I - 6 <<'PYVERIFY'
import os
import stat
import sys

fd = int(sys.argv[1])
expected = b"OTHER_SWIFT_FLAGS = $(inherited) -DNEMBRA_ES80_TODAY_RESEARCH\n"


def stable_identity(metadata):
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


metadata = os.fstat(fd)
if not stat.S_ISREG(metadata.st_mode):
    raise SystemExit("TODAY Research Xcode settings descriptor is not a regular file")
if stat.S_IMODE(metadata.st_mode) != 0o400:
    raise SystemExit("TODAY Research Xcode settings descriptor is not mode 0400")
if metadata.st_size != len(expected):
    raise SystemExit("TODAY Research Xcode settings descriptor size is not canonical")

before = os.lseek(fd, 0, os.SEEK_CUR)
if before != 0:
    raise SystemExit("TODAY Research Xcode settings descriptor was not positioned at byte zero")
actual = os.pread(fd, len(expected) + 1, 0)
if actual != expected:
    raise SystemExit("TODAY Research Xcode settings descriptor bytes are not canonical")

final_metadata = os.fstat(fd)
if stable_identity(final_metadata) != stable_identity(metadata):
    raise SystemExit("TODAY Research Xcode settings descriptor changed during verification")
if os.lseek(fd, 0, os.SEEK_CUR) != before:
    raise SystemExit("TODAY Research Xcode settings verification changed the descriptor offset")
PYVERIFY
then
  echo "TODAY Research Xcode settings descriptor failed exact opened-subject verification." >&2
  exit 3
fi

export XCODE_XCCONFIG_FILE="/dev/fd/6"
if [[ ! -r "$XCODE_XCCONFIG_FILE" ]]; then
  echo "TODAY Research Xcode settings descriptor is unavailable before signed production." >&2
  exit 3
fi

"$CANONICAL_PRODUCER" "$@"