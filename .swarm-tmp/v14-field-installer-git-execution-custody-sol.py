#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess

DIAGNOSTIC = "d228dc4eef45f9b3c32a62bdc573f8b5a79d061a"
DIAGNOSTIC_PARENT = "4bdc76fa68e9c49ca4304c75e456cad22ee2f895"


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def output(*args: str) -> bytes:
    return subprocess.check_output(args)


installer_path = Path("scripts/field/install_one_time_capture.command")
installer = installer_path.read_text(encoding="utf-8")
old_authority = '''EXPECTED_SOURCE_SHA="${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}"
[[ "$EXPECTED_SOURCE_SHA" =~ ^[0-9A-Fa-f]{40}$ ]] || die "Pass the exact software-accepted Capture source SHA as the first argument (40 hex characters)."
EXPECTED_SOURCE_SHA="$(printf '%s' "$EXPECTED_SOURCE_SHA" | tr '[:upper:]' '[:lower:]')"
SOURCE_SHA="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]] || die "Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA. Checkout the exact accepted SHA before building."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Working tree has local changes. Commit/stash them first."
say "Exact requested Capture source matched: $SOURCE_SHA"
'''
new_authority = '''EXPECTED_SOURCE_SHA="${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}"
[[ "$EXPECTED_SOURCE_SHA" =~ ^[0-9A-Fa-f]{40}$ ]] || die "Pass the exact software-accepted Capture source SHA as the first argument (40 hex characters)."
EXPECTED_SOURCE_SHA="$(printf '%s' "$EXPECTED_SOURCE_SHA" | tr '[:upper:]' '[:lower:]')"
FIELD_BOOTSTRAP_RELATIVE="Scripts/bootstrap_capture_tuya_sdk.sh"

run_accepted_field_source_gate() {
  local action="$1"
  /usr/bin/python3 -I - "$ROOT" "$EXPECTED_SOURCE_SHA" "$FIELD_BOOTSTRAP_RELATIVE" "$action" <<'PY_FIELD_AUTHORITY'
import hashlib
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
expected = sys.argv[2].lower()
bootstrap_relative = sys.argv[3]
action = sys.argv[4]


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(71)


if re.fullmatch(r"[0-9a-f]{40}", expected) is None:
    fail("accepted Capture source is not canonical 40-hex")
if action not in {"verify", "bootstrap"}:
    fail("field source gate action is invalid")
if not root.is_absolute() or Path(os.path.realpath(root)) != root:
    fail("field checkout root must be one physical absolute path")

git_dir = root / ".git"
try:
    git_dir_metadata = os.lstat(git_dir)
except OSError as error:
    fail(f"field checkout Git directory is unavailable: {error}")
if not stat.S_ISDIR(git_dir_metadata.st_mode) or stat.S_ISLNK(git_dir_metadata.st_mode):
    fail("field checkout must use one real non-symlink .git directory")

exclude_path = git_dir / "info" / "exclude"
if exclude_path.exists():
    if exclude_path.is_symlink() or not exclude_path.is_file():
        fail("repository-local Git exclude authority is not one regular file")
    active_excludes = [
        line.strip()
        for line in exclude_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if active_excludes:
        fail("repository-local .git/info/exclude patterns are forbidden for a field-authority checkout")

base_git_environment = {
    "PATH": "/usr/bin:/bin",
    "HOME": "/tmp",
    "LANG": "C",
    "LC_ALL": "C",
    "GIT_DIR": str(git_dir),
    "GIT_WORK_TREE": str(root),
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_NO_REPLACE_OBJECTS": "1",
    "GIT_CONFIG_COUNT": "5",
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
}


def git_bytes(*arguments: str, environment: dict[str, str] | None = None) -> bytes:
    try:
        return subprocess.check_output(
            ["/usr/bin/git", *arguments],
            cwd=root,
            env=base_git_environment if environment is None else environment,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"accepted field Git authority failed: {' '.join(arguments)} ({error})")


def audit_accepted_source() -> None:
    actual_head = git_bytes("rev-parse", "--verify", "HEAD^{commit}").decode("ascii").strip().lower()
    if actual_head != expected:
        fail(f"current checkout {actual_head} does not match accepted Capture source {expected}")

    descriptor, authority_index = tempfile.mkstemp(prefix="nembra-capture-field-index-")
    os.close(descriptor)
    os.unlink(authority_index)
    index_environment = dict(base_git_environment)
    index_environment["GIT_INDEX_FILE"] = authority_index
    try:
        git_bytes("read-tree", expected, environment=index_environment)
        status = git_bytes(
            "-c", "core.fsmonitor=false",
            "-c", "core.ignorestat=false",
            "-c", "core.filemode=true",
            "status", "--porcelain=v1", "--untracked-files=all",
            environment=index_environment,
        )
        if status:
            fail("resolver-bound field worktree is not clean against a fresh accepted-source index")
    finally:
        try:
            os.unlink(authority_index)
        except FileNotFoundError:
            pass

    tree = git_bytes("ls-tree", "-r", "-z", expected)
    checked = 0
    root_bytes = os.fsencode(root)
    for record in tree.split(b"\0"):
        if not record:
            continue
        metadata, relative_path = record.split(b"\t", 1)
        mode, object_type, expected_oid = metadata.split(b" ", 2)
        if object_type != b"blob" or mode not in {b"100644", b"100755", b"120000"}:
            fail(f"raw field worktree audit refuses unsupported tracked object: {metadata!r}")
        absolute_path = os.path.join(root_bytes, relative_path)
        try:
            current = os.lstat(absolute_path)
        except OSError as error:
            fail(f"raw field worktree subject unavailable: {os.fsdecode(relative_path)} ({error})")
        if mode == b"120000":
            if not stat.S_ISLNK(current.st_mode):
                fail(f"raw field worktree expected symlink: {os.fsdecode(relative_path)}")
            payload = os.readlink(absolute_path)
            if isinstance(payload, str):
                payload = os.fsencode(payload)
        else:
            if not stat.S_ISREG(current.st_mode):
                fail(f"raw field worktree expected regular file: {os.fsdecode(relative_path)}")
            expected_executable = mode == b"100755"
            if bool(current.st_mode & 0o111) != expected_executable:
                fail(f"raw field worktree executable mode mismatch: {os.fsdecode(relative_path)}")
            with open(absolute_path, "rb") as handle:
                payload = handle.read()
        actual_oid = hashlib.sha1(
            b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
        ).hexdigest().encode("ascii")
        if actual_oid != expected_oid:
            fail(f"raw field worktree blob mismatch: {os.fsdecode(relative_path)}")
        checked += 1
    if checked == 0:
        fail("raw field worktree audit found no tracked accepted-source blobs")


def run_accepted_bootstrap() -> None:
    object_id = git_bytes("rev-parse", "--verify", f"{expected}:{bootstrap_relative}").decode("ascii").strip().lower()
    if re.fullmatch(r"[0-9a-f]{40}", object_id) is None:
        fail("accepted bootstrap Git object identity is malformed")
    source = git_bytes("cat-file", "blob", object_id)
    computed = hashlib.sha1(
        b"blob " + str(len(source)).encode("ascii") + b"\0" + source
    ).hexdigest()
    if computed != object_id:
        fail("accepted bootstrap Git bytes do not match their Git object identity")

    pinned = tempfile.TemporaryFile(mode="w+b", prefix="nembra-capture-bootstrap-")
    read_descriptor = -1
    try:
        writable_descriptor = pinned.fileno()
        os.fchmod(writable_descriptor, 0o600)
        pinned.write(source)
        pinned.flush()
        os.fsync(writable_descriptor)
        pinned.seek(0)
        if pinned.read() != source:
            fail("sealed bootstrap bytes changed before execution")
        pinned.seek(0)
        read_descriptor = os.open(
            f"/dev/fd/{writable_descriptor}",
            os.O_RDONLY | getattr(os, "O_CLOEXEC", 0),
        )
        before = os.fstat(read_descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_uid != os.geteuid()
            or stat.S_IMODE(before.st_mode) != 0o600
            or before.st_size != len(source)
        ):
            fail("sealed bootstrap descriptor custody is invalid")
        pinned.close()

        child_environment = dict(os.environ)
        for key in list(child_environment):
            if key.startswith("GIT_") or key in {"BASH_ENV", "ENV"}:
                child_environment.pop(key, None)
        child_environment["BASH_ENV"] = ""
        child_environment["ENV"] = ""
        child_environment["NEMBRA_CAPTURE_BOOTSTRAP_FD_EXECUTION"] = "1"
        logical_path = str(root / bootstrap_relative)
        result = subprocess.run(
            [
                "/bin/bash", "--noprofile", "--norc", "-p", "-c",
                'source "$1"', logical_path, f"/dev/fd/{read_descriptor}",
            ],
            cwd=root,
            env=child_environment,
            pass_fds=(read_descriptor,),
        )
        if result.returncode != 0:
            raise SystemExit(result.returncode)
        after = os.fstat(read_descriptor)
        before_identity = (
            before.st_dev, before.st_ino, before.st_mode, before.st_uid,
            before.st_gid, before.st_nlink, before.st_size,
            before.st_mtime_ns, before.st_ctime_ns,
        )
        after_identity = (
            after.st_dev, after.st_ino, after.st_mode, after.st_uid,
            after.st_gid, after.st_nlink, after.st_size,
            after.st_mtime_ns, after.st_ctime_ns,
        )
        if before_identity != after_identity:
            fail("sealed bootstrap descriptor changed during execution")
    finally:
        if read_descriptor >= 0:
            os.close(read_descriptor)
        try:
            pinned.close()
        except Exception:
            pass


audit_accepted_source()
if action == "bootstrap":
    run_accepted_bootstrap()
    audit_accepted_source()
PY_FIELD_AUTHORITY
}

if ! run_accepted_field_source_gate verify; then
  die "Accepted Capture source/worktree authority failed before private field admission."
fi
SOURCE_SHA="$EXPECTED_SOURCE_SHA"
say "Exact requested Capture source and raw worktree bytes matched: $SOURCE_SHA"
'''
if installer.count(old_authority) != 1:
    raise SystemExit(f"expected one ambient source-authority block, found {installer.count(old_authority)}")
