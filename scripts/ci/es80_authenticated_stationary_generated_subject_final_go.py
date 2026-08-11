#!/usr/bin/env python3
"""Compose reviewed CocoaPods generated-build authority into authenticated Final GO.

This child intentionally delegates the privileged installer and the rest of the
physical-authorization machinery to the current accepted authenticated-stationary
Final-GO parent. It adds one missing authority field without copying or weakening
the parent's sealed installer execution path.
"""
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import json
import os
import re
import subprocess
import sys
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
CONTROL_AUTHORITY = "nembra-authenticated-stationary-generated-subject-control-plane-v1"
GENERATED_ENV = "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"
GENERATED_KEY = "cocoaPodsGeneratedBuildSubjectSHA256"
HEX64 = re.compile(r"^[0-9a-f]{64}$")
GENERATED_AUTHORITY_PATHS = (
    "Scripts/bootstrap_capture_tuya_sdk.sh",
    "Scripts/capture_cocoapods_build_subject.py",
    "Scripts/capture_tuya_private_input_provenance.py",
    "Scripts/capture_tuya_private_input_build_guard.py",
    "scripts/field/install_one_time_capture.command",
)


class GeneratedSubjectGoError(RuntimeError):
    pass


def _load_base_module():
    path = Path(__file__).with_name("es80_authenticated_stationary_final_go.py")
    spec = importlib.util.spec_from_file_location("nembra_authenticated_stationary_final_go", path)
    if spec is None or spec.loader is None:
        raise GeneratedSubjectGoError("authenticated-stationary Final-GO parent could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _canonical_digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or not HEX64.fullmatch(value) or value != value.lower():
        raise GeneratedSubjectGoError(f"{label} is not canonical lowercase SHA-256")
    return value


def _workflow_bound(run: dict[str, Any], *, pr: int, branch: str) -> bool:
    pulls = run.get("pull_requests", [])
    if run.get("event") == "pull_request":
        return (
            isinstance(pulls, list)
            and any(isinstance(item, dict) and item.get("number") == pr for item in pulls)
        ) or (pulls == [] and run.get("head_branch") == branch)
    return run.get("event") == "push" and run.get("head_branch") == branch


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

    _, child = get(f"/pulls/{base.pos(pr, 'generated-subject control-plane PR')}")
    child_head = child.get("head", {})
    child_base = child.get("base", {})
    child_state = child.get("state")
    child_merged = bool(child.get("merged_at"))
    child_draft = child.get("draft")
    child_branch = child_head.get("ref")
    if (
        base.canon(child_head.get("sha"), "generated-subject control-plane PR head") != source
        or child_head.get("repo", {}).get("full_name") != REPO
        or child_base.get("ref") != PARENT_BRANCH
        or not isinstance(child_branch, str)
        or not child_branch
        or not ((child_state == "open" and child_draft is False) or (child_state == "closed" and child_merged))
    ):
        raise GeneratedSubjectGoError("generated-subject control-plane PR is not exact/promotable")

    _, parent = get(f"/pulls/{base.pos(parent_pr, 'parent Final-GO PR')}")
    parent_head = parent.get("head", {})
    parent_base = parent.get("base", {})
    parent_sha = base.canon(parent_head.get("sha"), "parent Final-GO PR head")
    parent_state = parent.get("state")
    parent_merged = bool(parent.get("merged_at"))
    parent_draft = parent.get("draft")
    if (
        parent_head.get("ref") != PARENT_BRANCH
        or parent_head.get("repo", {}).get("full_name") != REPO
        or parent_base.get("ref") != "main"
        or base.canon(child_base.get("sha"), "generated-subject PR live parent") != parent_sha
        or not ((parent_state == "open" and parent_draft is False) or (parent_state == "closed" and parent_merged))
    ):
        raise GeneratedSubjectGoError("parent Final-GO control plane is stale or not promotable")

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

    _, parent_run = get(f"/actions/runs/{base.pos(parent_run_id, 'parent Final-GO workflow run')}")
    if (
        parent_run.get("name") != base.AUTH_WORKFLOW_NAME
        or parent_run.get("path") != base.AUTH_WORKFLOW_PATH
        or base.canon(parent_run.get("head_sha"), "parent Final-GO workflow head") != parent_sha
        or parent_run.get("status") != "completed"
        or parent_run.get("conclusion") != "success"
        or not _workflow_bound(parent_run, pr=parent_pr, branch=PARENT_BRANCH)
    ):
        raise GeneratedSubjectGoError("parent Final-GO workflow is not exact terminal SUCCESS")

    _, child_run = get(f"/actions/runs/{base.pos(run_id, 'generated-subject workflow run')}")
    if (
        child_run.get("name") != WORKFLOW_NAME
        or child_run.get("path") != WORKFLOW_PATH
        or base.canon(child_run.get("head_sha"), "generated-subject workflow head") != source
        or child_run.get("status") != "completed"
        or child_run.get("conclusion") != "success"
        or not _workflow_bound(child_run, pr=pr, branch=child_branch)
    ):
        raise GeneratedSubjectGoError("generated-subject workflow is not exact terminal SUCCESS")

    authority_paths = (
        "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py",
        "scripts/ci/es80_authenticated_stationary_final_go.py",
        "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
        "scripts/ci/es80_today_final_go_publication.py",
        WORKFLOW_PATH,
        "scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py",
    )
    blobs = {path: base.git(root, "rev-parse", f"HEAD:{path}").lower() for path in authority_paths}
    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", value) for value in blobs.values()):
        raise GeneratedSubjectGoError("generated-subject control-plane Git blob identity invalid")
    return {
        "authority": CONTROL_AUTHORITY,
        "sourceCommitSHA": source,
        "prNumber": pr,
        "headBranch": child_branch,
        "parentPRNumber": parent_pr,
        "parentSourceCommitSHA": parent_sha,
        "mainSHA": main_sha,
        "state": child_state,
        "merged": child_merged,
        "draft": child_draft,
        "workflowRunID": run_id,
        "workflowName": WORKFLOW_NAME,
        "workflowPath": WORKFLOW_PATH,
        "parentWorkflowRunID": parent_run_id,
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


def _current_generated_subject(root: Path) -> str:
    helper = root / "Scripts/capture_cocoapods_build_subject.py"
    try:
        process = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                "-B",
                str(helper),
                "digest",
                "--lockfile",
                str(root / "Podfile.lock"),
                "--pods",
                str(root / "Pods"),
                "--workspace",
                str(root / "NembraCapture.xcworkspace"),
            ],
            cwd=root,
            env={"PATH": "/usr/bin:/bin"},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise GeneratedSubjectGoError("generated build-subject helper could not run") from error
    value = process.stdout.strip()
    if process.returncode != 0 or not HEX64.fullmatch(value) or value != value.lower():
        raise GeneratedSubjectGoError("generated CocoaPods build subject could not be re-derived exactly")
    return value


def candidate_generated_authority(
    candidate_repo: Path,
    source: str,
    accepted_digest: str,
    *,
    base: Any,
    derive_subject: Callable[[Path], str] = _current_generated_subject,
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
        blob = base.git(root, "rev-parse", f"HEAD:{relative}").lower()
        actual = base.git(root, "hash-object", "--no-filters", "--", relative).lower()
        if blob != actual or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", blob):
            raise GeneratedSubjectGoError(f"generated build authority path drifted from accepted Git blob: {relative}")
        blobs[relative] = blob
        texts[relative] = path.read_text(encoding="utf-8")

    required_fragments = (
        (texts["Scripts/bootstrap_capture_tuya_sdk.sh"], GENERATED_ENV),
        (texts["Scripts/bootstrap_capture_tuya_sdk.sh"], "capture_cocoapods_build_subject.py"),
        (texts["Scripts/capture_cocoapods_build_subject.py"], "nembra-cocoapods-generated-build-subject-v1"),
        (texts["Scripts/capture_tuya_private_input_build_guard.py"], "accepted_generated_subject_sha256"),
        (texts["Scripts/capture_tuya_private_input_build_guard.py"], "require_accepted_generated_subject"),
        (texts["scripts/field/install_one_time_capture.command"], "bootstrap_capture_tuya_sdk.sh"),
        (texts["scripts/field/install_one_time_capture.command"], "capture_tuya_private_input_build_guard.py"),
    )
    if any(fragment not in text for text, fragment in required_fragments):
        raise GeneratedSubjectGoError("candidate source lacks required generated-build authority enforcement")

    current = derive_subject(root)
    if current != accepted_digest:
        raise GeneratedSubjectGoError("candidate generated CocoaPods subject does not match reviewed authority")
    return {
        "authority": "nembra-cocoapods-generated-build-subject-candidate-v1",
        "sourceCommitSHA": source,
        GENERATED_KEY: current,
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
def _parent_extensions(
    base: Any,
    *,
    accepted_generated_digest: str,
    review_adapter: Callable[..., dict[str, Any]],
) -> Iterator[None]:
    if getattr(base.build, "__globals__", None) is not vars(base):
        raise GeneratedSubjectGoError("parent Final-GO build globals are not patchable exact module authority")
    if getattr(base.installer, "__globals__", None) is not vars(base):
        raise GeneratedSubjectGoError("parent sealed installer globals are not patchable exact module authority")
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
    derive_subject: Callable[[Path], str] = _current_generated_subject,
    now: Any = None,
) -> dict[str, Any]:
    base = base_module or _load_base_module()
    get = get or base.api
    source = base.canon(source, "source")
    pr = base.pos(pr, "PR")

    # Read the exact retained visual subject first so the single owner review can
    # bind pixels + dependency lock + generated build graph in one authority.
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
        return review_v3(
            item_pr,
            item_review_id,
            item_source,
            item_visual,
            callback_get,
            base=base,
        )

    def inspect_callback(repo: Path, item_source: str, device: Path, install: dict[str, Any], output: Path):
        current = candidate_generated_authority(
            repo,
            item_source,
            accepted_generated,
            base=base,
            derive_subject=derive_subject,
        )
        if current != pre_candidate:
            raise base.GoError("generated build-subject authority changed before retained signed-artifact production")
        result = base.retained_signed_artifact(repo, item_source, device, install, output)
        return {**result, GENERATED_KEY: accepted_generated}

    def reinspect_callback(repo: Path, item_source: str, device: Path, install: dict[str, Any], output: Path):
        current = candidate_generated_authority(
            repo,
            item_source,
            accepted_generated,
            base=base,
            derive_subject=derive_subject,
        )
        if current != pre_candidate:
            raise base.GoError("generated build-subject authority changed before retained signed-artifact reinspection")
        result = base.retained_signed_artifact_reinspect(repo, item_source, device, install, output)
        return {**result, GENERATED_KEY: accepted_generated}

    with _parent_extensions(
        base,
        accepted_generated_digest=accepted_generated,
        review_adapter=review_adapter,
    ):
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
            inspect_signed_artifact=inspect_callback,
            reinspect_signed_artifact=reinspect_callback,
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
        raise GeneratedSubjectGoError("generated build-subject Final-GO authority changed during composition")
    signed = record.get("retainedSignedFieldArtifact")
    if not isinstance(signed, dict) or signed.get(GENERATED_KEY) != accepted_generated:
        raise GeneratedSubjectGoError("retained signed field artifact lost generated build-subject authority")
    if record.get("visualReview") != pre_review:
        raise GeneratedSubjectGoError("parent Final-GO record did not retain the single v3 owner review")

    return {
        **record,
        "schemaVersion": 2,
        "authority": FINAL_AUTHORITY,
        "acceptedCocoaPodsGeneratedBuildSubjectSHA256": accepted_generated,
        "generatedBuildSubjectCandidate": pre_candidate,
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
        digest = base.publication().publish_record_no_replace(arguments.output, raw)
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
