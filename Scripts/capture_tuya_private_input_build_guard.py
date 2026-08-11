#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import hmac
import importlib.util
import os
import pwd
import resource
import select
import stat
import subprocess
import sys
import types
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Callable, Iterable, Protocol, Sequence


class BuildGuardError(RuntimeError):
    pass


def _stat_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid, metadata.st_gid, metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns)


def _load_neighbor_module(filename: str, module_name: str):
    helper = Path(__file__).with_name(filename)
    spec = importlib.util.spec_from_file_location(module_name, helper)
    if spec is None or spec.loader is None:
        raise BuildGuardError(f"required build-custody helper could not be loaded: {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PRIVATE_REVIEW_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"
PROVENANCE_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PROVENANCE_HELPER_SHA256"
GENERATED_BUILD_SUBJECT_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_SUBJECT_HELPER_SHA256"
AUTHORITY_HELPER_MAX_BYTES = 262_144


def _load_accepted_helper_module(filename: str, module_name: str, environment_name: str):
    expected = os.environ.get(environment_name, "").lower()
    if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
        raise BuildGuardError(f"{environment_name} must remain available as exactly 64 hex characters through build-window admission")
    helper = Path(__file__).with_name(filename)
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(helper, flags)
    except OSError as error:
        raise BuildGuardError(f"accepted authority helper could not be opened under descriptor custody: {filename}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise BuildGuardError(f"accepted authority helper is not one regular single-link file: {filename}")
        if before.st_size <= 0 or before.st_size > AUTHORITY_HELPER_MAX_BYTES:
            raise BuildGuardError(f"accepted authority helper size is outside the accepted bound: {filename}")
        chunks: list[bytes] = []
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(65_536, remaining))
            if not chunk:
                raise BuildGuardError(f"accepted authority helper changed during descriptor read: {filename}")
            chunks.append(chunk)
            remaining -= len(chunk)
        source = b"".join(chunks)
        after = os.fstat(descriptor)
        if _stat_identity(before) != _stat_identity(after):
            raise BuildGuardError(f"accepted authority helper changed during descriptor custody: {filename}")
    finally:
        os.close(descriptor)
    actual = hashlib.sha256(source).hexdigest()
    if not hmac.compare_digest(actual, expected):
        raise BuildGuardError(f"accepted authority helper source does not match externally reviewed authority: {filename}")
    module = types.ModuleType(module_name)
    module.__file__ = f"<accepted-{filename}>"
    try:
        exec(compile(source, module.__file__, "exec"), module.__dict__)
    except Exception as error:
        raise BuildGuardError(f"accepted authority helper source could not be loaded: {filename}") from error
    return module


class _AuthorityHelperProxy:
    def __init__(self, filename: str, module_name: str, environment_name: str) -> None:
        self._filename = filename
        self._module_name = module_name
        self._environment_name = environment_name
        self._module = None
        self._accepted = False

    def require_accepted(self):
        self._module = _load_accepted_helper_module(self._filename, self._module_name, self._environment_name)
        self._accepted = True
        return self._module

    def __getattr__(self, name: str):
        if self._module is None:
            # Compatibility only for isolated package/unit callers. The physical
            # field CLI requires accepted authority helpers before any access.
            self._module = _load_neighbor_module(self._filename, self._module_name)
        return getattr(self._module, name)


provenance = _AuthorityHelperProxy(
    "capture_tuya_private_input_provenance.py",
    "capture_tuya_private_input_provenance",
    PROVENANCE_HELPER_ENV,
)
generated_build = _AuthorityHelperProxy(
    "capture_cocoapods_generated_build_subject.py",
    "capture_cocoapods_generated_build_subject",
    GENERATED_BUILD_SUBJECT_HELPER_ENV,
)


def _load_accepted_private_review_module():
    return _load_accepted_helper_module(
        "capture_private_review_commitment.py",
        "capture_private_review_commitment_accepted",
        PRIVATE_REVIEW_HELPER_ENV,
    )


@dataclass(frozen=True)
class PrivateInputs:
    lockfile: Path
    security_podspec: Path
    security_build: Path
    identity_podspec: Path
    identity_sources: Path
    generated_pods: Path | None = None
    generated_workspace: Path | None = None
    accepted_source_root: Path | None = None
    accepted_source_sha: str | None = None

    @property
    def private_provenance_record(self) -> Path:
        return self.identity_podspec.parent / "ResolvedTuyaDependencyProvenance.txt"

    @property
    def private_review_key(self) -> Path:
        return self.identity_podspec.parent / "PrivateReviewCommitment.key"

    def generated_build_subject(self) -> str:
        if self.generated_pods is None or self.generated_workspace is None:
            raise BuildGuardError("generated CocoaPods build inputs were not supplied to field-build custody")
        return generated_build.build_subject(
            lockfile=self.lockfile,
            pods=self.generated_pods,
            workspace=self.generated_workspace,
        )

    def generation_snapshot(self):
        private_snapshot = provenance._private_input_record_generation_snapshot(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )
        if self.generated_pods is None or self.generated_workspace is None:
            # Direct package/unit callers from the pre-generated-graph contract
            # retain their old private-only behavior. The real field CLI always
            # supplies both generated roots below and therefore cannot use this.
            return (private_snapshot,)
        return (private_snapshot, self.generated_build_subject())


class EventBackend(Protocol):
    def register(self, descriptor: int) -> None: ...
    def events(self, timeout: float) -> Sequence[object]: ...
    def close(self) -> None: ...


class KqueueVnodeBackend:
    """macOS vnode watcher used only for the physical field-build window."""

    def __init__(self) -> None:
        required = (
            "kqueue",
            "kevent",
            "KQ_FILTER_VNODE",
            "KQ_EV_ADD",
            "KQ_EV_ENABLE",
            "KQ_EV_CLEAR",
            "KQ_NOTE_DELETE",
            "KQ_NOTE_WRITE",
            "KQ_NOTE_EXTEND",
            "KQ_NOTE_LINK",
            "KQ_NOTE_ATTRIB",
            "KQ_NOTE_RENAME",
            "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing:
            raise BuildGuardError(
                "macOS kqueue vnode monitoring is unavailable: " + ", ".join(missing)
            )
        self._queue = select.kqueue()
        self._fflags = (
            select.KQ_NOTE_DELETE
            | select.KQ_NOTE_WRITE
            | select.KQ_NOTE_EXTEND
            | select.KQ_NOTE_LINK
            | select.KQ_NOTE_ATTRIB
            | select.KQ_NOTE_RENAME
            | select.KQ_NOTE_REVOKE
        )

    def register(self, descriptor: int) -> None:
        event = select.kevent(
            descriptor,
            filter=select.KQ_FILTER_VNODE,
            flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
            fflags=self._fflags,
        )
        self._queue.control([event], 0, 0)

    def events(self, timeout: float) -> Sequence[object]:
        return self._queue.control(None, 256, timeout)

    def close(self) -> None:
        self._queue.close()


def _lstat_identity(path: Path) -> tuple[int, ...]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise BuildGuardError(f"build input disappeared before vnode admission: {path}") from error
    return _stat_identity(metadata)


def _add_parent_watch_chain(paths: set[Path], path: Path, *, repository_root: Path) -> None:
    """Watch lexical parents so a whole admitted subtree cannot be swapped by rename."""

    current = path.parent
    while True:
        paths.add(current)
        if current == repository_root:
            return
        if current == current.parent or repository_root not in current.parents:
            raise BuildGuardError(
                f"build input escapes the accepted checkout parent chain: {path}"
            )
        current = current.parent


def _add_tree_watch_paths(paths: set[Path], root: Path, *, label: str) -> None:
    if not root.is_dir() or root.is_symlink():
        raise BuildGuardError(f"{label} is not one real directory: {root}")
    paths.add(root)
    for current_root, directories, files in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_root)
        paths.add(current)
        for name in directories:
            candidate = current / name
            if candidate.is_symlink():
                continue
            paths.add(candidate)
        for name in files:
            candidate = current / name
            if candidate.is_symlink():
                continue
            paths.add(candidate)


def _lexical_absolute(path: Path) -> Path:
    """Normalize spelling without resolving away a mutable ancestor selector."""

    return Path(os.path.abspath(os.fspath(path.expanduser())))


def _require_real_checkout_ancestry(path: Path, root: Path, *, label: str) -> Path:
    """Keep the exact checkout-visible path that xcodebuild may reopen under custody."""

    candidate = _lexical_absolute(path)
    authority_root = _lexical_absolute(root)
    try:
        relative = candidate.relative_to(authority_root)
    except ValueError as error:
        raise BuildGuardError(f"{label} must remain inside the accepted checkout root") from error

    try:
        root_metadata = authority_root.lstat()
    except OSError as error:
        raise BuildGuardError("accepted checkout root disappeared before build-window custody") from error
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        raise BuildGuardError("accepted checkout root must be one real directory")

    current = authority_root
    for component in relative.parts:
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as error:
            raise BuildGuardError(
                f"{label} path ancestry disappeared before build-window custody: {current}"
            ) from error
        if stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(f"{label} path ancestry must not contain symlinks: {current}")
    return candidate


@dataclass(frozen=True)
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



def _accepted_source_field_allowlist(inputs: object, repository_root: Path) -> tuple[set[str], set[str], set[str]]:
    """Return only the separately authenticated field-input roots admitted beside Git source."""

    authority_root = _lexical_absolute(repository_root)
    allowed_directories: set[str] = set()
    allowed_files: set[str] = set()

    def relative_if_inside(value: object) -> PurePosixPath | None:
        if value is None:
            return None
        candidate = _lexical_absolute(Path(value))
        try:
            relative = candidate.relative_to(authority_root)
        except ValueError:
            return None
        if not relative.parts:
            return None
        return PurePosixPath(*relative.parts)

    generated_pods = relative_if_inside(getattr(inputs, "generated_pods", None))
    if generated_pods is not None and generated_pods.as_posix() == "Pods":
        allowed_directories.add("Pods")

    generated_workspace = relative_if_inside(getattr(inputs, "generated_workspace", None))
    if generated_workspace is not None and generated_workspace.as_posix() == "NembraCapture.xcworkspace":
        allowed_directories.add("NembraCapture.xcworkspace")

    private_roots: set[str] = set()
    for attribute in (
        "security_podspec",
        "security_build",
        "identity_podspec",
        "identity_sources",
    ):
        private_subject = relative_if_inside(getattr(inputs, attribute, None))
        if (
            private_subject is not None
            and len(private_subject.parts) >= 2
            and private_subject.parts[0] == "LocalSecrets"
        ):
            private_roots.add(PurePosixPath(*private_subject.parts[:2]).as_posix())
    allowed_directories.update(private_roots)

    allowed_directory_ancestors: set[str] = set()
    for relative in allowed_directories:
        pure = PurePosixPath(relative)
        for depth in range(1, len(pure.parts)):
            allowed_directory_ancestors.add(PurePosixPath(*pure.parts[:depth]).as_posix())

    lockfile = relative_if_inside(getattr(inputs, "lockfile", None))
    if lockfile is not None and lockfile.as_posix() == "Podfile.lock":
        allowed_files.add("Podfile.lock")

    return allowed_directories, allowed_directory_ancestors, allowed_files


def _verify_accepted_source_physical_tree(
    inputs: object,
    manifest: Sequence[AcceptedTrackedSource],
    repository_root: Path,
) -> None:
    """Reject pre-armed unexpected checkout paths while vnode custody is already active.

    The outer field installer performs the same ignore-independent raw-tree policy before
    entering this process. This in-guard replay is intentionally later: all accepted
    tracked directory ancestry is already under vnode custody, so an unexpected source
    that existed before watcher registration is caught by inventory while any concurrent
    create/remove/rename is caught by the queued directory event before xcodebuild can be
    accepted.
    """

    authority_root = _lexical_absolute(repository_root)
    tracked_files: set[str] = set()
    tracked_directories: set[str] = set()
    for item in manifest:
        try:
            relative_path = item.path.relative_to(authority_root)
        except ValueError as error:
            raise BuildGuardError("accepted tracked source escaped raw-tree authority") from error
        relative = PurePosixPath(*relative_path.parts)
        if not relative.parts:
            raise BuildGuardError("accepted tracked source has an empty raw-tree path")
        relative_text = relative.as_posix()
        tracked_files.add(relative_text)
        for depth in range(1, len(relative.parts)):
            tracked_directories.add(PurePosixPath(*relative.parts[:depth]).as_posix())

    allowed_directories, allowed_directory_ancestors, allowed_files = _accepted_source_field_allowlist(inputs, authority_root)
    for relative in sorted(allowed_directories):
        candidate = authority_root / relative
        try:
            metadata = candidate.lstat()
        except OSError as error:
            raise BuildGuardError(
                f"accepted field-input directory disappeared during raw-tree admission: {relative}"
            ) from error
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(
                f"accepted field-input allowlist root is not one real directory: {relative}"
            )

    for relative in sorted(allowed_files):
        candidate = authority_root / relative
        try:
            metadata = candidate.lstat()
        except OSError as error:
            raise BuildGuardError(
                f"accepted field-input file disappeared during raw-tree admission: {relative}"
            ) from error
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(
                f"accepted field-input allowlist file is not one real regular file: {relative}"
            )

    seen_tracked_files: set[str] = set()
    seen_tracked_directories: set[str] = set()
    try:
        walk = os.walk(authority_root, topdown=True, followlinks=False)
        for current_raw, directories, files in walk:
            current = Path(current_raw)
            current_metadata = current.lstat()
            if not stat.S_ISDIR(current_metadata.st_mode) or stat.S_ISLNK(current_metadata.st_mode):
                raise BuildGuardError(
                    f"accepted source directory changed type during raw-tree admission: {current}"
                )
            current_relative_path = current.relative_to(authority_root)
            current_relative = PurePosixPath(*current_relative_path.parts)
            if current_relative.parts and current_relative.parts[0] in allowed_directories:
                directories[:] = []
                continue

            for name in list(directories):
                if not current_relative.parts and name == ".git":
                    directories.remove(name)
                    continue
                candidate = current / name
                relative = candidate.relative_to(authority_root).as_posix()
                if relative in allowed_directories:
                    directories.remove(name)
                    continue
                metadata = candidate.lstat()
                if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                    directories.remove(name)
                    raise BuildGuardError(
                        f"unexpected/non-directory accepted-source path before xcodebuild: {relative}"
                    )
                if relative in allowed_directory_ancestors:
                    continue
                if relative not in tracked_directories:
                    directories.remove(name)
                    raise BuildGuardError(
                        f"untracked accepted-source path outside field-input allowlist before xcodebuild: {relative}"
                    )
                seen_tracked_directories.add(relative)

            for name in files:
                candidate = current / name
                relative = candidate.relative_to(authority_root).as_posix()
                metadata = candidate.lstat()
                if relative in tracked_files:
                    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                        raise BuildGuardError(
                            f"accepted tracked source changed type during raw-tree admission: {relative}"
                        )
                    seen_tracked_files.add(relative)
                    continue
                if relative in allowed_files:
                    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                        raise BuildGuardError(
                            f"accepted field-input file changed type during raw-tree admission: {relative}"
                        )
                    continue
                raise BuildGuardError(
                    f"untracked accepted-source path outside field-input allowlist before xcodebuild: {relative}"
                )
    except OSError as error:
        raise BuildGuardError("accepted source raw physical-tree admission could not complete") from error

    if seen_tracked_files != tracked_files:
        missing = sorted(tracked_files - seen_tracked_files)
        raise BuildGuardError(
            "accepted source raw-tree admission did not observe every tracked file: "
            + ", ".join(missing[:8])
        )
    if seen_tracked_directories != tracked_directories:
        missing = sorted(tracked_directories - seen_tracked_directories)
        raise BuildGuardError(
            "accepted source raw-tree admission did not observe every tracked directory: "
            + ", ".join(missing[:8])
        )


def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:
    """Return every real file/directory whose mutation can change admitted build inputs."""

    if (inputs.generated_pods is None) != (inputs.generated_workspace is None):
        raise BuildGuardError("generated CocoaPods custody requires both Pods and workspace roots")

    paths: set[Path] = {
        inputs.lockfile,
        inputs.security_podspec,
        inputs.identity_podspec,
    }
    _add_tree_watch_paths(paths, inputs.security_build, label="private security build input tree")
    _add_tree_watch_paths(paths, inputs.identity_sources, label="private identity source tree")

    # The parent-chain contract is a field-build guarantee. Preserve the
    # pre-existing private-only API for isolated tests/tools that may stage the
    # five original inputs in separate temporary roots; the production CLI below
    # always supplies both generated roots and therefore always receives strict
    # checkout-parent custody plus the external private-review witness/key.
    if inputs.generated_pods is not None and inputs.generated_workspace is not None:
        repository_root = inputs.lockfile.parent
        paths.add(repository_root)
        field_paths = (
            (inputs.lockfile, "dependency lock"),
            (inputs.security_podspec, "private security podspec"),
            (inputs.security_build, "private security build tree"),
            (inputs.identity_podspec, "private identity podspec"),
            (inputs.identity_sources, "private identity source tree"),
            (inputs.private_provenance_record, "private review provenance witness"),
            (inputs.private_review_key, "private review commitment key"),
            (inputs.generated_pods, "generated CocoaPods Pods tree"),
            (inputs.generated_workspace, "generated CocoaPods workspace tree"),
        )
        for path, label in field_paths:
            admitted = _require_real_checkout_ancestry(path, repository_root, label=label)
            paths.add(admitted)
            _add_parent_watch_chain(paths, admitted, repository_root=repository_root)
        _add_tree_watch_paths(paths, inputs.generated_pods, label="generated CocoaPods Pods tree")
        _add_tree_watch_paths(paths, inputs.generated_workspace, label="generated CocoaPods workspace tree")

    return tuple(sorted(paths, key=lambda item: str(item)))


def _current_descriptor_count() -> int:
    try:
        return len(os.listdir("/dev/fd"))
    except OSError:
        return 64


def _ensure_fd_budget(watcher_count: int) -> None:
    """Raise the soft descriptor ceiling for a finite generated Pods watch set."""

    required = _current_descriptor_count() + watcher_count + 64
    try:
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    except (OSError, ValueError) as error:
        raise BuildGuardError("could not read the file-descriptor limit for build custody") from error

    if soft >= required:
        return
    if hard != resource.RLIM_INFINITY and hard < required:
        raise BuildGuardError(
            f"generated build custody needs at least {required} open descriptors, but the hard limit is {hard}"
        )

    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, (required, hard))
        updated_soft, _ = resource.getrlimit(resource.RLIMIT_NOFILE)
    except (OSError, ValueError) as error:
        raise BuildGuardError(
            f"could not raise the file-descriptor limit to {required} for generated build custody"
        ) from error
    if updated_soft < required:
        raise BuildGuardError(
            f"file-descriptor limit remained {updated_soft}; generated build custody requires {required}"
        )


