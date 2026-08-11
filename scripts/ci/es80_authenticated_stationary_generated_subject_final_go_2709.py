#!/usr/bin/env python3
"""Exact selected generated-subject adapter for authenticated Final GO.

The recovered Final-GO core deliberately preserves the current #2638 sealed
installer execution. This adapter binds the generated CocoaPods helper contract
selected by the build-side convergence and extends the candidate's exact
software-acceptance workflow set with the two gates that prove that authority.
"""
from __future__ import annotations

import contextlib
import importlib.util
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable, Iterator

CORE_PATH = Path(__file__).with_name(
    "es80_authenticated_stationary_generated_subject_final_go.py"
)
ADAPTER_PATH = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go_2709.py"
GENERATED_HELPER_PATH = "Scripts/capture_cocoapods_generated_build_subject.py"
GENERATED_SCHEMA = "nembra-capture-cocoapods-generated-build-subject-v1"
CONTROL_AUTHORITY = "nembra-authenticated-stationary-generated-subject-control-plane-v3"
GENERATED_BUILD_WORKFLOW = "Capture CocoaPods Build Subject Authority"
GENERATED_BUILD_WORKFLOW_PATH = ".github/workflows/capture-cocoapods-build-subject-redteam.yml"
VNODE_WORKFLOW = "Capture CocoaPods Vnode Attribute Convergence"
VNODE_WORKFLOW_PATH = ".github/workflows/capture-cocoapods-vnode-attribute-convergence.yml"
GENERATED_ACCEPTANCE_WORKFLOWS = (
    (GENERATED_BUILD_WORKFLOW, GENERATED_BUILD_WORKFLOW_PATH),
    (VNODE_WORKFLOW, VNODE_WORKFLOW_PATH),
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
_ORIGINAL_CANDIDATE = core.candidate_generated_authority
_ORIGINAL_BUILD = core.build


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
    if (
        process.returncode != 0
        or not core.HEX64.fullmatch(value)
        or value != value.lower()
    ):
        raise core.GeneratedSubjectGoError(
            "selected generated CocoaPods build subject could not be re-derived exactly"
        )
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
                f"generated build authority path is not a regular file: {relative}"
            )
        blob = base.git(root, "rev-parse", f"HEAD:{relative}").lower()
        actual = base.git(root, "hash-object", "--no-filters", "--", relative).lower()
        if blob != actual or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", blob):
            raise core.GeneratedSubjectGoError(
                f"generated build authority path drifted from accepted Git blob: {relative}"
            )
        blobs[relative] = blob
        texts[relative] = path.read_text(encoding="utf-8")

    bootstrap = texts["Scripts/bootstrap_capture_tuya_sdk.sh"]
    helper = texts[GENERATED_HELPER_PATH]
    guard = texts["Scripts/capture_tuya_private_input_build_guard.py"]
    installer = texts["scripts/field/install_one_time_capture.command"]
    generated_workflow = texts[GENERATED_BUILD_WORKFLOW_PATH]
    vnode_workflow = texts[VNODE_WORKFLOW_PATH]
    required_fragments = (
        (bootstrap, core.GENERATED_ENV),
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
        (generated_workflow, "Require exact generated CocoaPods build authority"),
        (generated_workflow, "test_capture_private_input_ancestor_retarget.py"),
        (vnode_workflow, "Real macOS chmod vnode evidence"),
        (vnode_workflow, "macos-15"),
    )
    if any(fragment not in text for text, fragment in required_fragments):
        raise core.GeneratedSubjectGoError(
            "candidate source lacks converged generated-build authority enforcement"
        )

    current = derive_subject(root)
    if current != accepted_digest:
        raise core.GeneratedSubjectGoError(
            "candidate generated CocoaPods subject does not match reviewed authority"
        )
    return {
        "authority": "nembra-cocoapods-generated-build-subject-candidate-v3",
        "implementation": GENERATED_HELPER_PATH,
        "sourceCommitSHA": source,
        core.GENERATED_KEY: current,
        "gitBlobs": blobs,
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
            "selected generated-subject adapter Git blob identity invalid"
        )
    git_blobs = dict(record.get("gitBlobs", {}))
    git_blobs[ADAPTER_PATH] = blob
    return {
        **record,
        "authority": CONTROL_AUTHORITY,
        "generatedBuildSubjectImplementation": GENERATED_HELPER_PATH,
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


def build(*args: Any, **kwargs: Any) -> dict[str, Any]:
    # The core build signature captured its then-current helper as a Python
    # default. Override that parameter and ensure base.public() requires the two
    # exact-head workflows that prove the selected build-side authority.
    kwargs.setdefault("derive_subject", _current_generated_subject)
    base = kwargs.get("base_module")
    if base is None:
        base = core._load_base_module()
        kwargs["base_module"] = base
    with _candidate_workflow_requirements(base):
        record = _ORIGINAL_BUILD(*args, **kwargs)
    candidate = record.get("generatedBuildSubjectCandidate")
    if (
        not isinstance(candidate, dict)
        or candidate.get("implementation") != GENERATED_HELPER_PATH
    ):
        raise core.GeneratedSubjectGoError(
            "Final-GO record did not retain the selected generated-build implementation"
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
            "Final-GO record did not retain exact generated-build workflow acceptance"
        )
    return {
        **record,
        "generatedBuildSubjectImplementation": GENERATED_HELPER_PATH,
        "requiredGeneratedBuildWorkflowAcceptance": sorted(required_names),
    }


@contextlib.contextmanager
def _install_adapter() -> Iterator[None]:
    saved_candidate = core.candidate_generated_authority
    saved_control = core.generated_control_plane
    saved_build = core.build
    core.candidate_generated_authority = candidate_generated_authority
    core.generated_control_plane = generated_control_plane
    core.build = build
    try:
        yield
    finally:
        core.candidate_generated_authority = saved_candidate
        core.generated_control_plane = saved_control
        core.build = saved_build


def main(argv: list[str] | None = None) -> int:
    with _install_adapter():
        return core.main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
