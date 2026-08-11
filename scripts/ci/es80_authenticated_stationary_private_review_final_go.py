#!/usr/bin/env python3
"""Final-GO recovery child for current vnode authority and race-safe physical reads.

The exact #2890 raw-tree implementation is executed from its immutable Git blob.
This child changes only two remaining authority boundaries:
- tracked regular-file payloads are read through no-follow descriptor custody;
- the retired CocoaPods vnode Convergence gate is replaced by the selected
  current vnode gate without recreating a stale workflow alias.
"""
from __future__ import annotations

import contextlib
import hashlib
import os
import re
import stat
import subprocess
import types
from pathlib import Path
from typing import Any, Callable, Iterator

PREDECESSOR_SOURCE = "fc662c996ad4551e3bd7bba6e225e3bee9aa620c"
PREDECESSOR_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PREDECESSOR_MODULE_GIT_BLOB = "89d5718af4fb7ad30fa15518e4dff9450b243ae6"
RETIRED_VNODE_WORKFLOW = "Capture CocoaPods Vnode Attribute Convergence"
RETIRED_VNODE_WORKFLOW_PATH = ".github/workflows/capture-cocoapods-vnode-attribute-convergence.yml"
CURRENT_VNODE_WORKFLOW = "Capture CocoaPods Vnode Attribute Current"
CURRENT_VNODE_WORKFLOW_PATH = ".github/workflows/capture-cocoapods-vnode-attribute-current.yml"
OID = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")


