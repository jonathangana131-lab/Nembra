#!/usr/bin/env python3
"""Carry current private-review build authority into authenticated stationary Final GO.

This layer is a direct child of the accepted generated-subject control plane. It
keeps that parent's sealed installer and execution modules intact, upgrades the
single owner review to v5, and carries only secret-safe private authority into
the installer environment: the opaque private-review HMAC plus the exact source
SHA-256 for each authority helper that the current field build executes.

The generated-subject parent is never imported from its mutable checkout path.
It is loaded from the exact Git blob at this control HEAD and must equal the
accepted #2775 parent blob before any parent code executes.
"""
from __future__ import annotations

import contextlib
import hashlib
import json
import re
import stat
import subprocess
import types
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Iterator

REPO = "jonathangana131-lab/Nembra"
OWNER = "jonathangana131-lab"
PARENT_BRANCH = "control/v14-auth-stationary-generated-subject-r3-sol"
WORKFLOW_NAME = "Capture Authenticated Stationary Private Review Final GO"
WORKFLOW_PATH = ".github/workflows/capture-authenticated-stationary-private-review-final-go.yml"
REVIEW_AUTHORITY = "nembra-capture-human-review-github-v5"
FINAL_AUTHORITY = "nembra-authenticated-stationary-final-go-v4"
PRIVATE_CONTROL_EXTENSION = "nembra-private-review-helper-control-extension-v2"
HEX64 = re.compile(r"^[0-9a-f]{64}$")

GENERATED_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
PARENT_GENERATED_MODULE_GIT_BLOB = "13720f812498d86f55c0f1ca4e98b873f0793cb9"

PRIVATE_REVIEW_COMMITMENT_KEY = "privateReviewCommitmentSHA256"
PRIVATE_REVIEW_HELPER_KEY = "privateReviewHelperSHA256"
PROVENANCE_HELPER_KEY = "provenanceHelperSHA256"
GENERATED_HELPER_KEY = "generatedBuildSubjectHelperSHA256"

PRIVATE_REVIEW_ENV = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"
PRIVATE_REVIEW_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"
PROVENANCE_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PROVENANCE_HELPER_SHA256"
GENERATED_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_SUBJECT_HELPER_SHA256"

PRIVATE_REVIEW_HELPER_PATH = "Scripts/capture_private_review_commitment.py"
PROVENANCE_HELPER_PATH = "Scripts/capture_tuya_private_input_provenance.py"
PRIVATE_REVIEW_DOMAIN = "nembra-capture-private-input-review-v1"


class PrivateReviewGoError(RuntimeError):
    pass


def _git_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "LANG": "C",
        "LC_ALL": "C",
    }


def _physical_git_command(repo: Path, *args: str) -> list[str]:
    """Bind Git metadata and worktree operations to one physical checkout root."""
    root = repo.expanduser().resolve(strict=True)
    marker = root / ".git"
    try:
        marker_stat = marker.lstat()
    except OSError as error:
        raise PrivateReviewGoError("candidate physical Git directory unavailable") from error
    if not stat.S_ISDIR(marker_stat.st_mode):
        raise PrivateReviewGoError("candidate physical Git authority requires a real .git directory")
    try:
        git_dir = marker.resolve(strict=True)
    except OSError as error:
        raise PrivateReviewGoError("candidate physical Git directory could not be resolved") from error
    return [
        "/usr/bin/git",
        "-C", str(root),
        f"--git-dir={git_dir}",
        f"--work-tree={root}",
        "-c", f"core.worktree={root}",
        *args,
    ]