def _open_watched_inputs(paths: Iterable[Path], backend: EventBackend) -> tuple[tuple[int, Path], ...]:
    opened: list[tuple[int, Path]] = []
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        for path in paths:
            before = _lstat_identity(path)
            try:
                descriptor = os.open(path, flags)
            except OSError as error:
                raise BuildGuardError(f"build input could not be opened for build-window custody: {path}") from error
            try:
                after = _stat_identity(os.fstat(descriptor))
                if before != after:
                    raise BuildGuardError(f"build input changed while vnode custody was armed: {path}")
                mode = os.fstat(descriptor).st_mode
                if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                    raise BuildGuardError(f"build input is not a watchable regular file/directory: {path}")
                backend.register(descriptor)
            except Exception:
                os.close(descriptor)
                raise
            opened.append((descriptor, path))
        return tuple(opened)
    except Exception:
        for descriptor, _ in opened:
            try:
                os.close(descriptor)
            except OSError:
                pass
        raise


def _describe_events(events: Sequence[object], watched: Sequence[tuple[int, Path]]) -> str:
    by_descriptor = {descriptor: path for descriptor, path in watched}
    descriptions: list[str] = []
    for event in events:
        descriptor = int(getattr(event, "ident", -1))
        path = by_descriptor.get(descriptor)
        fflags = int(getattr(event, "fflags", 0))
        descriptions.append(f"{path if path is not None else '<unknown>'} (flags=0x{fflags:x})")
    return "; ".join(descriptions)


