#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GUARD_PATH = ROOT / "Scripts" / "capture_tuya_private_input_build_guard.py"
INSTALLER_PATH = ROOT / "scripts" / "field" / "install_one_time_capture.command"
REGRESSION_PATH = ROOT / "scripts" / "ci" / "tests" / "test_capture_field_tracked_source_compiler_window_authority.py"


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if source.count(old) != 1:
        raise RuntimeError(f"{label}: expected exactly one marker, found {source.count(old)}")
    return source.replace(old, new, 1)


def patch_guard() -> None:
    source = GUARD_PATH.read_text(encoding="utf-8")

    if "from pathlib import Path, PurePosixPath" not in source:
        source = replace_once(
            source,
            "from pathlib import Path\n",
            "from pathlib import Path, PurePosixPath\n",
            "pathlib import",
        )

    if "accepted_source_root: Path | None = None" not in source:
        fields = "    generated_pods: Path | None = None\n    generated_workspace: Path | None = None\n"
        source = replace_once(
            source,
            fields,
            fields + "    accepted_source_root: Path | None = None\n    accepted_source_sha: str | None = None\n",
            "PrivateInputs accepted source fields",
        )

    if "class AcceptedSourceManifest:" not in source:
        marker = "\n\nclass EventBackend(Protocol):\n"
        block = r'''

@dataclass(frozen=True)
class AcceptedSourceEntry:
    relative_path: str
    mode: str
    object_id: str


@dataclass(frozen=True)
class AcceptedSourceManifest:
    root: Path
    source_sha: str
    entries: tuple[AcceptedSourceEntry, ...]


def _accepted_source_git_environment(root: Path) -> dict[str, str]:
    git_dir = root / ".git"
    try:
        metadata = git_dir.lstat()
    except OSError as error:
        raise BuildGuardError("accepted source Git directory is unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise BuildGuardError("accepted source Git directory must be one real directory")
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_DIR": os.fspath(git_dir),
        "GIT_WORK_TREE": os.fspath(root),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "core.worktree",
        "GIT_CONFIG_VALUE_0": os.fspath(root),
        "GIT_CONFIG_KEY_1": "core.bare",
        "GIT_CONFIG_VALUE_1": "false",
    }


def _load_accepted_source_manifest(root: Path, source_sha: str) -> AcceptedSourceManifest:
    authority_root = _lexical_absolute(root)
    try:
        root_metadata = authority_root.lstat()
    except OSError as error:
        raise BuildGuardError("accepted source root disappeared before compiler-window custody") from error
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        raise BuildGuardError("accepted source root must be one real directory")

    normalized_sha = source_sha.lower()
    if len(normalized_sha) != 40 or any(character not in "0123456789abcdef" for character in normalized_sha):
        raise BuildGuardError("accepted source SHA must be exactly 40 hexadecimal characters")

    environment = _accepted_source_git_environment(authority_root)
    try:
        tree = subprocess.check_output(
            ["/usr/bin/git", "ls-tree", "-r", "-z", normalized_sha],
            cwd=authority_root,
            env=environment,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise BuildGuardError("could not load the exact accepted source tree from isolated Git authority") from error

    entries: list[AcceptedSourceEntry] = []
    seen: set[str] = set()
    for record in tree.split(b"\0"):
        if not record:
            continue
        try:
            metadata, relative_raw = record.split(b"\t", 1)
            mode_raw, object_type, object_id_raw = metadata.split(b" ", 2)
        except ValueError as error:
            raise BuildGuardError("accepted source tree contains a malformed Git record") from error
        if object_type != b"blob" or mode_raw not in {b"100644", b"100755", b"120000"}:
            raise BuildGuardError("accepted source tree contains an unsupported tracked object")
        relative = os.fsdecode(relative_raw)
        parts = PurePosixPath(relative).parts
        if not parts or any(part in {"", ".", ".."} for part in parts) or relative.startswith("/"):
            raise BuildGuardError("accepted source tree contains an unsafe tracked path")
        if relative in seen:
            raise BuildGuardError("accepted source tree contains a duplicate tracked path")
        seen.add(relative)
        try:
            object_id = object_id_raw.decode("ascii", errors="strict").lower()
        except UnicodeDecodeError as error:
            raise BuildGuardError("accepted source tree contains a non-ASCII Git blob identity") from error
        if len(object_id) != 40 or any(character not in "0123456789abcdef" for character in object_id):
            raise BuildGuardError("accepted source tree contains a malformed Git blob identity")
        entries.append(
            AcceptedSourceEntry(
                relative_path=relative,
                mode=mode_raw.decode("ascii"),
                object_id=object_id,
            )
        )
    if not entries:
        raise BuildGuardError("accepted source tree contains no tracked blobs")
    return AcceptedSourceManifest(
        root=authority_root,
        source_sha=normalized_sha,
        entries=tuple(entries),
    )


def _tracked_parent_chain(root: Path, relative_path: str) -> tuple[Path, ...]:
    parts = PurePosixPath(relative_path).parts
    current = root
    parents: list[Path] = [root]
    for component in parts[:-1]:
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as error:
            raise BuildGuardError(
                f"accepted tracked-source ancestry disappeared before compiler-window custody: {relative_path}"
            ) from error
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(
                f"accepted tracked-source ancestry must remain real directories: {relative_path}"
            )
        parents.append(current)
    return tuple(parents)


def _regular_file_git_blob_oid(path: Path, relative_path: str) -> tuple[str, int]:
    try:
        before = path.lstat()
    except OSError as error:
        raise BuildGuardError(f"accepted tracked source disappeared: {relative_path}") from error
    if not stat.S_ISREG(before.st_mode) or stat.S_ISLNK(before.st_mode):
        raise BuildGuardError(f"accepted tracked source is not one real regular file: {relative_path}")
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise BuildGuardError(f"accepted tracked source could not be opened safely: {relative_path}") from error
    try:
        opened = os.fstat(descriptor)
        if _stat_identity(before) != _stat_identity(opened):
            raise BuildGuardError(f"accepted tracked source changed while it was opened: {relative_path}")
        digest = hashlib.sha1()
        digest.update(b"blob " + str(opened.st_size).encode("ascii") + b"\0")
        remaining = opened.st_size
        while remaining:
            chunk = os.read(descriptor, min(65_536, remaining))
            if not chunk:
                raise BuildGuardError(f"accepted tracked source changed during descriptor read: {relative_path}")
            digest.update(chunk)
            remaining -= len(chunk)
        final_descriptor = os.fstat(descriptor)
        if _stat_identity(opened) != _stat_identity(final_descriptor):
            raise BuildGuardError(f"accepted tracked source changed during descriptor custody: {relative_path}")
    finally:
        os.close(descriptor)
    try:
        after = path.lstat()
    except OSError as error:
        raise BuildGuardError(f"accepted tracked source disappeared after descriptor read: {relative_path}") from error
    if _stat_identity(before) != _stat_identity(after):
        raise BuildGuardError(f"accepted tracked source pathname changed during verification: {relative_path}")
    return digest.hexdigest(), after.st_mode


def _symlink_git_blob_oid(path: Path, relative_path: str) -> str:
    try:
        before = path.lstat()
    except OSError as error:
        raise BuildGuardError(f"accepted tracked symlink disappeared: {relative_path}") from error
    if not stat.S_ISLNK(before.st_mode):
        raise BuildGuardError(f"accepted tracked source is not the expected symlink: {relative_path}")
    try:
        payload = os.readlink(path)
    except OSError as error:
        raise BuildGuardError(f"accepted tracked symlink could not be read: {relative_path}") from error
    payload_bytes = os.fsencode(payload) if isinstance(payload, str) else payload
    try:
        after = path.lstat()
    except OSError as error:
        raise BuildGuardError(f"accepted tracked symlink disappeared during verification: {relative_path}") from error
    if _stat_identity(before) != _stat_identity(after):
        raise BuildGuardError(f"accepted tracked symlink changed during verification: {relative_path}")
    return hashlib.sha1(
        b"blob " + str(len(payload_bytes)).encode("ascii") + b"\0" + payload_bytes
    ).hexdigest()


def _verify_accepted_source_manifest(manifest: AcceptedSourceManifest) -> None:
    for entry in manifest.entries:
        _tracked_parent_chain(manifest.root, entry.relative_path)
        path = manifest.root.joinpath(*PurePosixPath(entry.relative_path).parts)
        if entry.mode == "120000":
            actual_object_id = _symlink_git_blob_oid(path, entry.relative_path)
        else:
            actual_object_id, actual_mode = _regular_file_git_blob_oid(path, entry.relative_path)
            expected_executable = entry.mode == "100755"
            actual_executable = bool(actual_mode & 0o111)
            if actual_executable != expected_executable:
                raise BuildGuardError(
                    f"accepted tracked source executable mode changed: {entry.relative_path}"
                )
        if not hmac.compare_digest(actual_object_id, entry.object_id):
            raise BuildGuardError(
                f"accepted tracked source bytes no longer match the accepted Git tree: {entry.relative_path}"
            )


def _accepted_source_watch_paths(manifest: AcceptedSourceManifest) -> tuple[Path, ...]:
    paths: set[Path] = {manifest.root}
    for entry in manifest.entries:
        parents = _tracked_parent_chain(manifest.root, entry.relative_path)
        paths.update(parents)
        if entry.mode != "120000":
            paths.add(manifest.root.joinpath(*PurePosixPath(entry.relative_path).parts))
    return tuple(sorted(paths, key=lambda item: str(item)))
'''
        source = replace_once(source, marker, block + marker, "accepted source helper block")

    if "accepted_source_manifest: AcceptedSourceManifest | None = None" not in source:
        old = "    initial_snapshot = inputs.generation_snapshot()\n    watch_paths = _watch_paths(inputs)\n    _ensure_fd_budget(len(watch_paths))\n"
        new = """    accepted_source_manifest: AcceptedSourceManifest | None = None
    if (inputs.accepted_source_root is None) != (inputs.accepted_source_sha is None):
        raise BuildGuardError("accepted source compiler-window custody requires both root and SHA")
    if inputs.accepted_source_root is not None and inputs.accepted_source_sha is not None:
        accepted_source_manifest = _load_accepted_source_manifest(
            inputs.accepted_source_root, inputs.accepted_source_sha
        )
        _verify_accepted_source_manifest(accepted_source_manifest)

    initial_snapshot = inputs.generation_snapshot()
    watch_path_set = set(_watch_paths(inputs))
    if accepted_source_manifest is not None:
        watch_path_set.update(_accepted_source_watch_paths(accepted_source_manifest))
    watch_paths = tuple(sorted(watch_path_set, key=lambda item: str(item)))
    _ensure_fd_budget(len(watch_paths))
"""
        source = replace_once(source, old, new, "run_guarded_build watch set")

    armed_old = """        if require_accepted_private_review_commitment:
            _verify_accepted_private_review_commitment(inputs)
        queued = backend.events(0)
"""
    armed_new = """        if require_accepted_private_review_commitment:
            _verify_accepted_private_review_commitment(inputs)
        if accepted_source_manifest is not None:
            _verify_accepted_source_manifest(accepted_source_manifest)
        queued = backend.events(0)
"""
    if source.count("_verify_accepted_source_manifest(accepted_source_manifest)") < 2:
        source = replace_once(source, armed_old, armed_new, "armed accepted-source reproof")

    final_old = """        if require_accepted_private_review_commitment:
            _verify_accepted_private_review_commitment(inputs)
        trailing = backend.events(0)
"""
    final_new = """        if require_accepted_private_review_commitment:
            _verify_accepted_private_review_commitment(inputs)
        if accepted_source_manifest is not None:
            _verify_accepted_source_manifest(accepted_source_manifest)
        trailing = backend.events(0)
"""
    if source.count("_verify_accepted_source_manifest(accepted_source_manifest)") < 3:
        source = replace_once(source, final_old, final_new, "final accepted-source reproof")

    if 'parser.add_argument("--accepted-source-root"' not in source:
        marker = '    parser.add_argument("--identity-sources", required=True, type=Path)\n'
        source = replace_once(
            source,
            marker,
            marker + '    parser.add_argument("--accepted-source-root", required=True, type=Path)\n    parser.add_argument("--accepted-source-sha", required=True)\n',
            "accepted source CLI",
        )

    if "accepted_source_root = _lexical_absolute(args.accepted_source_root)" not in source:
        marker = "    lockfile = _lexical_absolute(args.lockfile)\n    root = lockfile.parent\n"
        source = replace_once(
            source,
            marker,
            marker + "    accepted_source_root = _lexical_absolute(args.accepted_source_root)\n    if accepted_source_root != root:\n        raise BuildGuardError(\"accepted source root must exactly match the field-build checkout root\")\n    accepted_source_sha = args.accepted_source_sha.lower()\n",
            "accepted source CLI root binding",
        )

    if "accepted_source_root=accepted_source_root" not in source:
        marker = '            generated_pods=root / "Pods",\n            generated_workspace=root / "NembraCapture.xcworkspace",\n'
        source = replace_once(
            source,
            marker,
            marker + "            accepted_source_root=accepted_source_root,\n            accepted_source_sha=accepted_source_sha,\n",
            "PrivateInputs accepted source construction",
        )

    old_main = """def main(argv: Sequence[str] | None = None) -> int:
    inputs, command = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        return run_guarded_build(
"""
    if old_main in source:
        source = source.replace(
            old_main,
            """def main(argv: Sequence[str] | None = None) -> int:
    try:
        inputs, command = _parse_args(sys.argv[1:] if argv is None else argv)
        return run_guarded_build(
""",
            1,
        )

    if "KQ_NOTE_ATTRIB" not in source:
        raise RuntimeError("moved-base vnode attribute custody was lost")
    if source.count("_verify_accepted_source_manifest(accepted_source_manifest)") < 3:
        raise RuntimeError("accepted source must be proved before arm, after arm, and after build")
    GUARD_PATH.write_text(source, encoding="utf-8")


