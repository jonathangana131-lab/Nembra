#!/usr/bin/env python3
"""Extend reviewed generated-build Final GO with opaque private-input authority.

This layer deliberately preserves the selected generated-subject control plane,
its sealed installer, and the authenticated-stationary parent's accepted Git-blob
execution modules. It adds one owner-reviewed opaque private Tuya generation
commitment and carries that commitment only through the already-closed installer
environment into bootstrap/build-guard verification.
"""
from __future__ import annotations

import contextlib
import importlib.util
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Iterator

REPO = "jonathangana131-lab/Nembra"
OWNER = "jonathangana131-lab"
PARENT_BRANCH = "control/v14-auth-stationary-generated-subject-r3-sol"
WORKFLOW_NAME = "Capture Authenticated Stationary Private Review Final GO"
WORKFLOW_PATH = ".github/workflows/capture-authenticated-stationary-private-review-final-go.yml"
REVIEW_AUTHORITY = "nembra-capture-human-review-github-v4"
FINAL_AUTHORITY = "nembra-authenticated-stationary-final-go-v3"
PRIVATE_CONTROL_EXTENSION = "nembra-private-input-review-control-extension-v1"
PRIVATE_ENV = "NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT"
PRIVATE_KEY = "tuyaPrivateInputCommitment"
PRIVATE_HELPER_PATH = "Scripts/capture_tuya_private_input_review.py"
PRIVATE_HELPER_DOMAIN = "nembra-capture-private-input-review-v1"
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class PrivateReviewGoError(RuntimeError):
    pass


def _load_generated_module():
    path = Path(__file__).with_name("es80_authenticated_stationary_generated_subject_final_go.py")
    spec = importlib.util.spec_from_file_location("nembra_generated_subject_final_go_parent", path)
    if spec is None or spec.loader is None:
        raise PrivateReviewGoError("generated-subject Final-GO parent could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


generated = _load_generated_module()

CHILD_AUTHORITY_PATHS = (
    "scripts/ci/es80_authenticated_stationary_private_review_final_go.py",
    "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py",
    "scripts/ci/es80_authenticated_stationary_final_go.py",
    "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
    "scripts/ci/es80_today_final_go_publication.py",
    WORKFLOW_PATH,
    "scripts/ci/tests/test_es80_authenticated_stationary_private_review_final_go.py",
)
PARENT_PINNED_PATHS = (
    "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py",
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


def review_v4(
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
        "schemaVersion",
        "authority",
        "sourceCommitSHA",
        "visualRunID",
        "visualArtifactID",
        "standardScreenshotSHA256",
        "accessibilityScreenshotSHA256",
        "tuyaDependencyLockSHA256",
        generated.GENERATED_KEY,
        PRIVATE_KEY,
        "verdict",
    }
    lock_digest = _canonical_digest(payload.get("tuyaDependencyLockSHA256"), "reviewed Tuya dependency lock")
    generated_digest = _canonical_digest(
        payload.get(generated.GENERATED_KEY), "reviewed CocoaPods generated build subject"
    )
    private_commitment = _canonical_digest(
        payload.get(PRIVATE_KEY), "reviewed private Tuya input commitment"
    )
    if (
        set(payload) != required
        or payload.get("schemaVersion") != 4
        or payload.get("authority") != REVIEW_AUTHORITY
        or base.canon(payload.get("sourceCommitSHA"), "candidate review source") != source
        or payload.get("visualRunID") != visual["runID"]
        or payload.get("visualArtifactID") != visual["artifactID"]
        or payload.get("verdict") != "accepted"
    ):
        raise PrivateReviewGoError("GitHub candidate review v4 authority mismatch")

    user = review.get("user", {})
    if (
        review.get("id") != review_id
        or review.get("state") not in {"COMMENTED", "APPROVED"}
        or base.canon(review.get("commit_id"), "candidate review commit") != source
        or user.get("login") != OWNER
        or review.get("author_association") != "OWNER"
    ):
        raise PrivateReviewGoError("GitHub candidate review v4 custody mismatch")
    stamp = review.get("submitted_at")
    if not isinstance(stamp, str) or not stamp.endswith("Z"):
        raise PrivateReviewGoError("GitHub candidate review v4 timestamp invalid")
    try:
        datetime.fromisoformat(stamp[:-1] + "+00:00")
    except ValueError as error:
        raise PrivateReviewGoError("GitHub candidate review v4 timestamp invalid") from error

    screenshots = visual["screenshots"]
    standard = screenshots["unprovisioned-dark-standard"]["sha256"]
    accessibility = screenshots["unprovisioned-dark-accessibility-xxxl"]["sha256"]
    if (
        payload["standardScreenshotSHA256"] != standard
        or payload["accessibilityScreenshotSHA256"] != accessibility
    ):
        raise PrivateReviewGoError("GitHub candidate review v4 screenshot mismatch")

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
        PRIVATE_KEY: private_commitment,
    }


def _verified_candidate_blob(base: Any, root: Path, source: str, relative: str) -> str:
    path = root / relative
    if not path.is_file() or path.is_symlink():
        raise PrivateReviewGoError(f"private review authority path is not a regular file: {relative}")
    accepted = base.git(root, "rev-parse", f"{source}:{relative}").lower()
    actual = base.git(root, "hash-object", "--no-filters", "--", relative).lower()
    verbose = base.git(root, "ls-files", "-v", "--", relative)
    tagged = base.git(root, "ls-files", "-t", "--", relative)
    if (
        accepted != actual
        or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted)
        or not verbose
        or verbose[:1].islower()
        or tagged.startswith("S ")
    ):
        raise PrivateReviewGoError(f"private review authority Git/worktree identity drifted: {relative}")
    return accepted