installer = installer.replace(old_authority, new_authority, 1)

old_bootstrap_call = '''say "Validating official Tuya SDK and private app-identity provisioning"
"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"
[[ -d "$ROOT/NembraCapture.xcworkspace" ]] || die "NembraCapture.xcworkspace was not generated. Do not use NembraCapture.xcodeproj for the authenticated field build."
[[ "$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')" == "$SOURCE_SHA" ]] || die "Repository HEAD changed during private workspace bootstrap. Restart from the exact accepted source."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Private workspace bootstrap changed tracked or unignored accepted-source inputs. Review and re-accept before building."
'''
new_bootstrap_call = '''say "Validating official Tuya SDK and private app-identity provisioning"
if ! run_accepted_field_source_gate bootstrap; then
  die "Exact accepted bootstrap execution or post-bootstrap source custody failed."
fi
[[ -d "$ROOT/NembraCapture.xcworkspace" ]] || die "NembraCapture.xcworkspace was not generated. Do not use NembraCapture.xcodeproj for the authenticated field build."
'''
if installer.count(old_bootstrap_call) != 1:
    raise SystemExit(f"expected one mutable bootstrap execution block, found {installer.count(old_bootstrap_call)}")
installer = installer.replace(old_bootstrap_call, new_bootstrap_call, 1)
installer_path.write_text(installer, encoding="utf-8")

