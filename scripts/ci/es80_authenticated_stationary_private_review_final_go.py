#!/usr/bin/env python3
"""Final-GO child that seals candidate checkout authority without Git worktree trust.

The accepted #2873 private-review implementation remains the semantic parent.
This child executes that exact parent from its immutable Git blob, then replaces
only the candidate checkout's inherited Git view. Candidate cleanliness is
proved by comparing the accepted Git tree to the physical filesystem directly;
repository-local config, index flags, fsmonitor, filters, attributes, and ignore
metadata never participate in candidate worktree authority.
"""
from __future__ import annotations

import contextlib
import hashlib
import os
import re
import stat
import subprocess
import types
from pathlib import Path, PurePosixPath
from typing import Any, Iterator

PARENT_SOURCE = "3c8711f8520b93e2647ec9e3b52d50894193bc30"
PARENT_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PARENT_MODULE_GIT_BLOB = "c6c0b68ad9c2af7cd3378c721752fbca7d4ed9e9"
OID = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
FIELD_INPUT_DIRECTORIES = ("LocalSecrets", "Pods", "NembraCapture.xcworkspace")
FIELD_INPUT_FILES = ("Podfile.lock",)


def _closed_object_environment() -> dict[str, str]:
    """Environment for object-database-only Git commands.

    Local config can still describe repository format/object storage, but the
    only Git commands admitted below are rev-parse, ls-tree, and cat-file. They
    never inspect a pathname in the candidate worktree. Known worktree-side
    executable/config surfaces are explicitly disabled as defense in depth.
    """
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_CONFIG_COUNT": "4",
        "GIT_CONFIG_KEY_0": "core.fsmonitor",
        "GIT_CONFIG_VALUE_0": "false",
        "GIT_CONFIG_KEY_1": "core.hooksPath",
        "GIT_CONFIG_VALUE_1": "/dev/null",
        "GIT_CONFIG_KEY_2": "core.attributesFile",
        "GIT_CONFIG_VALUE_2": "/dev/null",
        "GIT_CONFIG_KEY_3": "core.excludesFile",
        "GIT_CONFIG_VALUE_3": "/dev/null",
    }


