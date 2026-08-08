#!/usr/bin/env python3
from pathlib import Path
import re

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
source = PRODUCER.read_text(encoding="utf-8")

closed_path = 'PATH="/usr/bin:/bin:/usr/sbin:/sbin"'
path_index = source.find(closed_path)
unset_index = source.find("unset NEMBRA_INTENDED_FIELD_DEVICE_UDID")
if path_index < 0 or unset_index < 0 or path_index > unset_index:
    raise SystemExit("producer must close executable PATH before any release child-process seam")
if "export PATH" not in source[path_index:unset_index]:
    raise SystemExit("closed producer PATH must be exported before child processes")

if 'PYTHON3="/usr/bin/python3"' not in source:
    raise SystemExit("producer must pin one absolute system Python interpreter")
if "assert_root_custodied_executable()" not in source:
    raise SystemExit("producer must define one root-custody executable verifier")
if 'assert_root_custodied_executable "$PYTHON3" "Python 3"' not in source:
    raise SystemExit("pinned Python must pass the root-custody verifier before use")

first_python_call = source.find('"$PYTHON3" -I')
python_custody = source.find('assert_root_custodied_executable "$PYTHON3" "Python 3"')
if first_python_call < 0 or python_custody < 0 or python_custody > first_python_call:
    raise SystemExit("Python custody must be proven before the first interpreter invocation")

custody_start = source.find("assert_root_custodied_executable()")
custody_end = source.find("\n}", custody_start)
custody = source[custody_start:custody_end + 2]
for token in ("-L", "stat -f %u", "stat -f %Mp%Lp", "owner_uid", "writable_bits"):
    if token not in custody:
        raise SystemExit(f"Python custody verifier is missing fail-closed invariant: {token}")

for line in source.splitlines():
    stripped = line.strip()
    if stripped.startswith("#"):
        continue
    if '"$PYTHON3"' in line and "assert_root_custodied_executable" not in line and "PYTHON3=" not in line:
        if " -I" not in line:
            raise SystemExit(f"Python invocation is not isolated: {line}")
    if re.search(r"(^|[;&|$(]\s*)python3(?:\s|$)", line):
        raise SystemExit(f"ambient python3 invocation bypasses pinned interpreter: {line}")

print("signed-field producer process/Python custody source contract: PASS")