bootstrap_path = Path("Scripts/bootstrap_capture_tuya_sdk.sh")
bootstrap = bootstrap_path.read_text(encoding="utf-8")
old_bootstrap_root = '''SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
'''
new_bootstrap_root = '''if [[ "${NEMBRA_CAPTURE_BOOTSTRAP_FD_EXECUTION:-}" == "1" ]]; then
  [[ "${BASH_SOURCE[0]}" == /dev/fd/[0-9]* ]] || {
    echo "ERROR: sealed field bootstrap mode requires an inherited /dev/fd source." >&2
    exit 19
  }
  BOOTSTRAP_LOGICAL_SOURCE="$0"
  [[ "$BOOTSTRAP_LOGICAL_SOURCE" == /*/Scripts/bootstrap_capture_tuya_sdk.sh ]] || {
    echo "ERROR: sealed field bootstrap logical path is not canonical." >&2
    exit 19
  }
else
  [[ -z "${NEMBRA_CAPTURE_BOOTSTRAP_FD_EXECUTION:-}" ]] || {
    echo "ERROR: invalid sealed field bootstrap execution marker." >&2
    exit 19
  }
  BOOTSTRAP_LOGICAL_SOURCE="${BASH_SOURCE[0]}"
fi
SCRIPT_DIR="$(cd "$(dirname "$BOOTSTRAP_LOGICAL_SOURCE")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
unset BOOTSTRAP_LOGICAL_SOURCE NEMBRA_CAPTURE_BOOTSTRAP_FD_EXECUTION || true
'''
if bootstrap.count(old_bootstrap_root) != 1:
    raise SystemExit(f"expected one bootstrap BASH_SOURCE root seam, found {bootstrap.count(old_bootstrap_root)}")