def _physical_git(repo: Path, *args: str) -> str:
    try:
        return subprocess.run(
            _physical_git_command(repo, *args),
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_git_environment(),
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise PrivateReviewGoError("candidate physical Git custody failed") from error


def _physical_git_bytes(repo: Path, *args: str) -> bytes:
    try:
        return subprocess.run(
            _physical_git_command(repo, *args),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_git_environment(),
        ).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        raise PrivateReviewGoError("candidate physical Git byte custody failed") from error


@contextlib.contextmanager
def _physical_worktree_git(base: Any) -> Iterator[None]:
    """Make accepted parent helpers describe the exact physical checkout they inspect."""
    original_git = getattr(base, "git", None)
    original_git_bytes = getattr(base, "git_bytes", None)
    if not callable(original_git) or not callable(original_git_bytes):
        raise PrivateReviewGoError("parent Final-GO Git authority is not patchable")
    base.git = _physical_git
    base.git_bytes = _physical_git_bytes
    try:
        yield
    finally:
        base.git = original_git
        base.git_bytes = original_git_bytes


def _load_generated_module():
    root = Path(__file__).resolve().parents[2]
    environment = _git_environment()
    try:
        source = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout.strip().lower()
        accepted_blob = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "rev-parse", f"{source}:{GENERATED_MODULE_PATH}"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout.strip().lower()
        payload = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "cat-file", "blob", accepted_blob],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout
        verified = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "hash-object", "--stdin"],
            input=payload,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout.decode("ascii").strip().lower()
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        raise PrivateReviewGoError("generated-subject Final-GO parent Git custody failed") from error
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", source):
        raise PrivateReviewGoError("private-review Final-GO control source is invalid")
    if accepted_blob != PARENT_GENERATED_MODULE_GIT_BLOB:
        raise PrivateReviewGoError("generated-subject parent Git blob is not the accepted #2775 authority")
    if not payload or verified != accepted_blob:
        raise PrivateReviewGoError("generated-subject parent execution bytes failed Git identity verification")
    filename = f"git:{source}:{GENERATED_MODULE_PATH}"
    module = types.ModuleType("nembra_generated_subject_final_go_parent")
    module.__file__ = filename
    module.__nembra_accepted_control_source__ = source
    module.__nembra_accepted_control_blob__ = accepted_blob
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise PrivateReviewGoError("accepted generated-subject Final-GO parent could not execute") from error
    return module


generated = _load_generated_module()

CHILD_AUTHORITY_PATHS = (
    "scripts/ci/es80_authenticated_stationary_private_review_final_go.py",
    GENERATED_MODULE_PATH,
    "scripts/ci/es80_authenticated_stationary_final_go.py",
    "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
    "scripts/ci/es80_today_final_go_publication.py",
    WORKFLOW_PATH,
    "scripts/ci/tests/test_es80_authenticated_stationary_private_review_final_go.py",
)
PARENT_PINNED_PATHS = (
    GENERATED_MODULE_PATH,
    "scripts/ci/es80_authenticated_stationary_final_go.py",
    "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
    "scripts/ci/es80_today_final_go_publication.py",
)


def _canonical_digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or not HEX64.fullmatch(value) or value != value.lower():
        raise PrivateReviewGoError(f"{label} is not canonical lowercase SHA-256")
    return value


def _promotable(pr: dict[str, Any]) -> bool:
    state = pr.get("state")
    return (state == "open" and pr.get("draft") is False) or (
        state == "closed" and bool(pr.get("merged_at"))
    )


def _workflow_bound(run: dict[str, Any], *, pr: int, branch: str) -> bool:
    pulls = run.get("pull_requests", [])
    if run.get("event") == "pull_request":
        return (
            isinstance(pulls, list)
            and any(isinstance(item, dict) and item.get("number") == pr for item in pulls)
        ) or (pulls == [] and run.get("head_branch") == branch)
    return run.get("event") == "push" and run.get("head_branch") == branch


def _worktree_blob(base: Any, root: Path, source: str, relative: str) -> str:
    path = root / relative
    if not path.is_file() or path.is_symlink():
        raise PrivateReviewGoError(f"control authority path is not a regular non-symlink file: {relative}")
    accepted = base.git(root, "rev-parse", f"{source}:{relative}").lower()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted):
        raise PrivateReviewGoError(f"control authority Git blob invalid: {relative}")
    verbose = base.git(root, "ls-files", "-v", "--", relative)
    tagged = base.git(root, "ls-files", "-t", "--", relative)
    if not verbose or verbose[:1].islower() or tagged.startswith("S "):
        raise PrivateReviewGoError(f"control authority path has suppressed worktree tracking: {relative}")
    actual = base.git(root, "hash-object", "--no-filters", "--", relative).lower()
    if actual != accepted:
        raise PrivateReviewGoError(f"control authority worktree bytes differ from accepted Git blob: {relative}")
    return accepted


