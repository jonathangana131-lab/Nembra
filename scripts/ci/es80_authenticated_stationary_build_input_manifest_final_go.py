#!/usr/bin/env python3
"""Extend the accepted Final-GO control with reviewed build-input manifest authority.

This is a control-plane successor, not a source-snapshot or installer rewrite. It
exact-loads the accepted retirement-dispatch parent, re-derives the generated/private
build-input manifest using the exact accepted snapshot helper blob, requires that
manifest digest in the GitHub-owner review, and exposes the accepted digest only through
the inherited semantic installer's closed environment constructor.

The current field installer does not yet consume this new environment key. Therefore a
green control child is an issuer ingredient only and creates no install/physical GO.
"""
from __future__ import annotations

import contextlib
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import types
from typing import Any, Callable, Iterator

REPO = "jonathangana131-lab/Nembra"
OWNER = "jonathangana131-lab"
PARENT_SOURCE = "01217c20215c31c7380405dc1e2bd1330136894e"
PARENT_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PARENT_BLOB = "63567c6674003fc4ddd1caabd398060818beb938"
MANIFEST_HELPER_PATH = "scripts/ci/capture_accepted_build_input_snapshot.py"
MANIFEST_HELPER_BLOB = "b29cf5a7f344710515d4adec80b068c237b44db3"
MANIFEST_SCHEMA_VERSION = 1
REVIEW_AUTHORITY = "nembra-capture-human-review-github-v4-build-input-manifest"
REVIEW_KEY = "generatedBuildInputManifestSHA256"
ENV_KEY = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_GENERATED_SUBJECTS = (
    "Podfile.lock",
    "NembraCapture.xcworkspace",
    "Pods",
    "LocalSecrets/TuyaSDK",
    "LocalSecrets/TuyaRuntime",
)


class BuildInputManifestFinalGoError(RuntimeError):
    pass


def _closed_git_environment() -> dict[str, str]:
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


def _canonical_blob_oid(payload: bytes, accepted_oid: str) -> str:
    raw = b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    if len(accepted_oid) == 40:
        return hashlib.sha1(raw).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(raw).hexdigest()
    raise BuildInputManifestFinalGoError("unsupported accepted Git object width")


def _accepted_git_blob(root: Path, source: str, relative: str, expected_blob: str) -> bytes:
    root = root.expanduser().resolve(strict=True)
    if source != "HEAD" and HEX40.fullmatch(source) is None:
        raise BuildInputManifestFinalGoError("accepted Git source is malformed")
    environment = _closed_git_environment()
    try:
        resolved = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "rev-parse", f"{source}:{relative}"],
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        ).stdout.strip().lower()
        if resolved != expected_blob:
            raise BuildInputManifestFinalGoError(
                f"accepted Git blob moved for {relative}: expected {expected_blob}, got {resolved}"
            )
        payload = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "cat-file", "blob", resolved],
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        raise BuildInputManifestFinalGoError(
            f"accepted Git bytes unavailable for {relative}"
        ) from error
    if not payload or _canonical_blob_oid(payload, resolved) != resolved:
        raise BuildInputManifestFinalGoError(
            f"accepted Git bytes failed canonical identity for {relative}"
        )
    return payload


def _load_parent(root: Path):
    payload = _accepted_git_blob(root, PARENT_SOURCE, PARENT_PATH, PARENT_BLOB)
    module = types.ModuleType("nembra_final_go_retirement_dispatch_parent")
    module.__file__ = str((root / PARENT_PATH).resolve())
    module.__nembra_accepted_parent_source__ = PARENT_SOURCE
    module.__nembra_accepted_parent_blob__ = PARENT_BLOB
    try:
        exec(
            compile(payload, f"git:{PARENT_SOURCE}:{PARENT_PATH}", "exec", dont_inherit=True),
            module.__dict__,
        )
    except Exception as error:
        raise BuildInputManifestFinalGoError(
            "accepted retirement-dispatch Final-GO parent could not execute"
        ) from error
    return module


