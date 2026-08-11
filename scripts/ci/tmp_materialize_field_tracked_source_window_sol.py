#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
REGRESSION = ROOT / "scripts/ci/tests/test_capture_field_tracked_source_window_authority.py"
BRANCH = "repair/v14-field-tracked-source-window-sol-20260811"
EXPECTED_GUARD_BLOB = "c0566bfca7f4065509e778b862a39e063610c5e6"
EXPECTED_INSTALLER_BLOB = "1de3da06ea6214d9e9b8ca5ce1231ada0a4fc814"


def run(*argv: str) -> str:
    return subprocess.check_output(argv, cwd=ROOT, text=True).strip()


def require_blob(path: Path, expected: str) -> None:
    actual = run("git", "hash-object", path.relative_to(ROOT).as_posix())
    if actual != expected:
        raise SystemExit(f"refusing stale materialization for {path}: {actual} != {expected}")


require_blob(GUARD, EXPECTED_GUARD_BLOB)
require_blob(INSTALLER, EXPECTED_INSTALLER_BLOB)

guard = GUARD.read_text(encoding="utf-8")

old_import = "from pathlib import Path\n"
if guard.count(old_import) != 1:
    raise SystemExit("guard pathlib import contract drifted")
guard = guard.replace(old_import, "from pathlib import Path, PurePosixPath\n", 1)

old_private_fields = '''    generated_pods: Path | None = None\n    generated_workspace: Path | None = None\n'''
new_private_fields = '''    generated_pods: Path | None = None\n    generated_workspace: Path | None = None\n    accepted_source_root: Path | None = None\n    accepted_source_sha: str | None = None\n'''
if guard.count(old_private_fields) != 1:
    raise SystemExit("PrivateInputs field contract drifted")
guard = guard.replace(old_private_fields, new_private_fields, 1)

old_required = '''            "KQ_NOTE_LINK",\n            "KQ_NOTE_RENAME",\n'''
new_required = '''            "KQ_NOTE_LINK",\n            "KQ_NOTE_ATTRIB",\n            "KQ_NOTE_RENAME",\n'''
if guard.count(old_required) != 1:
    raise SystemExit("kqueue required-flags contract drifted")
guard = guard.replace(old_required, new_required, 1)

old_flags = '''            | select.KQ_NOTE_LINK\n            | select.KQ_NOTE_RENAME\n'''
new_flags = '''            | select.KQ_NOTE_LINK\n            | select.KQ_NOTE_ATTRIB\n            | select.KQ_NOTE_RENAME\n'''
if guard.count(old_flags) != 1:
    raise SystemExit("kqueue fflags contract drifted")
guard = guard.replace(old_flags, new_flags, 1)

