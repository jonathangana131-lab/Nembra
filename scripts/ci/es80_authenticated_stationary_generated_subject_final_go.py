#!/usr/bin/env python3
"""Final-GO composition that binds the reviewed CocoaPods generated build subject.

This is intentionally a child control plane over the accepted authenticated-stationary
issuer. It adds one missing build-authority dimension without weakening any existing
software, visual, device, signing, runtime, or physical gate.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
import urllib.parse
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

REPO = "jonathangana131-lab/Nembra"
OWNER = "jonathangana131-lab"
PARENT_BRANCH = "control/v14-auth-stationary-final-go-sol"
WORKFLOW_NAME = "Capture Authenticated Stationary Generated Subject Final GO"
WORKFLOW_PATH = ".github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml"
REVIEW_AUTHORITY = "nembra-capture-generated-build-subject-human-review-github-v1"
FINAL_AUTHORITY = "nembra-authenticated-stationary-final-go-v2"
CONTROL_AUTHORITY = "nembra-authenticated-stationary-generated-subject-control-plane-v1"
GENERATED_ENV = "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"
GENERATED_KEY = "cocoaPodsGeneratedBuildSubjectSHA256"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
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
        raise GeneratedSubjectGoError("authenticated stationary Final-GO issuer could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _canonical_digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or not HEX64.fullmatch(value) or value != value.lower():
        raise GeneratedSubjectGoError(f"{label} is not canonical lowercase SHA-256")
    return value


def generated_subject_review(
    pr: int,
    review_id: int,
    source: str,
    *,
    get: Callable[[str], tuple[bytes, dict[str, Any]]],
    base: Any,
) -> dict[str, Any]:
    review_id = base.pos(review_id, "generated build-subject review ID")
    raw, review = get(f"/pulls/{pr}/reviews/{review_id}")
    del raw
    body = review.get("body")
    if not isinstance(body, str) or not body.strip():
        raise GeneratedSubjectGoError("generated build-subject review body missing")
    payload = base.obj(body.encode(), "generated build-subject review body")
    required = {
        "schemaVersion",
        "authority",
        "sourceCommitSHA",
        GENERATED_KEY,
        "verdict",
    }
    digest = payload.get(GENERATED_KEY)
    if (
        set(payload) != required
        or payload.get("schemaVersion") != 1
        or payload.get("authority") != REVIEW_AUTHORITY
        or base.canon(payload.get("sourceCommitSHA"), "generated build-subject review source") != source
        or _canonical_digest(digest, "reviewed CocoaPods generated build-subject digest") != digest
        or payload.get("verdict") != "accepted"
    ):
        raise GeneratedSubjectGoError("generated build-subject review authority mismatch")
    user = review.get("user", {})
    if (
        review.get("id") != review_id
        or review.get("state") not in {"COMMENTED", "APPROVED"}
        or base.canon(review.get("commit_id"), "generated build-subject review commit") != source
        or user.get("login") != OWNER
        or review.get("author_association") != "OWNER"
    ):
        raise GeneratedSubjectGoError("generated build-subject review custody mismatch")
    stamp = review.get("submitted_at")
    if not isinstance(stamp, str) or not stamp.endswith("Z"):
        raise GeneratedSubjectGoError("generated build-subject review timestamp invalid")
    try:
        datetime.fromisoformat(stamp[:-1] + "+00:00")
    except ValueError as error:
        raise GeneratedSubjectGoError("generated build-subject review timestamp invalid") from error
    return {
        "authority": REVIEW_AUTHORITY,
        "reviewID": review_id,
        "reviewNodeID": review.get("node_id"),
        "reviewBodySHA256": base.sha(body.encode()),
        "reviewedAtUTC": stamp,
        "reviewer": OWNER,
        "state": review["state"],
        "verdict": "accepted",
        GENERATED_KEY: digest,
    }


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
    source = base.canon(base.git(root, "rev-parse", "HEAD"), "generated-subject GO control-plane HEAD")
    if base.git(root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise GeneratedSubjectGoError("generated-subject GO control-plane checkout is not clean")

    _, wrapper_pr = get(f"/pulls/{base.pos(pr, 'generated-subject GO PR')}")
    wrapper_head = wrapper_pr.get("head", {})
    wrapper_base = wrapper_pr.get("base", {})
    wrapper_state = wrapper_pr.get("state")
    wrapper_merged = bool(wrapper_pr.get("merged_at"))
    wrapper_draft = wrapper_pr.get("draft")
    branch = wrapper_head.get("ref")
    if (
        base.canon(wrapper_head.get("sha"), "generated-subject GO PR head") != source
        or wrapper_head.get("repo", {}).get("full_name") != REPO
        or wrapper_base.get("ref") != PARENT_BRANCH
        or not isinstance(branch, str)
        or not branch
        or not ((wrapper_state == "open" and wrapper_draft is False) or (wrapper_state == "closed" and wrapper_merged))
    ):
        raise GeneratedSubjectGoError("generated-subject GO PR is not exact/promotable")

    _, parent = get(f"/pulls/{base.pos(parent_pr, 'parent GO control-plane PR')}")
    parent_head = parent.get("head", {})
    parent_base = parent.get("base", {})
    parent_sha = base.canon(parent_head.get("sha"), "parent GO control-plane PR head")
    parent_branch = parent_head.get("ref")
    parent_state = parent.get("state")
    parent_merged = bool(parent.get("merged_at"))
    parent_draft = parent.get("draft")
    if (
        parent_branch != PARENT_BRANCH
        or parent_head.get("repo", {}).get("full_name") != REPO
        or parent_base.get("ref") != "main"
        or not ((parent_state == "open" and parent_draft is False) or (parent_state == "closed" and parent_merged))
    ):
        raise GeneratedSubjectGoError("parent GO control plane is not exact/promotable")

    encoded_parent = urllib.parse.quote(PARENT_BRANCH, safe="")
    _, parent_ref = get(f"/git/ref/heads/{encoded_parent}")
    if base.canon(parent_ref.get("object", {}).get("sha"), "current parent GO branch head") != parent_sha:
        raise GeneratedSubjectGoError("parent GO control-plane PR head is stale")

    _, current_main = get("/branches/main")
    main_sha = base.canon(current_main.get("commit", {}).get("sha"), "current main")
    _, parent_comparison = get(f"/compare/{main_sha}...{parent_sha}")
    if (
        parent_comparison.get("status") not in {"ahead", "identical"}
        or base.canon(parent_comparison.get("merge_base_commit", {}).get("sha"), "parent/main merge base") != main_sha
    ):
        raise GeneratedSubjectGoError("parent GO control plane does not contain exact current main authority")
    _, child_comparison = get(f"/compare/{parent_sha}...{source}")
    if (
        child_comparison.get("status") not in {"ahead", "identical"}
        or base.canon(child_comparison.get("merge_base_commit", {}).get("sha"), "generated-subject/parent merge base") != parent_sha
    ):
        raise GeneratedSubjectGoError("generated-subject GO control plane does not contain exact parent authority")

    _, parent_run = get(f"/actions/runs/{base.pos(parent_run_id, 'parent GO workflow run')}")
    if (
        parent_run.get("name") != base.AUTH_WORKFLOW_NAME
        or parent_run.get("path") != base.AUTH_WORKFLOW_PATH
        or base.canon(parent_run.get("head_sha"), "parent GO workflow head") != parent_sha
        or parent_run.get("status") != "completed"
        or parent_run.get("conclusion") != "success"
        or not _workflow_bound(parent_run, pr=parent_pr, branch=PARENT_BRANCH)
    ):
        raise GeneratedSubjectGoError("parent GO control-plane workflow is not exact terminal SUCCESS")

    _, wrapper_run = get(f"/actions/runs/{base.pos(run_id, 'generated-subject GO workflow run')}")
    if (
        wrapper_run.get("name") != WORKFLOW_NAME
        or wrapper_run.get("path") != WORKFLOW_PATH
        or base.canon(wrapper_run.get("head_sha"), "generated-subject GO workflow head") != source
        or wrapper_run.get("status") != "completed"
        or wrapper_run.get("conclusion") != "success"
        or not _workflow_bound(wrapper_run, pr=pr, branch=branch)
    ):
        raise GeneratedSubjectGoError("generated-subject GO workflow is not exact terminal SUCCESS")

    paths = (
        "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py",
        "scripts/ci/es80_authenticated_stationary_final_go.py",
        "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
        WORKFLOW_PATH,
        "scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py",
    )
    blobs = {path: base.git(root, "rev-parse", f"HEAD:{path}").lower() for path in paths}
    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", value) for value in blobs.values()):
        raise GeneratedSubjectGoError("generated-subject GO control-plane Git blob identity invalid")
    return {
        "authority": CONTROL_AUTHORITY,
        "sourceCommitSHA": source,
        "prNumber": pr,
        "headBranch": branch,
        "parentPRNumber": parent_pr,
        "parentSourceCommitSHA": parent_sha,
        "mainSHA": main_sha,
        "state": wrapper_state,
        "merged": wrapper_merged,
        "draft": wrapper_draft,
        "workflowRunID": run_id,
        "workflowName": WORKFLOW_NAME,
        "workflowPath": WORKFLOW_PATH,
        "parentWorkflowRunID": parent_run_id,
        "gitBlobs": blobs,
    }


def _current_generated_subject(root: Path) -> str:
    helper = root / "Scripts/capture_cocoapods_build_subject.py"
    try:
        process = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
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
    accepted_digest = _canonical_digest(accepted_digest, "accepted CocoaPods generated build-subject digest")
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

    bootstrap = texts["Scripts/bootstrap_capture_tuya_sdk.sh"]
    helper = texts["Scripts/capture_cocoapods_build_subject.py"]
    guard = texts["Scripts/capture_tuya_private_input_build_guard.py"]
    installer = texts["scripts/field/install_one_time_capture.command"]
    required_fragments = (
        (bootstrap, GENERATED_ENV),
        (bootstrap, "capture_cocoapods_build_subject.py"),
        (bootstrap, "generated CocoaPods build subject does not match"),
        (helper, "nembra-cocoapods-generated-build-subject-v1"),
        (guard, "inputs.pods"),
        (guard, "inputs.workspace"),
        (installer, "bootstrap_capture_tuya_sdk.sh"),
        (installer, "capture_tuya_private_input_build_guard.py"),
    )
    if any(fragment not in text for text, fragment in required_fragments):
        raise GeneratedSubjectGoError("candidate source lacks required generated-build authority enforcement")

    current = derive_subject(root)
    if current != accepted_digest:
        raise GeneratedSubjectGoError("candidate generated CocoaPods build subject does not match human-reviewed authority")
    return {
        "authority": "nembra-cocoaPods-generated-build-subject-candidate-v1",
        "sourceCommitSHA": source,
        GENERATED_KEY: current,
        "gitBlobs": blobs,
    }


def _generated_installer(
    base: Any,
    accepted_generated_digest: str,
) -> Callable[[Path, str, Path, str, str], dict[str, Any]]:
    accepted_generated_digest = _canonical_digest(
        accepted_generated_digest, "accepted CocoaPods generated build-subject digest"
    )

    def run(
        repo: Path,
        source: str,
        device: Path,
        device_digest: str,
        accepted_lock_sha256: str,
    ) -> dict[str, Any]:
        root = repo.expanduser().resolve(strict=True)
        env = base.installer_environment(device, device_digest, accepted_lock_sha256)
        env[GENERATED_ENV] = accepted_generated_digest
        try:
            process = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-p", str(root / base.INSTALLER), source],
                cwd=root,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
        except OSError as error:
            raise base.GoError("private installer execution failed") from error
        if (
            process.returncode
            or "SDK-INTEGRATED CAPTURE LAUNCHED" not in process.stdout
            or base.canon(base.git(root, "rev-parse", "HEAD"), "post-install HEAD") != source
            or base.git(root, "status", "--porcelain=v1", "--untracked-files=all")
        ):
            raise base.GoError("private installer did not preserve exact accepted field subject")
        return {
            "authority": "accepted-candidate-private-installer-execution-v1",
            "result": "success",
            "sourceCommitSHA": source,
            "buildIdentifier": f"capture-v14-{source[:12]}",
            "bundleIdentifier": base.BUNDLE,
            "procedureIdentifier": base.PROC,
            "baselineDevice": base.DEVICE,
            "baselineProductType": base.PRODUCT,
            "baselineOS": "iOS 27",
        }

    return run


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
    generated_subject_review_id: int,
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

    generated_review = generated_subject_review(
        pr,
        generated_subject_review_id,
        source,
        get=get,
        base=base,
    )
    accepted_generated = generated_review[GENERATED_KEY]
    pre_candidate = candidate_generated_authority(
        candidate_repo,
        source,
        accepted_generated,
        base=base,
        derive_subject=derive_subject,
    )

    def control_callback(repo: Path, control_pr: int, control_run: int, callback_get: Any = get):
        return generated_control_plane(
            repo,
            control_pr,
            control_run,
            parent_pr=parent_authority_pr,
            parent_run_id=parent_authority_run,
            get=callback_get,
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
            raise base.GoError("generated CocoaPods authority changed before retained signed-artifact production")
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
            raise base.GoError("generated CocoaPods authority changed before retained signed-artifact reinspection")
        result = base.retained_signed_artifact_reinspect(repo, item_source, device, install, output)
        return {**result, GENERATED_KEY: accepted_generated}

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
        control_authority=control_callback,
        run_installer=_generated_installer(base, accepted_generated),
        inspect_signed_artifact=inspect_callback,
        reinspect_signed_artifact=reinspect_callback,
        now=now,
    )

    post_review = generated_subject_review(
        pr,
        generated_subject_review_id,
        source,
        get=get,
        base=base,
    )
    post_candidate = candidate_generated_authority(
        candidate_repo,
        source,
        accepted_generated,
        base=base,
        derive_subject=derive_subject,
    )
    if post_review != generated_review or post_candidate != pre_candidate:
        raise GeneratedSubjectGoError("generated build-subject authority changed during Final-GO execution")
    signed = record.get("retainedSignedFieldArtifact")
    if not isinstance(signed, dict) or signed.get(GENERATED_KEY) != accepted_generated:
        raise GeneratedSubjectGoError("retained signed field artifact lost generated build-subject authority")

    return {
        **record,
        "schemaVersion": 2,
        "authority": FINAL_AUTHORITY,
        "generatedBuildSubjectReview": generated_review,
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
    parser.add_argument("--generated-subject-review-id", type=int, required=True)
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
            generated_subject_review_id=arguments.generated_subject_review_id,
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
