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
- the exact retained signed IPA must survive fresh native Apple signing/provisioning reinspection,
  and every promoted signing/installable fact is cross-bound to the foundation candidate; and
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


foundation = _load(
    "nembra_final_go_foundation_impl",
    "_es80_today_final_go_foundation_impl.py",
)
trusted_xcode = _load(
    "nembra_trusted_capture_xcode_subject",
    "es80_today_trusted_capture_xcode_subject.py",
)
publication = _load("nembra_final_go_publication", "es80_today_final_go_publication.py")
crosscheck_custody = _load(
    "nembra_final_go_crosscheck_receipt_custody",
    "es80_today_crosscheck_receipt_custody.py",
)
signed_candidate_reinspection = _load(
    "nembra_today_signed_candidate_reinspection",
    "es80_today_signed_candidate_reinspection.py",
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


def _require_fresh_signed_candidate_match(
    candidate: dict[str, Any],
    fresh: dict[str, Any],
) -> None:
    """Cross-bind independently recomputed IPA facts to every foundation fact they authorize."""
    if fresh.get("authority") != signed_candidate_reinspection.REINSPECTION_AUTHORITY:
        raise FinalGoError("fresh signed-candidate reinspection lacks independent native authority")

    expected = {
        "inspectionRecordSHA256": candidate.get("signedArtifactInspectionSHA256"),
        "signedInstallableSHA256": candidate.get("retainedIPASHA256"),
        "ipaByteCount": candidate.get("retainedIPAByteCount"),
        "executableSHA256": candidate.get("executableSHA256"),
        "infoPlistSHA256": candidate.get("infoPlistSHA256"),
        "teamIdentifier": candidate.get("teamIdentifier"),
        "provisioningProfileSHA256": candidate.get("provisioningProfileSHA256"),
        "provisioningProfileUUID": candidate.get("provisioningProfileUUID"),
        "provisioningProfileExpirationUTC": candidate.get("provisioningProfileExpirationUTC"),
        "codeDirectoryHash": candidate.get("codeDirectoryHash"),
    }
    for key, value in expected.items():
        if fresh.get(key) != value:
            raise FinalGoError(
                f"fresh signed-candidate reinspection diverged from foundation subject: {key}"
            )

    if fresh.get("bundleIdentifier") != foundation.BUNDLE_ID:
        raise FinalGoError("fresh signed-candidate bundle identifier is not canonical Nembra")
    if fresh.get("platformName") != "iphoneos":
        raise FinalGoError("fresh signed-candidate platform is not physical iPhoneOS")
    supported = fresh.get("supportedPlatforms")
    if not isinstance(supported, list) or "iPhoneOS" not in supported or any(
        isinstance(item, str) and "simulator" in item.casefold() for item in supported
    ):
        raise FinalGoError("fresh signed-candidate reinspection does not describe a physical iPhone installable")
    if fresh.get("provisioningApplicationIdentifier") != (
        f"{candidate.get('teamIdentifier')}.{foundation.BUNDLE_ID}"
    ):
        raise FinalGoError("fresh signed-candidate provisioning application identifier diverged")
    authorities = fresh.get("signingAuthorities")
    if not isinstance(authorities, list) or not authorities or not all(
        isinstance(item, str) and item.strip() for item in authorities
    ):
        raise FinalGoError("fresh signed-candidate reinspection lacks signing authority evidence")


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

    fresh_reinspection: dict[str, Any] | None = None
    original_candidate_subject = foundation._candidate_subject

    def signed_candidate_adapter(candidate_path: Path, source: str, now_utc):
        nonlocal fresh_reinspection
        candidate, raw = original_candidate_subject(candidate_path, source, now_utc)
        try:
            fresh_reinspection = signed_candidate_reinspection.verify_signed_candidate_reinspection(
                candidate_root=candidate_path,
            )
        except signed_candidate_reinspection.SignedCandidateReinspectionError as error:
            raise FinalGoError(str(error)) from error
        _require_fresh_signed_candidate_match(candidate, fresh_reinspection)
        return candidate, raw

    original_trusted_subject = foundation._trusted_xcode_subject
    foundation._candidate_subject = signed_candidate_adapter
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
        foundation._candidate_subject = original_candidate_subject
        foundation._trusted_xcode_subject = original_trusted_subject

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

    # Partial unit-test stubs exercise isolated trust seams without pretending to be an authority
    # record. Every real Final-GO authority record is `decision: GO` and must prove that the private
    # foundation actually traversed the authenticated candidate seam; no GO may bypass native IPA
    # truth even if every caller-authored JSON field happens to agree.
    if record.get("decision") == "GO":
        if fresh_reinspection is None:
            raise FinalGoError("hardened Final GO did not consume fresh signed-candidate reinspection")
        candidate = record.get("acceptedSignedFieldCandidate")
        if not isinstance(candidate, dict):
            raise FinalGoError("hardened Final GO record lacks accepted signed field candidate subject")
        _require_fresh_signed_candidate_match(candidate, fresh_reinspection)
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