#!/usr/bin/env python3
"""Final-GO successor with an explicit sealed candidate-authority handoff.

This module consumes the continuous tracked-tree custody predecessor exactly from
its accepted Git blob. The predecessor remains responsible for detecting every
candidate mutation while the mutable checkout can still affect Final-GO. This
successor closes the terminal watcher-release gap differently: after the complete
private Final-GO build has produced the installed/retained signed-artifact record,
the checkout is retired as an authority input before watcher teardown.

A mutation observed before that transition still fails closed through predecessor
custody. A mutation after the transition cannot change the already-completed field
install, retained signed artifact, candidate postchecks, or publication input, and
candidate Git/blob APIs are fenced until custody teardown completes. This is an
authority handoff, not another finite event drain or endpoint rehash.
"""
from __future__ import annotations

import contextlib
import contextvars
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import threading
import types
from typing import Any, Iterator

PREDECESSOR_SOURCE = "cb36f9265f08708c8e47564f62f4857aeae7af0f"
PREDECESSOR_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PREDECESSOR_MODULE_GIT_BLOB = "baef9de23a680bedf16f9f7b367f45f7710ac0c6"
MAX_PREDECESSOR_BLOB_BYTES = 4 * 1024 * 1024


class _SealedHandoffError(RuntimeError):
    pass


def _closed_predecessor_object_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "core.fsmonitor",
        "GIT_CONFIG_VALUE_0": "false",
        "GIT_CONFIG_KEY_1": "core.hooksPath",
        "GIT_CONFIG_VALUE_1": "/dev/null",
    }


def _canonical_git_blob_oid(payload: bytes, accepted_oid: str) -> str:
    raw = b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    if len(accepted_oid) == 40:
        return hashlib.sha1(raw).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(raw).hexdigest()
    raise _SealedHandoffError("Final-GO predecessor has unsupported Git object width")


