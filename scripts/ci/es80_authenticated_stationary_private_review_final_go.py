#!/usr/bin/env python3
"""Final-GO successor with sealed candidate handoff and reviewed build-input authority.

This module consumes the continuous tracked-tree custody predecessor exactly from
its accepted Git blob. The predecessor remains responsible for detecting every
candidate mutation while the mutable checkout can still affect Final-GO. This
successor closes the terminal watcher-release gap differently: after the complete
private Final-GO build has produced the installed/retained signed-artifact record,
the checkout is retired as an authority input before watcher teardown.

V17 also binds the generated/private compiler-input manifest used by the field
build to an independent GitHub OWNER review on the exact candidate source. The
reviewed digest is injected only at the inherited closed installer-environment
boundary; hostile ambient caller values cannot select it. The exact review is
fetched again after the private build side effect and before the candidate handoff.
Any source, digest, body, node, reviewer, or state drift fails closed.

A mutation observed before retirement still fails closed through predecessor
custody. A mutation after retirement cannot change the already-completed field
install, retained signed artifact, candidate postchecks, or publication input.
No Bluetooth/Tuya/DP command or physical-result authority is added here.
"""
from __future__ import annotations

import contextlib
import contextvars
from datetime import datetime
import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
import threading
import types
from typing import Any, Callable, Iterator

PREDECESSOR_SOURCE = "cb36f9265f08708c8e47564f62f4857aeae7af0f"
PREDECESSOR_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PREDECESSOR_MODULE_GIT_BLOB = "baef9de23a680bedf16f9f7b367f45f7710ac0c6"
MAX_PREDECESSOR_BLOB_BYTES = 4 * 1024 * 1024

MANIFEST_REVIEW_AUTHORITY = "nembra-capture-generated-build-input-manifest-review-v1"
MANIFEST_RECORD_AUTHORITY = "nembra-authenticated-stationary-generated-manifest-v1"
MANIFEST_DIGEST_KEY = "generatedBuildInputManifestSHA256"
MANIFEST_ENV = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256"
MANIFEST_RECORD_KEY = "acceptedGeneratedBuildInputManifest"
HEX64 = re.compile(r"^[0-9a-f]{64}$")


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
OWNER = _previous.OWNER
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
_SEMANTIC_MODULE = _previous._direct_parent._parent
_CURRENT_VNODE_AUTHORITY = _previous._direct_parent._current_vnode_authority
_SEMANTIC_BUILD = _SEMANTIC_MODULE.build
_PREDECESSOR_PRIVATE_ENVIRONMENT_ADAPTER = _SEMANTIC_MODULE._private_environment_adapter
_PREDECESSOR_DISPATCH_LOCK: threading.RLock = _previous._PARENT_DISPATCH_LOCK
_MANIFEST_EXTENSION_LOCK = threading.RLock()

_CANDIDATE_RETIRED: contextvars.ContextVar[bool] = contextvars.ContextVar(
    "nembra_final_go_candidate_retired", default=False
)
_ACTIVE_MANIFEST_REVIEW: contextvars.ContextVar[dict[str, Any] | None] = contextvars.ContextVar(
    "nembra_final_go_generated_manifest_review", default=None
)


def _canonical_manifest_digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or not HEX64.fullmatch(value) or value != value.lower():
        raise PrivateReviewGoError(f"{label} is not canonical lowercase SHA-256")
    return value


def _parse_manifest_review_body(base: Any, body: str) -> dict[str, Any]:
    try:
        payload = base.obj(body.encode("utf-8"), "generated-manifest owner review body")
    except Exception as error:
        if isinstance(error, PrivateReviewGoError):
            raise
        raise PrivateReviewGoError("generated-manifest owner review body is not canonical JSON") from error
    if not isinstance(payload, dict):
        raise PrivateReviewGoError("generated-manifest owner review body must be one JSON object")
    return payload