helper_anchor = '''def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:\n'''
helpers = r'''@dataclass(frozen=True)
class AcceptedTrackedSource:
    path: Path
    expected_oid: str
    expected_executable: bool


def _accepted_source_git_output(root: Path, *arguments: str) -> bytes:
    authority_root = _lexical_absolute(root)
    git_dir = authority_root / ".git"
    try:
        metadata = git_dir.lstat()
    except OSError as error:
        raise BuildGuardError("accepted source Git directory is unavailable during build-window admission") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise BuildGuardError("accepted source Git authority must be one real checkout .git directory")
    environment = {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }
    command = [
        "/usr/bin/git",
        f"--git-dir={git_dir}",
        f"--work-tree={authority_root}",
        "-c", "core.fsmonitor=false",
        "-c", "core.ignorestat=false",
        "-c", "core.filemode=true",
        *arguments,
    ]
    try:
        return subprocess.check_output(
            command,
            cwd=authority_root,
            env=environment,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError as error:
        raise BuildGuardError("accepted source Git authority could not answer build-window admission") from error


def _tracked_blob_identity(path: Path) -> tuple[str, bool]:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        before_lstat = path.lstat()
        descriptor = os.open(path, flags)
    except OSError as error:
        raise BuildGuardError(f"accepted tracked source could not be opened: {path}") from error
    try:
        before = os.fstat(descriptor)
        if _stat_identity(before_lstat) != _stat_identity(before):
            raise BuildGuardError(f"accepted tracked source changed while descriptor custody armed: {path}")
        if not stat.S_ISREG(before.st_mode) or before.st_nlink < 1:
            raise BuildGuardError(f"accepted tracked source is not one regular file: {path}")
        digest = hashlib.sha1(
            b"blob " + str(before.st_size).encode("ascii") + b"\0"
        )
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(65_536, remaining))
            if not chunk:
                raise BuildGuardError(f"accepted tracked source changed during read: {path}")
            digest.update(chunk)
            remaining -= len(chunk)
        if os.read(descriptor, 1):
            raise BuildGuardError(f"accepted tracked source grew during read: {path}")
        after = os.fstat(descriptor)
        if _stat_identity(before) != _stat_identity(after):
            raise BuildGuardError(f"accepted tracked source changed during descriptor read: {path}")
        executable = bool(after.st_mode & 0o111)
        return digest.hexdigest(), executable
    finally:
        os.close(descriptor)


def _accepted_tracked_source_manifest(root: Path, source_sha: str) -> tuple[AcceptedTrackedSource, ...]:
    authority_root = _lexical_absolute(root)
    try:
        root_metadata = authority_root.lstat()
    except OSError as error:
        raise BuildGuardError("accepted source root disappeared before build-window admission") from error
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        raise BuildGuardError("accepted source root must be one real directory")

    normalized_sha = source_sha.lower()
    if len(normalized_sha) != 40 or any(character not in "0123456789abcdef" for character in normalized_sha):
        raise BuildGuardError("accepted source SHA must be exactly 40 lowercase/uppercase hex characters")
    object_type = _accepted_source_git_output(authority_root, "cat-file", "-t", normalized_sha).strip()
    if object_type != b"commit":
        raise BuildGuardError("accepted source SHA must name one commit object")
    resolved = _accepted_source_git_output(
        authority_root, "rev-parse", f"{normalized_sha}^{{commit}}"
    ).strip().decode("ascii", errors="strict")
    if resolved != normalized_sha:
        raise BuildGuardError("accepted source commit identity changed during build-window admission")

    tree = _accepted_source_git_output(authority_root, "ls-tree", "-r", "-z", normalized_sha)
    manifest: list[AcceptedTrackedSource] = []
    seen: set[str] = set()
    for record in tree.split(b"\0"):
        if not record:
            continue
        try:
            metadata, relative_raw = record.split(b"\t", 1)
            mode_raw, object_type_raw, expected_oid_raw = metadata.split(b" ", 2)
        except ValueError as error:
            raise BuildGuardError("accepted source tree contains malformed ls-tree output") from error
        if object_type_raw != b"blob" or mode_raw not in {b"100644", b"100755"}:
            raise BuildGuardError(
                "physical field build refuses tracked symlink/submodule/non-regular source subjects"
            )
        expected_oid = expected_oid_raw.decode("ascii", errors="strict")
        if len(expected_oid) != 40 or any(character not in "0123456789abcdef" for character in expected_oid):
            raise BuildGuardError("accepted tracked source blob identity is malformed")
        relative = os.fsdecode(relative_raw)
        pure = PurePosixPath(relative)
        if pure.is_absolute() or not pure.parts or any(part in {"", ".", ".."} for part in pure.parts):
            raise BuildGuardError("accepted source tree contains an unsafe tracked path")
        if relative in seen:
            raise BuildGuardError("accepted source tree contains a duplicate tracked path")
        seen.add(relative)
        path = _require_real_checkout_ancestry(
            authority_root.joinpath(*pure.parts),
            authority_root,
            label="accepted tracked source",
        )
        actual_oid, actual_executable = _tracked_blob_identity(path)
        expected_executable = mode_raw == b"100755"
        if not hmac.compare_digest(actual_oid, expected_oid):
            raise BuildGuardError(f"accepted tracked source blob mismatch before xcodebuild: {relative}")
        if actual_executable != expected_executable:
            raise BuildGuardError(f"accepted tracked source executable mode mismatch before xcodebuild: {relative}")
        manifest.append(
            AcceptedTrackedSource(
                path=path,
                expected_oid=expected_oid,
                expected_executable=expected_executable,
            )
        )
    if not manifest:
        raise BuildGuardError("accepted source tree contains no tracked regular files")
    return tuple(manifest)


def _verify_tracked_source_manifest(manifest: Sequence[AcceptedTrackedSource]) -> None:
    for item in manifest:
        actual_oid, actual_executable = _tracked_blob_identity(item.path)
        if not hmac.compare_digest(actual_oid, item.expected_oid):
            raise BuildGuardError(f"accepted tracked source changed across xcodebuild custody: {item.path}")
        if actual_executable != item.expected_executable:
            raise BuildGuardError(f"accepted tracked source mode changed across xcodebuild custody: {item.path}")


def _tracked_source_watch_paths(
    manifest: Sequence[AcceptedTrackedSource], repository_root: Path
) -> tuple[Path, ...]:
    authority_root = _lexical_absolute(repository_root)
    paths: set[Path] = {authority_root}
    for item in manifest:
        admitted = _require_real_checkout_ancestry(
            item.path, authority_root, label="accepted tracked source watch subject"
        )
        paths.add(admitted)
        _add_parent_watch_chain(paths, admitted, repository_root=authority_root)
    return tuple(sorted(paths, key=lambda item: str(item)))


'''
if guard.count(helper_anchor) != 1 or "def _accepted_tracked_source_manifest" in guard:
    raise SystemExit("tracked-source helper insertion contract drifted")
