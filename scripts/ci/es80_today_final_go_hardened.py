#!/usr/bin/env python3
"""Canonical hardened entrypoint for the external V14 ES80 TODAY Final GO record.

The Final GO foundation remains the closed-world validator for signed candidate, independent
crosscheck, install/runtime rendezvous, and operator attestation. This executable loads that
foundation directly; the historical `es80_today_final_go_record.py` compatibility module is
non-authorizing for both direct execution and imported builder calls.

This entrypoint removes authority defects that must not remain on the executable GO path:
- trusted Xcode acceptance comes only from the owner-commanded default-branch workflow whose Git
  blob is pinned independently from the candidate PR head;
- trusted workflow Git-object lookup reuses the foundation's producer-owned, closed Git custody
  boundary rather than caller PATH/config/replacement semantics;
- the independent retained-candidate crosscheck is re-executed from its exact pinned Git object and
  the supplied handoff receipt must be byte-identical to that trusted execution output; and
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


foundation = _load("nembra_final_go_foundation", "es80_today_final_go_foundation.py")
trusted_xcode = _load(
    "nembra_trusted_capture_xcode_subject",
    "es80_today_trusted_capture_xcode_subject.py",
)
trusted_crosscheck = _load(
    "nembra_trusted_crosscheck_subject",
    "es80_today_trusted_crosscheck_subject.py",
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
    """Run foundation validation with trusted Xcode and crosscheck execution adapters installed."""

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

    original_crosscheck_subject = foundation._crosscheck_subject

    def trusted_crosscheck_adapter(
        path: Path,
        candidate: dict[str, Any],
        adapter_frozen_source_repo: Path,
        adapter_tooling_repo: Path,
    ) -> dict[str, Any]:
        if path != independent_crosscheck_receipt:
            raise FinalGoError("foundation crosscheck path diverged from hardened handoff receipt")
        if adapter_frozen_source_repo != frozen_source_repo:
            raise FinalGoError("foundation frozen-source repository diverged from hardened crosscheck subject")
        if adapter_tooling_repo != tooling_repo:
            raise FinalGoError("foundation tooling repository diverged from hardened crosscheck subject")
        if candidate.get("sourceCommitSHA") != expected_source_sha:
            raise FinalGoError("foundation candidate source diverged before trusted crosscheck execution")
        try:
            execution = trusted_crosscheck.verify_trusted_crosscheck_receipt(
                candidate_root=candidate_root,
                expected_source_sha=expected_source_sha,
                supplied_receipt_path=independent_crosscheck_receipt,
                tooling_repo=tooling_repo,
            )
        except trusted_crosscheck.TrustedCrosscheckError as error:
            raise FinalGoError(str(error)) from error

        # Preserve every accepted semantic/repository check from the closed-world foundation. The
        # new producer-execution subject augments those checks rather than replacing them.
        subject = dict(
            original_crosscheck_subject(
                path,
                candidate,
                adapter_frozen_source_repo,
                adapter_tooling_repo,
            )
        )
        subject["trustedProducerExecution"] = execution
        return subject

    original_trusted_xcode = foundation._trusted_xcode_subject
    original_crosscheck = foundation._crosscheck_subject
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
        foundation._trusted_xcode_subject = original_trusted_xcode
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

    crosscheck_subject = record.get("independentRetainedCandidateCrosscheck")
    if not isinstance(crosscheck_subject, dict):
        raise FinalGoError("hardened Final GO record lacks independent crosscheck subject")
    execution = crosscheck_subject.get("trustedProducerExecution")
    if not isinstance(execution, dict) or execution.get("authority") != trusted_crosscheck.TRUSTED_EXECUTION_AUTHORITY:
        raise FinalGoError("hardened Final GO record lacks trusted pinned crosscheck execution authority")
    if execution.get("candidateSourceCommitSHA") != record.get("acceptedSourceCommitSHA"):
        raise FinalGoError("trusted crosscheck execution source diverged from accepted source")
    if execution.get("producerStatus") != "PASS_NOT_FINAL_GO":
        raise FinalGoError("trusted crosscheck execution did not retain PASS_NOT_FINAL_GO boundary")
    if execution.get("physicalExperimentAuthorization") != "not-granted":
        raise FinalGoError("trusted crosscheck execution widened physical authorization")
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
