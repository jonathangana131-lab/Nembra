#!/usr/bin/env python3
"""Exact selected build-authority adapter for authenticated Final GO.

This child keeps the sealed installer owned by the authenticated-stationary
parent. It binds the selected generated CocoaPods subject plus the opaque,
HMAC-keyed private Tuya review commitment, requires every exact-head workflow
that proves those subjects, and carries only the opaque commitment through the
installer/signed-artifact custody record. Raw private fingerprints, SDK bytes,
credentials, and the local HMAC key never enter this control plane.
"""
from __future__ import annotations

import contextlib
import importlib.util
import re
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Iterator

CORE_PATH = Path(__file__).with_name(
    "es80_authenticated_stationary_generated_subject_final_go.py"
)
ADAPTER_PATH = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go_2709.py"
GENERATED_HELPER_PATH = "Scripts/capture_cocoapods_generated_build_subject.py"
GENERATED_SCHEMA = "nembra-capture-cocoapods-generated-build-subject-v1"
PRIVATE_HELPER_PATH = "Scripts/capture_tuya_private_input_review.py"
PRIVATE_SCHEMA = "nembra-capture-private-input-review-v1"
PRIVATE_ENV = "NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT"
PRIVATE_KEY = "tuyaPrivateInputReviewCommitment"
PRIVATE_ACCEPTED_KEY = "acceptedTuyaPrivateInputReviewCommitment"
REVIEW_AUTHORITY = "nembra-capture-human-review-github-v4"
FINAL_AUTHORITY = "nembra-authenticated-stationary-private-reviewed-final-go-v1"
CONTROL_AUTHORITY = "nembra-authenticated-stationary-generated-subject-control-plane-v4"
GENERATED_BUILD_WORKFLOW = "Capture CocoaPods Build Subject Authority"
GENERATED_BUILD_WORKFLOW_PATH = ".github/workflows/capture-cocoapods-build-subject-redteam.yml"
VNODE_WORKFLOW = "Capture CocoaPods Vnode Attribute Convergence"
VNODE_WORKFLOW_PATH = ".github/workflows/capture-cocoapods-vnode-attribute-convergence.yml"
PRIVATE_REVIEW_WORKFLOW = "Capture Private Input Review Authority Closure"
PRIVATE_REVIEW_WORKFLOW_PATH = ".github/workflows/capture-private-input-review-authority-closure.yml"
GENERATED_ACCEPTANCE_WORKFLOWS = (
    (GENERATED_BUILD_WORKFLOW, GENERATED_BUILD_WORKFLOW_PATH),
    (VNODE_WORKFLOW, VNODE_WORKFLOW_PATH),
    (PRIVATE_REVIEW_WORKFLOW, PRIVATE_REVIEW_WORKFLOW_PATH),
)
GENERATED_AUTHORITY_PATHS = (
    "Scripts/bootstrap_capture_tuya_sdk.sh",
    GENERATED_HELPER_PATH,
    "Scripts/capture_tuya_private_input_provenance.py",
    PRIVATE_HELPER_PATH,
    "Scripts/capture_tuya_private_input_build_guard.py",
    "scripts/field/install_one_time_capture.command",
    GENERATED_BUILD_WORKFLOW_PATH,
    VNODE_WORKFLOW_PATH,
    PRIVATE_REVIEW_WORKFLOW_PATH,
)


