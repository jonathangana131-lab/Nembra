#!/usr/bin/env python3
"""One-shot materializer for verified accepted Git execution payloads.

This script intentionally patches only the field installer and one stale source
contract. The workflow that invokes it deletes this file before publishing the
clean production head.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
AUTHORITY_TEST = ROOT / "scripts/ci/tests/test_capture_field_installer_git_authority_red_team.py"
EXPECTED_INSTALLER_BLOB = "87430680649f9eb3160f30162f2c78f75809af68"
EXPECTED_TEST_BLOB = "514dc57300f6f6987248a09e20f307a18fa43b76"


def git_blob_oid(payload: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload).hexdigest()


def require_blob(path: Path, expected: str) -> None:
    actual = git_blob_oid(path.read_bytes())
    if actual != expected:
        raise SystemExit(f"refusing unexpected source blob for {path}: {actual} != {expected}")


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return source.replace(old, new, 1)


require_blob(INSTALLER, EXPECTED_INSTALLER_BLOB)
require_blob(AUTHORITY_TEST, EXPECTED_TEST_BLOB)
installer = INSTALLER.read_text(encoding="utf-8")

verified_reader = r'''read_verified_accepted_source() {
    local relative_path="$1"
    [[ "$relative_path" != /* && "$relative_path" != *".."* ]] || die "Accepted source path is invalid."
    /usr/bin/python3 -I -B -c '
import hashlib
import hmac
import os
from pathlib import PurePosixPath
import re
import subprocess
import sys

root, git_dir, source_sha, relative_path = sys.argv[1:5]
relative = PurePosixPath(relative_path)
if (
    not relative.parts
    or relative.is_absolute()
    or relative.as_posix() != relative_path
    or any(part in {"", ".", ".."} for part in relative.parts)
):
    raise SystemExit("accepted source path is not one canonical repository-relative path")
if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
    raise SystemExit("accepted source commit is not one canonical SHA-1 identity")

git_environment = {
    "PATH": "/usr/bin:/bin",
    "HOME": "/tmp",
    "LANG": "C",
    "LC_ALL": "C",
    "GIT_DIR": git_dir,
    "GIT_WORK_TREE": root,
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_NO_REPLACE_OBJECTS": "1",
    "GIT_CONFIG_COUNT": "7",
    "GIT_CONFIG_KEY_0": "core.worktree",
    "GIT_CONFIG_VALUE_0": root,
    "GIT_CONFIG_KEY_1": "core.bare",
    "GIT_CONFIG_VALUE_1": "false",
    "GIT_CONFIG_KEY_2": "core.fsmonitor",
    "GIT_CONFIG_VALUE_2": "false",
    "GIT_CONFIG_KEY_3": "core.ignorestat",
    "GIT_CONFIG_VALUE_3": "false",
    "GIT_CONFIG_KEY_4": "core.filemode",
    "GIT_CONFIG_VALUE_4": "true",
    "GIT_CONFIG_KEY_5": "core.excludesFile",
    "GIT_CONFIG_VALUE_5": "/dev/null",
    "GIT_CONFIG_KEY_6": "core.sparseCheckout",
    "GIT_CONFIG_VALUE_6": "false",
}
try:
    tree = subprocess.check_output(
        [
            "/usr/bin/git",
            "ls-tree",
            "-r",
            "-z",
            source_sha,
            "--",
            ":(literal)" + relative_path,
        ],
        cwd=root,
        env=git_environment,
        stderr=subprocess.DEVNULL,
    )
except subprocess.CalledProcessError as error:
    raise SystemExit("accepted source tree lookup failed") from error
records = [record for record in tree.split(b"\0") if record]
if len(records) != 1:
    raise SystemExit("accepted source path did not resolve to exactly one tracked blob")
try:
    metadata, path_raw = records[0].split(b"\t", 1)
    mode, object_type, oid_raw = metadata.split(b" ", 2)
    resolved_path = os.fsdecode(path_raw)
    expected_oid = oid_raw.decode("ascii")
except (ValueError, UnicodeDecodeError) as error:
    raise SystemExit("accepted source tree record is malformed") from error
if resolved_path != relative_path:
    raise SystemExit("accepted source tree resolved a different path")
if object_type != b"blob" or mode not in {b"100644", b"100755"}:
    raise SystemExit("accepted executable source is not one ordinary tracked file")
if re.fullmatch(r"[0-9a-f]{40}", expected_oid) is None:
    raise SystemExit("accepted executable source blob identity is malformed")
try:
    size_raw = subprocess.check_output(
        ["/usr/bin/git", "cat-file", "-s", expected_oid],
        cwd=root,
        env=git_environment,
        stderr=subprocess.DEVNULL,
    )
    size = int(size_raw.decode("ascii").strip(), 10)
except (subprocess.CalledProcessError, UnicodeDecodeError, ValueError) as error:
    raise SystemExit("accepted executable source size is unavailable") from error
if size <= 0 or size > 4 * 1024 * 1024:
    raise SystemExit("accepted executable source has an invalid bounded size")
try:
    payload = subprocess.check_output(
        ["/usr/bin/git", "cat-file", "blob", expected_oid],
        cwd=root,
        env=git_environment,
        stderr=subprocess.DEVNULL,
    )
except subprocess.CalledProcessError as error:
    raise SystemExit("accepted executable source payload is unavailable") from error
if len(payload) != size:
    raise SystemExit("accepted executable source payload size changed during object read")
actual_oid = hashlib.sha1(
    b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
).hexdigest()
if not hmac.compare_digest(actual_oid, expected_oid):
    raise SystemExit("accepted executable source Git payload does not match its accepted tree blob identity")
sys.stdout.buffer.write(payload)
' "$ROOT" "$AUTHORITY_GIT_DIR" "$SOURCE_SHA" "$relative_path"
}

'''
installer = replace_once(
    installer,
    "run_accepted_source_bash() {\n",
    verified_reader + "run_accepted_source_bash() {\n",
    "insert verified accepted-source reader",
)
installer = replace_once(
    installer,
    '''    if ! run_authority_git show "$SOURCE_SHA:$relative_path" |\n        /bin/bash --noprofile --norc -p -c 'source /dev/stdin' "$ROOT/$relative_path"; then\n''',
    '''    if ! read_verified_accepted_source "$relative_path" |\n        /bin/bash --noprofile --norc -p -c 'source /dev/stdin' "$ROOT/$relative_path"; then\n''',
    "bind accepted Bash execution payload",
)
installer = replace_once(
    installer,
    '''    run_authority_git show "$SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner.py" |\n        /usr/bin/env -i \\\n''',
    '''    read_verified_accepted_source "$PRIVATE_DEVICE_RUNNER_RELATIVE" |\n        /usr/bin/env -i \\\n''',
    "bind private-runner execution payload",
)

python_helper_start = installer.index("run_accepted_source_python() {\n")
python_helper_end_marker = 'GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git cat-file -e "$SOURCE_SHA:$TUYA_BUILD_WINDOW_GUARD_RELATIVE"'
python_helper_end = installer.index(python_helper_end_marker, python_helper_start)
verified_python_helper = r'''run_accepted_source_python() {
    local relative_path="$1"
    shift
    read_verified_accepted_source "$relative_path" |
        /usr/bin/python3 -I -B -c '
import sys
from pathlib import Path

root = Path(sys.argv[1])
source_sha = sys.argv[2]
relative_path = sys.argv[3]
helper_argv = sys.argv[4:]
source = sys.stdin.buffer.read(4 * 1024 * 1024 + 1)
if not source or len(source) > 4 * 1024 * 1024:
    raise RuntimeError("verified accepted helper source has an invalid bounded size")
namespace = {"__name__": "__main__", "__file__": str(root / relative_path)}
sys.argv = [str(root / relative_path), *helper_argv]
exec(compile(source, f"<accepted-{source_sha}:{relative_path}>", "exec"), namespace)
' "$ROOT" "$SOURCE_SHA" "$relative_path" "$@"
}
'''
installer = installer[:python_helper_start] + verified_python_helper + installer[python_helper_end:]
INSTALLER.write_text(installer, encoding="utf-8")

contract = AUTHORITY_TEST.read_text(encoding="utf-8")
contract = replace_once(
    contract,
    '''        self.assertIn('run_authority_git show "$SOURCE_SHA:$relative_path"', installer)\n''',
    '''        self.assertIn('read_verified_accepted_source "$relative_path"', installer)\n        self.assertIn('"ls-tree",', installer)\n        self.assertIn('["/usr/bin/git", "cat-file", "blob", expected_oid]', installer)\n        self.assertIn('accepted executable source Git payload does not match its accepted tree blob identity', installer)\n        self.assertNotIn('run_authority_git show "$SOURCE_SHA:$relative_path" |', installer)\n''',
    "update accepted-bootstrap execution contract",
)
AUTHORITY_TEST.write_text(contract, encoding="utf-8")

print("materialized verified accepted Git execution payload custody")
print("installer blob:", git_blob_oid(INSTALLER.read_bytes()))
print("authority-test blob:", git_blob_oid(AUTHORITY_TEST.read_bytes()))