def _stop_process(process: subprocess.Popen[bytes] | subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def _accepted_generated_build_subject_from_environment() -> str:
    value = os.environ.get("NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256", "")
    if len(value) != 64 or any(character not in "0123456789abcdefABCDEF" for character in value):
        raise BuildGuardError(
            "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 must remain available as exactly 64 hex characters through build-window admission"
        )
    return value.lower()


def _verify_accepted_generated_build_subject(inputs: PrivateInputs) -> None:
    accepted = _accepted_generated_build_subject_from_environment()
    actual = inputs.generated_build_subject()
    if not hmac.compare_digest(actual, accepted):
        raise BuildGuardError(
            "generated CocoaPods build inputs no longer match the preaccepted build subject before xcodebuild admission"
        )


def _accepted_private_review_commitment_from_environment() -> str:
    value = os.environ.get("NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256", "")
    if len(value) != 64 or any(character not in "0123456789abcdefABCDEF" for character in value):
        raise BuildGuardError(
            "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 must remain available as exactly 64 hex characters through build-window admission"
        )
    return value.lower()


def _verify_accepted_private_review_commitment(inputs: PrivateInputs) -> None:
    accepted = _accepted_private_review_commitment_from_environment()
    private_review = _load_accepted_private_review_module()
    try:
        private_review.verify_commitment(
            witness=inputs.private_provenance_record,
            key_path=inputs.private_review_key,
            expected_tag=accepted,
        )
        current = provenance.build_record(
            lockfile=inputs.lockfile,
            security_podspec=inputs.security_podspec,
            security_build=inputs.security_build,
            identity_podspec=inputs.identity_podspec,
            identity_sources=inputs.identity_sources,
        )
        provenance.verify_record(inputs.private_provenance_record, current)
    except (private_review.PrivateReviewCommitmentError, provenance.ProvenanceError) as error:
        raise BuildGuardError(
            f"private build inputs no longer match the externally accepted review commitment: {error}"
        ) from error


def _closed_xcode_environment() -> dict[str, str]:
    """Return the complete caller-independent environment admitted to xcodebuild.

    Build settings and toolchain selectors are passed explicitly in the command
    or selected by the separately reviewed system Xcode boundary. The compiler
    child therefore receives no ambient caller environment. HOME/identity come
    from the effective account database so automatic Apple signing can retain
    its normal user credential/profile lookup without trusting caller variables.
    """
    try:
        account = pwd.getpwuid(os.geteuid())
    except (KeyError, OSError) as exc:
        raise BuildGuardError("could not resolve effective account for closed xcodebuild environment") from exc

    home = account.pw_dir
    if (
        not account.pw_name
        or not home
        or not os.path.isabs(home)
        or "\x00" in account.pw_name
        or "\x00" in home
    ):
        raise BuildGuardError("effective account is not usable for closed xcodebuild environment")

    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": home,
        "USER": account.pw_name,
        "LOGNAME": account.pw_name,
        "LANG": "en_US.UTF-8",
    }