bootstrap = bootstrap.replace(old_bootstrap_root, new_bootstrap_root, 1)
bootstrap_path.write_text(bootstrap, encoding="utf-8")

# Carry the already-demonstrated attack witnesses onto the exact current repair.
run("git", "fetch", "--no-tags", "origin", DIAGNOSTIC, "--depth=2")
actual_parent = output("git", "rev-parse", f"{DIAGNOSTIC}^").decode().strip()
if actual_parent != DIAGNOSTIC_PARENT:
    raise SystemExit(f"diagnostic ancestry drifted: {actual_parent}")
test_path = Path("scripts/ci/tests/test_capture_field_installer_git_authority_red_team.py")
test_source = output("git", "show", f"{DIAGNOSTIC}:{test_path.as_posix()}").decode("utf-8")
test_source = test_source.replace("import os\nfrom pathlib", "import os\nimport re\nimport sys\nfrom pathlib", 1)
test_source = test_source.replace(
    'INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"\n',
    'INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"\nBOOTSTRAP = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"\n',
    1,
)
class_anchor = "class CaptureFieldInstallerGitAuthorityRedTeamTests(unittest.TestCase):\n"
helper_block = r'''class CaptureFieldInstallerGitAuthorityRedTeamTests(unittest.TestCase):
    def _authority_program(self) -> str:
        source = INSTALLER.read_text(encoding="utf-8")
        match = re.search(
            r"<<'PY_FIELD_AUTHORITY'\n(?P<program>.*?)\nPY_FIELD_AUTHORITY",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "field installer has no inline accepted-source authority program")
        return match.group("program")

    def _run_authority_gate(
        self,
        root: Path,
        expected_sha: str,
        *,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                "-I",
                "-",
                str(root),
                expected_sha,
                "Scripts/bootstrap_capture_tuya_sdk.sh",
                "verify",
            ],
            input=self._authority_program(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=os.environ.copy() if env is None else env,
            check=False,
        )

'''
if test_source.count(class_anchor) != 1:
    raise SystemExit("diagnostic class anchor drifted")
test_source = test_source.replace(class_anchor, helper_block, 1)

