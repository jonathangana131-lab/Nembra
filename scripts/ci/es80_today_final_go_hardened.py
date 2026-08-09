#!/usr/bin/env python3
"""Canonical hardened entrypoint for the external V14 ES80 TODAY Final GO record.

The closed-world Final GO validator is private implementation, not a public authority API. This
canonical executable loads `_es80_today_final_go_foundation_impl.py` directly so the public
`es80_today_final_go_foundation.py` compatibility module can fail closed for imported builders and
direct execution.

This entrypoint removes authority defects that must not remain on the executable GO path:
- trusted Xcode acceptance comes only from the owner-commanded default-branch workflow whose Git
  blob is pinned independently from the candidate PR head;
- trusted workflow Git-object lookup reuses the private foundation's producer-owned, closed Git
  custody boundary rather than caller PATH/config/replacement semantics;
- the signed field candidate is freshly re-inspected by the exact accepted-source private runner
  and canonical Apple inspector before caller-authored signing metadata can become GO authority; and
- record publication is failure-atomic after no-replace publication.

No physical result is created by this tool. A generated GO record is procedural authorization for
one stationary passive Experiment One only after all supplied evidence is already legitimate.
"""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import sys
from typing import Any, Callable

MODULE_DIR = Path(__file__).resolve().parent
PRIVATE_DEVICE_FILE_ENV = "NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"


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
publication = _load("nembra_final_go_publication", "es80_today_final_go_publication.py")
signed_candidate_reinspection = _load(
    "nembra_today_signed_candidate_reinspection",
    "es80_today_signed_candidate_reinspection.py",
)

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


def _private_device_file(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit
    value = os.environ.get(PRIVATE_DEVICE_FILE_ENV)
    if not value:
        raise FinalGoError(
            f"signed-candidate reinspection requires private intended-device file via {PRIVATE_DEVICE_FILE_ENV}"
        )
    return Path(value)


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
    intended_device_udid_file: Path | None = None,
) -> dict[str, Any]:
    """Run the private foundation only after fresh signed-candidate and Xcode authority."""
    private_device_file = _private_device_file(intended_device_udid_file)
    try:
        fresh_candidate = signed_candidate_reinspection.verify_signed_candidate_reinspection(
            candidate_root=candidate_root,
            expected_source_sha=expected_source_sha,
            frozen_source_repo=frozen_source_repo,
            private_runner_path=foundation.PRIVATE_RUNNER_PATH,
            inspector_path=foundation.INSPECTOR_PATH,
            intended_device_udid_file=private_device_file,
        )
    except signed_candidate_reinspection.SignedCandidateReinspectionError as error:
        raise FinalGoError(str(error)) from error

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

    candidate = record.get("acceptedSignedFieldCandidate")
    if not isinstance(candidate, dict):
        raise FinalGoError("hardened Final GO record lacks accepted signed field candidate subject")
    for key in (
        "retainedIPASHA256",
        "retainedIPAByteCount",
        "externalBuildRecordSHA256",
        "fieldBuildEvidenceRecordSHA256",
        "signedArtifactInspectionSHA256",
    ):
        if candidate.get(key) != fresh_candidate.get(key):
            raise FinalGoError(f"fresh signed-candidate reinspection diverged from foundation subject: {key}")
    if fresh_candidate.get("inspectorSourceCommitSHA") != record.get("acceptedSourceCommitSHA"):
        raise FinalGoError("fresh signed-candidate inspector source diverged from accepted source")

    candidate["freshSignedArtifactReinspection"] = {
        "executionCustody": fresh_candidate["executionCustody"],
        "inspectorSourceCommitSHA": fresh_candidate["inspectorSourceCommitSHA"],
        "privateRunnerGitBlob": fresh_candidate["privateRunnerGitBlob"],
        "canonicalInspectorGitBlob": fresh_candidate["canonicalInspectorGitBlob"],
    }
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