def patch_installer() -> None:
    source = INSTALLER_PATH.read_text(encoding="utf-8")
    if '--accepted-source-root "$ROOT"' not in source:
        marker = 'run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE" \\\n'
        replacement = marker + '    --accepted-source-root "$ROOT" \\\n    --accepted-source-sha "$SOURCE_SHA" \\\n'
        source = replace_once(source, marker, replacement, "field guard accepted source invocation")
    INSTALLER_PATH.write_text(source, encoding="utf-8")


REGRESSION = r'''#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
GUARD_PATH = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
SPEC = importlib.util.spec_from_file_location("capture_build_guard", GUARD_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Capture build guard")
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class CaptureFieldTrackedSourceCompilerWindowAuthorityTests(unittest.TestCase):
    def make_repo(self) -> tuple[tempfile.TemporaryDirectory[str], Path, str]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        subprocess.run(["/usr/bin/git", "init", "-q", str(root)], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "nembra@example.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Test"], check=True)
        (root / "Sources").mkdir()
        (root / "Sources" / "Capture.swift").write_text("let authority = \"accepted\"\n", encoding="utf-8")
        (root / "Scripts").mkdir()
        (root / "Scripts" / "alias").symlink_to("../Sources/Capture.swift")
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted"], check=True)
        sha = subprocess.check_output(["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
        return temporary, root, sha

    def test_installer_binds_exact_source_to_guarded_compiler_window(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        guard_source = GUARD_PATH.read_text(encoding="utf-8")
        start = installer.index('say "Building SDK-integrated Nembra Capture for the intended iPhone"')
        end = installer.index('verify_private_tuya_inputs\nverify_accepted_checkout_source', start)
        window = installer[start:end]
        self.assertIn('--accepted-source-root "$ROOT"', window)
        self.assertIn('--accepted-source-sha "$SOURCE_SHA"', window)
        self.assertIn("accepted_source_root", guard_source)
        self.assertIn("accepted_source_sha", guard_source)
        self.assertIn("GIT_NO_REPLACE_OBJECTS", guard_source)
        self.assertIn("KQ_NOTE_ATTRIB", guard_source)
        self.assertGreaterEqual(guard_source.count("_verify_accepted_source_manifest(accepted_source_manifest)"), 3)

    def test_manifest_is_stable_across_mutate_restore(self) -> None:
        temporary, root, sha = self.make_repo()
        try:
            manifest = guard._load_accepted_source_manifest(root, sha)
            guard._verify_accepted_source_manifest(manifest)
            source = root / "Sources" / "Capture.swift"
            accepted = source.read_bytes()
            source.write_text("let authority = \"attacker\"\n", encoding="utf-8")
            with self.assertRaises(guard.BuildGuardError):
                guard._verify_accepted_source_manifest(manifest)
            source.write_bytes(accepted)
            guard._verify_accepted_source_manifest(manifest)
        finally:
            temporary.cleanup()

    def test_watch_set_covers_tracked_files_and_symlink_parent(self) -> None:
        temporary, root, sha = self.make_repo()
        try:
            manifest = guard._load_accepted_source_manifest(root, sha)
            watched = set(guard._accepted_source_watch_paths(manifest))
            self.assertIn(root, watched)
            self.assertIn(root / "Sources", watched)
            self.assertIn(root / "Sources" / "Capture.swift", watched)
            self.assertIn(root / "Scripts", watched)
            self.assertNotIn(root / "Scripts" / "alias", watched)
            alias = root / "Scripts" / "alias"
            alias.unlink()
            alias.symlink_to("../Sources/Other.swift")
            with self.assertRaises(guard.BuildGuardError):
                guard._verify_accepted_source_manifest(manifest)
        finally:
            temporary.cleanup()

    def test_manifest_rejects_wrong_sha_and_executable_mode_drift(self) -> None:
        temporary, root, sha = self.make_repo()
        try:
            with self.assertRaises(guard.BuildGuardError):
                guard._load_accepted_source_manifest(root, "0" * 39)
            manifest = guard._load_accepted_source_manifest(root, sha)
            source = root / "Sources" / "Capture.swift"
            source.chmod(source.stat().st_mode | 0o111)
            with self.assertRaises(guard.BuildGuardError):
                guard._verify_accepted_source_manifest(manifest)
        finally:
            temporary.cleanup()


if __name__ == "__main__":
    unittest.main(verbosity=2)
'''


def main() -> None:
    patch_guard()
    patch_installer()
    REGRESSION_PATH.write_text(REGRESSION, encoding="utf-8")


if __name__ == "__main__":
    main()
