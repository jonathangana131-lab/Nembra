#!/usr/bin/env python3
"""Build a fail-closed V14 TODAY Final GO record from exact retained evidence.

This is procedural authority only. It never creates physical ES80 evidence, identifies a scooter,
or grants Bluetooth write authority. Missing, stale, substituted, or caller-only authority remains
NO-GO. The emitted record binds the trusted Xcode acceptance subject, signed candidate evidence,
exact retained-IPA installation handoff, and runtime rendezvous without retaining a private UDID.
"""
from __future__ import annotations

import argparse
import ctypes
from datetime import datetime, timezone
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from typing import Any, Callable

RECIPE = "ES80-FINGERPRINT-v1"
PROCEDURE = "V14"
BASELINE_DEVICE = "iPhone 12"
BASELINE_OS = "iOS 27"
BUNDLE_ID = "com.jonathangana131.nembra"
EXTERNAL_RECORD_NAME = "NembraCaptureExternalBuildRecord.json"
FIELD_RECORD_NAME = "NembraCaptureFieldBuildEvidenceRecord.json"
INSPECTION_NAME = "NembraCaptureSignedFieldArtifactInspection.json"
IPA_RELATIVE_PATH = Path("build-evidence/NembraField.ipa")

TRUSTED_WORKFLOW_NAME = "Capture Trusted Xcode 27 Exact-Head QA"
TRUSTED_JOB_NAME = "Build, test, and capture trusted exact Capture head"
TRUSTED_ARTIFACT_PREFIX = "nembra-capture-xcode27-"
INSTALL_ROUTE = "xcode-device-management-exact-retained-ipa"

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
TEAM = re.compile(r"^[A-Z0-9]{10}$")
SHA256_DIGEST = re.compile(r"^sha256:([0-9a-f]{64})$")


class FinalGoError(RuntimeError):
    pass


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _regular(path: Path, label: str) -> bytes:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise FinalGoError(f"{label} is unavailable: {path}") from error
    if path.is_symlink() or not stat.S_ISREG(metadata.st_mode) or metadata.st_size <= 0:
        raise FinalGoError(f"{label} must be one non-empty regular non-symlink file: {path}")
    try:
        return path.read_bytes()
    except OSError as error:
        raise FinalGoError(f"{label} is unreadable: {path}") from error


def _sha_file(path: Path, label: str) -> tuple[str, int]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise FinalGoError(f"{label} is unavailable: {path}") from error
    if path.is_symlink() or not stat.S_ISREG(metadata.st_mode) or metadata.st_size <= 0:
        raise FinalGoError(f"{label} must be one non-empty regular non-symlink file: {path}")
    digest = hashlib.sha256()
    count = 0
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
                count += len(chunk)
    except OSError as error:
        raise FinalGoError(f"{label} is unreadable: {path}") from error
    if count != metadata.st_size:
        raise FinalGoError(f"{label} byte count changed during hashing")
    return digest.hexdigest(), count