def generated_manifest_review(
    pr: int,
    review_id: int,
    source: str,
    get: Callable[[str], tuple[bytes, dict[str, Any]]],
    *,
    base: Any,
) -> dict[str, Any]:
    """Return one exact GitHub-custodied OWNER review for the manifest digest."""
    pr = base.pos(pr, "candidate PR")
    review_id = base.pos(review_id, "generated-manifest review ID")
    source = base.canon(source, "candidate source")
    _, review = get(f"/pulls/{pr}/reviews/{review_id}")
    if not isinstance(review, dict):
        raise PrivateReviewGoError("generated-manifest GitHub review response is invalid")

    body = review.get("body")
    if not isinstance(body, str) or not body.strip():
        raise PrivateReviewGoError("generated-manifest owner review body missing")
    payload = _parse_manifest_review_body(base, body)
    required = {
        "schemaVersion",
        "authority",
        "sourceCommitSHA",
        MANIFEST_DIGEST_KEY,
        "verdict",
    }
    digest = _canonical_manifest_digest(
        payload.get(MANIFEST_DIGEST_KEY), "reviewed generated build-input manifest"
    )
    if (
        set(payload) != required
        or payload.get("schemaVersion") != 1
        or payload.get("authority") != MANIFEST_REVIEW_AUTHORITY
        or base.canon(payload.get("sourceCommitSHA"), "generated-manifest review source") != source
        or payload.get("verdict") != "ACCEPT"
    ):
        raise PrivateReviewGoError("generated-manifest owner review payload is not exact accepted authority")

    user = review.get("user", {})
    node_id = review.get("node_id")
    if (
        review.get("id") != review_id
        or review.get("state") not in {"COMMENTED", "APPROVED"}
        or base.canon(review.get("commit_id"), "generated-manifest review commit") != source
        or not isinstance(user, dict)
        or user.get("login") != OWNER
        or review.get("author_association") != "OWNER"
        or not isinstance(node_id, str)
        or not node_id
    ):
        raise PrivateReviewGoError("generated-manifest GitHub OWNER review custody mismatch")

    stamp = review.get("submitted_at")
    if not isinstance(stamp, str) or not stamp.endswith("Z"):
        raise PrivateReviewGoError("generated-manifest OWNER review timestamp invalid")
    try:
        datetime.fromisoformat(stamp[:-1] + "+00:00")
    except ValueError as error:
        raise PrivateReviewGoError("generated-manifest OWNER review timestamp invalid") from error

    return {
        "authority": MANIFEST_REVIEW_AUTHORITY,
        "reviewID": review_id,
        "reviewNodeID": node_id,
        "reviewBodySHA256": base.sha(body.encode("utf-8")),
        "reviewedAtUTC": stamp,
        "reviewer": OWNER,
        "state": review["state"],
        "sourceCommitSHA": source,
        MANIFEST_DIGEST_KEY: digest,
        "verdict": "accepted",
    }


def _inject_manifest_environment(
    environment: dict[str, str], subject: dict[str, Any]
) -> dict[str, str]:
    """Replace, never inherit, caller authority for the generated manifest digest."""
    result = dict(environment)
    result.pop(MANIFEST_ENV, None)
    result[MANIFEST_ENV] = _canonical_manifest_digest(
        subject.get(MANIFEST_DIGEST_KEY), "accepted generated build-input manifest"
    )
    return result