def _load_core():
    spec = importlib.util.spec_from_file_location(
        "nembra_generated_subject_final_go_core", CORE_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("generated-subject Final-GO core could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


core = _load_core()
_ORIGINAL_CONTROL = core.generated_control_plane
_ORIGINAL_BUILD = core.build
_ORIGINAL_REVIEW = core.review_v3
_ORIGINAL_ENVIRONMENT_ADAPTER = core._environment_adapter


def _canonical_commitment(value: Any, label: str = "private Tuya input review commitment") -> str:
    return core._canonical_digest(value, label)


def _current_generated_subject(root: Path) -> str:
    helper = root / GENERATED_HELPER_PATH
    try:
        process = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                "-B",
                str(helper),
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
        raise core.GeneratedSubjectGoError(
            "selected generated CocoaPods build-subject helper could not run"
        ) from error
    value = process.stdout.strip()
    if process.returncode != 0 or not core.HEX64.fullmatch(value) or value != value.lower():
        raise core.GeneratedSubjectGoError(
            "selected generated CocoaPods build subject could not be re-derived exactly"
        )
    return value


def _current_private_commitment(root: Path, accepted: str) -> str:
    """Rebind the opaque accepted token to the current ignored private generation."""

    accepted = _canonical_commitment(accepted)
    helper = root / PRIVATE_HELPER_PATH
    runtime = root / "LocalSecrets/TuyaRuntime"
    try:
        process = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                "-B",
                str(helper),
                "verify",
                "--lockfile",
                str(root / "Podfile.lock"),
                "--security-podspec",
                str(root / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"),
                "--security-build",
                str(root / "LocalSecrets/TuyaSDK/Build"),
                "--identity-podspec",
                str(runtime / "NembraTuyaPrivateConfig.podspec"),
                "--identity-sources",
                str(runtime / "Sources/NembraTuyaPrivateConfig"),
                "--record",
                str(runtime / "ResolvedTuyaDependencyProvenance.txt"),
                "--key",
                str(runtime / "PrivateInputReviewKey.bin"),
                "--accepted-commitment",
                accepted,
            ],
            cwd=root,
            env={"PATH": "/usr/bin:/bin"},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise core.GeneratedSubjectGoError(
            "private Tuya review helper could not rebind the reviewed generation"
        ) from error
    value = process.stdout.strip()
    if process.returncode != 0 or value != accepted:
        raise core.GeneratedSubjectGoError(
            "current private Tuya SDK/app-identity generation does not match the reviewed commitment"
        )
    return value


def review_v4(
    pr: int,
    review_id: int,
    source: str,
    visual: dict[str, Any],
    get: Callable[[str], tuple[bytes, dict[str, Any]]],
    *,
    base: Any,
) -> dict[str, Any]:
    """One owner review binds pixels, public lock/graph, and opaque private generation."""

    review_id = base.pos(review_id, "candidate review ID")
    _, review = get(f"/pulls/{pr}/reviews/{review_id}")
    body = review.get("body")
    if not isinstance(body, str) or not body.strip():
        raise core.GeneratedSubjectGoError("GitHub candidate review v4 body missing")
    payload = base.obj(body.encode(), "GitHub candidate review v4 body")
    required = {
        "schemaVersion",
        "authority",
        "sourceCommitSHA",
        "visualRunID",
        "visualArtifactID",
        "standardScreenshotSHA256",
        "accessibilityScreenshotSHA256",
        "tuyaDependencyLockSHA256",
        core.GENERATED_KEY,
        PRIVATE_KEY,
        "verdict",
    }
    lock_digest = core._canonical_digest(
        payload.get("tuyaDependencyLockSHA256"), "reviewed Tuya dependency lock"
    )
    generated_digest = core._canonical_digest(
        payload.get(core.GENERATED_KEY), "reviewed CocoaPods generated build subject"
    )
    private_commitment = _canonical_commitment(payload.get(PRIVATE_KEY))
    if (
        set(payload) != required
        or payload.get("schemaVersion") != 4
        or payload.get("authority") != REVIEW_AUTHORITY
        or base.canon(payload.get("sourceCommitSHA"), "candidate review source") != source
        or payload.get("visualRunID") != visual["runID"]
        or payload.get("visualArtifactID") != visual["artifactID"]
        or payload.get("verdict") != "accepted"
    ):
        raise core.GeneratedSubjectGoError("GitHub candidate review v4 authority mismatch")
    user = review.get("user", {})
    if (
        review.get("id") != review_id
        or review.get("state") not in {"COMMENTED", "APPROVED"}
        or base.canon(review.get("commit_id"), "candidate review commit") != source
        or user.get("login") != core.OWNER
        or review.get("author_association") != "OWNER"
    ):
        raise core.GeneratedSubjectGoError("GitHub candidate review v4 custody mismatch")
    stamp = review.get("submitted_at")
    if not isinstance(stamp, str) or not stamp.endswith("Z"):
        raise core.GeneratedSubjectGoError("GitHub candidate review v4 timestamp invalid")
    try:
        datetime.fromisoformat(stamp[:-1] + "+00:00")
    except ValueError as error:
        raise core.GeneratedSubjectGoError("GitHub candidate review v4 timestamp invalid") from error

    screenshots = visual["screenshots"]
    standard = screenshots["unprovisioned-dark-standard"]["sha256"]
    accessibility = screenshots["unprovisioned-dark-accessibility-xxxl"]["sha256"]
    if (
        payload["standardScreenshotSHA256"] != standard
        or payload["accessibilityScreenshotSHA256"] != accessibility
    ):
        raise core.GeneratedSubjectGoError("GitHub candidate review v4 screenshot mismatch")
    return {
        "authority": REVIEW_AUTHORITY,
        "reviewID": review_id,
        "reviewNodeID": review.get("node_id"),
        "reviewBodySHA256": base.sha(body.encode()),
        "reviewedAtUTC": stamp,
        "reviewer": core.OWNER,
        "state": review["state"],
        "verdict": "accepted",
        "standardScreenshotSHA256": standard,
        "accessibilityScreenshotSHA256": accessibility,
        "tuyaDependencyLockSHA256": lock_digest,
        core.GENERATED_KEY: generated_digest,
        PRIVATE_KEY: private_commitment,
    }


def candidate_generated_authority(
    candidate_repo: Path,
    source: str,
    accepted_digest: str,
    *,
    base: Any,
    derive_subject: Callable[[Path], str] = _current_generated_subject,
) -> dict[str, Any]:
    root = candidate_repo.expanduser().resolve(strict=True)
    accepted_digest = core._canonical_digest(
        accepted_digest, "accepted CocoaPods generated build subject"
    )
    if base.canon(base.git(root, "rev-parse", "HEAD"), "candidate HEAD") != source:
        raise core.GeneratedSubjectGoError(
            "generated build-subject candidate is not exact accepted source"
        )
    if base.git(root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise core.GeneratedSubjectGoError(
            "generated build-subject candidate checkout is not clean"
        )

    blobs: dict[str, str] = {}
    texts: dict[str, str] = {}
    for relative in GENERATED_AUTHORITY_PATHS:
        path = root / relative
        if not path.is_file() or path.is_symlink():
            raise core.GeneratedSubjectGoError(
                f"generated/private build authority path is not a regular file: {relative}"
            )
        blob = base.git(root, "rev-parse", f"HEAD:{relative}").lower()
        actual = base.git(root, "hash-object", "--no-filters", "--", relative).lower()
        if blob != actual or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", blob):
            raise core.GeneratedSubjectGoError(
                f"generated/private build authority path drifted from accepted Git blob: {relative}"
            )
        blobs[relative] = blob
        texts[relative] = path.read_text(encoding="utf-8")

    bootstrap = texts["Scripts/bootstrap_capture_tuya_sdk.sh"]
    helper = texts[GENERATED_HELPER_PATH]
    private_helper = texts[PRIVATE_HELPER_PATH]
    guard = texts["Scripts/capture_tuya_private_input_build_guard.py"]
    installer = texts["scripts/field/install_one_time_capture.command"]
    generated_workflow = texts[GENERATED_BUILD_WORKFLOW_PATH]
    vnode_workflow = texts[VNODE_WORKFLOW_PATH]
    private_workflow = texts[PRIVATE_REVIEW_WORKFLOW_PATH]
    required_fragments = (
        (bootstrap, core.GENERATED_ENV),
        (bootstrap, PRIVATE_ENV),
        (bootstrap, "capture_cocoapods_generated_build_subject.py"),
        (bootstrap, "capture_tuya_private_input_review.py"),
        (helper, GENERATED_SCHEMA),
        (private_helper, PRIVATE_SCHEMA),
        (guard, "capture_cocoapods_generated_build_subject.py"),
        (guard, "capture_tuya_private_input_review.py"),
        (guard, "_verify_accepted_generated_build_subject"),
        (guard, "_verify_accepted_private_input_subject"),
        (guard, "require_accepted_generated_subject=True"),
        (guard, "require_accepted_private_subject=True"),
        (guard, "_authority_bound_initial_snapshot"),
        (guard, "_require_real_checkout_ancestry"),
        (guard, "_ensure_fd_budget"),
        (guard, "KQ_NOTE_ATTRIB"),
        (installer, "bootstrap_capture_tuya_sdk.sh"),
        (installer, "capture_tuya_private_input_build_guard.py"),
        (generated_workflow, "Require exact generated CocoaPods build authority"),
        (generated_workflow, "test_capture_private_input_ancestor_retarget.py"),
        (vnode_workflow, "Real macOS chmod vnode evidence"),
        (vnode_workflow, "macos-15"),
        (private_workflow, "Bind reviewed private generation before field build"),
        (private_workflow, "test_capture_private_input_review_authority_closure.py"),
    )
    if any(fragment not in text for text, fragment in required_fragments):
        raise core.GeneratedSubjectGoError(
            "candidate source lacks converged generated/private build authority enforcement"
        )

    current = derive_subject(root)
    if current != accepted_digest:
        raise core.GeneratedSubjectGoError(
            "candidate generated CocoaPods subject does not match reviewed authority"
        )
    return {
        "authority": "nembra-cocoapods-generated-build-subject-candidate-v4",
        "implementation": GENERATED_HELPER_PATH,
        "sourceCommitSHA": source,
        core.GENERATED_KEY: current,
        "gitBlobs": blobs,
    }


def candidate_private_authority(
    candidate_repo: Path,
    source: str,
    accepted_commitment: str,
    *,
    base: Any,
    verify_private: Callable[[Path, str], str] = _current_private_commitment,
) -> dict[str, Any]:
    root = candidate_repo.expanduser().resolve(strict=True)
    accepted = _canonical_commitment(accepted_commitment)
    if base.canon(base.git(root, "rev-parse", "HEAD"), "candidate HEAD") != source:
        raise core.GeneratedSubjectGoError(
            "private-review candidate is not exact accepted source"
        )
    if base.git(root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise core.GeneratedSubjectGoError(
            "private-review candidate checkout is not clean"
        )
    observed = verify_private(root, accepted)
    if observed != accepted:
        raise core.GeneratedSubjectGoError(
            "private-review verifier did not retain exact accepted commitment"
        )
    return {
        "authority": "nembra-private-tuya-input-review-candidate-v1",
        "implementation": PRIVATE_HELPER_PATH,
        "sourceCommitSHA": source,
        PRIVATE_KEY: accepted,
    }


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
    record = _ORIGINAL_CONTROL(
        authority_repo,
        pr,
        run_id,
        parent_pr=parent_pr,
        parent_run_id=parent_run_id,
        get=get,
        base=base,
    )
    root = authority_repo.expanduser().resolve(strict=True)
    blob = base.git(root, "rev-parse", f"HEAD:{ADAPTER_PATH}").lower()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", blob):
        raise core.GeneratedSubjectGoError(
            "selected generated/private authority adapter Git blob identity invalid"
        )
    git_blobs = dict(record.get("gitBlobs", {}))
    git_blobs[ADAPTER_PATH] = blob
    return {
        **record,
        "authority": CONTROL_AUTHORITY,
        "generatedBuildSubjectImplementation": GENERATED_HELPER_PATH,
        "privateInputReviewImplementation": PRIVATE_HELPER_PATH,
        "requiredCandidateWorkflows": [name for name, _ in GENERATED_ACCEPTANCE_WORKFLOWS],
        "gitBlobs": git_blobs,
    }


@contextlib.contextmanager
def _candidate_workflow_requirements(base: Any) -> Iterator[None]:
    """Extend the parent's exact candidate workflow set, then restore it."""

    original_workflows = base.WORKFLOWS
    original_paths = base.WORKFLOW_PATHS
    if not isinstance(original_workflows, tuple) or not isinstance(original_paths, dict):
        raise core.GeneratedSubjectGoError(
            "parent Final-GO software workflow authority is not patchable"
        )

    workflows = list(original_workflows)
    paths = dict(original_paths)
    for name, path in GENERATED_ACCEPTANCE_WORKFLOWS:
        if name in paths and paths[name] != path:
            raise core.GeneratedSubjectGoError(
                f"parent Final-GO workflow path conflicts with required build authority: {name}"
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


def _required_private_state(state: dict[str, str]) -> str:
    value = state.get(PRIVATE_KEY)
    if value is None:
        raise core.GeneratedSubjectGoError(
            "private review commitment was not established before privileged build authority"
        )
    return _canonical_commitment(value)


def _private_environment_adapter(
    base: Any,
    accepted_generated_digest: str,
    accepted_private_commitment: str,
):
    accepted_private = _canonical_commitment(accepted_private_commitment)
    generated_environment = _ORIGINAL_ENVIRONMENT_ADAPTER(base, accepted_generated_digest)

    def extended(device: Path, device_digest: str, accepted_lock_sha256: str) -> dict[str, str]:
        environment = generated_environment(device, device_digest, accepted_lock_sha256)
        if PRIVATE_ENV in environment:
            raise core.GeneratedSubjectGoError(
                "parent installer environment unexpectedly owns private-review authority"
            )
        environment[PRIVATE_ENV] = accepted_private
        return environment

    return extended


@contextlib.contextmanager
def _private_core_extensions(base: Any, state: dict[str, str]) -> Iterator[None]:
    """Patch only lookup seams; preserve exact underlying installer/artifact functions."""

    saved_review = core.review_v3
    saved_candidate = core.candidate_generated_authority
    saved_environment_adapter = core._environment_adapter
    original_signed = base.retained_signed_artifact
    original_reinspect = base.retained_signed_artifact_reinspect

    def review_adapter(*args: Any, **kwargs: Any) -> dict[str, Any]:
        record = review_v4(*args, **kwargs)
        commitment = _canonical_commitment(record.get(PRIVATE_KEY))
        previous = state.get(PRIVATE_KEY)
        if previous is not None and previous != commitment:
            raise core.GeneratedSubjectGoError(
                "private review commitment changed across Final-GO review observations"
            )
        state[PRIVATE_KEY] = commitment
        return record

    def candidate_adapter(*args: Any, **kwargs: Any) -> dict[str, Any]:
        generated = candidate_generated_authority(*args, **kwargs)
        candidate_repo = args[0] if args else kwargs["candidate_repo"]
        source = args[1] if len(args) > 1 else kwargs["source"]
        base_module = kwargs["base"]
        private = candidate_private_authority(
            candidate_repo,
            source,
            _required_private_state(state),
            base=base_module,
        )
        return {
            **generated,
            PRIVATE_KEY: private[PRIVATE_KEY],
            "privateInputReviewCandidate": private,
        }

    def environment_adapter(base_module: Any, accepted_generated_digest: str):
        return _private_environment_adapter(
            base_module,
            accepted_generated_digest,
            _required_private_state(state),
        )

    def signed_adapter(*args: Any, **kwargs: Any) -> dict[str, Any]:
        result = original_signed(*args, **kwargs)
        if PRIVATE_KEY in result:
            raise core.GeneratedSubjectGoError(
                "parent signed-artifact inspector unexpectedly owns private-review authority"
            )
        return {**result, PRIVATE_KEY: _required_private_state(state)}

    def reinspect_adapter(*args: Any, **kwargs: Any) -> dict[str, Any]:
        result = original_reinspect(*args, **kwargs)
        if PRIVATE_KEY in result:
            raise core.GeneratedSubjectGoError(
                "parent signed-artifact reinspection unexpectedly owns private-review authority"
            )
        return {**result, PRIVATE_KEY: _required_private_state(state)}

    core.review_v3 = review_adapter
    core.candidate_generated_authority = candidate_adapter
    core._environment_adapter = environment_adapter
    base.retained_signed_artifact = signed_adapter
    base.retained_signed_artifact_reinspect = reinspect_adapter
    try:
        yield
    finally:
        core.review_v3 = saved_review
        core.candidate_generated_authority = saved_candidate
        core._environment_adapter = saved_environment_adapter
        base.retained_signed_artifact = original_signed
        base.retained_signed_artifact_reinspect = original_reinspect


def build(*args: Any, **kwargs: Any) -> dict[str, Any]:
    kwargs.setdefault("derive_subject", _current_generated_subject)
    base = kwargs.get("base_module")
    if base is None:
        base = core._load_base_module()
        kwargs["base_module"] = base
    state: dict[str, str] = {}
    with _candidate_workflow_requirements(base), _private_core_extensions(base, state):
        record = _ORIGINAL_BUILD(*args, **kwargs)

    private = _required_private_state(state)
    candidate = record.get("generatedBuildSubjectCandidate")
    if (
        not isinstance(candidate, dict)
        or candidate.get("implementation") != GENERATED_HELPER_PATH
        or candidate.get(PRIVATE_KEY) != private
        or not isinstance(candidate.get("privateInputReviewCandidate"), dict)
        or candidate["privateInputReviewCandidate"].get(PRIVATE_KEY) != private
    ):
        raise core.GeneratedSubjectGoError(
            "Final-GO record did not retain exact generated/private candidate authority"
        )
    review = record.get("visualReview")
    if not isinstance(review, dict) or review.get(PRIVATE_KEY) != private:
        raise core.GeneratedSubjectGoError(
            "Final-GO record did not retain the owner-reviewed private commitment"
        )
    signed = record.get("retainedSignedFieldArtifact")
    if not isinstance(signed, dict) or signed.get(PRIVATE_KEY) != private:
        raise core.GeneratedSubjectGoError(
            "retained signed field-artifact custody lost private-review authority"
        )

    software = record.get("softwareAcceptance")
    accepted_names = {
        item.get("name")
        for item in software
        if isinstance(software, list) and isinstance(item, dict)
    } if isinstance(software, list) else set()
    required_names = {name for name, _ in GENERATED_ACCEPTANCE_WORKFLOWS}
    if not required_names.issubset(accepted_names):
        raise core.GeneratedSubjectGoError(
            "Final-GO record did not retain exact generated/private workflow acceptance"
        )
    return {
        **record,
        "schemaVersion": 3,
        "authority": FINAL_AUTHORITY,
        "generatedBuildSubjectImplementation": GENERATED_HELPER_PATH,
        "privateInputReviewImplementation": PRIVATE_HELPER_PATH,
        PRIVATE_ACCEPTED_KEY: private,
        "requiredGeneratedBuildWorkflowAcceptance": sorted(required_names),
    }


@contextlib.contextmanager
def _install_adapter() -> Iterator[None]:
    saved_control = core.generated_control_plane
    saved_build = core.build
    core.generated_control_plane = generated_control_plane
    core.build = build
    try:
        yield
    finally:
        core.generated_control_plane = saved_control
        core.build = saved_build


def main(argv: list[str] | None = None) -> int:
    with _install_adapter():
        return core.main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