def _json(path: Path, label: str) -> tuple[bytes, dict[str, Any]]:
    raw = _regular(path, label)
    try:
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FinalGoError(f"{label} is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise FinalGoError(f"{label} root must be an object")
    return raw, value


def _eq(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise FinalGoError(f"{label} mismatch: {actual!r} != {expected!r}")


def _shape(value: Any, pattern: re.Pattern[str], label: str) -> str:
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise FinalGoError(f"{label} is not canonical")
    return value


def _positive_int(value: Any, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise FinalGoError(f"{label} must be one positive integer")
    return value


def _trusted_xcode_subjects(
    *,
    source: str,
    job_record_path: Path,
    artifact_metadata_path: Path,
    artifact_archive_path: Path,
) -> dict[str, Any]:
    job_raw, job = _json(job_record_path, "trusted Xcode job record")
    job_id = _positive_int(job.get("id"), "trusted Xcode job ID")
    run_id = _positive_int(job.get("run_id"), "trusted Xcode run ID")
    run_attempt = _positive_int(job.get("run_attempt"), "trusted Xcode run attempt")
    _eq(job.get("workflow_name"), TRUSTED_WORKFLOW_NAME, "trusted Xcode workflow name")
    _eq(job.get("name"), TRUSTED_JOB_NAME, "trusted Xcode job name")
    _eq(job.get("head_sha"), source, "trusted Xcode job exact source SHA")
    _eq(job.get("status"), "completed", "trusted Xcode job status")
    _eq(job.get("conclusion"), "success", "trusted Xcode job conclusion")

    run_url = job.get("run_url")
    if not isinstance(run_url, str) or not run_url.endswith(f"/actions/runs/{run_id}"):
        raise FinalGoError("trusted Xcode job run URL does not bind the declared run ID")
    job_url = job.get("url")
    if not isinstance(job_url, str) or not job_url.endswith(f"/actions/jobs/{job_id}"):
        raise FinalGoError("trusted Xcode job URL does not bind the declared job ID")

    artifact_raw, artifact = _json(artifact_metadata_path, "trusted Xcode artifact metadata")
    artifact_id = _positive_int(artifact.get("id"), "trusted Xcode artifact ID")
    artifact_name = artifact.get("name")
    if not isinstance(artifact_name, str) or not artifact_name.startswith(TRUSTED_ARTIFACT_PREFIX):
        raise FinalGoError("trusted Xcode artifact name is not the Capture exact-head artifact")
    _eq(artifact.get("expired"), False, "trusted Xcode artifact expiration state")
    workflow_run = artifact.get("workflow_run")
    if not isinstance(workflow_run, dict):
        raise FinalGoError("trusted Xcode artifact metadata lacks workflow_run subject")
    _eq(workflow_run.get("id"), run_id, "trusted Xcode artifact run ID")
    _eq(workflow_run.get("head_sha"), source, "trusted Xcode artifact exact source SHA")

    archive_sha, archive_size = _sha_file(artifact_archive_path, "trusted Xcode artifact archive")
    declared_digest = artifact.get("digest")
    if not isinstance(declared_digest, str):
        raise FinalGoError("trusted Xcode artifact metadata lacks server-declared SHA-256 digest")
    match = SHA256_DIGEST.fullmatch(declared_digest)
    if match is None:
        raise FinalGoError("trusted Xcode artifact digest is not canonical sha256:<64-hex>")
    _eq(match.group(1), archive_sha, "trusted Xcode downloaded artifact archive digest")
    declared_size = artifact.get("size_in_bytes")
    if isinstance(declared_size, int) and not isinstance(declared_size, bool) and declared_size > 0:
        _eq(declared_size, archive_size, "trusted Xcode downloaded artifact archive byte count")

    archive_url = artifact.get("archive_download_url")
    if not isinstance(archive_url, str) or not archive_url.endswith(f"/actions/artifacts/{artifact_id}/zip"):
        raise FinalGoError("trusted Xcode artifact download URL does not bind the declared artifact ID")

    return {
        "workflowName": TRUSTED_WORKFLOW_NAME,
        "runID": run_id,
        "runAttempt": run_attempt,
        "jobID": job_id,
        "jobName": TRUSTED_JOB_NAME,
        "jobRecordSHA256": _sha(job_raw),
        "artifactID": artifact_id,
        "artifactName": artifact_name,
        "artifactMetadataSHA256": _sha(artifact_raw),
        "artifactArchiveSHA256": archive_sha,
        "artifactArchiveByteCount": archive_size,
    }


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
    source = _shape(expected_source_sha, HEX40, "expected source SHA")
    pre_install = _shape(pre_install_ipa_sha256, HEX64, "pre-install retained IPA SHA-256")
    post_install = _shape(post_install_ipa_sha256, HEX64, "post-install retained IPA SHA-256")
    _shape(expected_development_team, TEAM, "expected development TeamIdentifier")
    _eq(installation_route, INSTALL_ROUTE, "installation route")
    _eq(observed_device, BASELINE_DEVICE, "observed baseline device")
    _eq(observed_os, BASELINE_OS, "observed baseline OS")

    trusted_xcode = _trusted_xcode_subjects(
        source=source,
        job_record_path=trusted_xcode_job_record,
        artifact_metadata_path=trusted_xcode_artifact_metadata,
        artifact_archive_path=trusted_xcode_artifact_archive,
    )

    root = candidate_root.resolve(strict=True) / "inspection"
    external_raw, external = _json(root / EXTERNAL_RECORD_NAME, "external build record")
    field_raw, field = _json(root / FIELD_RECORD_NAME, "field-build evidence record")
    inspection_raw, inspection = _json(root / INSPECTION_NAME, "signed artifact inspection")
    ipa_sha, _ = _sha_file(root / IPA_RELATIVE_PATH, "retained IPA")
    external_sha = _sha(external_raw)
    field_sha = _sha(field_raw)
    inspection_sha = _sha(inspection_raw)

    for record, version, label in (
        (external, 3, "external"),
        (field, 1, "field"),
        (inspection, 2, "inspection"),
    ):
        _eq(record.get("schemaVersion"), version, f"{label} schema version")

    _eq(external.get("sourceCommitSHA"), source, "external source SHA")
    build = external.get("buildIdentifier")
    _eq(build, f"Capture Build V14-{source[:12]}", "external build identifier")
    instance = _shape(external.get("buildInstanceID"), UUID, "external build-instance ID")
    executable = _shape(external.get("executableSHA256"), HEX64, "external executable SHA-256")
    info_plist = _shape(external.get("infoPlistSHA256"), HEX64, "external Info.plist SHA-256")
    _eq(external.get("experimentRecipeID"), RECIPE, "external recipe")
    _eq(external.get("procedureVersion"), PROCEDURE, "external procedure")

    shared = {
        "buildIdentifier": build,
        "buildInstanceID": instance,
        "sourceCommitSHA": source,
        "executableSHA256": executable,
        "infoPlistSHA256": info_plist,
        "experimentRecipeID": RECIPE,
        "procedureVersion": PROCEDURE,
    }
    for label, record in (("field", field), ("inspection", inspection)):
        for key, expected in shared.items():
            _eq(record.get(key), expected, f"{label} {key}")

    links = (
        (field, "externalBuildRecordSHA256", external_sha, "field external-record digest"),
        (inspection, "externalBuildRecordSHA256", external_sha, "inspection external-record digest"),
        (inspection, "fieldBuildEvidenceRecordSHA256", field_sha, "inspection field-record digest"),
        (field, "signedInstallableSHA256", ipa_sha, "field retained IPA digest"),
        (inspection, "signedInstallableSHA256", ipa_sha, "inspection retained IPA digest"),
    )
    for record, key, expected, label in links:
        _eq(record.get(key), expected, label)

    _eq(pre_install, ipa_sha, "pre-install retained IPA digest")
    _eq(post_install, ipa_sha, "post-install retained IPA digest")
    _eq(field.get("signedInstallableKind"), "ipa", "field installable kind")
    _eq(inspection.get("signedInstallableKind"), "ipa", "inspection installable kind")
    _eq(
        inspection.get("authority"),
        "signed-field-artifact-inspection-not-field-authorization",
        "inspection authority boundary",
    )
    _eq(inspection.get("bundleIdentifier"), BUNDLE_ID, "inspection bundle identifier")
    _eq(inspection.get("platformName"), "iphoneos", "inspection platform")
    platforms = inspection.get("supportedPlatforms")
    if not isinstance(platforms, list) or "iPhoneOS" not in platforms:
        raise FinalGoError("signed inspection does not describe an iPhoneOS installable")
    _eq(inspection.get("teamIdentifier"), expected_development_team, "inspection team identifier")
    _eq(
        inspection.get("provisioningApplicationIdentifier"),
        f"{expected_development_team}.{BUNDLE_ID}",
        "inspection provisioning application identifier",
    )
    _shape(
        inspection.get("provisioningProfileSHA256"),
        HEX64,
        "inspection provisioning profile SHA-256",
    )
    if not isinstance(inspection.get("provisioningProfileUUID"), str) or not inspection[
        "provisioningProfileUUID"
    ].strip():
        raise FinalGoError("signed inspection lacks provisioning profile identity")
    expiration = inspection.get("provisioningProfileExpirationUTC")
    if not isinstance(expiration, str) or not expiration.endswith("Z"):
        raise FinalGoError("signed inspection lacks normalized provisioning profile expiration")
    try:
        expiration_utc = datetime.fromisoformat(expiration[:-1] + "+00:00")
    except ValueError as error:
        raise FinalGoError("signed inspection provisioning profile expiration is malformed") from error
    if expiration_utc <= datetime.now(timezone.utc):
        raise FinalGoError("provisioning profile expired before Final GO")
    authorities = inspection.get("signingAuthorities")
    if not isinstance(authorities, list) or not authorities:
        raise FinalGoError("signed inspection lacks signing authority evidence")

    for actual, expected, label in (
        (visible_recipe, RECIPE, "visible pre-scan recipe"),
        (visible_build_identifier, build, "visible pre-scan build identifier"),
        (visible_source_sha, source, "visible pre-scan source SHA"),
        (visible_build_instance_id, instance, "visible pre-scan build-instance ID"),
    ):
        _eq(actual, expected, label)

    independent_review = {
        "retainedAppEvidenceInspected": retained_app_evidence_inspected,
        "independentIntendedDeviceMembershipAccepted": intended_device_membership_accepted,
        "noApplicationCharacteristicWriteAuthority": no_application_write_authority,
        "installedWithoutRebuildOrSubstitution": installed_without_rebuild,
        "privateResearchAdmissionLive": research_admission_live,
        "canonicalCoordinatorPermittedProcedure": canonical_coordinator_permitted,
        "preflightHealthyBeforeScan": preflight_healthy,
    }
    operator_declarations = {
        "chargerFreshlyDeclaredDisconnected": charger_disconnected,
        "stationaryForSetup": stationary,
    }
    missing = [
        key
        for group in (independent_review, operator_declarations)
        for key, value in group.items()
        if value is not True
    ]
    if missing:
        raise FinalGoError("required GO confirmations are not all true: " + ", ".join(missing))

    return {
        "schemaVersion": 2,
        "authority": "today-final-go-procedural-record-not-physical-result",
        "decision": "GO",
        "acceptedSourceCommitSHA": source,
        "trustedXcodeAcceptance": trusted_xcode,
        "acceptedBuildIdentifier": build,
        "acceptedBuildInstanceID": instance,
        "retainedIPASHA256": ipa_sha,
        "externalBuildRecordSHA256": external_sha,
        "fieldBuildEvidenceRecordSHA256": field_sha,
        "signedArtifactInspectionSHA256": inspection_sha,
        "retainedExecutableSHA256": executable,
        "retainedInfoPlistSHA256": info_plist,
        "installationHandoff": {
            "route": INSTALL_ROUTE,
            "preInstallRetainedIPASHA256": pre_install,
            "postInstallRetainedIPASHA256": post_install,
            "runtimeRendezvousMatched": True,
            "observedDevice": BASELINE_DEVICE,
            "observedOS": BASELINE_OS,
        },
        "procedureVersion": PROCEDURE,
        "experimentRecipeID": RECIPE,
        "baselineDevice": BASELINE_DEVICE,
        "baselineOS": BASELINE_OS,
        "developmentTeam": expected_development_team,
        "independentReviewConfirmations": independent_review,
        "operatorDeclarations": operator_declarations,
        "expectedOutput": "exact raw Nembra Capture Share artifact for Experiment One",
        "stopConditions": [
            "foreground loss or app lifecycle invalidation",
            "build/provenance/rendezvous mismatch",
            "charger not disconnected or setup not stationary",
            "correlation ambiguity or target identity loss",
            "continuity, chronology, Horizon, seal, or integrity failure",
            "export/share failure or artifact substitution",
            "any application characteristic write or scooter command authority",
        ],
        "physicalResultCollected": False,
    }


def _publish_file_no_replace(staging_path: Path, output_path: Path) -> None:
    """Atomically publish one staged file without replacing an existing destination."""
    libc = ctypes.CDLL(None, use_errno=True)
    source = os.fsencode(staging_path)
    destination = os.fsencode(output_path)
    if sys.platform == "darwin":
        rename_exclusive = libc.renamex_np
        rename_exclusive.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        rename_exclusive.restype = ctypes.c_int
        result = rename_exclusive(source, destination, 0x00000004)  # RENAME_EXCL
    elif sys.platform.startswith("linux"):
        rename_exclusive = libc.renameat2
        rename_exclusive.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        rename_exclusive.restype = ctypes.c_int
        result = rename_exclusive(-100, source, -100, destination, 0x00000001)  # RENAME_NOREPLACE
    else:
        raise FinalGoError(
            f"atomic no-replace Final GO publication is unsupported on {sys.platform!r}"
        )
    if result != 0:
        error_number = ctypes.get_errno()
        if error_number in (errno.EEXIST, errno.ENOTEMPTY):
            raise FinalGoError(f"refusing to replace existing Final GO record: {output_path}")
        raise OSError(error_number, os.strerror(error_number), str(output_path))


def publish_record_no_replace(
    output_path: Path,
    raw: bytes,
    *,
    publisher: Callable[[Path, Path], None] = _publish_file_no_replace,
) -> str:
    """Durably stage, fsync, atomically no-replace publish, then fsync the parent directory."""
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
            prefix=f".{output.name}.",
            suffix=".staging",
            dir=parent,
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
        staged_raw = _regular(staging, "staged Final GO record")
        if staged_raw != raw:
            raise FinalGoError("staged Final GO record bytes changed before publication")

        publisher(staging, output)
        published = True
        staging = None

        directory_fd = os.open(parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)

        published_raw = _regular(output, "published Final GO record")
        if published_raw != raw:
            raise FinalGoError("published Final GO record bytes differ from staged authority")
        return _sha(raw)
    except Exception:
        if fd >= 0:
            os.close(fd)
        if not published and staging is not None:
            try:
                staging.unlink(missing_ok=True)
            except OSError:
                pass
        raise


def _args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    path_flags = (
        "candidate-root",
        "trusted-xcode-job-record",
        "trusted-xcode-artifact-metadata",
        "trusted-xcode-artifact-archive",
    )
    string_flags = (
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
    )
    for flag in path_flags:
        p.add_argument(f"--{flag}", required=True, type=Path)
    for flag in string_flags:
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