def run_guarded_build(
    inputs: PrivateInputs,
    command: Sequence[str],
    *,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
    popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
    poll_interval: float = 0.10,
    require_accepted_generated_subject: bool = False,
    require_accepted_private_review_commitment: bool = False,
    require_accepted_authority_helpers: bool = False,
    require_accepted_tracked_source: bool = False,
) -> int:
    if not command:
        raise BuildGuardError("no build command was supplied")

    accepted_authority_requested = (
        require_accepted_authority_helpers
        or require_accepted_generated_subject
        or require_accepted_private_review_commitment
    )
    if accepted_authority_requested:
        provenance.require_accepted()
        generated_build.require_accepted()

    tracked_manifest: tuple[AcceptedTrackedSource, ...] = ()
    if require_accepted_tracked_source:
        if inputs.accepted_source_root is None or inputs.accepted_source_sha is None:
            raise BuildGuardError("accepted tracked source root/SHA are required for physical xcodebuild custody")
        tracked_manifest = _accepted_tracked_source_manifest(
            inputs.accepted_source_root, inputs.accepted_source_sha
        )

    if require_accepted_generated_subject:
        _verify_accepted_generated_build_subject(inputs)
    if require_accepted_private_review_commitment:
        _verify_accepted_private_review_commitment(inputs)
    initial_snapshot = inputs.generation_snapshot()
    watch_paths = set(_watch_paths(inputs))
    if tracked_manifest:
        watch_paths.update(
            _tracked_source_watch_paths(tracked_manifest, inputs.accepted_source_root)  # type: ignore[arg-type]
        )
    ordered_watch_paths = tuple(sorted(watch_paths, key=lambda item: str(item)))
    _ensure_fd_budget(len(ordered_watch_paths))
    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watched_inputs(ordered_watch_paths, backend)

        if tracked_manifest:
            _verify_tracked_source_manifest(tracked_manifest)
            _verify_accepted_source_physical_tree(
                inputs, tracked_manifest, inputs.accepted_source_root  # type: ignore[arg-type]
            )
        armed_snapshot = inputs.generation_snapshot()
        if armed_snapshot != initial_snapshot:
            raise BuildGuardError("build inputs changed while build-window monitoring was armed")
        if require_accepted_generated_subject:
            _verify_accepted_generated_build_subject(inputs)
        if require_accepted_private_review_commitment:
            _verify_accepted_private_review_commitment(inputs)
        queued = backend.events(0)
        if queued:
            raise BuildGuardError(
                "build inputs changed before xcodebuild admission: "
                + _describe_events(queued, watched)
            )

        process = popen_factory(list(command), env=_closed_xcode_environment())
        while process.poll() is None:
            events = backend.events(poll_interval)
            if events:
                _stop_process(process)
                raise BuildGuardError(
                    "build input mutation was observed while xcodebuild was running: "
                    + _describe_events(events, watched)
                )

        trailing = backend.events(0)
        if trailing:
            raise BuildGuardError(
                "build input mutation was observed at xcodebuild completion: "
                + _describe_events(trailing, watched)
            )

        if tracked_manifest:
            _verify_tracked_source_manifest(tracked_manifest)
            _verify_accepted_source_physical_tree(
                inputs, tracked_manifest, inputs.accepted_source_root  # type: ignore[arg-type]
            )
        final_snapshot = inputs.generation_snapshot()
        if final_snapshot != initial_snapshot:
            raise BuildGuardError("build inputs changed across the guarded xcodebuild window")
        if require_accepted_generated_subject:
            _verify_accepted_generated_build_subject(inputs)
        if require_accepted_private_review_commitment:
            _verify_accepted_private_review_commitment(inputs)
        trailing = backend.events(0)
        if trailing:
            raise BuildGuardError(
                "build input mutation was observed during final build-window verification: "
                + _describe_events(trailing, watched)
            )
        return int(process.returncode or 0)
    finally:
        if process is not None and process.poll() is None:
            _stop_process(process)
        for descriptor, _ in watched:
            try:
                os.close(descriptor)
            except OSError:
                pass
        backend.close()