guard = guard.replace(helper_anchor, helpers + helper_anchor, 1)

old_signature = '''    require_accepted_generated_subject: bool = False,\n    require_accepted_private_review_commitment: bool = False,\n    require_accepted_authority_helpers: bool = False,\n) -> int:\n'''
new_signature = '''    require_accepted_generated_subject: bool = False,\n    require_accepted_private_review_commitment: bool = False,\n    require_accepted_authority_helpers: bool = False,\n    require_accepted_tracked_source: bool = False,\n) -> int:\n'''
if guard.count(old_signature) != 1:
    raise SystemExit("run_guarded_build signature drifted")
guard = guard.replace(old_signature, new_signature, 1)

old_authority = '''    if accepted_authority_requested:\n        provenance.require_accepted()\n        generated_build.require_accepted()\n\n    if require_accepted_generated_subject:\n'''
new_authority = '''    if accepted_authority_requested:\n        provenance.require_accepted()\n        generated_build.require_accepted()\n\n    tracked_manifest: tuple[AcceptedTrackedSource, ...] = ()\n    if require_accepted_tracked_source:\n        if inputs.accepted_source_root is None or inputs.accepted_source_sha is None:\n            raise BuildGuardError("accepted tracked source root/SHA are required for physical xcodebuild custody")\n        tracked_manifest = _accepted_tracked_source_manifest(\n            inputs.accepted_source_root, inputs.accepted_source_sha\n        )\n\n    if require_accepted_generated_subject:\n'''
if guard.count(old_authority) != 1:
    raise SystemExit("run_guarded_build authority seam drifted")
guard = guard.replace(old_authority, new_authority, 1)

old_watch = '''    initial_snapshot = inputs.generation_snapshot()\n    watch_paths = _watch_paths(inputs)\n    _ensure_fd_budget(len(watch_paths))\n'''
new_watch = '''    initial_snapshot = inputs.generation_snapshot()\n    watch_paths = set(_watch_paths(inputs))\n    if tracked_manifest:\n        watch_paths.update(\n            _tracked_source_watch_paths(tracked_manifest, inputs.accepted_source_root)  # type: ignore[arg-type]\n        )\n    ordered_watch_paths = tuple(sorted(watch_paths, key=lambda item: str(item)))\n    _ensure_fd_budget(len(ordered_watch_paths))\n'''
if guard.count(old_watch) != 1:
    raise SystemExit("watch set construction seam drifted")
guard = guard.replace(old_watch, new_watch, 1)

guard = guard.replace(
    "        watched = _open_watched_inputs(watch_paths, backend)\n\n        armed_snapshot = inputs.generation_snapshot()\n",
    "        watched = _open_watched_inputs(ordered_watch_paths, backend)\n\n        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n        armed_snapshot = inputs.generation_snapshot()\n",
    1,
)

old_final = '''        final_snapshot = inputs.generation_snapshot()\n        if final_snapshot != initial_snapshot:\n            raise BuildGuardError("build inputs changed across the guarded xcodebuild window")\n'''
new_final = '''        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n        final_snapshot = inputs.generation_snapshot()\n        if final_snapshot != initial_snapshot:\n            raise BuildGuardError("build inputs changed across the guarded xcodebuild window")\n'''
if guard.count(old_final) != 1:
    raise SystemExit("final verification seam drifted")
guard = guard.replace(old_final, new_final, 1)

old_parser_args = '''    parser.add_argument("--identity-sources", required=True, type=Path)\n    parser.add_argument("command", nargs=argparse.REMAINDER)\n'''
new_parser_args = '''    parser.add_argument("--identity-sources", required=True, type=Path)\n    parser.add_argument("--accepted-source-root", type=Path)\n    parser.add_argument("--accepted-source-sha")\n    parser.add_argument("command", nargs=argparse.REMAINDER)\n'''
if guard.count(old_parser_args) != 1:
    raise SystemExit("parser argument seam drifted")
guard = guard.replace(old_parser_args, new_parser_args, 1)

