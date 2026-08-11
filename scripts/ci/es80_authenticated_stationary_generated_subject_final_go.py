#!/usr/bin/env python3
"""Compose reviewed CocoaPods generated-build authority into authenticated Final GO.

This child deliberately preserves the current authenticated-stationary parent's
sealed installer and accepted control-module execution path. It adds one reviewed
generated CocoaPods build-subject digest to the parent's closed installer
environment and reuses the parent's default retained-artifact/publication modules
under this exact child control-plane Git authority.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import re
import subprocess
import sys
import types
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Iterator

REPO = "jonathangana131-lab/Nembra"
OWNER = "jonathangana131-lab"
PARENT_BRANCH = "control/v14-auth-stationary-final-go-sol"
WORKFLOW_NAME = "Capture Authenticated Stationary Generated Subject Final GO"
WORKFLOW_PATH = ".github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml"
REVIEW_AUTHORITY = "nembra-capture-human-review-github-v3"
FINAL_AUTHORITY = "nembra-authenticated-stationary-final-go-v2"
CONTROL_EXTENSION = "nembra-generated-build-subject-control-extension-v1"
GENERATED_ENV = "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"
GENERATED_KEY = "cocoaPodsGeneratedBuildSubjectSHA256"
GENERATED_HELPER_PATH = "Scripts/capture_cocoapods_generated_build_subject.py"
GENERATED_SCHEMA = "nembra-capture-cocoapods-generated-build-subject-v1"
GENERATED_BUILD_WORKFLOW = "Capture CocoaPods Build Subject Authority"
GENERATED_BUILD_WORKFLOW_PATH = ".github/workflows/capture-cocoapods-build-subject-redteam.yml"
VNODE_WORKFLOW = "Capture CocoaPods Vnode Attribute Convergence"
VNODE_WORKFLOW_PATH = ".github/workflows/capture-cocoapods-vnode-attribute-convergence.yml"
GENERATED_ACCEPTANCE_WORKFLOWS = (
    (GENERATED_BUILD_WORKFLOW, GENERATED_BUILD_WORKFLOW_PATH),
    (VNODE_WORKFLOW, VNODE_WORKFLOW_PATH),
)
HEX64 = re.compile(r"^[0-9a-f]{64}$")

# These child paths are part of the external physical-authorization control plane.
CHILD_AUTHORITY_PATHS = (
    "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py",
    "scripts/ci/es80_authenticated_stationary_final_go.py",
    "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
    "scripts/ci/es80_today_final_go_publication.py",
    WORKFLOW_PATH,
    "scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py",
    "scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_workflow_gates.py",
    "scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py",
)
PARENT_PINNED_PATHS = (
    "scripts/ci/es80_authenticated_stationary_final_go.py",
    "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
    "scripts/ci/es80_today_final_go_publication.py",
)
GENERATED_AUTHORITY_PATHS = (
    "Scripts/bootstrap_capture_tuya_sdk.sh",
    GENERATED_HELPER_PATH,
    "Scripts/capture_tuya_private_input_provenance.py",
    "Scripts/capture_tuya_private_input_build_guard.py",
    "scripts/field/install_one_time_capture.command",
    GENERATED_BUILD_WORKFLOW_PATH,
    VNODE_WORKFLOW_PATH,
)


class GeneratedSubjectGoError(RuntimeError):
    pass


BASE_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_final_go.py"


def _load_base_module():
    root = Path(__file__).resolve().parents[2]
    environment = {"PATH": "/usr/bin:/bin", "GIT_NO_REPLACE_OBJECTS": "1"}
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
            ["/usr/bin/git", "-C", str(root), "rev-parse", f"{source}:{BASE_MODULE_PATH}"],
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
        raise GeneratedSubjectGoError("authenticated-stationary Final-GO parent Git custody failed") from error
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", source):
        raise GeneratedSubjectGoError("authenticated-stationary Final-GO control source is invalid")
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted_blob):
        raise GeneratedSubjectGoError("authenticated-stationary Final-GO parent Git blob is invalid")
    if not payload or verified != accepted_blob:
        raise GeneratedSubjectGoError("authenticated-stationary Final-GO parent Git bytes failed identity verification")
    filename = f"git:{source}:{BASE_MODULE_PATH}"
    module = types.ModuleType("nembra_authenticated_stationary_final_go")
    module.__file__ = filename
    module.__nembra_accepted_control_source__ = source
    module.__nembra_accepted_control_blob__ = accepted_blob
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise GeneratedSubjectGoError("accepted authenticated-stationary Final-GO parent could not execute") from error
    return module


def _canonical_digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or not HEX64.fullmatch(value) or value != value.lower():
        raise GeneratedSubjectGoError(f"{label} is not canonical lowercase SHA-256")
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
        raise GeneratedSubjectGoError(f"control authority path is not a regular non-symlink file: {relative}")
    accepted = base.git(root, "rev-parse", f"{source}:{relative}").lower()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted):
        raise GeneratedSubjectGoError(f"control authority Git blob invalid: {relative}")
    verbose = base.git(root, "ls-files", "-v", "--", relative)
    tagged = base.git(root, "ls-files", "-t", "--", relative)
    if not verbose or verbose[:1].islower() or tagged.startswith("S "):
        raise GeneratedSubjectGoError(f"control authority path has suppressed worktree tracking: {relative}")
    actual = base.git(root, "hash-object", "--no-filters", "--", relative).lower()
    if actual != accepted:
        raise GeneratedSubjectGoError(f"control authority worktree bytes differ from accepted Git blob: {relative}")
    return accepted


def generated_control_plane(
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
    source = base.canon(base.git(root, "rev-parse", "HEAD"), "generated-subject control-plane HEAD")
    if base.git(root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise GeneratedSubjectGoError("generated-subject control-plane checkout is not clean")

    pr = base.pos(pr, "generated-subject control-plane PR")
    parent_pr = base.pos(parent_pr, "parent Final-GO PR")
    run_id = base.pos(run_id, "generated-subject workflow run")
    parent_run_id = base.pos(parent_run_id, "parent Final-GO workflow run")

    _, child = get(f"/pulls/{pr}")
    _, parent = get(f"/pulls/{parent_pr}")
    child_head = child.get("head", {})
    child_base = child.get("base", {})
    parent_head = parent.get("head", {})
    parent_base = parent.get("base", {})
    child_branch = child_head.get("ref")
    parent_sha = base.canon(parent_head.get("sha"), "parent Final-GO PR head")
    if (
        base.canon(child_head.get("sha"), "generated-subject PR head") != source
        or child_head.get("repo", {}).get("full_name") != REPO
        or child_base.get("ref") != PARENT_BRANCH
        or base.canon(child_base.get("sha"), "generated-subject live base") != parent_sha
        or not isinstance(child_branch, str)
        or not child_branch
        or not _promotable(child)
    ):
        raise GeneratedSubjectGoError("generated-subject control-plane PR is stale or not promotable")
    if (
        parent_head.get("ref") != PARENT_BRANCH
        or parent_head.get("repo", {}).get("full_name") != REPO
        or parent_base.get("ref") != "main"
        or not _promotable(parent)
    ):
        raise GeneratedSubjectGoError("parent Final-GO control plane is not promotable")

    _, current_main = get("/branches/main")
    main_sha = base.canon(current_main.get("commit", {}).get("sha"), "current main")
    _, parent_compare = get(f"/compare/{main_sha}...{parent_sha}")
    if (
        parent_compare.get("status") not in {"ahead", "identical"}
        or base.canon(parent_compare.get("merge_base_commit", {}).get("sha"), "parent/main merge base") != main_sha
    ):
        raise GeneratedSubjectGoError("parent Final-GO control plane does not contain exact current main")
    _, child_compare = get(f"/compare/{parent_sha}...{source}")
    if (
        child_compare.get("status") not in {"ahead", "identical"}
        or base.canon(child_compare.get("merge_base_commit", {}).get("sha"), "child/parent merge base") != parent_sha
    ):
        raise GeneratedSubjectGoError("generated-subject control plane does not contain exact current parent")

    _, parent_run = get(f"/actions/runs/{parent_run_id}")
    if (
        parent_run.get("name") != base.AUTH_WORKFLOW_NAME
        or parent_run.get("path") != base.AUTH_WORKFLOW_PATH
        or base.canon(parent_run.get("head_sha"), "parent Final-GO workflow head") != parent_sha
        or parent_run.get("status") != "completed"
        or parent_run.get("conclusion") != "success"
        or not _workflow_bound(parent_run, pr=parent_pr, branch=PARENT_BRANCH)
    ):
        raise GeneratedSubjectGoError("parent Final-GO workflow is not exact terminal SUCCESS")

    _, child_run = get(f"/actions/runs/{run_id}")
    if (
        child_run.get("name") != WORKFLOW_NAME
        or child_run.get("path") != WORKFLOW_PATH
        or base.canon(child_run.get("head_sha"), "generated-subject workflow head") != source
        or child_run.get("status") != "completed"
        or child_run.get("conclusion") != "success"
        or not _workflow_bound(child_run, pr=pr, branch=child_branch)
    ):
        raise GeneratedSubjectGoError("generated-subject workflow is not exact terminal SUCCESS")

    blobs = {relative: _worktree_blob(base, root, source, relative) for relative in CHILD_AUTHORITY_PATHS}
    for relative in PARENT_PINNED_PATHS:
        parent_blob = base.git(root, "rev-parse", f"{parent_sha}:{relative}").lower()
        if parent_blob != blobs[relative]:
            raise GeneratedSubjectGoError(f"child modified a parent-pinned execution module: {relative}")

    # Keep the parent's canonical authority string so its accepted-module loader
    # can use this exact child source + gitBlobs for signed-artifact/publication
    # execution. The extension marker records why the child exists.
    return {
        "authority": "nembra-authenticated-stationary-go-control-plane-v1",
        "extensionAuthority": CONTROL_EXTENSION,
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
        "requiredCandidateWorkflows": [name for name, _ in GENERATED_ACCEPTANCE_WORKFLOWS],
        "gitBlobs": blobs,
    }


def review_v3(
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
        raise GeneratedSubjectGoError("GitHub candidate review body missing")
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
        GENERATED_KEY,
        "verdict",
    }
    lock_digest = _canonical_digest(payload.get("tuyaDependencyLockSHA256"), "reviewed Tuya dependency lock")
    generated_digest = _canonical_digest(payload.get(GENERATED_KEY), "reviewed CocoaPods generated build subject")
    if (
        set(payload) != required
        or payload.get("schemaVersion") != 3
        or payload.get("authority") != REVIEW_AUTHORITY
        or base.canon(payload.get("sourceCommitSHA"), "candidate review source") != source
        or payload.get("visualRunID") != visual["runID"]
        or payload.get("visualArtifactID") != visual["artifactID"]
        or payload.get("verdict") != "accepted"
    ):
        raise GeneratedSubjectGoError("GitHub candidate review v3 authority mismatch")
    user = review.get("user", {})
    if (
        review.get("id") != review_id
        or review.get("state") not in {"COMMENTED", "APPROVED"}
        or base.canon(review.get("commit_id"), "candidate review commit") != source
        or user.get("login") != OWNER
        or review.get("author_association") != "OWNER"
    ):
        raise GeneratedSubjectGoError("GitHub candidate review v3 custody mismatch")
    stamp = review.get("submitted_at")
    if not isinstance(stamp, str) or not stamp.endswith("Z"):
        raise GeneratedSubjectGoError("GitHub candidate review v3 timestamp invalid")
    try:
        datetime.fromisoformat(stamp[:-1] + "+00:00")
    except ValueError as error:
        raise GeneratedSubjectGoError("GitHub candidate review v3 timestamp invalid") from error

    screenshots = visual["screenshots"]
    standard = screenshots["unprovisioned-dark-standard"]["sha256"]
    accessibility = screenshots["unprovisioned-dark-accessibility-xxxl"]["sha256"]
    if (
        payload["standardScreenshotSHA256"] != standard
        or payload["accessibilityScreenshotSHA256"] != accessibility
    ):
        raise GeneratedSubjectGoError("GitHub candidate review v3 screenshot mismatch")
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
        GENERATED_KEY: generated_digest,
    }


def _git_blob_oid(payload: bytes, accepted_oid: str) -> str:
    header = b"blob " + str(len(payload)).encode("ascii") + b"\0"
    if len(accepted_oid) == 40:
        return hashlib.sha1(header + payload).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(header + payload).hexdigest()
    raise GeneratedSubjectGoError("accepted generated-helper Git object ID has unsupported width")


def _accepted_generated_helper_bytes(root: Path, source: str, base: Any) -> bytes:
    accepted_oid = base.git(root, "rev-parse", f"{source}:{GENERATED_HELPER_PATH}").lower()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted_oid):
        raise GeneratedSubjectGoError("accepted generated-helper Git blob identity is invalid")
    payload = base.git_bytes(root, "show", f"{source}:{GENERATED_HELPER_PATH}")
    if not isinstance(payload, bytes) or not payload or len(payload) > 2 * 1024 * 1024:
        raise GeneratedSubjectGoError("accepted generated-helper Git blob has invalid bounded bytes")
    if _git_blob_oid(payload, accepted_oid) != accepted_oid:
        raise GeneratedSubjectGoError("generated-helper execution bytes do not match accepted Git blob")
    return payload


def _current_generated_subject(root: Path, source: str, base: Any) -> str:
    payload = _accepted_generated_helper_bytes(root, source, base)
    module = types.ModuleType("nembra_accepted_cocoapods_generated_build_subject")
    module.__file__ = f"{source}:{GENERATED_HELPER_PATH}"
    module.__package__ = ""
    try:
        code = compile(payload, module.__file__, "exec", dont_inherit=True)
        exec(code, module.__dict__)
    except Exception as error:
        raise GeneratedSubjectGoError("accepted generated-helper Git blob could not be evaluated") from error
    if getattr(module, "SCHEMA", None) != GENERATED_SCHEMA.encode("ascii"):
        raise GeneratedSubjectGoError("accepted generated-helper schema does not match Final-GO authority")
    build_subject = getattr(module, "build_subject", None)
    if not callable(build_subject):
        raise GeneratedSubjectGoError("accepted generated-helper Git blob lacks build_subject authority")
    try:
        value = build_subject(
            lockfile=root / "Podfile.lock",
            pods=root / "Pods",
            workspace=root / "NembraCapture.xcworkspace",
        )
    except Exception as error:
        raise GeneratedSubjectGoError("accepted generated-helper rejected the current CocoaPods subject") from error
    if not isinstance(value, str) or not HEX64.fullmatch(value) or value != value.lower():
        raise GeneratedSubjectGoError("generated CocoaPods build subject could not be re-derived exactly")
    return value


def candidate_generated_authority(
    candidate_repo: Path,
    source: str,
    accepted_digest: str,
    *,
    base: Any,
    derive_subject: Callable[[Path, str, Any], str] = _current_generated_subject,
) -> dict[str, Any]:
    root = candidate_repo.expanduser().resolve(strict=True)
    accepted_digest = _canonical_digest(accepted_digest, "accepted CocoaPods generated build subject")
    if base.canon(base.git(root, "rev-parse", "HEAD"), "candidate HEAD") != source:
        raise GeneratedSubjectGoError("generated build-subject candidate is not exact accepted source")
    if base.git(root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise GeneratedSubjectGoError("generated build-subject candidate checkout is not clean")

    blobs: dict[str, str] = {}
    texts: dict[str, str] = {}
    for relative in GENERATED_AUTHORITY_PATHS:
        path = root / relative
        if not path.is_file() or path.is_symlink():
            raise GeneratedSubjectGoError(f"generated build authority path is not a regular file: {relative}")
        blob = base.git(root, "rev-parse", f"{source}:{relative}").lower()
        actual = base.git(root, "hash-object", "--no-filters", "--", relative).lower()
        verbose = base.git(root, "ls-files", "-v", "--", relative)
        tagged = base.git(root, "ls-files", "-t", "--", relative)
        if (
            blob != actual
            or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", blob)
            or not verbose
            or verbose[:1].islower()
            or tagged.startswith("S ")
        ):
            raise GeneratedSubjectGoError(f"generated build authority Git/worktree identity drifted: {relative}")
        blobs[relative] = blob
        texts[relative] = path.read_text(encoding="utf-8")

    bootstrap = texts["Scripts/bootstrap_capture_tuya_sdk.sh"]
    helper = texts[GENERATED_HELPER_PATH]
    guard = texts["Scripts/capture_tuya_private_input_build_guard.py"]
    installer = texts["scripts/field/install_one_time_capture.command"]
    generated_workflow = texts[GENERATED_BUILD_WORKFLOW_PATH]
    vnode_workflow = texts[VNODE_WORKFLOW_PATH]
    required_fragments = (
        (bootstrap, GENERATED_ENV),
        (bootstrap, "capture_cocoapods_generated_build_subject.py"),
        (helper, GENERATED_SCHEMA),
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
        (vnode_workflow, "name: Capture CocoaPods Vnode Attribute Convergence"),
        (vnode_workflow, "Real macOS chmod vnode evidence"),
        (vnode_workflow, "macos-15"),
    )
    if any(fragment not in text for text, fragment in required_fragments):
        raise GeneratedSubjectGoError("candidate source lacks converged generated-build authority enforcement")

    current = derive_subject(root, source, base)
    if current != accepted_digest:
        raise GeneratedSubjectGoError("candidate generated CocoaPods subject does not match reviewed authority")
    return {
        "authority": "nembra-cocoapods-generated-build-subject-candidate-v3",
        "implementation": GENERATED_HELPER_PATH,
        "sourceCommitSHA": source,
        GENERATED_KEY: current,
        "requiredCandidateWorkflows": [name for name, _ in GENERATED_ACCEPTANCE_WORKFLOWS],
        "gitBlobs": blobs,
    }


def _environment_adapter(base: Any, accepted_generated_digest: str):
    accepted_generated_digest = _canonical_digest(
        accepted_generated_digest, "accepted CocoaPods generated build subject"
    )
    original = base.installer_environment

    def extended(device: Path, device_digest: str, accepted_lock_sha256: str) -> dict[str, str]:
        environment = original(device, device_digest, accepted_lock_sha256)
        if GENERATED_ENV in environment:
            raise GeneratedSubjectGoError("parent installer environment unexpectedly owns generated-subject authority")
        environment[GENERATED_ENV] = accepted_generated_digest
        return environment

    return extended


@contextlib.contextmanager
def _candidate_workflow_requirements(base: Any) -> Iterator[None]:
    original_workflows = base.WORKFLOWS
    original_paths = base.WORKFLOW_PATHS
    if not isinstance(original_workflows, tuple) or not isinstance(original_paths, dict):
        raise GeneratedSubjectGoError("parent Final-GO software workflow authority is not patchable")

    workflows = list(original_workflows)
    paths = dict(original_paths)
    for name, path in GENERATED_ACCEPTANCE_WORKFLOWS:
        if name in paths and paths[name] != path:
            raise GeneratedSubjectGoError(
                f"parent Final-GO workflow path conflicts with required generated authority: {name}"
            )
        if name not in workflows:
            workflows.append(name)
        paths[name] = path

    base.WORKFLOWS = tuple(workflows)
    base.WORKFLOW_PATHS = paths
    try:
        yield
    finally:
        base.WORKFLOWS = original_workflows
        base.WORKFLOW_PATHS = original_paths


@contextlib.contextmanager
def _parent_extensions(
    base: Any,
    *,
    accepted_generated_digest: str,
    review_adapter: Callable[..., dict[str, Any]],
) -> Iterator[None]:
    if getattr(base.build, "__globals__", None) is not vars(base):
        raise GeneratedSubjectGoError("parent Final-GO build globals are not exact module authority")
    if getattr(base.installer, "__globals__", None) is not vars(base):
        raise GeneratedSubjectGoError("parent sealed installer globals are not exact module authority")
    original_review = base.review
    original_environment = base.installer_environment
    base.review = review_adapter
    base.installer_environment = _environment_adapter(base, accepted_generated_digest)
    try:
        yield
    finally:
        base.review = original_review
        base.installer_environment = original_environment


def build(
    *,
    authority_repo: Path,
    authority_pr: int,
    authority_run: int,
    parent_authority_pr: int,
    parent_authority_run: int,
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
    derive_subject: Callable[[Path, str, Any], str] = _current_generated_subject,
    now: Any = None,
) -> dict[str, Any]:
    base = base_module or _load_base_module()
    get = get or base.api
    source = base.canon(source, "source")
    pr = base.pos(pr, "PR")

    visual_subject = base.visual(source, runs[base.VISUAL], base.pos(artifact_id, "artifact"), archive, get)
    pre_review = review_v3(pr, review_id, source, visual_subject, get, base=base)
    accepted_generated = pre_review[GENERATED_KEY]
    pre_candidate = candidate_generated_authority(
        candidate_repo,
        source,
        accepted_generated,
        base=base,
        derive_subject=derive_subject,
    )

    def control_adapter(repo: Path, control_pr: int, control_run: int, callback_get: Any = get):
        return generated_control_plane(
            repo,
            control_pr,
            control_run,
            parent_pr=parent_authority_pr,
            parent_run_id=parent_authority_run,
            get=callback_get,
            base=base,
        )

    def review_adapter(
        item_pr: int,
        item_review_id: int,
        item_source: str,
        item_visual: dict[str, Any],
        callback_get: Any = get,
    ):
        return review_v3(item_pr, item_review_id, item_source, item_visual, callback_get, base=base)

    with _candidate_workflow_requirements(base), _parent_extensions(
        base,
        accepted_generated_digest=accepted_generated,
        review_adapter=review_adapter,
    ):
        # Do not override run_installer, inspect_signed_artifact, or
        # reinspect_signed_artifact. The current parent defaults preserve its
        # sealed installer and accepted Git-blob module execution custody.
        record = base.build(
            authority_repo=authority_repo,
            authority_pr=authority_pr,
            authority_run=authority_run,
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
            control_authority=control_adapter,
            now=now,
        )

    post_visual = base.visual(source, runs[base.VISUAL], artifact_id, archive, get)
    post_review = review_v3(pr, review_id, source, post_visual, get, base=base)
    post_candidate = candidate_generated_authority(
        candidate_repo,
        source,
        accepted_generated,
        base=base,
        derive_subject=derive_subject,
    )
    if post_visual != visual_subject or post_review != pre_review or post_candidate != pre_candidate:
        raise GeneratedSubjectGoError("generated build-subject authority changed during Final-GO composition")
    if record.get("visualReview") != pre_review:
        raise GeneratedSubjectGoError("parent Final-GO record did not retain the single v3 owner review")
    control = record.get("finalGOControlPlane")
    if (
        not isinstance(control, dict)
        or control.get("authority") != "nembra-authenticated-stationary-go-control-plane-v1"
        or control.get("extensionAuthority") != CONTROL_EXTENSION
    ):
        raise GeneratedSubjectGoError("parent Final-GO record lost generated-subject control authority")

    software = record.get("softwareAcceptance")
    accepted_names = {
        item.get("name")
        for item in software
        if isinstance(software, list) and isinstance(item, dict)
    } if isinstance(software, list) else set()
    required_names = {name for name, _ in GENERATED_ACCEPTANCE_WORKFLOWS}
    if not required_names.issubset(accepted_names):
        raise GeneratedSubjectGoError(
            "Final-GO record did not retain exact generated-build workflow acceptance"
        )

    return {
        **record,
        "schemaVersion": 2,
        "authority": FINAL_AUTHORITY,
        "acceptedCocoaPodsGeneratedBuildSubjectSHA256": accepted_generated,
        "generatedBuildSubjectCandidate": pre_candidate,
        "requiredGeneratedBuildWorkflowAcceptance": sorted(required_names),
    }


def _parse_workflows(values: list[str], *, base: Any) -> dict[str, int]:
    runs: dict[str, int] = {}
    for value in values:
        name, separator, identifier = value.rpartition("=")
        if not separator or name in runs:
            raise GeneratedSubjectGoError("--workflow must be unique NAME=RUN_ID")
        runs[name] = base.pos(int(identifier), name)
    return runs


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--authority-repo", type=Path, required=True)
    parser.add_argument("--authority-pr-number", type=int, required=True)
    parser.add_argument("--authority-workflow-run", type=int, required=True)
    parser.add_argument("--parent-authority-pr-number", type=int, required=True)
    parser.add_argument("--parent-authority-workflow-run", type=int, required=True)
    parser.add_argument("--candidate-repo", type=Path, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--pr-number", type=int, required=True)
    parser.add_argument("--workflow", action="append", required=True)
    parser.add_argument("--visual-artifact-id", type=int, required=True)
    parser.add_argument("--visual-artifact-archive", type=Path, required=True)
    parser.add_argument("--visual-review-id", type=int, required=True)
    parser.add_argument("--intended-device-udid-file", type=Path, required=True)
    parser.add_argument("--retained-field-ipa", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run-private-installer", action="store_true")
    arguments = parser.parse_args(argv)
    if not arguments.run_private_installer:
        parser.error("--run-private-installer is required")
    base = _load_base_module()
    try:
        record = build(
            authority_repo=arguments.authority_repo,
            authority_pr=arguments.authority_pr_number,
            authority_run=arguments.authority_workflow_run,
            parent_authority_pr=arguments.parent_authority_pr_number,
            parent_authority_run=arguments.parent_authority_workflow_run,
            candidate_repo=arguments.candidate_repo,
            source=arguments.source_sha,
            pr=arguments.pr_number,
            runs=_parse_workflows(arguments.workflow, base=base),
            artifact_id=arguments.visual_artifact_id,
            review_id=arguments.visual_review_id,
            archive=arguments.visual_artifact_archive,
            device_file=arguments.intended_device_udid_file,
            retained_ipa=arguments.retained_field_ipa,
        )
        raw = (json.dumps(record, indent=2, sort_keys=True) + "\n").encode()
        publication = base.publication(
            authority_repo=arguments.authority_repo,
            control=record["finalGOControlPlane"],
        )
        digest = publication.publish_record_no_replace(arguments.output, raw)
    except (GeneratedSubjectGoError, base.GoError, OSError, ValueError) as error:
        print(f"AUTHENTICATED STATIONARY GENERATED-SUBJECT FINAL GO: NO-GO: {error}", file=sys.stderr)
        return 2
    print(
        "AUTHENTICATED STATIONARY GENERATED-SUBJECT FINAL GO: GO: "
        f"{arguments.output.resolve(strict=True)}\nrecord_sha256={digest}\nPHYSICAL RESULT COLLECTED: NO"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
