#!/bin/bash -p
set -euo pipefail

# TODAY-only private-research wrapper for the first stationary passive ES80 artifact.
#
# The normal signed-field producer remains release-grade/fail-closed. This wrapper adds one
# compile-time capability that cannot be created by editing Info.plist after compilation, delegates
# every signing/source/device/recipe/hash responsibility to the canonical producer, and then proves
# from the retained archive log that the actual NembraBluetoothCapture Release target consumed that
# condition before the candidate becomes publicly visible at its final path.
#
# This script does not authorize the physical run. Its output still requires terminal exact-head
# Xcode acceptance, independent signed-IPA inspection, intended-device installation, runtime
# rendezvous, and an exact recipe/runbook GO record before Experiment One may begin.

PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
CANONICAL_PRODUCER="$SCRIPT_DIR/xcode27_signed_field_candidate.sh"
PYTHON3="/usr/bin/python3"

if [[ ! -x "$CANONICAL_PRODUCER" ]]; then
  echo "Canonical signed-field producer is missing or not executable: $CANONICAL_PRODUCER" >&2
  exit 2
fi
if [[ ! -x "$PYTHON3" ]]; then
  echo "TODAY research compile-capability proof requires system Python 3 at $PYTHON3." >&2
  exit 2
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "TODAY research field-candidate production requires macOS." >&2
  exit 2
fi

# Do not combine caller-supplied Swift authority with the narrow TODAY capability. The delegated
# producer receives exactly the inherited project flags plus this one compile condition. Ordinary
# direct invocation of the canonical signed producer remains mechanically non-research.
unset SWIFT_ACTIVE_COMPILATION_CONDITIONS
export OTHER_SWIFT_FLAGS='$(inherited) -DNEMBRA_ES80_TODAY_RESEARCH'

