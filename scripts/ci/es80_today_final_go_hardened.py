#!/usr/bin/env python3
"""Canonical hardened entrypoint for the external V14 ES80 TODAY Final GO record.

The private Final GO foundation implementation remains the closed-world validator for signed
candidate, independent crosscheck, install/runtime rendezvous, and operator attestation. This
executable loads that implementation directly; both public compatibility/foundation modules are
non-authorizing for direct execution and ordinary builder imports.

This entrypoint removes the authority defects that must not remain on the executable GO path:
- trusted Xcode acceptance comes only from the owner-commanded default-branch workflow whose Git
  blob is pinned independently from the candidate PR head;
- trusted workflow Git-object lookup reuses the private foundation's producer-owned, closed Git
  custody boundary rather than caller PATH/config/replacement semantics;
- the independent retained-candidate receipt must be exact fresh stdout from the pinned crosscheck
  Git object rather than caller-authored JSON that merely names that object;
- signed-field Apple signing/provisioning facts are freshly re-derived by the exact reviewed private
  runner + canonical inspector from the accepted source commit and private intended-device input;
- the private foundation's accepted signed-field candidate must exactly equal that fresh subject; and
- record publication is failure-atomic after no-replace publication.

No physical result is created by this tool. A generated GO record is procedural authorization for
one stationary passive Experiment One only after all supplied evidence is already legitimate.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
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


foundation = _load(
    "nembra_final_go_foundation_impl",
    "_es80_today_final_go_foundation_impl.py",
)
trusted_xcode = _load(
    "nembra_trusted_capture_xcode_subject",
    "es80_today_trusted_capture_xcode_subject.py",
)
trusted_signed_candidate = _load(
    "nembra_trusted_signed_candidate_reinspection",
    "es80_today_trusted_signed_candidate_reinspection.py",
)
publication = _load("nembra_final_go_publication", "es80_today_final_go_publication.py")
crosscheck_custody = _load(
    "nembra_final_go_crosscheck_receipt_custody",
    "es80_today_crosscheck_receipt_custody.py",
)

FinalGoError = foundation.FinalGoError


def _workflow_blob_sha_at_commit(tooling_repo: Path, commit: str, path: str) -> str:
    """Resolve the workflow blob only through the private foundation's closed Git boundary."""
    try:
        return foundation._git(tooling_repo, "rev-parse", f"{commit}:{path}").strip().lower()
    except FinalGoError:
        raise
    except (OSError, RuntimeError) as error:
        raise FinalGoError(
            "trusted default-branch workflow Git blob is unavailable from tooling repository"
        ) from error


def _fresh_signed_candidate_subject(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    frozen_source_repo: Path,
    intended_device_udid_file: Path,
    now_utc: datetime,
) -> dict[str, Any]:
    """Derive signed-candidate authority only from fresh reviewed Apple inspection output."""
    try:
        with trusted_signed_candidate.trusted_reinspection_candidate_root(
            candidate_root=candidate_root,
            expected_source_sha=expected_source_sha,
            frozen_source_repo=frozen_source_repo,
            intended_device_udid_file=intended_device_udid_file,
        ) as fresh_candidate_root:
            subject, _ = foundation._candidate_subject(
                fresh_candidate_root,
                expected_source_sha,
                now_utc,
            )
            return subject
    except trusted_signed_candidate.TrustedSignedCandidateReinspectionError as error:
        raise FinalGoError(str(error)) from error


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
    intended_device_udid_file: Path,
    github_get_json: Callable[[str], tuple[bytes, dict[str, Any]]] = foundation._api_get_json,
    now_utc=None,
) -> dict[str, Any]:
    """Run the private foundation only after fresh pinned-crosscheck and Xcode authority."""
    try:
        crosscheck_execution = crosscheck_custody.verify_crosscheck_receipt_custody(
            candidate_root=candidate_root,
            expected_source_sha=expected_source_sha,
            receipt_path=independent_crosscheck_receipt,
            tooling_repo=tooling_repo,
            expected_tool_commit=foundation.PINNED_CROSSCHECK_COMMIT,
            expected_tool_path=foundation.CROSSCHECK_PATH,
            expected_tool_blob=foundation.PINNED_CROSSCHECK_BLOB,
        )
    except crosscheck_custody.CrosscheckReceiptCustodyError as error:
        raise FinalGoError(str(error)) from error

    now = (now_utc or datetime.now(timezone.utc)).astimezone(timezone.utc)
    fresh_candidate = _fresh_signed_candidate_subject(
        candidate_root=candidate_root,
        expected_source_sha=expected_source_sha,
        frozen_source_repo=frozen_source_repo,
        intended_device_udid_file=intended_device_udid_file,
        now_utc=now,
    )

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
            now_utc=now,
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

    crosscheck = record.get("independentRetainedCandidateCrosscheck")
    if not isinstance(crosscheck, dict):
        raise FinalGoError("hardened Final GO record lacks independent crosscheck subject")
    for key in ("receiptSHA256", "toolCommit", "toolGitBlob"):
        if crosscheck.get(key) != crosscheck_execution.get(key):
            raise FinalGoError(f"fresh pinned crosscheck execution diverged from foundation subject: {key}")
    crosscheck["executionCustody"] = crosscheck_execution["executionCustody"]

    accepted_candidate = record.get("acceptedSignedFieldCandidate")
    if not isinstance(accepted_candidate, dict):
        raise FinalGoError("hardened Final GO record lacks accepted signed-field candidate")
    if accepted_candidate != fresh_candidate:
        raise FinalGoError(
            "Final GO signed-field candidate diverged from fresh reviewed Apple reinspection"
        )
    return record


def publish_record_no_replace(output_path: Path, raw: bytes) -> str:
    try:
        return publication.publish_record_no_replace(output_path, raw)
    except publication.FinalGoPublicationError as error:
        raise FinalGoError(str(error)) from error


def _args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate-root", required=True, type=Path)
    parser.add_argument("--expected-source-sha", required=True)
    parser.add_argument("--expected-pr-number", required=True, type=int)
    parser.add_argument("--trusted-xcode-run-id", required=True, type=int)
    parser.add_argument("--trusted-xcode-job-id", required=True, type=int)
    parser.add_argument("--trusted-xcode-artifact-id", required=True, type=int)
    parser.add_argument("--trusted-xcode-artifact-archive", required=True, type=Path)
    parser.add_argument("--independent-crosscheck-receipt", required=True, type=Path)
    parser.add_argument("--frozen-source-repo", required=True, type=Path)
    parser.add_argument("--tooling-repo", required=True, type=Path)
    parser.add_argument("--operator-attestation", required=True, type=Path)
    parser.add_argument(
        "--intended-device-udid-file",
        required=True,
        type=Path,
        help="external private mode-0600 file used only for provisioning membership reinspection",
    )
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _args(sys.argv[1:] if argv is None else argv)
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
