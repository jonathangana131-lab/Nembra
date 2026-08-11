#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
TEST = ROOT / "scripts/ci/tests/test_capture_field_git_packed_blob_execution_red_team.py"
WORKFLOW = ROOT / ".github/workflows/capture-field-git-packed-blob-execution-red-team.yml"
PARENT_SHA = "d0b134ca2a49edc029f114660dfb8e216ece682e"
DIAGNOSTIC_BRANCH = "adversarial/v14-field-packed-blob-execution-sol-20260811"
DIAGNOSTIC_SHA = "85349b6e9586d7d0cb076d6eb24be17f026fc5ee"
TEST_BLOB = "7c2da715c65214c2fc0cd832947914f0d09e9791"
WORKFLOW_BLOB = "01223db900b2370e293495a06b8d8e756c5c22bb"


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def materialize_diagnostic() -> None:
    subprocess.run(["git", "fetch", "--no-tags", "origin", DIAGNOSTIC_BRANCH], cwd=ROOT, check=True)
    require(git("rev-parse", "FETCH_HEAD") == DIAGNOSTIC_SHA, "diagnostic branch moved")
    for path, expected_blob in ((TEST, TEST_BLOB), (WORKFLOW, WORKFLOW_BLOB)):
        payload = subprocess.check_output(
            ["git", "show", f"{DIAGNOSTIC_SHA}:{path.relative_to(ROOT).as_posix()}"],
            cwd=ROOT,
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        require(git("hash-object", path.relative_to(ROOT).as_posix()) == expected_blob, f"diagnostic blob mismatch: {path}")


def patch_installer() -> None:
    source = INSTALLER.read_text(encoding="utf-8")
    require("accepted_source_blob_oid()" not in source, "accepted blob repair already present")

    function_anchor = '''run_authority_git() {\n    /usr/bin/env -i \\\n        PATH=/usr/bin:/bin \\\n        HOME=/tmp \\\n        LANG=C \\\n        LC_ALL=C \\\n        GIT_DIR="$AUTHORITY_GIT_DIR" \\\n        GIT_WORK_TREE="$ROOT" \\\n        GIT_CONFIG_NOSYSTEM=1 \\\n        GIT_CONFIG_GLOBAL=/dev/null \\\n        GIT_NO_REPLACE_OBJECTS=1 \\\n        GIT_CONFIG_COUNT=7 \\\n        GIT_CONFIG_KEY_0=core.worktree \\\n        GIT_CONFIG_VALUE_0="$ROOT" \\\n        GIT_CONFIG_KEY_1=core.bare \\\n        GIT_CONFIG_VALUE_1=false \\\n        GIT_CONFIG_KEY_2=core.fsmonitor \\\n        GIT_CONFIG_VALUE_2=false \\\n        GIT_CONFIG_KEY_3=core.ignorestat \\\n        GIT_CONFIG_VALUE_3=false \\\n        GIT_CONFIG_KEY_4=core.filemode \\\n        GIT_CONFIG_VALUE_4=true \\\n        GIT_CONFIG_KEY_5=core.excludesFile \\\n        GIT_CONFIG_VALUE_5=/dev/null \\\n        GIT_CONFIG_KEY_6=core.sparseCheckout \\\n        GIT_CONFIG_VALUE_6=false \\\n        /usr/bin/git "$@"\n}\n'''
    require(source.count(function_anchor) == 1, "run_authority_git anchor changed")
    blob_helper = function_anchor + r'''

accepted_source_blob_oid() {
    local relative_path="$1"
    local expected_oid
    [[ "$relative_path" != /* && "$relative_path" != *".."* ]] || die "Accepted source path is invalid."
    expected_oid="$(run_authority_git rev-parse --verify "$SOURCE_SHA:$relative_path")" || \
        die "Accepted source blob identity is unavailable from the exact accepted tree: $relative_path"
    expected_oid="$(printf '%s' "$expected_oid" | tr '[:upper:]' '[:lower:]')"
    [[ "$expected_oid" =~ ^[0-9a-f]{40}$ ]] || die "Accepted source blob identity is malformed: $relative_path"
    [[ "$(run_authority_git cat-file -t "$expected_oid")" == "blob" ]] || die "Accepted source subject is not a blob: $relative_path"
    printf '%s' "$expected_oid"
}
'''
    source = source.replace(function_anchor, blob_helper, 1)

    old_bash = r'''run_accepted_source_bash() {
    local relative_path="$1"
    [[ "$relative_path" != /* && "$relative_path" != *".."* ]] || die "Accepted Bash source path is invalid."
    if ! run_authority_git show "$SOURCE_SHA:$relative_path" |
        /bin/bash --noprofile --norc -p -c 'source /dev/stdin' "$ROOT/$relative_path"; then
        die "Accepted Bash source failed or could not be executed from exact Git authority: $relative_path"
    fi
}
'''
    new_bash = r'''run_accepted_source_bash() {
    local relative_path="$1"
    local expected_blob_oid
    [[ "$relative_path" != /* && "$relative_path" != *".."* ]] || die "Accepted Bash source path is invalid."
    expected_blob_oid="$(accepted_source_blob_oid "$relative_path")"
    if ! run_authority_git show "$SOURCE_SHA:$relative_path" |
        /usr/bin/python3 -I -B -c '
import hashlib
import hmac
import subprocess
import sys

expected_oid = sys.argv[1]
script_name = sys.argv[2]
source = sys.stdin.buffer.read(2 * 1024 * 1024 + 1)
if not source or len(source) > 2 * 1024 * 1024:
    raise RuntimeError("accepted Bash source has an invalid bounded size")
actual_oid = hashlib.sha1(
    b"blob " + str(len(source)).encode("ascii") + b"\\0" + source
).hexdigest()
if not hmac.compare_digest(actual_oid, expected_oid):
    raise RuntimeError("accepted Bash Git payload does not match its accepted blob identity")
completed = subprocess.run(
    ["/bin/bash", "--noprofile", "--norc", "-p", "-c", "source /dev/stdin", script_name],
    input=source,
    check=False,
)
raise SystemExit(completed.returncode)
' "$expected_blob_oid" "$ROOT/$relative_path"; then
        die "Accepted Bash source failed or could not be executed from exact Git authority: $relative_path"
    fi
}
'''
    require(source.count(old_bash) == 1, "accepted Bash execution anchor changed")
    source = source.replace(old_bash, new_bash, 1)

    old_private = r'''PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_DEVICE_RUNNER_RELATIVE="scripts/ci/es80_signed_field_artifact_private_runner.py"
if ! DEVICE_UDID="$(
    run_authority_git show "$SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner.py" |
        /usr/bin/env -i \
            PATH=/usr/bin:/bin \
            HOME=/tmp \
            LANG=C \
            LC_ALL=C \
            NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" \
            /usr/bin/python3 -I -B -c '
import hashlib
import hmac
import os
import re
import sys
from pathlib import Path
from types import ModuleType

relative_path = sys.argv[1]
source = sys.stdin.buffer.read(2 * 1024 * 1024 + 1)
if not source or len(source) > 2 * 1024 * 1024:
    raise RuntimeError("accepted private intended-device reader source has an invalid bounded size")
module = ModuleType("nembra_private_device_reader")
module.__file__ = f"<accepted-{relative_path}>"
exec(compile(source, module.__file__, "exec"), module.__dict__)
reader = getattr(module, "read_private_identifier", None)
if not callable(reader):
    raise RuntimeError("accepted private intended-device reader does not expose the required contract")
value = reader(Path(sys.argv[2]), Path(sys.argv[3]))
expected_digest = os.environ.get("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256", "")
if re.fullmatch(r"[0-9a-f]{64}", expected_digest) is None:
    raise RuntimeError("expected intended-device digest is unavailable or malformed")
actual_digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
if not hmac.compare_digest(actual_digest, expected_digest):
    raise RuntimeError("private intended-device identifier does not match Final GO authority")
sys.stdout.write(value)
' "$PRIVATE_DEVICE_RUNNER_RELATIVE" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT"
)"; then
'''
    new_private = r'''PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_DEVICE_RUNNER_RELATIVE="scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_DEVICE_RUNNER_BLOB_OID="$(accepted_source_blob_oid "$PRIVATE_DEVICE_RUNNER_RELATIVE")"
if ! DEVICE_UDID="$(
    run_authority_git show "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_RELATIVE" |
        /usr/bin/env -i \
            PATH=/usr/bin:/bin \
            HOME=/tmp \
            LANG=C \
            LC_ALL=C \
            NEMBRA_ACCEPTED_PRIVATE_RUNNER_BLOB_OID="$PRIVATE_DEVICE_RUNNER_BLOB_OID" \
            NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" \
            /usr/bin/python3 -I -B -c '
import hashlib
import hmac
import os
import re
import sys
from pathlib import Path
from types import ModuleType

relative_path = sys.argv[1]
source = sys.stdin.buffer.read(2 * 1024 * 1024 + 1)
if not source or len(source) > 2 * 1024 * 1024:
    raise RuntimeError("accepted private intended-device reader source has an invalid bounded size")
expected_source_oid = os.environ.get("NEMBRA_ACCEPTED_PRIVATE_RUNNER_BLOB_OID", "")
if re.fullmatch(r"[0-9a-f]{40}", expected_source_oid) is None:
    raise RuntimeError("accepted private intended-device reader blob identity is unavailable or malformed")
actual_source_oid = hashlib.sha1(
    b"blob " + str(len(source)).encode("ascii") + b"\\0" + source
).hexdigest()
if not hmac.compare_digest(actual_source_oid, expected_source_oid):
    raise RuntimeError("accepted private intended-device reader payload does not match its accepted blob identity")
module = ModuleType("nembra_private_device_reader")
module.__file__ = f"<accepted-{relative_path}>"
exec(compile(source, module.__file__, "exec"), module.__dict__)
reader = getattr(module, "read_private_identifier", None)
if not callable(reader):
    raise RuntimeError("accepted private intended-device reader does not expose the required contract")
value = reader(Path(sys.argv[2]), Path(sys.argv[3]))
expected_digest = os.environ.get("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256", "")
if re.fullmatch(r"[0-9a-f]{64}", expected_digest) is None:
    raise RuntimeError("expected intended-device digest is unavailable or malformed")
actual_digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
if not hmac.compare_digest(actual_digest, expected_digest):
    raise RuntimeError("private intended-device identifier does not match Final GO authority")
sys.stdout.write(value)
' "$PRIVATE_DEVICE_RUNNER_RELATIVE" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT"
)"; then
'''
    require(source.count(old_private) == 1, "private runner execution anchor changed")
    source = source.replace(old_private, new_private, 1)

    old_python_import = r'''import subprocess
import sys
from pathlib import Path
'''
    new_python_import = r'''import hashlib
import hmac
import re
import subprocess
import sys
from pathlib import Path
'''
    # Limit the replacement to the run_accepted_source_python heredoc by splitting first.
    marker = 'run_accepted_source_python() {'
    require(source.count(marker) == 1, "accepted Python helper anchor changed")
    prefix, suffix = source.split(marker, 1)
    require(suffix.count(old_python_import) >= 1, "accepted Python helper imports changed")
    suffix = suffix.replace(old_python_import, new_python_import, 1)

    old_python_lookup = r'''    source = subprocess.check_output(
        ["/usr/bin/git", "show", f"{source_sha}:{relative_path}"],
        cwd=root,
        env=git_environment,
        stderr=subprocess.DEVNULL,
    )
except subprocess.CalledProcessError as error:
    raise SystemExit(f"accepted source helper is unavailable from exact Git authority: {relative_path}") from error
namespace = {"__name__": "__main__", "__file__": str(root / relative_path)}
'''
    new_python_lookup = r'''    expected_oid = subprocess.check_output(
        ["/usr/bin/git", "rev-parse", "--verify", f"{source_sha}:{relative_path}"],
        cwd=root,
        env=git_environment,
        stderr=subprocess.DEVNULL,
        text=True,
    ).strip().lower()
    if re.fullmatch(r"[0-9a-f]{40}", expected_oid) is None:
        raise RuntimeError("accepted source helper blob identity is malformed")
    source = subprocess.check_output(
        ["/usr/bin/git", "show", f"{source_sha}:{relative_path}"],
        cwd=root,
        env=git_environment,
        stderr=subprocess.DEVNULL,
    )
except (subprocess.CalledProcessError, RuntimeError) as error:
    raise SystemExit(f"accepted source helper is unavailable from exact Git authority: {relative_path}") from error
actual_oid = hashlib.sha1(
    b"blob " + str(len(source)).encode("ascii") + b"\\0" + source
).hexdigest()
if not hmac.compare_digest(actual_oid, expected_oid):
    raise SystemExit(f"accepted source helper payload does not match its accepted blob identity: {relative_path}")
namespace = {"__name__": "__main__", "__file__": str(root / relative_path)}
'''
    require(suffix.count(old_python_lookup) == 1, "accepted Python helper Git lookup changed")
    suffix = suffix.replace(old_python_lookup, new_python_lookup, 1)
    source = prefix + marker + suffix

    INSTALLER.write_text(source, encoding="utf-8")


def main() -> None:
    require(git("rev-parse", "HEAD") != "", "missing construction head")
    require(git("merge-base", PARENT_SHA, "HEAD") == PARENT_SHA, "unexpected parent lineage")
    materialize_diagnostic()
    patch_installer()


if __name__ == "__main__":
    main()
