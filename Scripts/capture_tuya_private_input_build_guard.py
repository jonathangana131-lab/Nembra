#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import hmac
import importlib.util
import os
import resource
import select
import stat
import subprocess
import sys
import types
from dataclasses import dataclass
from pathlib import Path
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



def _accepted_source_git_environment(root: Path) -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_DIR": str(root / ".git"),
        "GIT_WORK_TREE": str(root),
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
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


def _accepted_source_manifest(inputs: PrivateInputs) -> dict[Path, tuple[str, bool]]:
    """Read and verify the exact accepted tracked tree without checkout index/config trust."""

    if inputs.accepted_source_root is None and inputs.accepted_source_sha is None:
        return {}
    if inputs.accepted_source_root is None or inputs.accepted_source_sha is None:
        raise BuildGuardError("accepted tracked-source custody requires both checkout root and source SHA")

    root = _lexical_absolute(inputs.accepted_source_root)
    if root != _lexical_absolute(inputs.lockfile.parent):
        raise BuildGuardError("accepted tracked-source root must equal the field checkout root")
    try:
        root_metadata = root.lstat()
        git_metadata = (root / ".git").lstat()
    except OSError as error:
        raise BuildGuardError("accepted tracked-source checkout authority disappeared before build-window custody") from error
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        raise BuildGuardError("accepted tracked-source root must be one real directory")
    if not stat.S_ISDIR(git_metadata.st_mode) or stat.S_ISLNK(git_metadata.st_mode):
        raise BuildGuardError("accepted tracked-source Git authority must be one real .git directory")

    source_sha = inputs.accepted_source_sha.lower()
    if len(source_sha) != 40 or any(character not in "0123456789abcdef" for character in source_sha):
        raise BuildGuardError("accepted tracked-source SHA must be exactly 40 hexadecimal characters")

    git_environment = _accepted_source_git_environment(root)
    try:
        current = subprocess.check_output(
            ["/usr/bin/git", "rev-parse", "--verify", "HEAD^{commit}"],
            cwd=root,
            env=git_environment,
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip().lower()
        tree = subprocess.check_output(
            ["/usr/bin/git", "ls-tree", "-r", "-z", source_sha],
            cwd=root,
            env=git_environment,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise BuildGuardError("accepted tracked-source Git tree could not be read from exact authority") from error
    if current != source_sha:
        raise BuildGuardError("accepted tracked-source checkout HEAD no longer matches the externally accepted SHA")

    manifest: dict[Path, tuple[str, bool]] = {}
    for record in tree.split(b"\0"):
        if not record:
            continue
        try:
            header, raw_path = record.split(b"\t", 1)
            raw_mode, raw_type, raw_oid = header.split(b" ", 2)
            mode = raw_mode.decode("ascii")
            object_type = raw_type.decode("ascii")
            oid = raw_oid.decode("ascii").lower()
        except (ValueError, UnicodeDecodeError) as error:
            raise BuildGuardError("accepted tracked-source Git tree contains a malformed entry") from error
        if object_type != "blob" or mode not in {"100644", "100755"}:
            raise BuildGuardError(
                f"accepted tracked-source entry has unsupported type/mode: {object_type} {mode}"
            )
        if len(oid) != 40 or any(character not in "0123456789abcdef" for character in oid):
            raise BuildGuardError("accepted tracked-source Git blob identity is malformed")
        relative = Path(os.fsdecode(raw_path))
        if relative.is_absolute() or not relative.parts or ".." in relative.parts or "." in relative.parts:
            raise BuildGuardError("accepted tracked-source Git path escapes the checkout root")
        path = root / relative
        try:
            metadata = path.lstat()
        except OSError as error:
            raise BuildGuardError(f"accepted tracked source disappeared before custody: {relative}") from error
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(f"accepted tracked source must be one real regular file: {relative}")
        expected_executable = mode == "100755"
        if bool(stat.S_IMODE(metadata.st_mode) & 0o111) != expected_executable:
            raise BuildGuardError(f"accepted tracked source executable mode differs from Git authority: {relative}")
        if path in manifest:
            raise BuildGuardError(f"accepted tracked-source Git path is duplicated: {relative}")
        manifest[path] = (oid, expected_executable)
    if not manifest:
        raise BuildGuardError("accepted tracked-source Git tree is empty")
    return manifest


def _verify_accepted_tracked_source_descriptors(
    manifest: dict[Path, tuple[str, bool]],
    watched: Sequence[tuple[int, Path]],
) -> None:
    """Bind watched checkout files to accepted Git blobs before/after compiler use."""

    if not manifest:
        return
    descriptors = {path: descriptor for descriptor, path in watched}
    for path, (expected_oid, expected_executable) in manifest.items():
        descriptor = descriptors.get(path)
        if descriptor is None:
            raise BuildGuardError(f"accepted tracked source is not under descriptor custody: {path}")
        try:
            before = os.fstat(descriptor)
            path_before = path.lstat()
        except OSError as error:
            raise BuildGuardError(f"accepted tracked source disappeared during descriptor custody: {path}") from error
        if _stat_identity(before) != _stat_identity(path_before):
            raise BuildGuardError(f"accepted tracked source path retargeted after descriptor admission: {path}")
        if not stat.S_ISREG(before.st_mode):
            raise BuildGuardError(f"accepted tracked source is not one regular file: {path}")
        if bool(stat.S_IMODE(before.st_mode) & 0o111) != expected_executable:
            raise BuildGuardError(f"accepted tracked source executable mode differs from exact Git authority: {path}")

        digest = hashlib.sha1()
        digest.update(b"blob " + str(before.st_size).encode("ascii") + b"\0")
        offset = 0
        while offset < before.st_size:
            try:
                chunk = os.pread(descriptor, min(65_536, before.st_size - offset), offset)
            except OSError as error:
                raise BuildGuardError(f"accepted tracked source could not be read under descriptor custody: {path}") from error
            if not chunk:
                raise BuildGuardError(f"accepted tracked source changed during descriptor read: {path}")
            digest.update(chunk)
            offset += len(chunk)

        try:
            after = os.fstat(descriptor)
            path_after = path.lstat()
        except OSError as error:
            raise BuildGuardError(f"accepted tracked source disappeared after descriptor read: {path}") from error
        if _stat_identity(before) != _stat_identity(after) or _stat_identity(after) != _stat_identity(path_after):
            raise BuildGuardError(f"accepted tracked source changed during descriptor verification: {path}")
        if not hmac.compare_digest(digest.hexdigest(), expected_oid):
            raise BuildGuardError(f"accepted tracked source bytes differ from exact Git authority: {path}")


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

    accepted_manifest = _accepted_source_manifest(inputs)
    if accepted_manifest:
        accepted_source_root = _lexical_absolute(inputs.accepted_source_root)  # type: ignore[arg-type]
        paths.add(accepted_source_root)
        for tracked_path in accepted_manifest:
            paths.add(tracked_path)
            _add_parent_watch_chain(paths, tracked_path, repository_root=accepted_source_root)

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

    if require_accepted_generated_subject:
        _verify_accepted_generated_build_subject(inputs)
    if require_accepted_private_review_commitment:
        _verify_accepted_private_review_commitment(inputs)
    initial_snapshot = inputs.generation_snapshot()
    accepted_source_manifest = _accepted_source_manifest(inputs)
    watch_paths = _watch_paths(inputs)
    _ensure_fd_budget(len(watch_paths))
    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watched_inputs(watch_paths, backend)
        _verify_accepted_tracked_source_descriptors(accepted_source_manifest, watched)

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

        process = popen_factory(list(command))
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

        final_snapshot = inputs.generation_snapshot()
        if final_snapshot != initial_snapshot:
            raise BuildGuardError("build inputs changed across the guarded xcodebuild window")
        _verify_accepted_tracked_source_descriptors(accepted_source_manifest, watched)
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

    return (
        PrivateInputs(
            lockfile=lockfile,
            security_podspec=security_podspec,
            security_build=security_build,
            identity_podspec=identity_podspec,
            identity_sources=identity_sources,
            generated_pods=root / "Pods",
            generated_workspace=root / "NembraCapture.xcworkspace",
            accepted_source_root=(
                _lexical_absolute(args.accepted_source_root)
                if args.accepted_source_root is not None
                else None
            ),
            accepted_source_sha=args.accepted_source_sha,
        ),
        command,
    )


def main(argv: Sequence[str] | None = None) -> int:
    inputs, command = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if inputs.accepted_source_root is None or inputs.accepted_source_sha is None:
            raise BuildGuardError(
                "physical field build requires exact accepted checkout root and source SHA custody"
            )
        return run_guarded_build(
            inputs,
            command,
            require_accepted_generated_subject=True,
            require_accepted_private_review_commitment=True,
            require_accepted_authority_helpers=True,
        )
    except BuildGuardError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except Exception:
        print("ERROR: unexpected build-window custody failure; field build refused", file=sys.stderr)
        return 77


if __name__ == "__main__":
    raise SystemExit(main())