old_identity_parse = '''    identity_sources = _require_real_checkout_ancestry(\n        args.identity_sources, root, label="private identity source tree"\n    )\n\n    return (\n'''
new_identity_parse = '''    identity_sources = _require_real_checkout_ancestry(\n        args.identity_sources, root, label="private identity source tree"\n    )\n    accepted_source_root: Path | None = None\n    accepted_source_sha: str | None = None\n    if (args.accepted_source_root is None) != (args.accepted_source_sha is None):\n        raise BuildGuardError("accepted source root and SHA must be supplied together")\n    if args.accepted_source_root is not None and args.accepted_source_sha is not None:\n        accepted_source_root = _require_real_checkout_ancestry(\n            args.accepted_source_root, root, label="accepted source root"\n        )\n        if accepted_source_root != root:\n            raise BuildGuardError("accepted source root must equal the field checkout root")\n        accepted_source_sha = args.accepted_source_sha.lower()\n\n    return (\n'''
if guard.count(old_identity_parse) != 1:
    raise SystemExit("parser source authority seam drifted")
guard = guard.replace(old_identity_parse, new_identity_parse, 1)

old_fields = '''            generated_pods=root / "Pods",\n            generated_workspace=root / "NembraCapture.xcworkspace",\n        ),\n'''
new_fields = '''            generated_pods=root / "Pods",\n            generated_workspace=root / "NembraCapture.xcworkspace",\n            accepted_source_root=accepted_source_root,\n            accepted_source_sha=accepted_source_sha,\n        ),\n'''
if guard.count(old_fields) != 1:
    raise SystemExit("PrivateInputs parser construction drifted")
guard = guard.replace(old_fields, new_fields, 1)

old_main = '''            require_accepted_generated_subject=True,\n            require_accepted_private_review_commitment=True,\n            require_accepted_authority_helpers=True,\n        )\n'''
new_main = '''            require_accepted_generated_subject=True,\n            require_accepted_private_review_commitment=True,\n            require_accepted_authority_helpers=True,\n            require_accepted_tracked_source=True,\n        )\n'''
if guard.count(old_main) != 1:
    raise SystemExit("physical guard main contract drifted")
guard = guard.replace(old_main, new_main, 1)

GUARD.write_text(guard, encoding="utf-8")

installer = INSTALLER.read_text(encoding="utf-8")
old_invocation = '''run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE" \\\n    --lockfile "$ROOT/Podfile.lock" \\\n'''
new_invocation = '''run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE" \\\n    --accepted-source-root "$ROOT" \\\n    --accepted-source-sha "$SOURCE_SHA" \\\n    --lockfile "$ROOT/Podfile.lock" \\\n'''
if installer.count(old_invocation) != 1:
    raise SystemExit("field guard invocation seam drifted")
INSTALLER.write_text(installer.replace(old_invocation, new_invocation, 1), encoding="utf-8")

subprocess.run(["/usr/bin/python3", "-m", "py_compile", str(GUARD), str(REGRESSION)], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/python3", str(REGRESSION)], cwd=ROOT, check=True)
subprocess.run(["/bin/bash", "-n", str(INSTALLER)], cwd=ROOT, check=True)
subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)

for marker in (
    "def _accepted_tracked_source_manifest",
    "def _verify_tracked_source_manifest",
    "def _tracked_source_watch_paths",
    "require_accepted_tracked_source=True",
    "KQ_NOTE_ATTRIB",
):
    if marker not in GUARD.read_text(encoding="utf-8"):
        raise SystemExit(f"missing tracked-source custody marker: {marker}")
for marker in ('--accepted-source-root "$ROOT"', '--accepted-source-sha "$SOURCE_SHA"'):
    if marker not in INSTALLER.read_text(encoding="utf-8"):
        raise SystemExit(f"missing field installer tracked-source marker: {marker}")

subprocess.run(
    [
        "git", "add",
        "Scripts/capture_tuya_private_input_build_guard.py",
        "scripts/field/install_one_time_capture.command",
    ],
    cwd=ROOT,
    check=True,
)
subprocess.run(["git", "diff", "--cached", "--check"], cwd=ROOT, check=True)
subprocess.run(["git", "config", "user.name", "nembra-sol-bot"], cwd=ROOT, check=True)
subprocess.run(["git", "config", "user.email", "nembra-sol-bot@users.noreply.github.com"], cwd=ROOT, check=True)
subprocess.run(["git", "commit", "-m", "Guard accepted tracked source through xcodebuild"], cwd=ROOT, check=True)
subprocess.run(["git", "push", "origin", f"HEAD:{BRANCH}"], cwd=ROOT, check=True)