def _capture_predecessor_blob(root: Path) -> bytes:
    git_dir = root / ".git"
    try:
        metadata = git_dir.lstat()
    except OSError as error:
        raise _SealedHandoffError("Final-GO predecessor Git directory unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise _SealedHandoffError("Final-GO predecessor requires one real .git directory")

    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            [
                "/usr/bin/git",
                f"--git-dir={git_dir}",
                "cat-file",
                "blob",
                PREDECESSOR_MODULE_GIT_BLOB,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=_closed_predecessor_object_environment(),
        )
        if process.stdout is None:
            raise _SealedHandoffError("Final-GO predecessor capture pipe unavailable")
        payload = process.stdout.read(MAX_PREDECESSOR_BLOB_BYTES + 1)
        if len(payload) > MAX_PREDECESSOR_BLOB_BYTES:
            process.kill()
            process.wait()
            raise _SealedHandoffError("Final-GO predecessor exceeds bounded blob limit")
        if process.wait() != 0:
            raise _SealedHandoffError("Final-GO predecessor Git blob capture failed")
    except OSError as error:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        raise _SealedHandoffError("Final-GO predecessor Git blob capture failed") from error
    finally:
        if process is not None and process.stdout is not None:
            process.stdout.close()

    if _canonical_git_blob_oid(payload, PREDECESSOR_MODULE_GIT_BLOB) != PREDECESSOR_MODULE_GIT_BLOB:
        raise _SealedHandoffError("Final-GO predecessor Git lookup returned unaccepted bytes")
    return payload


def _load_predecessor() -> types.ModuleType:
    root = Path(__file__).resolve().parents[2]
    payload = _capture_predecessor_blob(root)
    module = types.ModuleType("nembra_final_go_predecessor_3042")
    module.__file__ = str(Path(__file__).resolve())
    module.__nembra_predecessor_source__ = PREDECESSOR_SOURCE
    module.__nembra_predecessor_blob__ = PREDECESSOR_MODULE_GIT_BLOB
    filename = f"git:{PREDECESSOR_SOURCE}:{PREDECESSOR_MODULE_PATH}"
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise _SealedHandoffError("accepted #3042 Final-GO predecessor could not execute") from error
    return module


_previous = _load_predecessor()

# Preserve the #3042/#2921 compatibility surface so existing exact authority
# regressions continue to exercise the accepted implementation rather than a
# rewritten approximation.
_direct_parent = _previous._direct_parent
_parent = _previous._parent
generated = _previous.generated
PrivateReviewGoError = _previous.PrivateReviewGoError
PARENT_SOURCE = _previous.PARENT_SOURCE
PARENT_MODULE_GIT_BLOB = _previous.PARENT_MODULE_GIT_BLOB
DIRECT_PARENT_SOURCE = _previous.DIRECT_PARENT_SOURCE
DIRECT_PARENT_MODULE_PATH = _previous.DIRECT_PARENT_MODULE_PATH
DIRECT_PARENT_MODULE_GIT_BLOB = _previous.DIRECT_PARENT_MODULE_GIT_BLOB
FIELD_INPUT_DIRECTORIES = _previous.FIELD_INPUT_DIRECTORIES
FIELD_INPUT_FILES = _previous.FIELD_INPUT_FILES
review_v5 = _previous.review_v5
candidate_private_authority = _previous.candidate_private_authority

_PREDECESSOR_PHYSICAL_BLOB_OID = _previous._physical_blob_oid
_PREDECESSOR_AUDIT_CANDIDATE_TREE = _previous._audit_candidate_tree
_PREDECESSOR_CANDIDATE_GIT_CUSTODY = _previous._candidate_git_custody
_CURRENT_VNODE_AUTHORITY = _previous._direct_parent._current_vnode_authority
_SEMANTIC_BUILD = _previous._direct_parent._parent.build
_PREDECESSOR_DISPATCH_LOCK: threading.RLock = _previous._PARENT_DISPATCH_LOCK

_CANDIDATE_RETIRED: contextvars.ContextVar[bool] = contextvars.ContextVar(
    "nembra_final_go_candidate_retired", default=False
)


def _retired_candidate_error() -> PrivateReviewGoError:
    return PrivateReviewGoError(
        "candidate repository authority retired after sealed Final-GO handoff"
    )


def _physical_blob_oid(root: Path, relative: str, mode: bytes, accepted_oid: str) -> str:
    if _CANDIDATE_RETIRED.get():
        raise _retired_candidate_error()
    return _PREDECESSOR_PHYSICAL_BLOB_OID(root, relative, mode, accepted_oid)


@contextlib.contextmanager
def _dispatch_predecessor_physical_reads() -> Iterator[None]:
    """Route #3042's inherited physical reads through this retirement fence."""
    with _PREDECESSOR_DISPATCH_LOCK:
        original = _previous._physical_blob_oid

        def dispatch(root: Path, relative: str, mode: bytes, accepted_oid: str) -> str:
            return globals()["_physical_blob_oid"](root, relative, mode, accepted_oid)

        _previous._physical_blob_oid = dispatch
        try:
            yield
        finally:
            _previous._physical_blob_oid = original


def _audit_candidate_tree(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    """Compatibility audit; Final-GO authority is granted only by build()."""
    with _dispatch_predecessor_physical_reads():
        return _PREDECESSOR_AUDIT_CANDIDATE_TREE(root, source)


@contextlib.contextmanager
def _candidate_git_custody(base: Any, candidate_repo: Path, source: str) -> Iterator[Any]:
    """Compatibility custody for focused tests; production build adds retirement."""
    with _dispatch_predecessor_physical_reads():
        with _PREDECESSOR_CANDIDATE_GIT_CUSTODY(base, candidate_repo, source) as value:
            yield value


def _require_sealed_final_go_record(record: Any) -> dict[str, Any]:
    if not isinstance(record, dict):
        raise _SealedHandoffError("Final-GO handoff requires one completed record object")
    for key in ("privateFieldInstall", "retainedSignedFieldArtifact", "physicalResultCollected"):
        if key not in record:
            raise _SealedHandoffError(f"Final-GO handoff record missing {key}")
    if record["privateFieldInstall"] is None:
        raise _SealedHandoffError("Final-GO handoff missing completed private field install")
    if record["retainedSignedFieldArtifact"] is None:
        raise _SealedHandoffError("Final-GO handoff missing retained signed field artifact")
    if record["physicalResultCollected"] is not False:
        raise _SealedHandoffError(
            "Final-GO software handoff must precede first physical-result collection"
        )
    return record


class _CandidateRetirementBoundary:
    """One-way Git/blob dispatch fence held through every inherited restore."""

    def __init__(self, base: Any) -> None:
        self.base = base
        self.original_git = base.git
        self.original_git_bytes = base.git_bytes
        self.token: contextvars.Token[bool] | None = None
        self.retired = False

        def dispatch_git(*args: Any, **kwargs: Any) -> str:
            if _CANDIDATE_RETIRED.get():
                raise _retired_candidate_error()
            return self.original_git(*args, **kwargs)

        def dispatch_git_bytes(*args: Any, **kwargs: Any) -> bytes:
            if _CANDIDATE_RETIRED.get():
                raise _retired_candidate_error()
            return self.original_git_bytes(*args, **kwargs)

        # These stable dispatchers are installed before inherited custody enters.
        # That means an inner finally can only restore retirement-aware functions,
        # never the raw candidate-capable callables captured by this boundary.
        self.dispatch_git = dispatch_git
        self.dispatch_git_bytes = dispatch_git_bytes

    def __enter__(self) -> "_CandidateRetirementBoundary":
        self.token = _CANDIDATE_RETIRED.set(False)
        self.base.git = self.dispatch_git
        self.base.git_bytes = self.dispatch_git_bytes
        return self

    def retire(self, record: Any) -> dict[str, Any]:
        if self.retired:
            raise _SealedHandoffError("Final-GO candidate authority retirement admitted twice")
        accepted = _require_sealed_final_go_record(record)
        self.retired = True
        _CANDIDATE_RETIRED.set(True)

        # Reinstall the same stable dispatchers immediately. The currently active
        # inherited candidate context may have replaced base.git/base.git_bytes
        # with its guarded views, but its saved "originals" are these dispatchers
        # because they were present before that context entered. Its finally can
        # therefore restore only retirement-aware functions during outer teardown.
        self.base.git = self.dispatch_git
        self.base.git_bytes = self.dispatch_git_bytes
        return accepted

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        self.base.git = self.original_git
        self.base.git_bytes = self.original_git_bytes
        if self.token is not None:
            _CANDIDATE_RETIRED.reset(self.token)
            self.token = None


def build(
    *,
    candidate_repo: Path,
    source: str,
    base_module: Any | None = None,
    **kwargs: Any,
) -> dict[str, Any]:
    """Complete every candidate consumer, then retire the checkout before release.

    #3057 exact validation proved that the accepted semantic stack performs the
    private installer, retained signed-artifact inspection/reinspection, and all
    candidate postchecks before `_SEMANTIC_BUILD` returns; later publication takes
    only the completed record/control outputs. Therefore the mutable checkout is
    no longer an authority input once `retirement.retire(record)` succeeds.
    """
    base = base_module or generated._load_base_module()
    source = base.canon(source, "source")
    candidate_repo = candidate_repo.expanduser().resolve(strict=True)

    with _CandidateRetirementBoundary(base) as retirement, _dispatch_predecessor_physical_reads():
        with _PREDECESSOR_CANDIDATE_GIT_CUSTODY(
            base, candidate_repo, source
        ), _CURRENT_VNODE_AUTHORITY():
            record = _SEMANTIC_BUILD(
                candidate_repo=candidate_repo,
                source=source,
                base_module=base,
                **kwargs,
            )
            return retirement.retire(record)


def __getattr__(name: str) -> Any:
    return getattr(_previous, name)


if __name__ == "__main__":
    raise SystemExit(
        "This exact-predecessor Final-GO successor is exercised by exact-head workflows; "
        "physical publication remains NO-GO until final composed authority is accepted."
    )
