#!/usr/bin/env python3
"""Canonical hardened entrypoint for the external V14 ES80 TODAY Final GO record.

The Final GO foundation remains the closed-world validator for signed candidate, independent
crosscheck, install/runtime rendezvous, and operator attestation. This executable loads that
foundation directly; the historical `es80_today_final_go_record.py` compatibility module is
non-authorizing for both direct execution and imported builder calls.

This entrypoint removes the authority defects that must not remain on the executable GO path:
- trusted Xcode acceptance comes only from the owner-commanded default-branch workflow whose Git
  blob is pinned independently from the candidate PR head;
- trusted workflow and independent-crosscheck Git-object lookup reuse the foundation's closed Git
  custody boundary rather than caller PATH/config/replacement semantics;
- the independent PASS_NOT_FINAL_GO receipt must exactly equal output produced by executing the
  pinned crosscheck Git blob in isolated Python against the exact candidate directory; and
- record publication is failure-atomic after no-replace publication.

No physical result is created by this tool. A generated GO record is procedural authorization for
one stationary passive Experiment One only after all supplied evidence is already legitimate.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any, Callable

MODULE_DIR = Path(__file__).resolve().parent


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, MODULE_DIR / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


foundation = _load("nembra_final_go_foundation", "es80_today_final_go_foundation.py")
trusted_xcode = _load(
    "nembra_trusted_capture_xcode_subject",
    "es80_today_trusted_capture_xcode_subject.py",
)
publication = _load("nembra_final_go_publication", "es80_today_final_go_publication.py")

FinalGoError = foundation.FinalGoError


def _workflow_blob_sha_at_commit(tooling_repo: Path, commit: str, path: str) -> str:
    """Resolve the workflow blob only through the foundation's closed Git authority boundary.

    `foundation._git` pins `/usr/bin/git`, removes system/global config, disables replacement
    objects, restricts PATH, and rejects symlink/non-directory repository custody. Reusing that
    boundary prevents caller PATH, Git config, or refs/replace state from manufacturing the trusted
    workflow blob identity.
    """
    try:
        return foundation._git(tooling_repo, "rev-parse", f"{commit}:{path}").strip().lower()
    except FinalGoError:
        raise
    except (OSError, RuntimeError) as error:
        raise FinalGoError(
            "trusted default-branch workflow Git blob is unavailable from tooling repository"
        ) from error


def _closed_git_blob_bytes(tooling_repo: Path, blob_sha: str) -> bytes:
    """Read one already-pinned Git blob through the same closed Git process boundary."""
    try:
        metadata = tooling_repo.lstat()
    except OSError as error:
        raise FinalGoError(f"Git repository is unavailable: {tooling_repo}") from error
    if tooling_repo.is_symlink() or not tooling_repo.is_dir():
        raise FinalGoError(
            f"Git repository must be one real non-symlink directory: {tooling_repo}"
        )
    env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": "/tmp",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }
    try:
        return subprocess.check_output(
            [
                "/usr/bin/git",
                "-C",
                str(tooling_repo.resolve()),
                "cat-file",
                "blob",
                blob_sha,
            ],
            env=env,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise FinalGoError("pinned independent crosscheck Git blob is unavailable") from error


def _verified_independent_crosscheck_receipt(
    *,
    receipt_path: Path,
    candidate_root: Path,
    expected_source_sha: str,
    tooling_repo: Path,
) -> bytes:
    """Re-run the pinned independent producer and require exact receipt-byte identity."""
    tool_blob = foundation._git(
        tooling_repo,
        "rev-parse",
        f"{foundation.PINNED_CROSSCHECK_COMMIT}:{foundation.CROSSCHECK_PATH}",
    ).strip().lower()
    if tool_blob != foundation.PINNED_CROSSCHECK_BLOB:
        raise FinalGoError("pinned independent crosscheck tool Git blob mismatch")

    source = _closed_git_blob_bytes(tooling_repo, tool_blob)
    try:
        source_text = source.decode("utf-8")
    except UnicodeDecodeError as error:
        raise FinalGoError("pinned independent crosscheck source is not UTF-8 Python") from error

    try:
        candidate = candidate_root.expanduser().resolve(strict=True)
    except OSError as error:
        raise FinalGoError("independent crosscheck candidate directory is unavailable") from error

    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LC_ALL": "C",
        "PYTHONNOUSERSITE": "1",
    }
    try:
        completed = subprocess.run(
            [
                sys.executable,
                "-I",
                "-c",
                source_text,
                "--candidate-dir",
                str(candidate),
                "--expected-source-sha",
                expected_source_sha,
            ],
            env=env,
            cwd="/tmp",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise FinalGoError("pinned independent crosscheck producer could not execute") from error
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        suffix = f": {detail}" if detail else ""
        raise FinalGoError(f"pinned independent crosscheck producer rejected candidate{suffix}")
    if not completed.stdout:
        raise FinalGoError("pinned independent crosscheck producer emitted no receipt bytes")

    supplied = foundation._regular(
        receipt_path,
        "independent retained-candidate cross-check receipt",
    )
    if supplied != completed.stdout:
        raise FinalGoError(
            "independent crosscheck receipt bytes were not produced by the pinned producer"
        )
    return completed.stdout


def build_final_go_record(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    expected_pr_number: int,
    trusted_xcode_run_id: int,
    trusted_xcode_job_id: int,
    trusted_xcode_artifact_id: int,
    trusted_xcode_artifact_archive: Path,
    independent_crosscheck_receipt: Path,
    frozen_source_repo: Path,
    tooling_repo: Path,
    operator_attestation: Path,
    github_get_json: Callable[[str], tuple[bytes, dict[str, Any]]] = foundation._api_get_json,
    now_utc=None,
) -> dict[str, Any]:
    """Run the foundation with trusted Xcode and crosscheck execution authority seams."""

    def trusted_subject_adapter(
        *,
        source: str,
        expected_pr_number: int,
        run_id: int,
        job_id: int,
        artifact_id: int,
        artifact_archive_path: Path,
        github_get_json: Callable[[str], tuple[bytes, dict[str, Any]]],
    ) -> dict[str, Any]:
        try:
            return trusted_xcode.verify_trusted_capture_xcode_subject(
                source_commit_sha=source,
                expected_pr_number=expected_pr_number,
                run_id=run_id,
                job_id=job_id,
                artifact_id=artifact_id,
                artifact_archive_path=artifact_archive_path,
                github_get_json=github_get_json,
                workflow_blob_sha_at_commit=lambda commit, path: _workflow_blob_sha_at_commit(
                    tooling_repo, commit, path
                ),
            )
        except trusted_xcode.TrustedCaptureXcodeError as error:
            raise FinalGoError(str(error)) from error

    original_trusted = foundation._trusted_xcode_subject
    original_crosscheck = foundation._crosscheck_subject

    def trusted_crosscheck_adapter(
        path: Path,
        candidate: dict[str, Any],
        frozen_repo: Path,
        adapter_tooling_repo: Path,
    ) -> dict[str, Any]:
        if adapter_tooling_repo.resolve() != tooling_repo.resolve():
            raise FinalGoError("independent crosscheck tooling repository changed during composition")
        raw = _verified_independent_crosscheck_receipt(
            receipt_path=path,
            candidate_root=candidate_root,
            expected_source_sha=expected_source_sha,
            tooling_repo=adapter_tooling_repo,
        )
        subject = original_crosscheck(path, candidate, frozen_repo, adapter_tooling_repo)
        digest = hashlib.sha256(raw).hexdigest()
        if subject.get("receiptSHA256") != digest:
            raise FinalGoError("independent crosscheck subject digest diverged from pinned producer output")
        return subject

    foundation._trusted_xcode_subject = trusted_subject_adapter
    foundation._crosscheck_subject = trusted_crosscheck_adapter
    try:
        record = foundation.build_final_go_record(
            candidate_root=candidate_root,
            expected_source_sha=expected_source_sha,
            expected_pr_number=expected_pr_number,
            trusted_xcode_run_id=trusted_xcode_run_id,
            trusted_xcode_job_id=trusted_xcode_job_id,
            trusted_xcode_artifact_id=trusted_xcode_artifact_id,
            trusted_xcode_artifact_archive=trusted_xcode_artifact_archive,
            independent_crosscheck_receipt=independent_crosscheck_receipt,
            frozen_source_repo=frozen_source_repo,
            tooling_repo=tooling_repo,
            operator_attestation=operator_attestation,
            github_get_json=github_get_json,
            now_utc=now_utc,
        )
    finally:
        foundation._trusted_xcode_subject = original_trusted
        foundation._crosscheck_subject = original_crosscheck

    subject = record.get("trustedXcodeAcceptance")
    if not isinstance(subject, dict):
        raise FinalGoError("hardened Final GO record lacks trusted Xcode acceptance subject")
    if subject.get("authority") != "default-branch-owner-command-v1":
        raise FinalGoError("hardened Final GO record did not consume default-branch Xcode authority")
    if subject.get("candidateSourceCommitSHA") != record.get("acceptedSourceCommitSHA"):
        raise FinalGoError("hardened Xcode subject candidate source diverged from accepted source")
    if subject.get("workflowSourceCommitSHA") == subject.get("candidateSourceCommitSHA"):
        raise FinalGoError("trusted workflow source must remain independent from candidate source")
    crosscheck = record.get("independentRetainedCandidateCrosscheck")
    if not isinstance(crosscheck, dict):
        raise FinalGoError("hardened Final GO record lacks independent crosscheck subject")
    if crosscheck.get("toolCommit") != foundation.PINNED_CROSSCHECK_COMMIT:
        raise FinalGoError("hardened Final GO record crosscheck commit is not pinned authority")
    if crosscheck.get("toolGitBlob") != foundation.PINNED_CROSSCHECK_BLOB:
        raise FinalGoError("hardened Final GO record crosscheck blob is not pinned authority")
    return record


def publish_record_no_replace(output_path: Path, raw: bytes) -> str:
    try:
        return publication.publish_record_no_replace(output_path, raw)
    except publication.FinalGoPublicationError as error:
        raise FinalGoError(str(error)) from error


def main(argv: list[str] | None = None) -> int:
    args = foundation._args(sys.argv[1:] if argv is None else argv)
    values = vars(args).copy()
    output = values.pop("output")
    try:
        record = build_final_go_record(**values)
        raw = (json.dumps(record, indent=2, sort_keys=True) + "\n").encode()
        record_sha = publish_record_no_replace(output, raw)
    except (FinalGoError, FileNotFoundError, OSError) as error:
        print(f"TODAY Final GO: NO-GO: {error}", file=sys.stderr)
        return 2
    print(f"TODAY Final GO record: {output.resolve(strict=True)}")
    print(f"record_sha256={record_sha}")
    print("PHYSICAL RESULT COLLECTED: NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
