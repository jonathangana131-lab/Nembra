#!/usr/bin/env python3
"""Compose the two accepted-strength TODAY Final GO validators without weakening either.

The current #1482 foundation owns closed-world candidate/inspection validation and verifies that the
retained Xcode ZIP itself contains an exact-source Capture build record. The recovered exact-subject
validator binds the trusted GitHub job/artifact metadata, the downloaded archive digest, the exact
retained-IPA install handoff, and runtime rendezvous. A physical GO record is constructed only when
both independently accept the same source/candidate/install tuple.

Publication is transactional and fail-closed. A failure after the no-replace rename actively retracts
the authoritative destination and fsyncs that removal. If durable retraction cannot be proven, the
operation reports an explicit ambiguous/quarantine failure and never prints a success digest.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import secrets
import stat
import sys
import tempfile
from typing import Any, Callable

MODULE_DIR = Path(__file__).resolve().parent


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, MODULE_DIR / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


foundation = _load("nembra_final_go_foundation", "es80_today_final_go_record.py")
exact = _load("nembra_final_go_exact_subjects", "es80_today_final_go_exact_subjects.py")

FinalGoError = exact.FinalGoError
RECIPE = exact.RECIPE
PROCEDURE = exact.PROCEDURE
BASELINE_DEVICE = exact.BASELINE_DEVICE
BASELINE_OS = exact.BASELINE_OS
BUNDLE_ID = exact.BUNDLE_ID
INSTALL_ROUTE = exact.INSTALL_ROUTE
TRUSTED_WORKFLOW_NAME = exact.TRUSTED_WORKFLOW_NAME
TRUSTED_JOB_NAME = exact.TRUSTED_JOB_NAME
TRUSTED_ARTIFACT_PREFIX = exact.TRUSTED_ARTIFACT_PREFIX
EXTERNAL_RECORD_NAME = exact.EXTERNAL_RECORD_NAME
FIELD_RECORD_NAME = exact.FIELD_RECORD_NAME
INSPECTION_NAME = exact.INSPECTION_NAME


def _eq(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise FinalGoError(f"{label} mismatch: {actual!r} != {expected!r}")


def _trusted_run_and_job(path: Path) -> tuple[int, int]:
    _, job = exact._json(path, "trusted Xcode job record")
    return (
        exact._positive_int(job.get("run_id"), "trusted Xcode run ID"),
        exact._positive_int(job.get("id"), "trusted Xcode job ID"),
    )


def build_final_go_record(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    expected_development_team: str,
    trusted_xcode_job_record: Path,
    trusted_xcode_artifact_metadata: Path,
    trusted_xcode_artifact_archive: Path,
    pre_install_ipa_sha256: str,
    post_install_ipa_sha256: str,
    installation_route: str,
    visible_recipe: str,
    visible_build_identifier: str,
    visible_source_sha: str,
    visible_build_instance_id: str,
    installed_without_rebuild: bool,
    retained_app_evidence_inspected: bool,
    intended_device_membership_accepted: bool,
    no_application_write_authority: bool,
    observed_device: str,
    observed_os: str,
    research_admission_live: bool,
    canonical_coordinator_permitted: bool,
    preflight_healthy: bool,
    charger_disconnected: bool,
    stationary: bool,
) -> dict[str, Any]:
    values = dict(
        candidate_root=candidate_root,
        expected_source_sha=expected_source_sha,
        expected_development_team=expected_development_team,
        trusted_xcode_job_record=trusted_xcode_job_record,
        trusted_xcode_artifact_metadata=trusted_xcode_artifact_metadata,
        trusted_xcode_artifact_archive=trusted_xcode_artifact_archive,
        pre_install_ipa_sha256=pre_install_ipa_sha256,
        post_install_ipa_sha256=post_install_ipa_sha256,
        installation_route=installation_route,
        visible_recipe=visible_recipe,
        visible_build_identifier=visible_build_identifier,
        visible_source_sha=visible_source_sha,
        visible_build_instance_id=visible_build_instance_id,
        installed_without_rebuild=installed_without_rebuild,
        retained_app_evidence_inspected=retained_app_evidence_inspected,
        intended_device_membership_accepted=intended_device_membership_accepted,
        no_application_write_authority=no_application_write_authority,
        observed_device=observed_device,
        observed_os=observed_os,
        research_admission_live=research_admission_live,
        canonical_coordinator_permitted=canonical_coordinator_permitted,
        preflight_healthy=preflight_healthy,
        charger_disconnected=charger_disconnected,
        stationary=stationary,
    )
    exact_record = exact.build_final_go_record(**values)
    run_id, job_id = _trusted_run_and_job(trusted_xcode_job_record)

    # The foundation's install-route spelling predates the exact-subject recovery. It verifies the
    # same retained IPA pre/post handoff internally; caller authority still uses the newer canonical
    # exact-subject route and cannot select this compatibility spelling.
    foundation_record = foundation.build_final_go_record(
        candidate_root=candidate_root,
        expected_source_sha=expected_source_sha,
        trusted_xcode_run_id=run_id,
        trusted_xcode_job_id=job_id,
        trusted_xcode_artifact=trusted_xcode_artifact_archive,
        pre_install_ipa_sha256=pre_install_ipa_sha256,
        post_install_ipa_sha256=post_install_ipa_sha256,
        installation_route=foundation.INSTALL_ROUTE,
        expected_development_team=expected_development_team,
        visible_recipe=visible_recipe,
        visible_build_identifier=visible_build_identifier,
        visible_source_sha=visible_source_sha,
        visible_build_instance_id=visible_build_instance_id,
        installed_without_rebuild=installed_without_rebuild,
        terminal_software_acceptance=True,
        retained_app_evidence_inspected=retained_app_evidence_inspected,
        intended_device_membership_accepted=intended_device_membership_accepted,
        no_application_write_authority=no_application_write_authority,
        observed_device=observed_device,
        observed_os=observed_os,
        research_admission_live=research_admission_live,
        canonical_coordinator_permitted=canonical_coordinator_permitted,
        preflight_healthy=preflight_healthy,
        charger_disconnected=charger_disconnected,
        stationary=stationary,
    )

    for key in (
        "acceptedSourceCommitSHA",
        "acceptedBuildIdentifier",
        "acceptedBuildInstanceID",
        "retainedIPASHA256",
        "externalBuildRecordSHA256",
        "fieldBuildEvidenceRecordSHA256",
        "retainedExecutableSHA256",
        "retainedInfoPlistSHA256",
        "procedureVersion",
        "experimentRecipeID",
        "baselineDevice",
        "baselineOS",
        "developmentTeam",
        "physicalResultCollected",
    ):
        _eq(exact_record.get(key), foundation_record.get(key), f"composed {key}")

    exact_acceptance = exact_record.get("trustedXcodeAcceptance")
    foundation_acceptance = foundation_record.get("trustedXcodeAcceptanceSubject")
    if not isinstance(exact_acceptance, dict) or not isinstance(foundation_acceptance, dict):
        raise FinalGoError("composed trusted Xcode acceptance subjects are unavailable")
    _eq(exact_acceptance.get("runID"), foundation_acceptance.get("runID"), "composed Xcode run ID")
    _eq(exact_acceptance.get("jobID"), foundation_acceptance.get("jobID"), "composed Xcode job ID")
    _eq(
        exact_acceptance.get("artifactArchiveSHA256"),
        foundation_acceptance.get("retainedArtifactSHA256"),
        "composed retained Xcode archive digest",
    )
    _eq(
        exact_record.get("signedArtifactInspectionSHA256"),
        foundation_record.get("signedArtifactInspectionRecordSHA256"),
        "composed signed inspection digest",
    )

    record = dict(exact_record)
    record["trustedXcodeAcceptance"] = dict(exact_acceptance)
    record["trustedXcodeAcceptance"]["retainedExternalBuildRecordSHA256"] = (
        foundation_acceptance["retainedExternalBuildRecordSHA256"]
    )
    record["signedFieldInspectionSubject"] = foundation_record["signedFieldInspectionSubject"]
    record["compositionVerification"] = {
        "exactGitHubJobAndArtifactSubjectAccepted": True,
        "closedWorldCandidateSchemasAccepted": True,
        "retainedXcodeArchiveSourceTupleAccepted": True,
        "signedInspectionStructureAccepted": True,
        "preAndPostInstallDigestsAcceptedByBothValidators": True,
        "runtimeRendezvousAcceptedByBothValidators": True,
        "foundationValidatorSchemaVersion": foundation_record["schemaVersion"],
        "exactSubjectValidatorSchemaVersion": exact_record["schemaVersion"],
    }
    return record


def _fsync_directory(parent: Path) -> None:
    directory_fd = os.open(parent, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def _retract_published_record(output: Path, raw: bytes) -> None:
    if not (output.exists() or output.is_symlink()):
        _fsync_directory(output.parent)
        return
    published = exact._regular(output, "failed published Final GO record")
    if published != raw:
        raise FinalGoError(
            "post-publication failure left a changed destination; refusing to delete unknown bytes"
        )
    output.unlink()
    _fsync_directory(output.parent)
    if output.exists() or output.is_symlink():
        raise FinalGoError("post-publication rollback did not remove the authoritative destination")


def _quarantine_published_record(output: Path, raw: bytes) -> Path | None:
    if not (output.exists() or output.is_symlink()):
        _fsync_directory(output.parent)
        return None
    published = exact._regular(output, "ambiguous published Final GO record")
    if published != raw:
        raise FinalGoError("ambiguous Final GO destination bytes changed before quarantine")
    quarantine = output.parent / (
        f".{output.name}.QUARANTINED-NO-GO.{os.getpid()}.{secrets.token_hex(8)}"
    )
    exact._publish_file_no_replace(output, quarantine)
    _fsync_directory(output.parent)
    if output.exists() or output.is_symlink():
        raise FinalGoError("quarantine move did not remove the authoritative Final GO destination")
    return quarantine


def publish_record_no_replace(
    output_path: Path,
    raw: bytes,
    *,
    publisher: Callable[[Path, Path], None] = exact._publish_file_no_replace,
) -> str:
    """Durably publish exact bytes; retract/quarantine authority on every post-rename failure."""
    if not raw:
        raise FinalGoError("Final GO record bytes must not be empty")
    output = output_path.expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    parent = output.parent.resolve(strict=True)
    output = parent / output.name
    if output.exists() or output.is_symlink():
        raise FinalGoError(f"output already exists: {output}")

    fd = -1
    staging: Path | None = None
    published = False
    try:
        fd, staging_name = tempfile.mkstemp(
            prefix=f".{output.name}.", suffix=".staging", dir=parent
        )
        staging = Path(staging_name)
        os.fchmod(fd, 0o600)
        offset = 0
        while offset < len(raw):
            written = os.write(fd, raw[offset:])
            if written <= 0:
                raise OSError("short write while staging Final GO record")
            offset += written
        os.fsync(fd)
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size != len(raw):
            raise FinalGoError("staged Final GO record does not match expected byte count")
        os.close(fd)
        fd = -1
        staged_raw = exact._regular(staging, "staged Final GO record")
        if staged_raw != raw:
            raise FinalGoError("staged Final GO record bytes changed before publication")

        publisher(staging, output)
        published = True
        staging = None
        _fsync_directory(parent)
        published_raw = exact._regular(output, "published Final GO record")
        if published_raw != raw:
            raise FinalGoError("published Final GO record bytes differ from staged authority")
        return exact._sha(raw)
    except Exception as original_error:
        if fd >= 0:
            os.close(fd)
        if not published and staging is not None:
            try:
                staging.unlink(missing_ok=True)
            except OSError:
                pass
        if published:
            try:
                _retract_published_record(output, raw)
            except Exception as rollback_error:
                try:
                    quarantine = _quarantine_published_record(output, raw)
                except Exception as quarantine_error:
                    raise FinalGoError(
                        "Final GO publication failed after rename and durable rollback/quarantine "
                        f"could not be proven. Treat {output} as AMBIGUOUS NO-GO and do not consume it. "
                        f"rollback={rollback_error}; quarantine={quarantine_error}"
                    ) from quarantine_error
                quarantine_note = (
                    f"; bytes quarantined at {quarantine}" if quarantine is not None else ""
                )
                raise FinalGoError(
                    "Final GO publication failed after rename; authoritative destination was "
                    f"removed but ordinary rollback was not proven{quarantine_note}"
                ) from rollback_error
        raise original_error


def _args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    for flag in (
        "candidate-root",
        "trusted-xcode-job-record",
        "trusted-xcode-artifact-metadata",
        "trusted-xcode-artifact-archive",
    ):
        p.add_argument(f"--{flag}", required=True, type=Path)
    for flag in (
        "expected-source-sha",
        "expected-development-team",
        "pre-install-ipa-sha256",
        "post-install-ipa-sha256",
        "installation-route",
        "visible-recipe",
        "visible-build-identifier",
        "visible-source-sha",
        "visible-build-instance-id",
        "observed-device",
        "observed-os",
    ):
        p.add_argument(f"--{flag}", required=True)
    for flag in (
        "installed-without-rebuild",
        "retained-app-evidence-inspected",
        "intended-device-membership-accepted",
        "no-application-write-authority",
        "research-admission-live",
        "canonical-coordinator-permitted",
        "preflight-healthy",
        "charger-disconnected",
        "stationary",
    ):
        p.add_argument(f"--{flag}", action="store_true")
    p.add_argument("--output", required=True, type=Path)
    return p.parse_args(argv)


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
