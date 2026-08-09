#!/usr/bin/env python3
"""Canonical hardened entrypoint for the external V14 ES80 TODAY Final GO record.

The private Final GO implementation remains the closed-world validator for signed candidate,
independent crosscheck, install/runtime rendezvous, and operator attestation. This executable loads
that implementation directly; the historical `es80_today_final_go_record.py` and public
`es80_today_final_go_foundation.py` compatibility surfaces are non-authorizing for imported builder
calls and direct execution.

This entrypoint removes the authority defects that must not remain on the executable GO path:
- trusted Xcode acceptance comes only from the owner-commanded default-branch workflow whose Git
  blob is pinned independently from the candidate PR head;
- trusted workflow Git-object lookup reuses the private validator's producer-owned, closed Git
  custody boundary rather than caller PATH/config/replacement semantics; and
- record publication is failure-atomic after no-replace publication.

No physical result is created by this tool. A generated GO record is procedural authorization for
one stationary passive Experiment One only after all supplied evidence is already legitimate.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
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


foundation = _load("nembra_final_go_foundation_impl", "_es80_today_final_go_foundation_impl.py")
trusted_xcode = _load(
    "nembra_trusted_capture_xcode_subject",
    "es80_today_trusted_capture_xcode_subject.py",
)
publication = _load("nembra_final_go_publication", "es80_today_final_go_publication.py")

FinalGoError = foundation.FinalGoError


def _workflow_blob_sha_at_commit(tooling_repo: Path, commit: str, path: str) -> str:
    """Resolve the workflow blob only through the private validator's closed Git boundary."""
    try:
        return foundation._git(tooling_repo, "rev-parse", f"{commit}:{path}").strip().lower()
    except FinalGoError:
        raise
    except (OSError, RuntimeError) as error:
        raise FinalGoError(
            "trusted default-branch workflow Git blob is unavailable from tooling repository"
        ) from error


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
    """Run the private validator with its Xcode trust seam replaced by default-branch authority."""

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

    original = foundation._trusted_xcode_subject
    foundation._trusted_xcode_subject = trusted_subject_adapter
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
        foundation._trusted_xcode_subject = original

    subject = record.get("trustedXcodeAcceptance")
    if not isinstance(subject, dict):
        raise FinalGoError("hardened Final GO record lacks trusted Xcode acceptance subject")
    if subject.get("authority") != "default-branch-owner-command-v1":
        raise FinalGoError("hardened Final GO record did not consume default-branch Xcode authority")
    if subject.get("candidateSourceCommitSHA") != record.get("acceptedSourceCommitSHA"):
        raise FinalGoError("hardened Xcode subject candidate source diverged from accepted source")
    if subject.get("workflowSourceCommitSHA") == subject.get("candidateSourceCommitSHA"):
        raise FinalGoError("trusted workflow source must remain independent from candidate source")
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