def _manifest_environment_adapter(
    original_adapter: Callable[..., Callable[..., dict[str, str]]],
    review: dict[str, Any],
) -> Callable[..., Callable[..., dict[str, str]]]:
    """Extend the accepted two-stage adapter at its final environment boundary."""
    subject = _ACTIVE_MANIFEST_REVIEW.get()
    if subject is None:
        raise PrivateReviewGoError("generated-manifest review authority is not active")
    inherited_adapter = _PREDECESSOR_PRIVATE_ENVIRONMENT_ADAPTER(original_adapter, review)

    def adapter(*args: Any, **kwargs: Any) -> Callable[..., dict[str, str]]:
        inherited_environment = inherited_adapter(*args, **kwargs)
        if not callable(inherited_environment):
            raise PrivateReviewGoError("inherited installer environment adapter is invalid")

        def extended(*environment_args: Any, **environment_kwargs: Any) -> dict[str, str]:
            environment = inherited_environment(*environment_args, **environment_kwargs)
            if not isinstance(environment, dict):
                raise PrivateReviewGoError("inherited closed installer environment is invalid")
            return _inject_manifest_environment(environment, subject)

        return extended

    return adapter


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
    pr: int,
    generated_manifest_review_id: int,
    **kwargs: Any,
) -> dict[str, Any]:
    """Complete candidate consumers under one independently reviewed manifest authority.

    The production entrypoint never accepts caller-selected GitHub review transport
    or base authority. It loads the accepted base internally, fetches the manifest
    review after entering the composition lock, and re-fetches it after the private
    semantic-build side effect before candidate retirement.
    """
    forbidden = {"get", "base_module"}.intersection(kwargs)
    if forbidden:
        raise PrivateReviewGoError(
            "caller-supplied Final-GO review authority is forbidden"
        )

    base = generated._load_base_module()
    source = base.canon(source, "source")
    pr = base.pos(pr, "PR")
    generated_manifest_review_id = base.pos(
        generated_manifest_review_id, "generated-manifest review ID"
    )
    trusted_get = base.api
    if not callable(trusted_get):
        raise PrivateReviewGoError("accepted GitHub review transport is unavailable")
    candidate_repo = candidate_repo.expanduser().resolve(strict=True)

    with _MANIFEST_EXTENSION_LOCK:
        original_environment_adapter = _SEMANTIC_MODULE._private_environment_adapter
        if original_environment_adapter is not _PREDECESSOR_PRIVATE_ENVIRONMENT_ADAPTER:
            raise PrivateReviewGoError(
                "Final-GO private environment adapter is not exact accepted authority"
            )

        pre_review = generated_manifest_review(
            pr, generated_manifest_review_id, source, trusted_get, base=base
        )
        token = _ACTIVE_MANIFEST_REVIEW.set(pre_review)
        _SEMANTIC_MODULE._private_environment_adapter = _manifest_environment_adapter
        try:
            with _CandidateRetirementBoundary(base) as retirement, _dispatch_predecessor_physical_reads():
                with _PREDECESSOR_CANDIDATE_GIT_CUSTODY(
                    base, candidate_repo, source
                ), _CURRENT_VNODE_AUTHORITY():
                    record = _SEMANTIC_BUILD(
                        candidate_repo=candidate_repo,
                        source=source,
                        pr=pr,
                        get=trusted_get,
                        base_module=base,
                        **kwargs,
                    )
                    post_review = generated_manifest_review(
                        pr,
                        generated_manifest_review_id,
                        source,
                        trusted_get,
                        base=base,
                    )
                    if post_review != pre_review:
                        raise PrivateReviewGoError(
                            "generated-manifest OWNER review changed during Final-GO composition"
                        )
                    if not isinstance(record, dict):
                        raise PrivateReviewGoError(
                            "accepted Final-GO semantic build returned invalid record"
                        )
                    if MANIFEST_RECORD_KEY in record:
                        raise PrivateReviewGoError(
                            "Final-GO record unexpectedly predefines generated-manifest authority"
                        )
                    record[MANIFEST_RECORD_KEY] = {
                        "authority": MANIFEST_RECORD_AUTHORITY,
                        "reviewAuthority": MANIFEST_REVIEW_AUTHORITY,
                        "reviewID": pre_review["reviewID"],
                        "reviewNodeID": pre_review["reviewNodeID"],
                        "reviewBodySHA256": pre_review["reviewBodySHA256"],
                        "reviewedAtUTC": pre_review["reviewedAtUTC"],
                        "reviewer": pre_review["reviewer"],
                        "state": pre_review["state"],
                        "sourceCommitSHA": source,
                        MANIFEST_DIGEST_KEY: pre_review[MANIFEST_DIGEST_KEY],
                    }
                    return retirement.retire(record)
        finally:
            _SEMANTIC_MODULE._private_environment_adapter = original_environment_adapter
            _ACTIVE_MANIFEST_REVIEW.reset(token)


def __getattr__(name: str) -> Any:
    return getattr(_previous, name)


if __name__ == "__main__":
    raise SystemExit(
        "This exact-predecessor Final-GO successor is exercised by exact-head workflows; "
        "physical authorization remains NO-GO until final composed authority is accepted."
    )