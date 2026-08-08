#!/usr/bin/env python3
from pathlib import Path
import re

producer_path = Path("scripts/ci/xcode27_signed_field_candidate.sh")
source = producer_path.read_text(encoding="utf-8")

source, replacement_count = re.subn(r"(?<![A-Za-z0-9_])python3(?=\s)", '"$PYTHON3" -I', source)
if replacement_count < 8:
    raise SystemExit(f"unexpected producer Python invocation count: {replacement_count}")

anchor = "unset NEMBRA_INTENDED_FIELD_DEVICE_UDID\n"
block = '''unset NEMBRA_INTENDED_FIELD_DEVICE_UDID

# Python participates directly in private-input validation and signed-field evidence admission.
# Never discover it through caller PATH, and always use isolated mode so caller PYTHON* startup or
# import state cannot execute before the exact descriptor-bound Nembra source.
PYTHON3="/usr/bin/python3"
if [[ ! -x "$PYTHON3" || -L "$PYTHON3" ]]; then
  echo "Signed field-candidate production requires the sealed system Python 3 at $PYTHON3." >&2
  exit 2
fi
'''
if source.count(anchor) != 1:
    raise SystemExit("python custody anchor drifted")
source = source.replace(anchor, block, 1)

descriptor_anchor = '''exec 7< "$PRIVATE_RUNNER_SNAPSHOT"
exec 8< "$INSPECTOR_SNAPSHOT"
exec 9< "$PRIVATE_RUNNER_SNAPSHOT"
'''
descriptor_block = '''exec 7< "$PRIVATE_RUNNER_SNAPSHOT"
exec 8< "$INSPECTOR_SNAPSHOT"
exec 9< "$PRIVATE_RUNNER_SNAPSHOT"

# Re-bind each independently opened subject to the exact accepted Git blob. Path hashing before open
# alone leaves a same-user pathname replacement race. os.pread preserves the shared execution offset.
verify_open_git_blob_descriptor() {
  local descriptor_path="$1"
  local descriptor_number="$2"
  local expected_blob_sha="$3"
  if ! "$PYTHON3" -I - "$descriptor_number" "$expected_blob_sha" <<'PYVERIFY'
import hashlib
import os
import sys
fd = int(sys.argv[1])
expected = sys.argv[2]
if len(expected) == 40:
    digest_factory = hashlib.sha1
elif len(expected) == 64:
    digest_factory = hashlib.sha256
else:
    raise SystemExit("unsupported Git object ID width")
before = os.lseek(fd, 0, os.SEEK_CUR)
if before != 0:
    raise SystemExit("tool descriptor was not positioned at byte zero")
chunks = []
offset = 0
while True:
    chunk = os.pread(fd, 1024 * 1024, offset)
    if not chunk:
        break
    chunks.append(chunk)
    offset += len(chunk)
raw = b"".join(chunks)
header = b"blob " + str(len(raw)).encode("ascii") + b"\\0"
if digest_factory(header + raw).hexdigest() != expected:
    raise SystemExit("opened tool descriptor does not match accepted Git blob")
if os.lseek(fd, 0, os.SEEK_CUR) != before:
    raise SystemExit("tool descriptor verification changed execution offset")
PYVERIFY
  then
    echo "Opened signed-field tool failed exact Git-object custody: $descriptor_path" >&2
    return 1
  fi
}
verify_open_git_blob_descriptor "/dev/fd/7" 7 "$PRIVATE_RUNNER_BLOB_SHA"
verify_open_git_blob_descriptor "/dev/fd/8" 8 "$INSPECTOR_BLOB_SHA"
verify_open_git_blob_descriptor "/dev/fd/9" 9 "$PRIVATE_RUNNER_BLOB_SHA"
'''
if source.count(descriptor_anchor) != 1:
    raise SystemExit("descriptor-open anchor drifted")
source = source.replace(descriptor_anchor, descriptor_block, 1)
producer_path.write_text(source, encoding="utf-8")

source_test_path = Path("scripts/ci/tests/test_xcode27_signed_field_candidate_source.py")
test = source_test_path.read_text(encoding="utf-8")
for old, new in (("python3 /dev/fd/7", '"$PYTHON3" -I /dev/fd/7'), ("python3 /dev/fd/9", '"$PYTHON3" -I /dev/fd/9')):
    if old not in test:
        raise SystemExit(f"incumbent descriptor expectation drifted: {old}")
    test = test.replace(old, new)
source_test_path.write_text(test, encoding="utf-8")