def _load_manifest_helper(root: Path):
    payload = _accepted_git_blob(root, "HEAD", MANIFEST_HELPER_PATH, MANIFEST_HELPER_BLOB)
    module = types.ModuleType("nembra_accepted_build_input_snapshot")
    module.__file__ = str((root / MANIFEST_HELPER_PATH).resolve())
    try:
        exec(compile(payload, module.__file__, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise BuildInputManifestFinalGoError(
            "accepted build-input snapshot helper could not execute"
        ) from error
    if getattr(module, "SCHEMA_VERSION", None) != MANIFEST_SCHEMA_VERSION:
        raise BuildInputManifestFinalGoError("accepted build-input manifest schema moved")
    subjects = tuple(path.as_posix() for path in getattr(module, "GENERATED_SUBJECTS", ()))
    if subjects != EXPECTED_GENERATED_SUBJECTS:
        raise BuildInputManifestFinalGoError("accepted build-input manifest subject set moved")
    derive = getattr(module, "generated_manifest_sha256", None)
    if not callable(derive):
        raise BuildInputManifestFinalGoError("accepted build-input helper exposes no digest authority")
    return module


def _git_text(root: Path, *arguments: str) -> str:
    try:
        return subprocess.run(
            ["/usr/bin/git", "-C", str(root), *arguments],
            env=_closed_git_environment(),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise BuildInputManifestFinalGoError("candidate Git authority unavailable") from error


def _canonical_digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or HEX64.fullmatch(value) is None or value != value.lower():
        raise BuildInputManifestFinalGoError(f"{label} is not canonical lowercase SHA-256")
    return value


def derive_generated_manifest_sha256(candidate_repo: Path, source: str) -> str:
    root = candidate_repo.expanduser().resolve(strict=True)
    source = source.lower()
    if HEX40.fullmatch(source) is None:
        raise BuildInputManifestFinalGoError("candidate source is not canonical 40-hex")
    if _git_text(root, "rev-parse", "HEAD").lower() != source:
        raise BuildInputManifestFinalGoError("candidate checkout is not exact reviewed source")
    if _git_text(root, "status", "--porcelain=v1", "--untracked-files=no"):
        raise BuildInputManifestFinalGoError("candidate tracked worktree is not clean")

    helper = _load_manifest_helper(Path(__file__).resolve().parents[2])
    try:
        first = helper.generated_manifest_sha256(root, source)
        second = helper.generated_manifest_sha256(root, source)
    except Exception as error:
        raise BuildInputManifestFinalGoError(
            "accepted helper rejected current generated/private build inputs"
        ) from error
    first = _canonical_digest(first, "current generated build-input manifest")
    second = _canonical_digest(second, "re-read generated build-input manifest")
    if first != second:
        raise BuildInputManifestFinalGoError("generated/private build-input manifest changed during review")
    if _git_text(root, "rev-parse", "HEAD").lower() != source:
        raise BuildInputManifestFinalGoError("candidate source moved during manifest review")
    if _git_text(root, "status", "--porcelain=v1", "--untracked-files=no"):
        raise BuildInputManifestFinalGoError("candidate tracked worktree changed during manifest review")
    return first


def review_v4(
    pr: int,
    review_id: int,
    source: str,
    visual: dict[str, Any],
    get: Callable[[str], tuple[bytes, dict[str, Any]]],
    *,
    semantic: dict[str, Any],
) -> dict[str, Any]:
    pos = semantic.get("pos")
    canon = semantic.get("canon")
    obj = semantic.get("obj")
    sha = semantic.get("sha")
    if not all(callable(value) for value in (pos, canon, obj, sha)):
        raise BuildInputManifestFinalGoError("semantic review primitives are unavailable")
    review_id = pos(review_id, "candidate review ID")
    _raw, review = get(f"/pulls/{pr}/reviews/{review_id}")
    body = review.get("body")
    if not isinstance(body, str) or not body.strip():
        raise BuildInputManifestFinalGoError("GitHub candidate review body missing")
    payload = obj(body.encode(), "GitHub candidate review body")
    required = {
        "schemaVersion",
        "authority",
        "sourceCommitSHA",
        "visualRunID",
        "visualArtifactID",
        "standardScreenshotSHA256",
        "accessibilityScreenshotSHA256",
        "tuyaDependencyLockSHA256",
        REVIEW_KEY,
        "verdict",
    }
    if set(payload) != required:
        raise BuildInputManifestFinalGoError("GitHub candidate review v4 key set mismatch")
    lock_digest = _canonical_digest(payload.get("tuyaDependencyLockSHA256"), "reviewed Tuya lock")
    manifest_digest = _canonical_digest(payload.get(REVIEW_KEY), "reviewed generated build-input manifest")
    if (
        payload.get("schemaVersion") != 4
        or payload.get("authority") != REVIEW_AUTHORITY
        or canon(payload.get("sourceCommitSHA"), "candidate review source") != source
        or payload.get("visualRunID") != visual.get("runID")
        or payload.get("visualArtifactID") != visual.get("artifactID")
        or payload.get("verdict") != "accepted"
    ):
        raise BuildInputManifestFinalGoError("GitHub candidate review v4 authority mismatch")
    screenshots = visual.get("screenshots")
    if not isinstance(screenshots, dict):
        raise BuildInputManifestFinalGoError("visual review screenshots missing")
    try:
        standard = screenshots["unprovisioned-dark-standard"]["sha256"]
        accessibility = screenshots["unprovisioned-dark-accessibility-xxxl"]["sha256"]
    except (KeyError, TypeError) as error:
        raise BuildInputManifestFinalGoError("visual review screenshot authority missing") from error
    if (
        payload.get("standardScreenshotSHA256") != standard
        or payload.get("accessibilityScreenshotSHA256") != accessibility
    ):
        raise BuildInputManifestFinalGoError("GitHub candidate review v4 screenshot mismatch")

    user = review.get("user", {})
    if (
        review.get("id") != review_id
        or review.get("state") not in {"COMMENTED", "APPROVED"}
        or canon(review.get("commit_id"), "candidate review commit") != source
        or not isinstance(user, dict)
        or user.get("login") != OWNER
        or review.get("author_association") != "OWNER"
    ):
        raise BuildInputManifestFinalGoError("GitHub candidate review v4 custody mismatch")
    stamp = review.get("submitted_at")
    if not isinstance(stamp, str) or not stamp.endswith("Z"):
        raise BuildInputManifestFinalGoError("GitHub candidate review v4 timestamp invalid")
    try:
        datetime.fromisoformat(stamp[:-1] + "+00:00")
    except ValueError as error:
        raise BuildInputManifestFinalGoError("GitHub candidate review v4 timestamp invalid") from error

    return {
        "authority": REVIEW_AUTHORITY,
        "reviewID": review_id,
        "reviewNodeID": review.get("node_id"),
        "reviewBodySHA256": sha(body.encode()),
        "reviewedAtUTC": stamp,
        "reviewer": OWNER,
        "state": review.get("state"),
        "verdict": "accepted",
        "standardScreenshotSHA256": standard,
        "accessibilityScreenshotSHA256": accessibility,
        "tuyaDependencyLockSHA256": lock_digest,
        REVIEW_KEY: manifest_digest,
    }


@contextlib.contextmanager
def _semantic_manifest_authority(
    parent: Any,
    *,
    candidate_repo: Path,
    source: str,
) -> Iterator[dict[str, Any]]:
    semantic_build = getattr(parent, "_SEMANTIC_BUILD", None)
    semantic = getattr(semantic_build, "__globals__", None)
    if not callable(semantic_build) or not isinstance(semantic, dict):
        raise BuildInputManifestFinalGoError("accepted parent exposes no exact semantic build globals")
    original_review = semantic.get("review")
    original_environment = semantic.get("installer_environment")
    if not callable(original_review) or not callable(original_environment):
        raise BuildInputManifestFinalGoError("accepted semantic review/environment seams moved")
    state: dict[str, Any] = {"review": None, "digest": None}

    def review_adapter(
        pr: int,
        review_id: int,
        item_source: str,
        visual: dict[str, Any],
        get: Callable[[str], tuple[bytes, dict[str, Any]]],
    ) -> dict[str, Any]:
        reviewed = review_v4(pr, review_id, item_source, visual, get, semantic=semantic)
        current = derive_generated_manifest_sha256(candidate_repo, item_source)
        accepted = reviewed[REVIEW_KEY]
        if current != accepted:
            raise BuildInputManifestFinalGoError(
                "current generated/private build inputs do not match owner-reviewed manifest"
            )
        if state["digest"] is None:
            state["digest"] = accepted
            state["review"] = reviewed
        elif state["digest"] != accepted or state["review"] != reviewed:
            raise BuildInputManifestFinalGoError("reviewed build-input authority changed during Final-GO")
        return reviewed

    def environment_adapter(
        device: Path,
        device_digest: str,
        accepted_lock_sha256: str,
    ) -> dict[str, str]:
        accepted = state.get("digest")
        if not isinstance(accepted, str) or HEX64.fullmatch(accepted) is None:
            raise BuildInputManifestFinalGoError(
                "installer environment requested before owner-reviewed build-input authority"
            )
        environment = original_environment(device, device_digest, accepted_lock_sha256)
        if not isinstance(environment, dict):
            raise BuildInputManifestFinalGoError("accepted installer environment is malformed")
        if ENV_KEY in environment:
            raise BuildInputManifestFinalGoError(
                "parent installer environment unexpectedly already owns build-input manifest authority"
            )
        environment = dict(environment)
        environment[ENV_KEY] = accepted
        return environment

    semantic["review"] = review_adapter
    semantic["installer_environment"] = environment_adapter
    try:
        yield state
    finally:
        semantic["review"] = original_review
        semantic["installer_environment"] = original_environment


def build(*, candidate_repo: Path, source: str, parent_module: Any | None = None, **kwargs: Any) -> dict[str, Any]:
    root = Path(__file__).resolve().parents[2]
    parent = parent_module or _load_parent(root)
    source = source.lower()
    if HEX40.fullmatch(source) is None:
        raise BuildInputManifestFinalGoError("Final-GO candidate source is malformed")
    parent_build = getattr(parent, "build", None)
    if not callable(parent_build):
        raise BuildInputManifestFinalGoError("accepted retirement-dispatch parent exposes no build")
    with _semantic_manifest_authority(parent, candidate_repo=candidate_repo, source=source) as state:
        record = parent_build(candidate_repo=candidate_repo, source=source, **kwargs)
    if not isinstance(record, dict):
        raise BuildInputManifestFinalGoError("accepted parent returned no Final-GO record")
    review = state.get("review")
    digest = state.get("digest")
    if not isinstance(review, dict) or not isinstance(digest, str):
        raise BuildInputManifestFinalGoError("accepted build completed without reviewed manifest authority")
    if record.get("visualReview") != review:
        raise BuildInputManifestFinalGoError("accepted parent did not retain the owner review v4")
    if record.get("physicalResultCollected") is not False:
        raise BuildInputManifestFinalGoError("build-input control child may not promote physical authority")
    return {
        **record,
        "acceptedGeneratedBuildInputManifestSHA256": digest,
        "generatedBuildInputManifestAuthority": {
            "authority": "nembra-capture-generated-build-input-manifest-control-v1",
            "reviewAuthority": REVIEW_AUTHORITY,
            "manifestHelperGitBlob": MANIFEST_HELPER_BLOB,
            "manifestSchemaVersion": MANIFEST_SCHEMA_VERSION,
            "acceptedSHA256": digest,
            "installerEnvironmentKey": ENV_KEY,
            "installerConsumerIntegrated": False,
            "physicalAuthorityCreated": False,
        },
    }


def __getattr__(name: str) -> Any:
    return getattr(_load_parent(Path(__file__).resolve().parents[2]), name)


if __name__ == "__main__":
    raise SystemExit(
        "Build-input manifest Final-GO control is an exact-head tested issuer ingredient; "
        "installer consumption and physical authorization remain NO-GO."
    )