WRAPPER_INSTANCE_ID="$("$PYTHON3" -I -c 'import uuid; print(str(uuid.uuid4()))')"
if [[ ! "$WRAPPER_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Could not create canonical TODAY wrapper instance ID." >&2
  exit 3
fi

RAW_FINAL_ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/artifacts/Xcode27TodayResearchFieldCandidate-$WRAPPER_INSTANCE_ID}"
if [[ "$RAW_FINAL_ARTIFACTS_DIR" != /* ]]; then
  RAW_FINAL_ARTIFACTS_DIR="$ROOT/$RAW_FINAL_ARTIFACTS_DIR"
fi
FINAL_ARTIFACTS_DIR="$("$PYTHON3" -I - "$RAW_FINAL_ARTIFACTS_DIR" <<'PY'
import sys
from pathlib import Path
print(Path(sys.argv[1]).resolve(strict=False))
PY
)"
FINAL_PARENT="$(dirname "$FINAL_ARTIFACTS_DIR")"
QUARANTINED_CANDIDATE="$FINAL_PARENT/.nembra-today-research-$WRAPPER_INSTANCE_ID.staging"
PRODUCER_OUTPUT="${TMPDIR:-/tmp}/nembra-today-research-$WRAPPER_INSTANCE_ID.log"
QUARANTINE_OWNED=0

if [[ -z "$FINAL_ARTIFACTS_DIR" || "$FINAL_ARTIFACTS_DIR" == "/" || "$FINAL_ARTIFACTS_DIR" == "$ROOT" ]]; then
  echo "ARTIFACTS_DIR is not a safe TODAY research output path: $FINAL_ARTIFACTS_DIR" >&2
  exit 4
fi
if [[ -e "$FINAL_ARTIFACTS_DIR" || -L "$FINAL_ARTIFACTS_DIR" ]]; then
  echo "Final TODAY research candidate path already exists; refusing overwrite: $FINAL_ARTIFACTS_DIR" >&2
  exit 5
fi
if [[ -e "$QUARANTINED_CANDIDATE" || -L "$QUARANTINED_CANDIDATE" ]]; then
  echo "TODAY research quarantine path already exists; refusing reuse: $QUARANTINED_CANDIDATE" >&2
  exit 6
fi

cleanup() {
  if [[ "${QUARANTINE_OWNED:-0}" == "1" && -n "${QUARANTINED_CANDIDATE:-}" ]]; then
    rm -rf "$QUARANTINED_CANDIDATE"
  fi
  rm -f "${PRODUCER_OUTPUT:-}"
}
trap cleanup EXIT

# The canonical producer atomically publishes a complete signed/evidence-bound candidate only into
# this private quarantine path. The final user-facing path remains absent until compile proof passes.
export ARTIFACTS_DIR="$QUARANTINED_CANDIDATE"
if ! "$CANONICAL_PRODUCER" "$@" >"$PRODUCER_OUTPUT" 2>&1; then
  cat "$PRODUCER_OUTPUT" >&2
  echo "Canonical signed-field candidate production failed; TODAY candidate was not published." >&2
  exit 7
fi
QUARANTINE_OWNED=1

ARCHIVE_LOG="$QUARANTINED_CANDIDATE/logs/xcodebuild-archive.log"
if [[ ! -f "$ARCHIVE_LOG" || -L "$ARCHIVE_LOG" ]]; then
  echo "TODAY candidate lacks one retained archive log for compile-capability proof." >&2
  exit 8
fi

# Mechanical compile proof: require one emitted Swift compiler/driver command whose own module name
# is exactly NembraBluetoothCapture and whose same command carries the dedicated TODAY condition.
# Merely mentioning NembraBluetoothCapture as an import/search path is not target identity and must
# never satisfy this proof.
if ! ARCHIVE_LOG_SHA256="$("$PYTHON3" -I - "$ARCHIVE_LOG" <<'PY'
import hashlib
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
raw = path.read_bytes()
if len(raw) > 128 * 1024 * 1024:
    raise SystemExit("archive log exceeds bounded compile-proof size")
text = raw.decode("utf-8", errors="replace")
condition = "NEMBRA_ES80_TODAY_RESEARCH"
module = "NembraBluetoothCapture"

# Bind both facts to one emitted Swift command: the compiler is compiling this exact module, and
# that exact invocation carries the research condition. Support the canonical spaced module-name
# form plus an equals spelling defensively; accept both '-D NAME' and '-DNAME'.
module_pattern = re.compile(
    r"(?:^|\s)-module-name(?:\s+|=)" + re.escape(module) + r"(?:\s|$)"
)
condition_pattern = re.compile(r"(?:^|\s)-D\s*" + re.escape(condition) + r"(?:\s|$)")
matched = False
for line in text.splitlines():
    if module not in line or condition not in line:
        continue
    if "swift" not in line.lower():
        continue
    if module_pattern.search(line) and condition_pattern.search(line):
        matched = True
        break

if not matched:
    raise SystemExit(
        "retained archive log does not prove NembraBluetoothCapture compiled with " + condition
    )
print(hashlib.sha256(raw).hexdigest())
PY
)"; then
  echo "Signed TODAY archive did not prove the dedicated NembraBluetoothCapture compile capability." >&2
  echo "Candidate remains NO-GO and the quarantined bytes will be removed." >&2
  exit 9
fi
if [[ ! "$ARCHIVE_LOG_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "TODAY compile-capability proof did not yield one canonical archive-log SHA-256." >&2
  exit 9
fi

PROOF_FILE="$QUARANTINED_CANDIDATE/today-research-compile-capability.txt"
{
  echo "today_research_compile_capability=verified"
  echo "package_target=NembraBluetoothCapture"
  echo "compiler_module_name=NembraBluetoothCapture"
  echo "compile_condition=NEMBRA_ES80_TODAY_RESEARCH"
  echo "proof_source=logs/xcodebuild-archive.log"
  echo "proof_source_sha256=$ARCHIVE_LOG_SHA256"
  echo "authority=compile-capability-evidence-not-physical-authorization"
} > "$PROOF_FILE"
chmod 0400 "$PROOF_FILE"

# Durably flush the additive proof before publication. Existing canonical signed evidence remains
# byte-for-byte untouched; this wrapper-level receipt describes only compile-condition consumption.
"$PYTHON3" -I - "$PROOF_FILE" "$QUARANTINED_CANDIDATE" <<'PY'
import os
import sys
proof, directory = sys.argv[1:3]
fd = os.open(proof, os.O_RDONLY)
try:
    os.fsync(fd)
finally:
    os.close(fd)
dfd = os.open(directory, os.O_RDONLY)
try:
    os.fsync(dfd)
finally:
    os.close(dfd)
PY

# Publish the now-proven complete directory atomically and without replacement on macOS. The final
# path never names a candidate that has not passed the package-target compile-capability proof.
"$PYTHON3" -I - "$QUARANTINED_CANDIDATE" "$FINAL_ARTIFACTS_DIR" <<'PY'
import ctypes
import errno
import os
import sys
source, destination = map(os.fsencode, sys.argv[1:3])
libc = ctypes.CDLL(None, use_errno=True)
rename_exclusive = libc.renamex_np
rename_exclusive.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
rename_exclusive.restype = ctypes.c_int
if rename_exclusive(source, destination, 0x00000004) != 0:  # RENAME_EXCL
    number = ctypes.get_errno()
    if number in (errno.EEXIST, errno.ENOTEMPTY):
        raise SystemExit("refusing to overwrite concurrently published TODAY research candidate")
    raise OSError(number, os.strerror(number), os.fsdecode(destination))
PY
QUARANTINE_OWNED=0

# Reopen the final proof receipt before reporting success. This is software/build evidence only.
if [[ "$(/usr/bin/grep -c '^today_research_compile_capability=verified$' "$FINAL_ARTIFACTS_DIR/today-research-compile-capability.txt")" != "1" ]]; then
  echo "Final TODAY research candidate lost compile-capability proof after publication." >&2
  exit 10
fi

echo "Signed TODAY research Nembra iOS field-build CANDIDATE retained at: $FINAL_ARTIFACTS_DIR"
echo "NembraBluetoothCapture dedicated research compile capability: VERIFIED from retained archive log."
echo "Independent signed-IPA acceptance has NOT occurred."
echo "PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN."