static_start = '''    def test_field_installer_must_not_split_git_authority_from_bootstrap_execution(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")

        self.assertNotIn(
            'SOURCE_SHA="$(git rev-parse HEAD |',
            source,
            "field source authority still inherits caller/repository Git selection semantics",
        )
        self.assertNotIn(
            '[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]]',
            source,
            "field cleanliness still trusts the ambient repository/index/worktree selection",
        )
        self.assertNotIn(
            '"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"',
            source,
            "accepted-source checks must not be followed by reopening the bootstrap from a mutable checkout pathname",
        )
'''
static_replacement = r'''    def test_current_gate_rejects_ambient_git_dir_worktree_split(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            accepted = root / "accepted"
            attacked = root / "attacked"
            self._make_repository(accepted)
            accepted_sha, _ = self._clone_and_mutate(accepted, attacked)
            env = os.environ.copy()
            env["GIT_DIR"] = str(accepted / ".git")
            env["GIT_WORK_TREE"] = str(accepted)
            result = self._run_authority_gate(attacked, accepted_sha, env=env)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("raw field worktree blob mismatch", result.stderr)

    def test_current_gate_rejects_repository_core_worktree_split(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            accepted = root / "accepted"
            attacked = root / "attacked"
            self._make_repository(accepted)
            accepted_sha, _ = self._clone_and_mutate(accepted, attacked)
            subprocess.run(
                ["git", "config", "core.worktree", str(accepted)],
                cwd=attacked,
                check=True,
            )
            result = self._run_authority_gate(attacked, accepted_sha)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("raw field worktree blob mismatch", result.stderr)

    def test_current_gate_accepts_one_clean_exact_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            accepted = root / "accepted"
            self._make_repository(accepted)
            accepted_sha = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=accepted, text=True
            ).strip()
            result = self._run_authority_gate(accepted, accepted_sha)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_field_installer_must_not_split_git_authority_from_bootstrap_execution(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")

        self.assertNotIn('SOURCE_SHA="$(git rev-parse HEAD |', source)
        self.assertNotIn('[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]]', source)
        self.assertNotIn('"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"', source)
        for required in (
            'GIT_DIR": str(git_dir)',
            'GIT_WORK_TREE": str(root)',
            'GIT_CONFIG_NOSYSTEM": "1"',
            'GIT_CONFIG_GLOBAL": "/dev/null"',
            'GIT_NO_REPLACE_OBJECTS": "1"',
            'index_environment["GIT_INDEX_FILE"] = authority_index',
            'git_bytes("read-tree", expected, environment=index_environment)',
            'git_bytes("ls-tree", "-r", "-z", expected)',
            'hashlib.sha1(',
            'git_bytes("cat-file", "blob", object_id)',
            'tempfile.TemporaryFile(mode="w+b", prefix="nembra-capture-bootstrap-")',
            'f"/dev/fd/{read_descriptor}"',
            'pass_fds=(read_descriptor,)',
            'NEMBRA_CAPTURE_BOOTSTRAP_FD_EXECUTION',
        ):
            self.assertIn(required, source)
        self.assertIn('[[ "${BASH_SOURCE[0]}" == /dev/fd/[0-9]* ]]', bootstrap)
        self.assertIn('BOOTSTRAP_LOGICAL_SOURCE="$0"', bootstrap)
        self.assertIn('unset BOOTSTRAP_LOGICAL_SOURCE NEMBRA_CAPTURE_BOOTSTRAP_FD_EXECUTION', bootstrap)
'''
if test_source.count(static_start) != 1:
    raise SystemExit("diagnostic static source-contract block drifted")
test_source = test_source.replace(static_start, static_replacement, 1)
test_path.write_text(test_source, encoding="utf-8")

workflow_path = Path(".github/workflows/capture-field-build-provenance.yml")
workflow = workflow_path.read_text(encoding="utf-8")
trigger_anchor = "      - scripts/ci/tests/test_capture_field_accepted_source_path_contract.py\n"
if workflow.count(trigger_anchor) != 1:
    raise SystemExit("Field provenance test trigger anchor drifted")
workflow = workflow.replace(
    trigger_anchor,
    trigger_anchor + "      - scripts/ci/tests/test_capture_field_installer_git_authority_red_team.py\n",
    1,
)
validation_anchor = '''          bash -n scripts/field/install_one_time_capture.command
          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_field_accepted_source_path_contract.py
          /usr/bin/python3 scripts/ci/tests/test_capture_field_accepted_source_path_contract.py
'''
validation_replacement = '''          bash -n scripts/field/install_one_time_capture.command
          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_field_accepted_source_path_contract.py
          /usr/bin/python3 scripts/ci/tests/test_capture_field_accepted_source_path_contract.py
          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_field_installer_git_authority_red_team.py
          /usr/bin/python3 scripts/ci/tests/test_capture_field_installer_git_authority_red_team.py
'''
if workflow.count(validation_anchor) != 1:
    raise SystemExit("Field provenance validation anchor drifted")
workflow = workflow.replace(validation_anchor, validation_replacement, 1)
workflow_path.write_text(workflow, encoding="utf-8")

run("bash", "-n", str(installer_path))
run("bash", "-n", str(bootstrap_path))
run("python3", "-m", "py_compile", str(test_path))
run("python3", str(test_path))
run("git", "diff", "--check")

expected_paths = sorted([
    ".github/workflows/capture-field-build-provenance.yml",
    "Scripts/bootstrap_capture_tuya_sdk.sh",
    "scripts/ci/tests/test_capture_field_installer_git_authority_red_team.py",
    "scripts/field/install_one_time_capture.command",
])
actual_paths = sorted(output("git", "diff", "--name-only").decode().splitlines())
if actual_paths != expected_paths:
    raise SystemExit(f"unexpected repair paths: {actual_paths!r}")