def _bootstrap_git_dir(root: Path) -> Path:
    marker = root / ".git"
    try:
        metadata = marker.lstat()
    except OSError as error:
        raise RuntimeError("Final-GO recovery physical Git directory unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise RuntimeError("Final-GO recovery requires one real .git directory")
    resolved = marker.resolve(strict=True)
    if resolved.parent != root:
        raise RuntimeError("Final-GO recovery Git directory escaped checkout")
    return resolved


def _bootstrap_object_bytes(root: Path, *args: str) -> bytes:
    if not args or args[0] not in {"rev-parse", "cat-file"}:
        raise RuntimeError("Final-GO recovery bootstrap Git command is outside object allowlist")
    environment = {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "core.hooksPath",
        "GIT_CONFIG_VALUE_0": "/dev/null",
        "GIT_CONFIG_KEY_1": "core.fsmonitor",
        "GIT_CONFIG_VALUE_1": "false",
    }
    try:
        return subprocess.run(
            ["/usr/bin/git", f"--git-dir={_bootstrap_git_dir(root)}", *args],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        raise RuntimeError("Final-GO recovery predecessor Git custody failed") from error


def _bootstrap_blob_oid(payload: bytes, accepted_oid: str) -> str:
    header = b"blob " + str(len(payload)).encode("ascii") + b"\0"
    if len(accepted_oid) == 40:
        return hashlib.sha1(header + payload).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(header + payload).hexdigest()
    raise RuntimeError("Final-GO recovery predecessor object width is unsupported")


def _load_predecessor() -> types.ModuleType:
    root = Path(__file__).resolve().parents[2]
    try:
        accepted = _bootstrap_object_bytes(
            root, "rev-parse", f"{PREDECESSOR_SOURCE}:{PREDECESSOR_MODULE_PATH}"
        ).decode("ascii").strip().lower()
    except UnicodeDecodeError as error:
        raise RuntimeError("Final-GO recovery predecessor identity is not canonical ASCII") from error
    if accepted != PREDECESSOR_MODULE_GIT_BLOB or not OID.fullmatch(accepted):
        raise RuntimeError("Final-GO recovery predecessor path is not exact #2890 authority")
    payload = _bootstrap_object_bytes(root, "cat-file", "blob", accepted)
    if not payload or _bootstrap_blob_oid(payload, accepted) != accepted:
        raise RuntimeError("Final-GO recovery predecessor bytes failed Git object identity")
    module = types.ModuleType("nembra_final_go_raw_tree_predecessor_2890")
    module.__file__ = str(Path(__file__).resolve())
    module.__nembra_accepted_control_source__ = PREDECESSOR_SOURCE
    module.__nembra_accepted_control_blob__ = accepted
    try:
        exec(
            compile(payload, f"git:{PREDECESSOR_SOURCE}:{PREDECESSOR_MODULE_PATH}", "exec", dont_inherit=True),
            module.__dict__,
        )
    except Exception as error:
        raise RuntimeError("exact #2890 Final-GO predecessor could not execute") from error
    return module


_predecessor = _load_predecessor()
_parent = _predecessor._parent
generated = _predecessor.generated
PrivateReviewGoError = _predecessor.PrivateReviewGoError
PARENT_SOURCE = _predecessor.PARENT_SOURCE
PARENT_MODULE_GIT_BLOB = _predecessor.PARENT_MODULE_GIT_BLOB
FIELD_INPUT_DIRECTORIES = _predecessor.FIELD_INPUT_DIRECTORIES
FIELD_INPUT_FILES = _predecessor.FIELD_INPUT_FILES
REPO = _predecessor.REPO
OWNER = _predecessor.OWNER
PARENT_BRANCH = _predecessor.PARENT_BRANCH
WORKFLOW_NAME = _predecessor.WORKFLOW_NAME
WORKFLOW_PATH = _predecessor.WORKFLOW_PATH
REVIEW_AUTHORITY = _predecessor.REVIEW_AUTHORITY
FINAL_AUTHORITY = _predecessor.FINAL_AUTHORITY
PRIVATE_CONTROL_EXTENSION = _predecessor.PRIVATE_CONTROL_EXTENSION
PRIVATE_REVIEW_COMMITMENT_KEY = _predecessor.PRIVATE_REVIEW_COMMITMENT_KEY
PRIVATE_REVIEW_HELPER_KEY = _predecessor.PRIVATE_REVIEW_HELPER_KEY
PROVENANCE_HELPER_KEY = _predecessor.PROVENANCE_HELPER_KEY
GENERATED_HELPER_KEY = _predecessor.GENERATED_HELPER_KEY
PRIVATE_REVIEW_ENV = _predecessor.PRIVATE_REVIEW_ENV
PRIVATE_REVIEW_HELPER_ENV = _predecessor.PRIVATE_REVIEW_HELPER_ENV
PROVENANCE_HELPER_ENV = _predecessor.PROVENANCE_HELPER_ENV
GENERATED_HELPER_ENV = _predecessor.GENERATED_HELPER_ENV
PRIVATE_REVIEW_HELPER_PATH = _predecessor.PRIVATE_REVIEW_HELPER_PATH
PROVENANCE_HELPER_PATH = _predecessor.PROVENANCE_HELPER_PATH
PRIVATE_REVIEW_DOMAIN = _predecessor.PRIVATE_REVIEW_DOMAIN
CHILD_AUTHORITY_PATHS = _predecessor.CHILD_AUTHORITY_PATHS
PARENT_PINNED_PATHS = _predecessor.PARENT_PINNED_PATHS
PARENT_GENERATED_MODULE_GIT_BLOB = _predecessor.PARENT_GENERATED_MODULE_GIT_BLOB
review_v5 = _predecessor.review_v5
private_control_plane = _predecessor.private_control_plane
candidate_private_authority = _predecessor.candidate_private_authority
_private_environment_adapter = _predecessor._private_environment_adapter
_generated_extensions = _predecessor._generated_extensions
_tree_entries = _predecessor._tree_entries
_object_git_bytes = _predecessor._object_git_bytes
_blob_oid = _predecessor._blob_oid
_candidate_relative_oid = _predecessor._candidate_relative_oid
_candidate_git_custody = _predecessor._candidate_git_custody


def _stat_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _read_physical_payload(root: Path, relative: str, mode: bytes) -> tuple[bytes, os.stat_result]:
    """Read one tracked regular file with descriptor-bound no-follow custody."""
    if mode not in {b"100644", b"100755"}:
        raise RuntimeError("candidate tracked symlink/object mode is not admitted: " + relative)
    parts = Path(relative).parts
    if not parts or Path(relative).is_absolute() or any(part in {"", ".", ".."} for part in parts):
        raise RuntimeError("candidate tracked path is unsafe: " + relative)

    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
    file_flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW
    directory_fd = -1
    file_fd = -1
    try:
        directory_fd = os.open(root, directory_flags)
        for component in parts[:-1]:
            next_fd = os.open(component, directory_flags, dir_fd=directory_fd)
            os.close(directory_fd)
            directory_fd = next_fd

        leaf = parts[-1]
        before = os.stat(leaf, dir_fd=directory_fd, follow_symlinks=False)
        if not stat.S_ISREG(before.st_mode) or stat.S_ISLNK(before.st_mode):
            raise RuntimeError("candidate expected tracked regular file: " + relative)
        expected_executable = mode == b"100755"
        if bool(before.st_mode & 0o111) != expected_executable:
            raise RuntimeError("candidate tracked executable mode differs from accepted tree: " + relative)

        file_fd = os.open(leaf, file_flags, dir_fd=directory_fd)
        opened = os.fstat(file_fd)
        if _stat_identity(opened) != _stat_identity(before):
            raise RuntimeError("candidate tracked file identity changed before descriptor bind: " + relative)

        chunks: list[bytes] = []
        while True:
            chunk = os.read(file_fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        payload = b"".join(chunks)

        after_fd = os.fstat(file_fd)
        after_path = os.stat(leaf, dir_fd=directory_fd, follow_symlinks=False)
        if _stat_identity(after_fd) != _stat_identity(opened):
            raise RuntimeError("candidate tracked descriptor changed while being read: " + relative)
        if _stat_identity(after_path) != _stat_identity(after_fd):
            raise RuntimeError("candidate tracked pathname changed during descriptor read: " + relative)
        return payload, after_fd
    except OSError as error:
        raise RuntimeError("candidate tracked path could not be read under descriptor custody: " + relative) from error
    finally:
        if file_fd >= 0:
            os.close(file_fd)
        if directory_fd >= 0:
            os.close(directory_fd)


# All predecessor raw-tree and inherited parent candidate reads resolve this
# module-global at call time. Replacing it here preserves #2890's exact audit
# while sealing the lstat -> reopen race found by independent review.
_predecessor._read_physical_payload = _read_physical_payload
_physical_blob_oid = _predecessor._physical_blob_oid
_audit_candidate_tree = _predecessor._audit_candidate_tree


def _candidate_generated_authority_current(
    candidate_repo: Path,
    source: str,
    accepted_digest: str,
    *,
    base: Any,
    derive_subject: Callable[[Path, str, Any], str] | None = None,
) -> dict[str, Any]:
    """Exact #2775 generated candidate contract, advanced to the current vnode gate."""
    root = candidate_repo.expanduser().resolve(strict=True)
    accepted_digest = generated._canonical_digest(accepted_digest, "accepted CocoaPods generated build subject")
    if base.canon(base.git(root, "rev-parse", "HEAD"), "candidate HEAD") != source:
        raise generated.GeneratedSubjectGoError("generated build-subject candidate is not exact accepted source")
    if base.git(root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise generated.GeneratedSubjectGoError("generated build-subject candidate checkout is not clean")

    authority_paths = tuple(
        CURRENT_VNODE_WORKFLOW_PATH if item == RETIRED_VNODE_WORKFLOW_PATH else item
        for item in generated.GENERATED_AUTHORITY_PATHS
    )
    acceptance_workflows = tuple(
        (CURRENT_VNODE_WORKFLOW, CURRENT_VNODE_WORKFLOW_PATH)
        if (name, path) == (RETIRED_VNODE_WORKFLOW, RETIRED_VNODE_WORKFLOW_PATH)
        else (name, path)
        for name, path in generated.GENERATED_ACCEPTANCE_WORKFLOWS
    )
    blobs: dict[str, str] = {}
    texts: dict[str, str] = {}
    for relative in authority_paths:
        try:
            mode, accepted_oid = _candidate_relative_oid(root, source, relative)
            payload, _ = _read_physical_payload(root, relative, mode)
        except (RuntimeError, PrivateReviewGoError) as error:
            raise generated.GeneratedSubjectGoError(
                "generated build authority path is not current sealed physical source: " + relative
            ) from error
        if _blob_oid(payload, accepted_oid) != accepted_oid:
            raise generated.GeneratedSubjectGoError(
                "generated build authority physical bytes differ from accepted Git blob: " + relative
            )
        try:
            texts[relative] = payload.decode("utf-8")
        except UnicodeDecodeError as error:
            raise generated.GeneratedSubjectGoError(
                "generated build authority path is not canonical UTF-8: " + relative
            ) from error
        blobs[relative] = accepted_oid

    bootstrap = texts["Scripts/bootstrap_capture_tuya_sdk.sh"]
    helper = texts[generated.GENERATED_HELPER_PATH]
    guard = texts["Scripts/capture_tuya_private_input_build_guard.py"]
    installer = texts["scripts/field/install_one_time_capture.command"]
    generated_workflow = texts[generated.GENERATED_BUILD_WORKFLOW_PATH]
    vnode_workflow = texts[CURRENT_VNODE_WORKFLOW_PATH]
    required_fragments = (
        (bootstrap, generated.GENERATED_ENV),
        (bootstrap, "capture_cocoapods_generated_build_subject.py"),
        (helper, generated.GENERATED_SCHEMA),
        (guard, "capture_cocoapods_generated_build_subject.py"),
        (guard, "_verify_accepted_generated_build_subject"),
        (guard, "require_accepted_generated_subject=True"),
        (guard, "_require_real_checkout_ancestry"),
        (guard, "_ensure_fd_budget"),
        (guard, "KQ_NOTE_ATTRIB"),
        (installer, "bootstrap_capture_tuya_sdk.sh"),
        (installer, "capture_tuya_private_input_build_guard.py"),
        (generated_workflow, "name: Capture CocoaPods Build Subject Authority"),
        (generated_workflow, "Require exact generated CocoaPods build authority"),
        (generated_workflow, "test_capture_private_input_ancestor_retarget.py"),
        (vnode_workflow, "name: Capture CocoaPods Vnode Attribute Current"),
        (vnode_workflow, "Real macOS chmod vnode evidence"),
        (vnode_workflow, "macos-15"),
    )
    if any(fragment not in text for text, fragment in required_fragments):
        raise generated.GeneratedSubjectGoError("candidate source lacks current generated-build authority enforcement")

    derive = derive_subject or generated._current_generated_subject
    current = derive(root, source, base)
    if current != accepted_digest:
        raise generated.GeneratedSubjectGoError("candidate generated CocoaPods subject does not match reviewed authority")
    return {
        "authority": "nembra-cocoapods-generated-build-subject-candidate-v4-current-vnode",
        "implementation": generated.GENERATED_HELPER_PATH,
        "sourceCommitSHA": source,
        generated.GENERATED_KEY: current,
        "requiredCandidateWorkflows": [name for name, _ in acceptance_workflows],
        "gitBlobs": blobs,
    }


@contextlib.contextmanager
def _current_generated_authority_contract() -> Iterator[None]:
    original_workflow = generated.VNODE_WORKFLOW
    original_workflow_path = generated.VNODE_WORKFLOW_PATH
    original_acceptance = generated.GENERATED_ACCEPTANCE_WORKFLOWS
    original_paths = generated.GENERATED_AUTHORITY_PATHS
    original_candidate = generated.candidate_generated_authority
    if original_workflow != RETIRED_VNODE_WORKFLOW or original_workflow_path != RETIRED_VNODE_WORKFLOW_PATH:
        raise PrivateReviewGoError("accepted generated parent vnode authority is not the exact retired contract")
    if (RETIRED_VNODE_WORKFLOW, RETIRED_VNODE_WORKFLOW_PATH) not in original_acceptance:
        raise PrivateReviewGoError("accepted generated parent lacks the expected retired vnode gate")
    if RETIRED_VNODE_WORKFLOW_PATH not in original_paths:
        raise PrivateReviewGoError("accepted generated parent lacks the expected retired vnode authority path")

    generated.VNODE_WORKFLOW = CURRENT_VNODE_WORKFLOW
    generated.VNODE_WORKFLOW_PATH = CURRENT_VNODE_WORKFLOW_PATH
    generated.GENERATED_ACCEPTANCE_WORKFLOWS = tuple(
        (CURRENT_VNODE_WORKFLOW, CURRENT_VNODE_WORKFLOW_PATH)
        if (name, path) == (RETIRED_VNODE_WORKFLOW, RETIRED_VNODE_WORKFLOW_PATH)
        else (name, path)
        for name, path in original_acceptance
    )
    generated.GENERATED_AUTHORITY_PATHS = tuple(
        CURRENT_VNODE_WORKFLOW_PATH if path == RETIRED_VNODE_WORKFLOW_PATH else path
        for path in original_paths
    )
    generated.candidate_generated_authority = _candidate_generated_authority_current
    try:
        yield
    finally:
        generated.VNODE_WORKFLOW = original_workflow
        generated.VNODE_WORKFLOW_PATH = original_workflow_path
        generated.GENERATED_ACCEPTANCE_WORKFLOWS = original_acceptance
        generated.GENERATED_AUTHORITY_PATHS = original_paths
        generated.candidate_generated_authority = original_candidate


def build(*, candidate_repo: Path, source: str, base_module: Any | None = None, **kwargs: Any) -> dict[str, Any]:
    with _current_generated_authority_contract():
        return _predecessor.build(
            candidate_repo=candidate_repo,
            source=source,
            base_module=base_module,
            **kwargs,
        )


def __getattr__(name: str) -> Any:
    return getattr(_predecessor, name)


if __name__ == "__main__":
    raise SystemExit(
        "This current-vnode/descriptor-custody Final-GO recovery is exercised by exact-head QA; "
        "physical publication remains delegated to the sealed parent issuer."
    )