def candidate_private_authority(
    candidate_repo: Path,
    source: str,
    accepted_generated_digest: str,
    accepted_private_commitment: str,
    *,
    base: Any,
    derive_subject: Callable[[Path], str] = generated._current_generated_subject,
) -> dict[str, Any]:
    root = candidate_repo.expanduser().resolve(strict=True)
    private_commitment = _canonical_digest(
        accepted_private_commitment, "accepted private Tuya input commitment"
    )
    generated_candidate = generated.candidate_generated_authority(
        root,
        source,
        accepted_generated_digest,
        base=base,
        derive_subject=derive_subject,
    )

    helper_blob = _verified_candidate_blob(base, root, source, PRIVATE_HELPER_PATH)
    helper = (root / PRIVATE_HELPER_PATH).read_text(encoding="utf-8")
    bootstrap = (root / "Scripts/bootstrap_capture_tuya_sdk.sh").read_text(encoding="utf-8")
    guard = (root / "Scripts/capture_tuya_private_input_build_guard.py").read_text(encoding="utf-8")
    required_fragments = (
        (helper, PRIVATE_HELPER_DOMAIN),
        (bootstrap, PRIVATE_ENV),
        (bootstrap, "capture_tuya_private_input_review.py"),
        (guard, "capture_tuya_private_input_review.py"),
        (guard, "_verify_accepted_private_input_subject"),
        (guard, "require_accepted_private_subject=True"),
    )
    if any(fragment not in text for text, fragment in required_fragments):
        raise PrivateReviewGoError("candidate source lacks selected private-review authority enforcement")

    return {
        "authority": "nembra-private-input-review-candidate-v1",
        "implementation": PRIVATE_HELPER_PATH,
        "sourceCommitSHA": source,
        PRIVATE_KEY: private_commitment,
        "generatedBuildSubjectCandidate": generated_candidate,
        "gitBlobs": {PRIVATE_HELPER_PATH: helper_blob},
    }


def _private_environment_adapter(
    original_adapter: Callable[[Any, str], Callable[..., dict[str, str]]],
    accepted_private_commitment: str,
):
    accepted_private_commitment = _canonical_digest(
        accepted_private_commitment, "accepted private Tuya input commitment"
    )

    def adapter(base: Any, accepted_generated_digest: str):
        generated_environment = original_adapter(base, accepted_generated_digest)

        def extended(device: Path, device_digest: str, accepted_lock_sha256: str) -> dict[str, str]:
            environment = generated_environment(device, device_digest, accepted_lock_sha256)
            if PRIVATE_ENV in environment:
                raise PrivateReviewGoError(
                    "generated-subject parent installer environment unexpectedly owns private review authority"
                )
            environment[PRIVATE_ENV] = accepted_private_commitment
            return environment

        return extended

    return adapter


@contextlib.contextmanager
def _generated_extensions(
    *,
    accepted_private_commitment: str,
) -> Iterator[None]:
    if getattr(generated.build, "__globals__", None) is not vars(generated):
        raise PrivateReviewGoError("generated-subject parent build globals are not exact module authority")
    original_review = generated.review_v3
    original_environment_adapter = generated._environment_adapter
    original_control_plane = generated.generated_control_plane

    def review_adapter(pr, review_id, source, visual, get, *, base):
        return review_v4(pr, review_id, source, visual, get, base=base)

    generated.review_v3 = review_adapter
    generated._environment_adapter = _private_environment_adapter(
        original_environment_adapter,
        accepted_private_commitment,
    )
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
    derive_subject: Callable[[Path], str] = generated._current_generated_subject,
    now: Any = None,
) -> dict[str, Any]:
    base = base_module or generated._load_base_module()
    get = get or base.api
    source = base.canon(source, "source")
    pr = base.pos(pr, "PR")

    visual_subject = base.visual(source, runs[base.VISUAL], base.pos(artifact_id, "artifact"), archive, get)
    pre_review = review_v4(pr, review_id, source, visual_subject, get, base=base)
    accepted_generated = pre_review[generated.GENERATED_KEY]
    accepted_private = pre_review[PRIVATE_KEY]
    pre_private_candidate = candidate_private_authority(
        candidate_repo,
        source,
        accepted_generated,
        accepted_private,
        base=base,
        derive_subject=derive_subject,
    )

    with _generated_extensions(accepted_private_commitment=accepted_private):
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
    post_review = review_v4(pr, review_id, source, post_visual, get, base=base)
    post_private_candidate = candidate_private_authority(
        candidate_repo,
        source,
        accepted_generated,
        accepted_private,
        base=base,
        derive_subject=derive_subject,
    )
    if (
        post_visual != visual_subject
        or post_review != pre_review
        or post_private_candidate != pre_private_candidate
    ):
        raise PrivateReviewGoError("private-review authority changed during Final-GO composition")
    if record.get("visualReview") != pre_review:
        raise PrivateReviewGoError("generated-subject Final-GO record did not retain the single v4 owner review")
    if record.get("acceptedCocoaPodsGeneratedBuildSubjectSHA256") != accepted_generated:
        raise PrivateReviewGoError("generated-subject Final-GO record lost reviewed generated authority")
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
        "schemaVersion": 3,
        "authority": FINAL_AUTHORITY,
        "acceptedTuyaPrivateInputCommitment": accepted_private,
        "privateInputReviewCandidate": pre_private_candidate,
    }


if __name__ == "__main__":
    raise SystemExit(
        "This control extension is exercised by its exact-head workflow/test harness; "
        "physical publication remains delegated to the sealed generated-subject/parent issuer."
    )