def private_control_plane(
    authority_repo: Path,
    pr: int,
    run_id: int,
    *,
    parent_pr: int,
    parent_run_id: int,
    get: Callable[[str], tuple[bytes, dict[str, Any]]],
    base: Any,
) -> dict[str, Any]:
    root = authority_repo.expanduser().resolve(strict=True)
    source = base.canon(base.git(root, "rev-parse", "HEAD"), "private-review control-plane HEAD")
    if base.git(root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise PrivateReviewGoError("private-review control-plane checkout is not clean")

    pr = base.pos(pr, "private-review control-plane PR")
    parent_pr = base.pos(parent_pr, "generated-subject parent PR")
    run_id = base.pos(run_id, "private-review workflow run")
    parent_run_id = base.pos(parent_run_id, "generated-subject parent workflow run")

    _, child = get(f"/pulls/{pr}")
    _, parent = get(f"/pulls/{parent_pr}")
    child_head = child.get("head", {})
    child_base = child.get("base", {})
    parent_head = parent.get("head", {})
    parent_base = parent.get("base", {})
    child_branch = child_head.get("ref")
    parent_sha = base.canon(parent_head.get("sha"), "generated-subject parent head")
    if (
        base.canon(child_head.get("sha"), "private-review PR head") != source
        or child_head.get("repo", {}).get("full_name") != REPO
        or child_base.get("ref") != PARENT_BRANCH
        or base.canon(child_base.get("sha"), "private-review live base") != parent_sha
        or not isinstance(child_branch, str)
        or not child_branch
        or not _promotable(child)
    ):
        raise PrivateReviewGoError("private-review control-plane PR is stale or not promotable")
    if (
        parent_head.get("ref") != PARENT_BRANCH
        or parent_head.get("repo", {}).get("full_name") != REPO
        or parent_base.get("ref") != generated.PARENT_BRANCH
        or not _promotable(parent)
    ):
        raise PrivateReviewGoError("generated-subject parent control plane is stale or not promotable")

    _, current_main = get("/branches/main")
    main_sha = base.canon(current_main.get("commit", {}).get("sha"), "current main")
    _, parent_compare = get(f"/compare/{main_sha}...{parent_sha}")
    if (
        parent_compare.get("status") not in {"ahead", "identical"}
        or base.canon(parent_compare.get("merge_base_commit", {}).get("sha"), "parent/main merge base") != main_sha
    ):
        raise PrivateReviewGoError("generated-subject parent does not contain exact current main")
    _, child_compare = get(f"/compare/{parent_sha}...{source}")
    if (
        child_compare.get("status") not in {"ahead", "identical"}
        or base.canon(child_compare.get("merge_base_commit", {}).get("sha"), "child/parent merge base") != parent_sha
    ):
        raise PrivateReviewGoError("private-review control plane does not contain exact generated-subject parent")

    _, parent_run = get(f"/actions/runs/{parent_run_id}")
    if (
        parent_run.get("name") != generated.WORKFLOW_NAME
        or parent_run.get("path") != generated.WORKFLOW_PATH
        or base.canon(parent_run.get("head_sha"), "generated-subject workflow head") != parent_sha
        or parent_run.get("status") != "completed"
        or parent_run.get("conclusion") != "success"
        or not _workflow_bound(parent_run, pr=parent_pr, branch=PARENT_BRANCH)
    ):
        raise PrivateReviewGoError("generated-subject parent workflow is not exact terminal SUCCESS")

    _, child_run = get(f"/actions/runs/{run_id}")
    if (
        child_run.get("name") != WORKFLOW_NAME
        or child_run.get("path") != WORKFLOW_PATH
        or base.canon(child_run.get("head_sha"), "private-review workflow head") != source
        or child_run.get("status") != "completed"
        or child_run.get("conclusion") != "success"
        or not _workflow_bound(child_run, pr=pr, branch=child_branch)
    ):
        raise PrivateReviewGoError("private-review workflow is not exact terminal SUCCESS")

    blobs = {relative: _worktree_blob(base, root, source, relative) for relative in CHILD_AUTHORITY_PATHS}
    for relative in PARENT_PINNED_PATHS:
        parent_blob = base.git(root, "rev-parse", f"{parent_sha}:{relative}").lower()
        if parent_blob != blobs[relative]:
            raise PrivateReviewGoError(f"child modified generated-subject parent execution module: {relative}")
    if blobs[GENERATED_MODULE_PATH] != PARENT_GENERATED_MODULE_GIT_BLOB:
        raise PrivateReviewGoError("private-review control plane lost the accepted generated-parent blob")

    return {
        "authority": "nembra-authenticated-stationary-go-control-plane-v1",
        "extensionAuthority": generated.CONTROL_EXTENSION,
        "privateReviewExtensionAuthority": PRIVATE_CONTROL_EXTENSION,
        "sourceCommitSHA": source,
        "prNumber": pr,
        "headBranch": child_branch,
        "parentPRNumber": parent_pr,
        "parentSourceCommitSHA": parent_sha,
        "mainSHA": main_sha,
        "state": child.get("state"),
        "merged": bool(child.get("merged_at")),
        "draft": child.get("draft"),
        "workflowRunID": run_id,
        "workflowName": WORKFLOW_NAME,
        "workflowPath": WORKFLOW_PATH,
        "parentWorkflowRunID": parent_run_id,
        "gitBlobs": blobs,
    }


def review_v5(
    pr: int,
    review_id: int,
    source: str,
    visual: dict[str, Any],
    get: Callable[[str], tuple[bytes, dict[str, Any]]],
    *,
    base: Any,
) -> dict[str, Any]:
    review_id = base.pos(review_id, "candidate review ID")
    _, review = get(f"/pulls/{pr}/reviews/{review_id}")
    body = review.get("body")
    if not isinstance(body, str) or not body.strip():
        raise PrivateReviewGoError("GitHub candidate review body missing")
    payload = base.obj(body.encode(), "GitHub candidate review body")
    required = {
        "schemaVersion", "authority", "sourceCommitSHA", "visualRunID", "visualArtifactID",
        "standardScreenshotSHA256", "accessibilityScreenshotSHA256", "tuyaDependencyLockSHA256",
        generated.GENERATED_KEY, PRIVATE_REVIEW_COMMITMENT_KEY, PRIVATE_REVIEW_HELPER_KEY,
        PROVENANCE_HELPER_KEY, GENERATED_HELPER_KEY, "verdict",
    }
    lock_digest = _canonical_digest(payload.get("tuyaDependencyLockSHA256"), "reviewed Tuya dependency lock")
    generated_digest = _canonical_digest(payload.get(generated.GENERATED_KEY), "reviewed CocoaPods generated build subject")
    private_commitment = _canonical_digest(payload.get(PRIVATE_REVIEW_COMMITMENT_KEY), "reviewed private input HMAC")
    private_helper = _canonical_digest(payload.get(PRIVATE_REVIEW_HELPER_KEY), "reviewed private-review helper")
    provenance_helper = _canonical_digest(payload.get(PROVENANCE_HELPER_KEY), "reviewed provenance helper")
    generated_helper = _canonical_digest(payload.get(GENERATED_HELPER_KEY), "reviewed generated-subject helper")
    if (
        set(payload) != required
        or payload.get("schemaVersion") != 5
        or payload.get("authority") != REVIEW_AUTHORITY
        or base.canon(payload.get("sourceCommitSHA"), "candidate review source") != source
        or payload.get("visualRunID") != visual["runID"]
        or payload.get("visualArtifactID") != visual["artifactID"]
        or payload.get("verdict") != "accepted"
    ):
        raise PrivateReviewGoError("GitHub candidate review v5 authority mismatch")

    user = review.get("user", {})
    if (
        review.get("id") != review_id
        or review.get("state") not in {"COMMENTED", "APPROVED"}
        or base.canon(review.get("commit_id"), "candidate review commit") != source
        or user.get("login") != OWNER
        or review.get("author_association") != "OWNER"
    ):
        raise PrivateReviewGoError("GitHub candidate review v5 custody mismatch")
    stamp = review.get("submitted_at")
    if not isinstance(stamp, str) or not stamp.endswith("Z"):
        raise PrivateReviewGoError("GitHub candidate review v5 timestamp invalid")
    try:
        datetime.fromisoformat(stamp[:-1] + "+00:00")
    except ValueError as error:
        raise PrivateReviewGoError("GitHub candidate review v5 timestamp invalid") from error

    screenshots = visual["screenshots"]
    standard = screenshots["unprovisioned-dark-standard"]["sha256"]
    accessibility = screenshots["unprovisioned-dark-accessibility-xxxl"]["sha256"]
    if payload["standardScreenshotSHA256"] != standard or payload["accessibilityScreenshotSHA256"] != accessibility:
        raise PrivateReviewGoError("GitHub candidate review v5 screenshot mismatch")

    return {
        "authority": REVIEW_AUTHORITY,
        "reviewID": review_id,
        "reviewNodeID": review.get("node_id"),
        "reviewBodySHA256": base.sha(body.encode()),
        "reviewedAtUTC": stamp,
        "reviewer": OWNER,
        "state": review["state"],
        "verdict": "accepted",
        "standardScreenshotSHA256": standard,
        "accessibilityScreenshotSHA256": accessibility,
        "tuyaDependencyLockSHA256": lock_digest,
        generated.GENERATED_KEY: generated_digest,
        PRIVATE_REVIEW_COMMITMENT_KEY: private_commitment,
        PRIVATE_REVIEW_HELPER_KEY: private_helper,
        PROVENANCE_HELPER_KEY: provenance_helper,
        GENERATED_HELPER_KEY: generated_helper,
    }


def _accepted_candidate_bytes(base: Any, root: Path, source: str, relative: str) -> tuple[str, bytes]:
    accepted = base.git(root, "rev-parse", f"{source}:{relative}").lower()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted):
        raise PrivateReviewGoError(f"candidate authority Git blob invalid: {relative}")
    payload = base.git_bytes(root, "show", f"{source}:{relative}")
    if not isinstance(payload, bytes) or not payload or len(payload) > 2 * 1024 * 1024:
        raise PrivateReviewGoError(f"candidate authority Git bytes are invalid: {relative}")
    if generated._git_blob_oid(payload, accepted) != accepted:
        raise PrivateReviewGoError(f"candidate authority Git bytes failed object identity: {relative}")
    return accepted, payload