def _parse_args(argv: Sequence[str]) -> tuple[PrivateInputs, list[str]]:
    parser = argparse.ArgumentParser(
        description=(
            "Run the Capture field build while macOS vnode custody watches every admitted "
            "private, review-commitment, and CocoaPods-generated build input."
        )
    )
    parser.add_argument("--lockfile", required=True, type=Path)
    parser.add_argument("--security-podspec", required=True, type=Path)
    parser.add_argument("--security-build", required=True, type=Path)
    parser.add_argument("--identity-podspec", required=True, type=Path)
    parser.add_argument("--identity-sources", required=True, type=Path)
    parser.add_argument("--accepted-source-root", type=Path)
    parser.add_argument("--accepted-source-sha")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]

    lockfile = _lexical_absolute(args.lockfile)
    root = lockfile.parent
    lockfile = _require_real_checkout_ancestry(lockfile, root, label="dependency lock")
    security_podspec = _require_real_checkout_ancestry(
        args.security_podspec, root, label="private security podspec"
    )
    security_build = _require_real_checkout_ancestry(
        args.security_build, root, label="private security build tree"
    )
    identity_podspec = _require_real_checkout_ancestry(
        args.identity_podspec, root, label="private identity podspec"
    )
    identity_sources = _require_real_checkout_ancestry(
        args.identity_sources, root, label="private identity source tree"
    )
    accepted_source_root: Path | None = None
    accepted_source_sha: str | None = None
    if (args.accepted_source_root is None) != (args.accepted_source_sha is None):
        raise BuildGuardError("accepted source root and SHA must be supplied together")
    if args.accepted_source_root is not None and args.accepted_source_sha is not None:
        accepted_source_root = _require_real_checkout_ancestry(
            args.accepted_source_root, root, label="accepted source root"
        )
        if accepted_source_root != root:
            raise BuildGuardError("accepted source root must equal the field checkout root")
        accepted_source_sha = args.accepted_source_sha.lower()

    return (
        PrivateInputs(
            lockfile=lockfile,
            security_podspec=security_podspec,
            security_build=security_build,
            identity_podspec=identity_podspec,
            identity_sources=identity_sources,
            generated_pods=root / "Pods",
            generated_workspace=root / "NembraCapture.xcworkspace",
            accepted_source_root=accepted_source_root,
            accepted_source_sha=accepted_source_sha,
        ),
        command,
    )


def main(argv: Sequence[str] | None = None) -> int:
    inputs, command = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        return run_guarded_build(
            inputs,
            command,
            require_accepted_generated_subject=True,
            require_accepted_private_review_commitment=True,
            require_accepted_authority_helpers=True,
            require_accepted_tracked_source=True,
        )
    except BuildGuardError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except Exception:
        print("ERROR: unexpected build-window custody failure; field build refused", file=sys.stderr)
        return 77


if __name__ == "__main__":
    raise SystemExit(main())
