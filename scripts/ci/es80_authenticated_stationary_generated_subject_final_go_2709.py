#!/usr/bin/env python3
"""Exact #2709 adapter for generated-subject authenticated Final GO.

The recovered Final-GO core deliberately preserves the current #2638 sealed
installer execution. This adapter changes only the generated CocoaPods helper
contract selected by the winning build-side lineage: helper filename, CLI, and
schema domain. The core review/environment/retained-artifact/parent-authority
semantics remain unchanged.
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
CONTROL_AUTHORITY = "nembra-authenticated-stationary-generated-subject-control-plane-v2"
GENERATED_AUTHORITY_PATHS = (
    "Scripts/bootstrap_capture_tuya_sdk.sh",
    GENERATED_HELPER_PATH,
    "Scripts/capture_tuya_private_input_provenance.py",
    "Scripts/capture_tuya_private_input_build_guard.py",
    "scripts/field/install_one_time_capture.command",
)
GIT_OID = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")


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


def _git_environment() -> dict[str, str]:
    # Keep source/blob resolution replacement-blind and independent of caller Git
    # configuration. The accepted source commit, not mutable worktree state, owns
    # the helper bytes that participate in physical Final-GO authority.
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/var/empty",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }


def _git_bytes(root: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
    try:
        process = subprocess.run(
            ["/usr/bin/git", "-C", str(root), *args],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=_git_environment(),
        )
    except OSError as error:
        raise core.GeneratedSubjectGoError("accepted generated-helper Git custody could not run") from error
    if process.returncode != 0:
        raise core.GeneratedSubjectGoError("accepted generated-helper Git custody failed closed")
    return process.stdout


def _accepted_helper_bytes(root: Path, source: str) -> tuple[str, bytes]:
    if not isinstance(source, str) or not GIT_OID.fullmatch(source.lower()):
        raise core.GeneratedSubjectGoError("accepted generated-helper source commit is malformed")
    source = source.lower()
    blob = _git_bytes(root, "rev-parse", f"{source}:{GENERATED_HELPER_PATH}").decode(
        "ascii", errors="strict"
    ).strip().lower()
    if not GIT_OID.fullmatch(blob):
        raise core.GeneratedSubjectGoError("accepted generated-helper Git blob identity is malformed")
    raw = _git_bytes(root, "cat-file", "blob", blob)
    actual = _git_bytes(root, "hash-object", "--stdin", input_bytes=raw).decode(
        "ascii", errors="strict"
    ).strip().lower()
    if actual != blob:
        raise core.GeneratedSubjectGoError("accepted generated-helper blob bytes failed Git object revalidation")
    return blob, raw


def _execute_accepted_helper(
    root: Path,
    source: str,
    helper_args: list[str],
) -> subprocess.CompletedProcess[str]:
    _, raw = _accepted_helper_bytes(root, source)
    # Feed the exact accepted Git blob on stdin to a tiny isolated executor. The
    # mutable checkout pathname is retained only as __file__/argv display context;
    # Python never reopens it as executable authority.
    executor = r'''
import sys
raw = sys.stdin.buffer.read()
path = sys.argv[1]
helper_args = sys.argv[2:]
sys.argv = [path, *helper_args]
scope = {
    "__name__": "__main__",
    "__file__": path,
    "__package__": None,
    "__cached__": None,
}
exec(compile(raw, path, "exec"), scope, scope)
'''
    try:
        return subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                "-B",
                "-c",
                executor,
                str(root / GENERATED_HELPER_PATH),
                *helper_args,
            ],
            cwd=root,
            env={"PATH": "/usr/bin:/bin"},
            input=raw,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=False,
            check=False,
        )
    except OSError as error:
        raise core.GeneratedSubjectGoError(
            "accepted generated CocoaPods build-subject helper could not run"
        ) from error


def _current_generated_subject(root: Path, source: str) -> str:
    process = _execute_accepted_helper(
        root,
        source,
        [
            "--lockfile",
            str(root / "Podfile.lock"),
            "--pods",
            str(root / "Pods"),
            "--workspace",
            str(root / "NembraCapture.xcworkspace"),
        ],
    )
    try:
        value = process.stdout.decode("utf-8", errors="strict").strip()
    except UnicodeDecodeError as error:
        raise core.GeneratedSubjectGoError(
            "selected generated CocoaPods build subject was not canonical UTF-8"
        ) from error
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
    derive_subject: Callable[[Path, str], str] = _current_generated_subject,
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
    required_fragments = (
        (bootstrap, core.GENERATED_ENV),
        (bootstrap, "capture_cocoapods_generated_build_subject.py"),
        (helper, GENERATED_SCHEMA),
        (guard, "capture_cocoapods_generated_build_subject.py"),
        (guard, "_verify_accepted_generated_build_subject"),
        (guard, "require_accepted_generated_subject=True"),
        (installer, "bootstrap_capture_tuya_sdk.sh"),
        (installer, "capture_tuya_private_input_build_guard.py"),
    )
    if any(fragment not in text for text, fragment in required_fragments):
        raise core.GeneratedSubjectGoError(
            "candidate source lacks selected generated-build authority enforcement"
        )

    current = derive_subject(root, source)
    if current != accepted_digest:
        raise core.GeneratedSubjectGoError(
            "candidate generated CocoaPods subject does not match reviewed authority"
        )
    return {
        "authority": "nembra-cocoapods-generated-build-subject-candidate-v2",
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
        "gitBlobs": git_blobs,
    }


def build(*args: Any, **kwargs: Any) -> dict[str, Any]:
    # The core build signature captured its then-current helper as a Python
    # default. Override that boundary explicitly so the selected adapter always
    # derives with helper bytes bound to the candidate's exact source commit.
    kwargs.setdefault("derive_subject", _current_generated_subject)
    record = _ORIGINAL_BUILD(*args, **kwargs)
    candidate = record.get("generatedBuildSubjectCandidate")
    if (
        not isinstance(candidate, dict)
        or candidate.get("implementation") != GENERATED_HELPER_PATH
    ):
        raise core.GeneratedSubjectGoError(
            "Final-GO record did not retain the selected generated-build implementation"
        )
    return {
        **record,
        "generatedBuildSubjectImplementation": GENERATED_HELPER_PATH,
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