def candidate_private_authority(
    candidate_repo: Path,
    source: str,
    review: dict[str, Any],
    *,
    base: Any,
    derive_subject: Callable[[Path, str, Any], str] = generated._current_generated_subject,
) -> dict[str, Any]:
    root = candidate_repo.expanduser().resolve(strict=True)
    if base.canon(base.git(root, "rev-parse", "HEAD"), "candidate HEAD") != source:
        raise PrivateReviewGoError("private-review candidate is not exact accepted source")
    if base.git(root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise PrivateReviewGoError("private-review candidate checkout is not clean")

    generated_candidate = generated.candidate_generated_authority(
        root, source, review[generated.GENERATED_KEY], base=base, derive_subject=derive_subject
    )
    helper_contracts = (
        (PRIVATE_REVIEW_HELPER_PATH, PRIVATE_REVIEW_HELPER_KEY),
        (PROVENANCE_HELPER_PATH, PROVENANCE_HELPER_KEY),
        (generated.GENERATED_HELPER_PATH, GENERATED_HELPER_KEY),
    )
    helper_blobs: dict[str, str] = {}
    helper_sha256: dict[str, str] = {}
    for relative, key in helper_contracts:
        blob, payload = _accepted_candidate_bytes(base, root, source, relative)
        digest = hashlib.sha256(payload).hexdigest()
        if digest != review[key]:
            raise PrivateReviewGoError(f"reviewed helper SHA-256 does not match exact accepted candidate bytes: {relative}")
        helper_blobs[relative] = blob
        helper_sha256[key] = digest

    _, private_helper = _accepted_candidate_bytes(base, root, source, PRIVATE_REVIEW_HELPER_PATH)
    _, bootstrap_raw = _accepted_candidate_bytes(base, root, source, "Scripts/bootstrap_capture_tuya_sdk.sh")
    _, guard_raw = _accepted_candidate_bytes(base, root, source, "Scripts/capture_tuya_private_input_build_guard.py")
    try:
        private_text = private_helper.decode("utf-8")
        bootstrap = bootstrap_raw.decode("utf-8")
        guard = guard_raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PrivateReviewGoError("private-review candidate authority source is not UTF-8") from error
    required_fragments = (
        (private_text, PRIVATE_REVIEW_DOMAIN),
        (bootstrap, PRIVATE_REVIEW_ENV),
        (bootstrap, PRIVATE_REVIEW_HELPER_ENV),
        (bootstrap, PROVENANCE_HELPER_ENV),
        (bootstrap, GENERATED_HELPER_ENV),
        (bootstrap, "run_accepted_python_helper()"),
        (guard, PRIVATE_REVIEW_HELPER_ENV),
        (guard, PROVENANCE_HELPER_ENV),
        (guard, GENERATED_HELPER_ENV),
        (guard, "_load_accepted_helper_module"),
    )
    if any(fragment not in text for text, fragment in required_fragments):
        raise PrivateReviewGoError("candidate source lacks current private-review/helper execution authority")

    return {
        "authority": "nembra-private-review-helper-candidate-v2",
        "sourceCommitSHA": source,
        PRIVATE_REVIEW_COMMITMENT_KEY: review[PRIVATE_REVIEW_COMMITMENT_KEY],
        **helper_sha256,
        "generatedBuildSubjectCandidate": generated_candidate,
        "gitBlobs": helper_blobs,
    }


def _private_environment_adapter(original_adapter: Callable[..., Callable[..., dict[str, str]]], review: dict[str, Any]):
    values = {
        PRIVATE_REVIEW_ENV: _canonical_digest(review[PRIVATE_REVIEW_COMMITMENT_KEY], "accepted private review HMAC"),
        PRIVATE_REVIEW_HELPER_ENV: _canonical_digest(review[PRIVATE_REVIEW_HELPER_KEY], "accepted private-review helper"),
        PROVENANCE_HELPER_ENV: _canonical_digest(review[PROVENANCE_HELPER_KEY], "accepted provenance helper"),
        GENERATED_HELPER_ENV: _canonical_digest(review[GENERATED_HELPER_KEY], "accepted generated helper"),
    }

    def adapter(base: Any, accepted_generated_digest: str):
        generated_environment = original_adapter(base, accepted_generated_digest)

        def extended(device: Path, device_digest: str, accepted_lock_sha256: str) -> dict[str, str]:
            environment = generated_environment(device, device_digest, accepted_lock_sha256)
            collisions = sorted(key for key in values if key in environment)
            if collisions:
                raise PrivateReviewGoError("generated-subject parent unexpectedly owns private authority: " + ", ".join(collisions))
            environment.update(values)
            return environment

        return extended

    return adapter


@contextlib.contextmanager
def _generated_extensions(*, review: dict[str, Any]) -> Iterator[None]:
    if getattr(generated.build, "__globals__", None) is not vars(generated):
        raise PrivateReviewGoError("generated-subject parent build globals are not exact module authority")
    original_review = generated.review_v3
    original_environment_adapter = generated._environment_adapter
    original_control_plane = generated.generated_control_plane

    def review_adapter(pr, review_id, source, visual, get, *, base):
        return review_v5(pr, review_id, source, visual, get, base=base)

    generated.review_v3 = review_adapter
    generated._environment_adapter = _private_environment_adapter(original_environment_adapter, review)
    generated.generated_control_plane = private_control_plane
    try:
        yield
    finally:
        generated.review_v3 = original_review
        generated._environment_adapter = original_environment_adapter
        generated.generated_control_plane = original_control_plane


def build(
    *,
    authority_repo: Path,
    authority_pr: int,
    authority_run: int,
    generated_authority_pr: int,
    generated_authority_run: int,
    candidate_repo: Path,
    source: str,
    pr: int,
    runs: dict[str, int],
    artifact_id: int,
    review_id: int,
    archive: Path,
    device_file: Path,
    retained_ipa: Path,
    get: Callable[[str], tuple[bytes, dict[str, Any]]] | None = None,
    base_module: Any | None = None,
    derive_subject: Callable[[Path, str, Any], str] = generated._current_generated_subject,
    now: Any = None,
) -> dict[str, Any]:
    base = base_module or generated._load_base_module()
    get = get or base.api
    source = base.canon(source, "source")
    pr = base.pos(pr, "PR")

    visual_subject = base.visual(source, runs[base.VISUAL], base.pos(artifact_id, "artifact"), archive, get)
    pre_review = review_v5(pr, review_id, source, visual_subject, get, base=base)
    with _physical_worktree_git(base):
        pre_private_candidate = candidate_private_authority(
            candidate_repo, source, pre_review, base=base, derive_subject=derive_subject
        )

    with _generated_extensions(review=pre_review), _physical_worktree_git(base):
        record = generated.build(
            authority_repo=authority_repo,
            authority_pr=authority_pr,
            authority_run=authority_run,
            parent_authority_pr=generated_authority_pr,
            parent_authority_run=generated_authority_run,
            candidate_repo=candidate_repo,
            source=source,
            pr=pr,
            runs=runs,
            artifact_id=artifact_id,
            review_id=review_id,
            archive=archive,
            device_file=device_file,
            retained_ipa=retained_ipa,
            get=get,
            base_module=base,
            derive_subject=derive_subject,
            now=now,
        )

    post_visual = base.visual(source, runs[base.VISUAL], artifact_id, archive, get)
    post_review = review_v5(pr, review_id, source, post_visual, get, base=base)
    with _physical_worktree_git(base):
        post_private_candidate = candidate_private_authority(
            candidate_repo, source, post_review, base=base, derive_subject=derive_subject
        )
    if post_visual != visual_subject or post_review != pre_review or post_private_candidate != pre_private_candidate:
        raise PrivateReviewGoError("private-review authority changed during Final-GO composition")
    if record.get("visualReview") != pre_review:
        raise PrivateReviewGoError("generated-subject Final-GO record did not retain the single v5 owner review")
    control = record.get("finalGOControlPlane")
    if (
        not isinstance(control, dict)
        or control.get("authority") != "nembra-authenticated-stationary-go-control-plane-v1"
        or control.get("extensionAuthority") != generated.CONTROL_EXTENSION
        or control.get("privateReviewExtensionAuthority") != PRIVATE_CONTROL_EXTENSION
    ):
        raise PrivateReviewGoError("Final-GO record lost private-review control authority")

    return {
        **record,
        "schemaVersion": 4,
        "authority": FINAL_AUTHORITY,
        "acceptedPrivateReviewCommitmentSHA256": pre_review[PRIVATE_REVIEW_COMMITMENT_KEY],
        "acceptedPrivateReviewHelperSHA256": pre_review[PRIVATE_REVIEW_HELPER_KEY],
        "acceptedProvenanceHelperSHA256": pre_review[PROVENANCE_HELPER_KEY],
        "acceptedGeneratedBuildSubjectHelperSHA256": pre_review[GENERATED_HELPER_KEY],
        "privateReviewCandidate": pre_private_candidate,
    }


if __name__ == "__main__":
    raise SystemExit(
        "This current-parent private-review control extension is exercised by its exact-head workflow; "
        "physical publication remains delegated to the sealed generated-subject/parent issuer."
    )
