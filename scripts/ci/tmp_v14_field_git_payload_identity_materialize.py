#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/field/install_one_time_capture.command")
text = path.read_text(encoding="utf-8")

anchor = '''        /usr/bin/git "$@"
}

SOURCE_SHA='''
if text.count(anchor) != 1:
    raise SystemExit("run_authority_git insertion anchor drifted")

helper = r'''        /usr/bin/git "$@"
}

# Git object names come from the accepted tree, but the mutable local object
# database is not itself execution authority. Before any accepted Git payload is
# interpreted, bind the exact returned bytes back to the tree's blob OID using
# Git's canonical blob framing. Keep the complete payload buffered until that
# comparison succeeds so unverified bytes can never reach an interpreter.
read_verified_accepted_git_blob() {
    local relative_path="$1"
    [[ "$relative_path" != /* && "$relative_path" != *".."* ]] || die "Accepted Git source path is invalid."
    /usr/bin/env -i \
        PATH=/usr/bin:/bin \
        HOME=/tmp \
        LANG=C \
        LC_ALL=C \
        NEMBRA_ROOT="$ROOT" \
        NEMBRA_AUTHORITY_GIT_DIR="$AUTHORITY_GIT_DIR" \
        NEMBRA_SOURCE_SHA="$SOURCE_SHA" \
        NEMBRA_RELATIVE_PATH="$relative_path" \
        /usr/bin/python3 -I -B -c '
import hashlib
import hmac
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

root = Path(os.environ["NEMBRA_ROOT"])
git_dir = os.environ["NEMBRA_AUTHORITY_GIT_DIR"]
source_sha = os.environ["NEMBRA_SOURCE_SHA"]
relative_path = os.environ["NEMBRA_RELATIVE_PATH"]
parts = PurePosixPath(relative_path).parts
if PurePosixPath(relative_path).is_absolute() or not parts or any(part in {"", ".", ".."} for part in parts):
    raise SystemExit("accepted Git source path is unsafe")

git_environment = {
    "PATH": "/usr/bin:/bin",
    "HOME": "/tmp",
    "LANG": "C",
    "LC_ALL": "C",
    "GIT_DIR": git_dir,
    "GIT_WORK_TREE": str(root),
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_NO_REPLACE_OBJECTS": "1",
    "GIT_CONFIG_COUNT": "7",
    "GIT_CONFIG_KEY_0": "core.worktree",
    "GIT_CONFIG_VALUE_0": str(root),
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
        ["/usr/bin/git", "ls-tree", "-z", source_sha, "--", relative_path],
        cwd=root,
        env=git_environment,
        stderr=subprocess.DEVNULL,
    )
except subprocess.CalledProcessError as error:
    raise SystemExit("accepted Git tree lookup failed") from error
records = [record for record in tree.split(b"\0") if record]
if len(records) != 1:
    raise SystemExit("accepted Git source must resolve to exactly one tree entry")
try:
    metadata, tree_path = records[0].split(b"\t", 1)
    mode, object_type, expected_oid_raw = metadata.split(b" ", 2)
except ValueError as error:
    raise SystemExit("accepted Git tree entry is malformed") from error
if tree_path != os.fsencode(relative_path):
    raise SystemExit("accepted Git tree returned a different source path")
if object_type != b"blob" or mode not in {b"100644", b"100755"}:
    raise SystemExit("accepted Git executable source is not one regular blob")
expected_oid = expected_oid_raw.decode("ascii", errors="strict").lower()
if re.fullmatch(r"[0-9a-f]{40}", expected_oid) is None:
    raise SystemExit("accepted Git blob identity is malformed")

limit = 2 * 1024 * 1024
process = subprocess.Popen(
    ["/usr/bin/git", "cat-file", "blob", expected_oid],
    cwd=root,
    env=git_environment,
    stdin=subprocess.DEVNULL,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
)
assert process.stdout is not None
payload = bytearray()
while True:
    remaining = limit + 1 - len(payload)
    if remaining <= 0:
        process.kill()
        process.wait()
        raise SystemExit("accepted Git executable source exceeds the bounded payload limit")
    chunk = process.stdout.read(min(65536, remaining))
    if not chunk:
        break
    payload.extend(chunk)
    if len(payload) > limit:
        process.kill()
        process.wait()
        raise SystemExit("accepted Git executable source exceeds the bounded payload limit")
if process.wait() != 0:
    raise SystemExit("accepted Git blob payload lookup failed")
source = bytes(payload)
actual_oid = hashlib.sha1(
    b"blob " + str(len(source)).encode("ascii") + b"\0" + source
).hexdigest()
if not hmac.compare_digest(actual_oid, expected_oid):
    raise SystemExit("accepted Git blob payload does not match the accepted tree identity")
sys.stdout.buffer.write(source)
'
}

SOURCE_SHA='''
text = text.replace(anchor, helper, 1)