def _real_git_dir(root: Path) -> Path:
    marker = root / ".git"
    try:
        metadata = marker.lstat()
    except OSError as error:
        raise RuntimeError("candidate physical Git directory unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise RuntimeError("candidate authority requires one real .git directory")
    try:
        resolved = marker.resolve(strict=True)
    except OSError as error:
        raise RuntimeError("candidate physical Git directory could not be resolved") from error
    if resolved.parent != root:
        raise RuntimeError("candidate physical Git directory escaped the accepted checkout")
    return resolved


def _object_git_bytes(root: Path, *args: str) -> bytes:
    """Run a tightly scoped Git object-database command, never a worktree command."""
    if not args or args[0] not in {"rev-parse", "ls-tree", "cat-file"}:
        raise RuntimeError("candidate object Git command is outside the accepted allowlist")
    git_dir = _real_git_dir(root)
    try:
        return subprocess.run(
            ["/usr/bin/git", f"--git-dir={git_dir}", *args],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_closed_object_environment(),
        ).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        raise RuntimeError("candidate object-database Git custody failed") from error


def _object_git_text(root: Path, *args: str) -> str:
    try:
        return _object_git_bytes(root, *args).decode("ascii").strip()
    except UnicodeDecodeError as error:
        raise RuntimeError("candidate object Git output was not canonical ASCII") from error


def _blob_oid(payload: bytes, accepted_oid: str) -> str:
    header = b"blob " + str(len(payload)).encode("ascii") + b"\0"
    if len(accepted_oid) == 40:
        return hashlib.sha1(header + payload).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(header + payload).hexdigest()
    raise RuntimeError("candidate accepted Git object has unsupported width")


def _head_oid(root: Path) -> str:
    value = _object_git_text(root, "rev-parse", "--verify", "HEAD^{commit}").lower()
    if not OID.fullmatch(value):
        raise RuntimeError("candidate HEAD is not a canonical Git object ID")
    return value


def _tree_entries(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    source = source.lower()
    if not OID.fullmatch(source):
        raise RuntimeError("candidate source is not a canonical Git object ID")
    raw = _object_git_bytes(root, "ls-tree", "-r", "-z", source)
    entries: dict[str, tuple[bytes, str]] = {}
    for record in raw.split(b"\0"):
        if not record:
            continue
        try:
            metadata, relative_raw = record.split(b"\t", 1)
            mode, object_type, oid_raw = metadata.split(b" ", 2)
            relative = os.fsdecode(relative_raw)
            oid = oid_raw.decode("ascii").lower()
        except (ValueError, UnicodeDecodeError) as error:
            raise RuntimeError("candidate accepted tree record is malformed") from error
        if object_type != b"blob" or mode not in {b"100644", b"100755", b"120000"}:
            raise RuntimeError("candidate accepted tree contains unsupported tracked object")
        if not OID.fullmatch(oid):
            raise RuntimeError("candidate accepted tree contains invalid blob identity")
        parts = PurePosixPath(relative).parts
        if not parts or relative.startswith("/") or any(part in {"", ".", ".."} for part in parts):
            raise RuntimeError("candidate accepted tree contains unsafe tracked path")
        if relative in entries:
            raise RuntimeError("candidate accepted tree contains duplicate tracked path")
        entries[relative] = (mode, oid)
    if not entries:
        raise RuntimeError("candidate accepted tree contains no tracked blobs")
    return entries


def _read_physical_payload(root: Path, relative: str, mode: bytes) -> tuple[bytes, os.stat_result]:
    parts = PurePosixPath(relative).parts
    current = root
    for component in parts[:-1]:
        current = current / component
        try:
            metadata = os.lstat(current)
        except OSError as error:
            raise RuntimeError("candidate tracked path ancestry is unavailable: " + relative) from error
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise RuntimeError("candidate tracked path has symlink/non-directory ancestry: " + relative)
    path = root.joinpath(*parts)
    try:
        metadata = os.lstat(path)
    except OSError as error:
        raise RuntimeError("candidate tracked path is unavailable: " + relative) from error
    if mode == b"120000":
        if not stat.S_ISLNK(metadata.st_mode):
            raise RuntimeError("candidate expected tracked symlink: " + relative)
        target = os.readlink(path)
        return (os.fsencode(target) if isinstance(target, str) else target), metadata
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise RuntimeError("candidate expected tracked regular file: " + relative)
    expected_executable = mode == b"100755"
    if bool(metadata.st_mode & 0o111) != expected_executable:
        raise RuntimeError("candidate tracked executable mode differs from accepted tree: " + relative)
    try:
        payload = path.read_bytes()
    except OSError as error:
        raise RuntimeError("candidate tracked file could not be read: " + relative) from error
    return payload, metadata


def _physical_blob_oid(root: Path, relative: str, mode: bytes, accepted_oid: str) -> str:
    payload, _ = _read_physical_payload(root, relative, mode)
    return _blob_oid(payload, accepted_oid)


def _audit_candidate_tree(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    """Compare exact accepted tree authority to the raw physical candidate.

    The audit does not call git status, hash-object(path), ls-files, check-ignore,
    or any other command that can consult candidate filters, fsmonitor, index
    flags, attributes, or ignore metadata.
    """
    root = root.expanduser().resolve(strict=True)
    _real_git_dir(root)
    if _head_oid(root) != source.lower():
        raise RuntimeError("candidate physical checkout HEAD differs from accepted source")
    entries = _tree_entries(root, source)
    tracked_directories: set[str] = set()
    for relative, (mode, accepted_oid) in entries.items():
        parts = PurePosixPath(relative).parts
        for index in range(1, len(parts)):
            tracked_directories.add(PurePosixPath(*parts[:index]).as_posix())
        actual_oid = _physical_blob_oid(root, relative, mode, accepted_oid)
        if actual_oid != accepted_oid:
            raise RuntimeError("candidate physical tracked bytes differ from accepted tree: " + relative)

    for relative in FIELD_INPUT_DIRECTORIES:
        path = root / relative
        try:
            metadata = os.lstat(path)
        except OSError as error:
            raise RuntimeError("required candidate field-input directory is unavailable: " + relative) from error
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise RuntimeError("candidate field-input allowlist root must be one real directory: " + relative)
    for relative in FIELD_INPUT_FILES:
        path = root / relative
        try:
            metadata = os.lstat(path)
        except OSError as error:
            raise RuntimeError("required candidate field-input file is unavailable: " + relative) from error
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise RuntimeError("candidate field-input allowlist file must be one real regular file: " + relative)

    allowed_roots = set(FIELD_INPUT_DIRECTORIES)
    allowed_files = set(FIELD_INPUT_FILES)
    tracked = set(entries)
    try:
        walker = os.walk(root, topdown=True, followlinks=False)
        for current_raw, directories, files in walker:
            current = Path(current_raw)
            current_relative = current.relative_to(root)
            if current_relative.parts and current_relative.parts[0] in allowed_roots:
                directories[:] = []
                continue
            for name in list(directories):
                candidate = current / name
                relative = candidate.relative_to(root).as_posix()
                if not current_relative.parts and name == ".git":
                    directories.remove(name)
                    continue
                if not current_relative.parts and name in allowed_roots:
                    directories.remove(name)
                    continue
                metadata = os.lstat(candidate)
                if stat.S_ISLNK(metadata.st_mode):
                    directories.remove(name)
                    if relative not in tracked or entries[relative][0] != b"120000":
                        raise RuntimeError("untracked candidate symlink outside field-input allowlist: " + relative)
                    continue
                if relative not in tracked_directories:
                    raise RuntimeError("untracked candidate directory outside field-input allowlist: " + relative)
            for name in files:
                candidate = current / name
                relative = candidate.relative_to(root).as_posix()
                if relative in tracked or relative in allowed_files:
                    continue
                raise RuntimeError("untracked candidate path outside field-input allowlist: " + relative)
    except OSError as error:
        raise RuntimeError("candidate raw filesystem enumeration failed") from error
    return entries


def _load_parent_module() -> types.ModuleType:
    root = Path(__file__).resolve().parents[2]
    entries = _tree_entries(root, PARENT_SOURCE)
    parent_entry = entries.get(PARENT_MODULE_PATH)
    if parent_entry is None or parent_entry[1] != PARENT_MODULE_GIT_BLOB:
        raise RuntimeError("Final-GO parent path is not the accepted #2873 Git blob")
    payload = _object_git_bytes(root, "cat-file", "blob", PARENT_MODULE_GIT_BLOB)
    if not payload or _blob_oid(payload, PARENT_MODULE_GIT_BLOB) != PARENT_MODULE_GIT_BLOB:
        raise RuntimeError("Final-GO parent execution bytes failed Git object identity")
    module = types.ModuleType("nembra_private_review_final_go_parent_2873")
    module.__file__ = str(Path(__file__).resolve())
    module.__nembra_accepted_control_source__ = PARENT_SOURCE
    module.__nembra_accepted_control_blob__ = PARENT_MODULE_GIT_BLOB
    filename = f"git:{PARENT_SOURCE}:{PARENT_MODULE_PATH}"
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise RuntimeError("accepted #2873 private-review Final-GO parent could not execute") from error
    return module


_parent = _load_parent_module()
generated = _parent.generated
PrivateReviewGoError = _parent.PrivateReviewGoError
REPO = _parent.REPO
OWNER = _parent.OWNER
PARENT_BRANCH = _parent.PARENT_BRANCH
WORKFLOW_NAME = _parent.WORKFLOW_NAME
WORKFLOW_PATH = _parent.WORKFLOW_PATH
REVIEW_AUTHORITY = _parent.REVIEW_AUTHORITY
FINAL_AUTHORITY = _parent.FINAL_AUTHORITY
PRIVATE_CONTROL_EXTENSION = _parent.PRIVATE_CONTROL_EXTENSION
PRIVATE_REVIEW_COMMITMENT_KEY = _parent.PRIVATE_REVIEW_COMMITMENT_KEY
PRIVATE_REVIEW_HELPER_KEY = _parent.PRIVATE_REVIEW_HELPER_KEY
PROVENANCE_HELPER_KEY = _parent.PROVENANCE_HELPER_KEY
GENERATED_HELPER_KEY = _parent.GENERATED_HELPER_KEY
PRIVATE_REVIEW_ENV = _parent.PRIVATE_REVIEW_ENV
PRIVATE_REVIEW_HELPER_ENV = _parent.PRIVATE_REVIEW_HELPER_ENV
PROVENANCE_HELPER_ENV = _parent.PROVENANCE_HELPER_ENV
GENERATED_HELPER_ENV = _parent.GENERATED_HELPER_ENV
PRIVATE_REVIEW_HELPER_PATH = _parent.PRIVATE_REVIEW_HELPER_PATH
PROVENANCE_HELPER_PATH = _parent.PROVENANCE_HELPER_PATH
PRIVATE_REVIEW_DOMAIN = _parent.PRIVATE_REVIEW_DOMAIN
CHILD_AUTHORITY_PATHS = _parent.CHILD_AUTHORITY_PATHS
PARENT_PINNED_PATHS = _parent.PARENT_PINNED_PATHS
PARENT_GENERATED_MODULE_GIT_BLOB = _parent.PARENT_GENERATED_MODULE_GIT_BLOB
review_v5 = _parent.review_v5
private_control_plane = _parent.private_control_plane
candidate_private_authority = _parent.candidate_private_authority
_private_environment_adapter = _parent._private_environment_adapter
_generated_extensions = _parent._generated_extensions


def _candidate_relative_oid(root: Path, source: str, relative: str) -> tuple[bytes, str]:
    entries = _tree_entries(root, source)
    try:
        return entries[relative]
    except KeyError as error:
        raise PrivateReviewGoError("candidate Git path is not tracked by accepted source: " + relative) from error


def _candidate_git_text(root: Path, source: str, *args: str) -> str:
    if args == ("rev-parse", "HEAD") or args == ("rev-parse", "--verify", "HEAD^{commit}"):
        return _head_oid(root)
    if len(args) == 2 and args[0] == "rev-parse" and ":" in args[1]:
        revision, relative = args[1].split(":", 1)
        if revision not in {"HEAD", source}:
            raise PrivateReviewGoError("candidate Git path requested outside accepted source")
        return _candidate_relative_oid(root, source, relative)[1]
    if args and args[0] == "status":
        if args != ("status", "--porcelain=v1", "--untracked-files=all"):
            raise PrivateReviewGoError("candidate status request is outside raw-audit contract")
        _audit_candidate_tree(root, source)
        return ""
    if len(args) == 5 and args[:4] == ("hash-object", "--no-filters", "--", args[3]):
        # Kept only for defensive compatibility with unusual tuple construction.
        relative = args[4]
        mode, accepted_oid = _candidate_relative_oid(root, source, relative)
        return _physical_blob_oid(root, relative, mode, accepted_oid)
    if len(args) == 4 and args[:3] == ("hash-object", "--no-filters", "--"):
        relative = args[3]
        mode, accepted_oid = _candidate_relative_oid(root, source, relative)
        return _physical_blob_oid(root, relative, mode, accepted_oid)
    if len(args) == 5 and args[0] == "ls-files" and args[1] in {"-v", "-t"} and args[2] == "--":
        relative = args[4]
        _candidate_relative_oid(root, source, relative)
        return "H " + relative
    if len(args) == 4 and args[0] == "ls-files" and args[1] in {"-v", "-t"} and args[2] == "--":
        relative = args[3]
        _candidate_relative_oid(root, source, relative)
        return "H " + relative
    raise PrivateReviewGoError("candidate inherited Git command is outside sealed raw-filesystem authority")


def _candidate_git_bytes(root: Path, source: str, *args: str) -> bytes:
    if len(args) == 2 and args[0] == "show" and ":" in args[1]:
        revision, relative = args[1].split(":", 1)
        if revision not in {"HEAD", source}:
            raise PrivateReviewGoError("candidate Git byte request is outside accepted source")
        oid = _candidate_relative_oid(root, source, relative)[1]
        payload = _object_git_bytes(root, "cat-file", "blob", oid)
        if _blob_oid(payload, oid) != oid:
            raise PrivateReviewGoError("candidate accepted Git bytes failed object identity")
        return payload
    if len(args) == 3 and args[:2] == ("cat-file", "blob"):
        oid = args[2].lower()
        accepted_oids = {item[1] for item in _tree_entries(root, source).values()}
        if oid not in accepted_oids:
            raise PrivateReviewGoError("candidate blob request is outside accepted source tree")
        payload = _object_git_bytes(root, "cat-file", "blob", oid)
        if _blob_oid(payload, oid) != oid:
            raise PrivateReviewGoError("candidate accepted blob bytes failed object identity")
        return payload
    raise PrivateReviewGoError("candidate inherited Git byte command is outside sealed object authority")


@contextlib.contextmanager
def _candidate_git_custody(base: Any, candidate_repo: Path, source: str) -> Iterator[None]:
    root = candidate_repo.expanduser().resolve(strict=True)
    source = source.lower()
    try:
        _audit_candidate_tree(root, source)
    except RuntimeError as error:
        raise PrivateReviewGoError(str(error)) from error
    original_git = getattr(base, "git", None)
    original_git_bytes = getattr(base, "git_bytes", None)
    if not callable(original_git) or not callable(original_git_bytes):
        raise PrivateReviewGoError("parent Final-GO Git authority is not patchable")

    def guarded_git(repo: Path, *args: str) -> str:
        try:
            item_root = repo.expanduser().resolve(strict=True)
        except OSError as error:
            raise PrivateReviewGoError("Git repository path is unavailable") from error
        if item_root != root:
            return original_git(repo, *args)
        try:
            return _candidate_git_text(root, source, *args)
        except RuntimeError as error:
            raise PrivateReviewGoError(str(error)) from error

    def guarded_git_bytes(repo: Path, *args: str) -> bytes:
        try:
            item_root = repo.expanduser().resolve(strict=True)
        except OSError as error:
            raise PrivateReviewGoError("Git repository path is unavailable") from error
        if item_root != root:
            return original_git_bytes(repo, *args)
        try:
            return _candidate_git_bytes(root, source, *args)
        except RuntimeError as error:
            raise PrivateReviewGoError(str(error)) from error

    base.git = guarded_git
    base.git_bytes = guarded_git_bytes
    try:
        yield
    finally:
        base.git = original_git
        base.git_bytes = original_git_bytes


def build(*, candidate_repo: Path, source: str, base_module: Any | None = None, **kwargs: Any) -> dict[str, Any]:
    base = base_module or generated._load_base_module()
    source = base.canon(source, "source")
    with _candidate_git_custody(base, candidate_repo, source):
        return _parent.build(
            candidate_repo=candidate_repo,
            source=source,
            base_module=base,
            **kwargs,
        )


def __getattr__(name: str) -> Any:
    return getattr(_parent, name)


if __name__ == "__main__":
    raise SystemExit(
        "This current-parent private-review control extension is exercised by its exact-head workflow; "
        "physical publication remains delegated to the sealed generated-subject/parent issuer."
    )