old_bootstrap = 'run_authority_git show "$SOURCE_SHA:$relative_path" |\n        /bin/bash --noprofile --norc -p -c \'source /dev/stdin\' "$ROOT/$relative_path"'
new_bootstrap = 'read_verified_accepted_git_blob "$relative_path" |\n        /bin/bash --noprofile --norc -p -c \'source /dev/stdin\' "$ROOT/$relative_path"'
if text.count(old_bootstrap) != 1:
    raise SystemExit("accepted Bash execution anchor drifted")
text = text.replace(old_bootstrap, new_bootstrap, 1)

old_private = 'run_authority_git show "$SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner.py" |\n        /usr/bin/env -i'
new_private = 'read_verified_accepted_git_blob "$PRIVATE_DEVICE_RUNNER_RELATIVE" |\n        /usr/bin/env -i'
if text.count(old_private) != 1:
    raise SystemExit("private runner execution anchor drifted")
text = text.replace(old_private, new_private, 1)

start_marker = 'run_accepted_source_python() {'
end_marker = '\n}\nGIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git cat-file -e'
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit("accepted Python execution block drifted")
end += 2
new_python_runner = r'''run_accepted_source_python() {
    local relative_path="$1"
    shift
    if ! read_verified_accepted_git_blob "$relative_path" |
        NEMBRA_ACCEPTED_SOURCE_ROOT="$ROOT" \
        NEMBRA_ACCEPTED_SOURCE_SHA="$SOURCE_SHA" \
        NEMBRA_ACCEPTED_SOURCE_RELATIVE="$relative_path" \
        /usr/bin/python3 -I -B -c '
import os
from pathlib import Path
import sys

root = Path(os.environ["NEMBRA_ACCEPTED_SOURCE_ROOT"])
source_sha = os.environ["NEMBRA_ACCEPTED_SOURCE_SHA"]
relative_path = os.environ["NEMBRA_ACCEPTED_SOURCE_RELATIVE"]
source = sys.stdin.buffer.read(2 * 1024 * 1024 + 1)
if not source or len(source) > 2 * 1024 * 1024:
    raise RuntimeError("verified accepted Python source has an invalid bounded size")
namespace = {"__name__": "__main__", "__file__": str(root / relative_path)}
sys.argv = [str(root / relative_path), *sys.argv[1:]]
exec(compile(source, f"<accepted-{source_sha}:{relative_path}>", "exec"), namespace)
' "$@"; then
        return 1
    fi
}'''
text = text[:start] + new_python_runner + text[end:]

for forbidden in (
    'run_authority_git show "$SOURCE_SHA:$relative_path" |',
    'run_authority_git show "$SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner.py" |',
    '["/usr/bin/git", "show", f"{source_sha}:{relative_path}"]',
):
    if forbidden in text:
        raise SystemExit("unverified accepted Git execution path remains: " + forbidden)

required = (
    'read_verified_accepted_git_blob "$relative_path" |',
    'read_verified_accepted_git_blob "$PRIVATE_DEVICE_RUNNER_RELATIVE" |',
    'hashlib.sha1(',
    'hmac.compare_digest(actual_oid, expected_oid)',
    '["/usr/bin/git", "cat-file", "blob", expected_oid]',
)
for token in required:
    if token not in text:
        raise SystemExit("materialized installer is missing authority token: " + token)

path.write_text(text, encoding="utf-8")
