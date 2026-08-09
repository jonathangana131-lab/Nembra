#!/usr/bin/env python3
"""Emit the external V14 ES80 TODAY Final GO record from exact retained evidence.

This helper is intentionally external to the frozen signed-app lineage. It validates live GitHub
exact-head acceptance, the retained Simulator artifact, the signed field candidate, the pinned
independent PASS_NOT_FINAL_GO receipt, frozen-source Git-blob claims, the exact retained-IPA
installation handoff, and one explicit operator attestation. It never creates physical ES80
evidence and never grants Bluetooth write/command authority.
"""
from __future__ import annotations

import argparse
import ctypes
from datetime import datetime, timedelta, timezone
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
from typing import Any, Callable
import urllib.error
import urllib.request
import zipfile

RECIPE = "ES80-FINGERPRINT-v1"
PROCEDURE = "V14"
BASELINE_DEVICE = "iPhone 12"
BASELINE_OS = "iOS 27"
BUNDLE_ID = "com.jonathangana131.nembra"
REPOSITORY = "jonathangana131-lab/Nembra"
TRUSTED_WORKFLOW_NAME = "Xcode 27 PR Exact-Head QA"
TRUSTED_WORKFLOW_PATH = ".github/workflows/xcode27-pr-command.yml"
TRUSTED_JOB_NAME = "Build, test, and capture exact PR head"
TRUSTED_ARTIFACT_PREFIX = "nembra-xcode27-pr-"
PINNED_CROSSCHECK_COMMIT = "d827a296048386bda62024ea3278775d5344c47c"
PINNED_CROSSCHECK_BLOB = "c3b2b620280484c05316fc5c2fa2ca451f1fdc83"
RESEARCH_COMPILE_MODE = "private-today-v1"
RESEARCH_COMPILE_AUTHORITY = "canonical-producer-explicit-mode"
RESEARCH_COMPILE_CONDITION = "NEMBRA_ES80_TODAY_RESEARCH"
CROSSCHECK_PATH = "scripts/ci/es80_today_independent_candidate_crosscheck.py"
PRIVATE_RUNNER_PATH = "scripts/ci/es80_signed_field_artifact_private_runner.py"
INSPECTOR_PATH = "scripts/ci/es80_signed_field_artifact_evidence.py"
INSTALL_ROUTE = "exact-retained-ipa-via-xcode-device-management"
OPERATOR_AUTHORITY = "operator-field-attestation-not-machine-evidence"
CROSSCHECK_AUTHORITY = "independent-retained-candidate-evidence-crosscheck-not-final-go"

EXTERNAL_RECORD_NAME = "NembraCaptureExternalBuildRecord.json"
FIELD_RECORD_NAME = "NembraCaptureFieldBuildEvidenceRecord.json"
INSPECTION_NAME = "NembraCaptureSignedFieldArtifactInspection.json"
IPA_RELATIVE_PATH = Path("build-evidence/NembraField.ipa")

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
GIT_OID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
TEAM = re.compile(r"^[A-Z0-9]{10}$")
CDHASH = re.compile(r"^[0-9a-f]{40,64}$")
SHA256_DIGEST = re.compile(r"^sha256:([0-9a-f]{64})$")

EXTERNAL_KEYS = {
    "schemaVersion", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "executableSHA256", "infoPlistSHA256", "experimentRecipeID", "procedureVersion",
}
FIELD_KEYS = {
    "schemaVersion", "externalBuildRecordSHA256", "signedInstallableSHA256",
    "signedInstallableKind", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "executableSHA256", "infoPlistSHA256", "experimentRecipeID", "procedureVersion",
}
INSPECTION_KEYS = {
    "schemaVersion", "authority", "fieldBuildEvidenceRecordSHA256",
    "externalBuildRecordSHA256", "signedInstallableSHA256", "signedInstallableKind",
    "ipaByteCount", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "bundleIdentifier", "platformName", "supportedPlatforms", "teamIdentifier",
    "signingAuthorities", "codeDirectoryHash", "provisioningProfileSHA256",
    "provisioningProfileUUID", "provisioningProfileExpirationUTC",
    "provisioningApplicationIdentifier", "executableSHA256", "infoPlistSHA256",
    "experimentRecipeID", "procedureVersion",
}
CROSSCHECK_KEYS = {
    "schemaVersion", "authority", "status", "sourceCommitSHA", "buildIdentifier",
    "buildInstanceID", "experimentRecipeID", "procedureVersion", "researchCompileMode",
    "researchCompileAuthority", "researchCompileCondition", "signedInstallableSHA256",
    "signedInstallableByteCount", "externalBuildRecordSHA256", "fieldBuildEvidenceRecordSHA256",
    "signedFieldArtifactInspectionSHA256", "executableSHA256", "infoPlistSHA256",
    "exportOptionsSHA256", "teamIdentifier", "allowProvisioningUpdates",
    "privateRunnerSourceGitBlobClaim", "canonicalInspectorSourceGitBlobClaim", "xcodeVersion",
    "xcodeBuildVersion", "provisioningProfileSHA256", "provisioningProfileUUID",
    "provisioningProfileExpirationUTC", "singleRetainedIPA", "crossRecordDigestLinksVerified",
    "researchCompileTupleVerified", "producerPhysicalAuthorizationRemainsNotGranted",
    "appleSigningInspectionRequired", "toolBlobClaimsRequireRepositoryCrossCheck",
    "exactRetainedIPAInstallHandoffRequired", "physicalExperimentAuthorization",
}
ATTESTATION_KEYS = {
    "schemaVersion", "authority", "attestationID", "recordedAtUTC", "simulatorArtifactReview",
    "installationRoute", "preInstallRetainedIPASHA256", "postInstallRetainedIPASHA256",
    "installedWithoutRebuildOrSubstitution", "installedOnIntendedDevice", "observedDevice",
    "observedOS", "runtimeVisibleSourceCommitSHA", "runtimeVisibleBuildIdentifier",
    "runtimeVisibleBuildInstanceID", "runtimeVisibleRecipe", "runtimeResearchAdmission",
    "canonicalCoordinatorPermission", "ordinaryGeneralBuildAuthority", "preflightHealth",
    "chargerState", "motionState", "explicitOperatorActionRequired",
    "noApplicationWriteAuthorityReview",
}


class FinalGoError(RuntimeError):
    pass


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise FinalGoError(f"JSON contains duplicate object key: {key}")
        result[key] = value
    return result


def _regular(path: Path, label: str) -> bytes:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise FinalGoError(f"{label} is unavailable: {path}") from error
    if path.is_symlink() or not stat.S_ISREG(metadata.st_mode) or metadata.st_size <= 0:
        raise FinalGoError(f"{label} must be one non-empty regular non-symlink file: {path}")
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise FinalGoError(f"{label} is unreadable: {path}") from error
    if len(raw) != metadata.st_size:
        raise FinalGoError(f"{label} byte count changed while reading")
    return raw


def _sha_file(path: Path, label: str) -> tuple[str, int]:
    raw = _regular(path, label)
    return _sha(raw), len(raw)


def _json_bytes(raw: bytes, label: str) -> dict[str, Any]:
    try:
        value = json.loads(raw, object_pairs_hook=_reject_duplicate_pairs)
    except FinalGoError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FinalGoError(f"{label} is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise FinalGoError(f"{label} root must be one JSON object")
    return value


def _json_file(path: Path, label: str, *, exact_keys: set[str] | None = None) -> tuple[bytes, dict[str, Any]]:
    raw = _regular(path, label)
    value = _json_bytes(raw, label)
    if exact_keys is not None and set(value) != exact_keys:
        raise FinalGoError(f"{label} schema shape drifted: {sorted(value)!r}")
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


def _parse_utc(value: Any, label: str) -> datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise FinalGoError(f"{label} must be normalized UTC text")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise FinalGoError(f"{label} is malformed") from error
    return parsed.astimezone(timezone.utc)


def _api_get_json(path: str) -> tuple[bytes, dict[str, Any]]:
    url = f"https://api.github.com/repos/{REPOSITORY}{path}"
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "Nembra-V14-Final-GO",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.geturl().split("?", 1)[0] != url:
                raise FinalGoError(f"GitHub API metadata request redirected unexpectedly: {url}")
            raw = response.read()
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise FinalGoError(f"GitHub API metadata unavailable: {url}") from error
    return raw, _json_bytes(raw, f"GitHub API response {path}")


def _trusted_xcode_subject(
    *,
    source: str,
    expected_pr_number: int,
    run_id: int,
    job_id: int,
    artifact_id: int,
    artifact_archive_path: Path,
    github_get_json: Callable[[str], tuple[bytes, dict[str, Any]]],
) -> dict[str, Any]:
    run_raw, run = github_get_json(f"/actions/runs/{run_id}")
    _eq(_positive_int(run.get("id"), "trusted Xcode run ID"), run_id, "trusted Xcode run ID")
    _eq(run.get("name"), TRUSTED_WORKFLOW_NAME, "trusted Xcode workflow name")
    _eq(run.get("path"), TRUSTED_WORKFLOW_PATH, "trusted Xcode workflow path")
    _eq(run.get("event"), "pull_request", "trusted Xcode workflow event")
    _eq(run.get("head_sha"), source, "trusted Xcode run exact source SHA")
    _eq(run.get("status"), "completed", "trusted Xcode run status")
    _eq(run.get("conclusion"), "success", "trusted Xcode run conclusion")
    run_attempt = _positive_int(run.get("run_attempt"), "trusted Xcode run attempt")
    run_number = _positive_int(run.get("run_number"), "trusted Xcode run number")
    repository = run.get("repository")
    head_repository = run.get("head_repository")
    if not isinstance(repository, dict) or repository.get("full_name") != REPOSITORY:
        raise FinalGoError("trusted Xcode run repository is not canonical Nembra")
    if not isinstance(head_repository, dict) or head_repository.get("full_name") != REPOSITORY:
        raise FinalGoError("trusted Xcode run is not a same-repository subject")
    pull_requests = run.get("pull_requests")
    if not isinstance(pull_requests, list) or expected_pr_number not in [
        item.get("number") for item in pull_requests if isinstance(item, dict)
    ]:
        raise FinalGoError("trusted Xcode run does not identify the expected Capture PR")

    job_raw, job = github_get_json(f"/actions/jobs/{job_id}")
    _eq(_positive_int(job.get("id"), "trusted Xcode job ID"), job_id, "trusted Xcode job ID")
    _eq(job.get("run_id"), run_id, "trusted Xcode job run ID")
    _eq(job.get("run_attempt"), run_attempt, "trusted Xcode job run attempt")
    _eq(job.get("workflow_name"), TRUSTED_WORKFLOW_NAME, "trusted Xcode job workflow name")
    _eq(job.get("name"), TRUSTED_JOB_NAME, "trusted Xcode job name")
    _eq(job.get("head_sha"), source, "trusted Xcode job exact source SHA")
    _eq(job.get("status"), "completed", "trusted Xcode job status")
    _eq(job.get("conclusion"), "success", "trusted Xcode job conclusion")
    labels = job.get("labels")
    if not isinstance(labels, list) or "xcode-27" not in labels:
        raise FinalGoError("trusted Xcode job did not run on the xcode-27 runner class")
    required_steps = {
        "Reject stale PR head before scarce Mac work",
        "Verify immutable PR head",
        "Build, test, and capture Simulator states",
        "Verify retained Capture build evidence",
        "Reject head movement before acceptance completion",
    }
    steps = job.get("steps")
    if not isinstance(steps, list):
        raise FinalGoError("trusted Xcode job lacks step evidence")
    step_results = {
        item.get("name"): item.get("conclusion")
        for item in steps
        if isinstance(item, dict) and isinstance(item.get("name"), str)
    }
    for name in required_steps:
        _eq(step_results.get(name), "success", f"trusted Xcode step {name}")
    run_url = job.get("run_url")
    job_url = job.get("url")
    if not isinstance(run_url, str) or not run_url.endswith(f"/actions/runs/{run_id}"):
        raise FinalGoError("trusted Xcode job run URL does not bind the run ID")
    if not isinstance(job_url, str) or not job_url.endswith(f"/actions/jobs/{job_id}"):
        raise FinalGoError("trusted Xcode job URL does not bind the job ID")

    artifact_raw, artifact = github_get_json(f"/actions/artifacts/{artifact_id}")
    _eq(_positive_int(artifact.get("id"), "trusted Xcode artifact ID"), artifact_id, "trusted Xcode artifact ID")
    expected_name = f"{TRUSTED_ARTIFACT_PREFIX}{expected_pr_number}-{run_number}-{run_attempt}"
    _eq(artifact.get("name"), expected_name, "trusted Xcode artifact name")
    _eq(artifact.get("expired"), False, "trusted Xcode artifact expiration state")
    workflow_run = artifact.get("workflow_run")
    if not isinstance(workflow_run, dict):
        raise FinalGoError("trusted Xcode artifact metadata lacks workflow_run subject")
    _eq(workflow_run.get("id"), run_id, "trusted Xcode artifact run ID")
    _eq(workflow_run.get("head_sha"), source, "trusted Xcode artifact exact source SHA")
    archive_sha, archive_size = _sha_file(artifact_archive_path, "trusted Xcode artifact archive")
    digest = artifact.get("digest")
    if not isinstance(digest, str) or SHA256_DIGEST.fullmatch(digest) is None:
        raise FinalGoError("trusted Xcode artifact lacks canonical server-declared SHA-256")
    _eq(SHA256_DIGEST.fullmatch(digest).group(1), archive_sha, "trusted Xcode downloaded artifact archive digest")
    declared_size = artifact.get("size_in_bytes")
    if isinstance(declared_size, int) and not isinstance(declared_size, bool) and declared_size > 0:
        _eq(declared_size, archive_size, "trusted Xcode downloaded artifact archive byte count")

    embedded = _inspect_xcode_archive(artifact_archive_path, source)
    return {
        "workflowName": TRUSTED_WORKFLOW_NAME,
        "workflowPath": TRUSTED_WORKFLOW_PATH,
        "prNumber": expected_pr_number,
        "runID": run_id,
        "runNumber": run_number,
        "runAttempt": run_attempt,
        "jobID": job_id,
        "jobName": TRUSTED_JOB_NAME,
        "runAPIResponseSHA256": _sha(run_raw),
        "jobAPIResponseSHA256": _sha(job_raw),
        "artifactID": artifact_id,
        "artifactName": expected_name,
        "artifactAPIResponseSHA256": _sha(artifact_raw),
        "artifactArchiveSHA256": archive_sha,
        "artifactArchiveByteCount": archive_size,
        "embeddedExternalBuildRecordSHA256": embedded["sha256"],
        "embeddedBuildIdentifier": embedded["buildIdentifier"],
        "embeddedBuildInstanceID": embedded["buildInstanceID"],
        "classification": "live-github-exact-head-acceptance-plus-retained-artifact",
    }


def _inspect_xcode_archive(path: Path, source: str) -> dict[str, str]:
    try:
        with zipfile.ZipFile(path) as archive:
            matches = [name for name in archive.namelist() if Path(name).name == EXTERNAL_RECORD_NAME]
            if len(matches) != 1:
                raise FinalGoError("trusted Xcode artifact must contain exactly one external build record")
            raw = archive.read(matches[0])
    except (OSError, zipfile.BadZipFile, KeyError) as error:
        raise FinalGoError("trusted Xcode artifact is not a readable retained ZIP") from error
    record = _json_bytes(raw, "trusted Xcode embedded external build record")
    if set(record) != EXTERNAL_KEYS or record.get("schemaVersion") != 3:
        raise FinalGoError("trusted Xcode embedded external build record schema drifted")
    _eq(record.get("sourceCommitSHA"), source, "trusted Xcode embedded source SHA")
    _eq(record.get("buildIdentifier"), f"Capture Build V14-{source[:12]}", "trusted Xcode embedded build identifier")
    _eq(record.get("experimentRecipeID"), RECIPE, "trusted Xcode embedded recipe")
    _eq(record.get("procedureVersion"), PROCEDURE, "trusted Xcode embedded procedure")
    _shape(record.get("buildInstanceID"), UUID, "trusted Xcode embedded build-instance ID")
    _shape(record.get("executableSHA256"), HEX64, "trusted Xcode embedded executable SHA-256")
    _shape(record.get("infoPlistSHA256"), HEX64, "trusted Xcode embedded Info.plist SHA-256")
    return {
        "sha256": _sha(raw),
        "buildIdentifier": record["buildIdentifier"],
        "buildInstanceID": record["buildInstanceID"],
    }


def _git(repository: Path, *arguments: str) -> str:
    try:
        metadata = repository.lstat()
    except OSError as error:
        raise FinalGoError(f"Git repository is unavailable: {repository}") from error
    if repository.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
        raise FinalGoError(f"Git repository must be one real non-symlink directory: {repository}")
    env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }
    try:
        return subprocess.check_output(
            ["/usr/bin/git", "-C", str(repository.resolve()), *arguments],
            env=env,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise FinalGoError(f"Git evidence lookup failed: {' '.join(arguments)}") from error


def _candidate_subject(candidate_root: Path, source: str, now_utc: datetime) -> tuple[dict[str, Any], dict[str, str]]:
    root = candidate_root.resolve(strict=True) / "inspection"
    external_raw, external = _json_file(root / EXTERNAL_RECORD_NAME, "external build record", exact_keys=EXTERNAL_KEYS)
    field_raw, field = _json_file(root / FIELD_RECORD_NAME, "field-build evidence record", exact_keys=FIELD_KEYS)
    inspection_raw, inspection = _json_file(root / INSPECTION_NAME, "signed artifact inspection", exact_keys=INSPECTION_KEYS)
    ipa_sha, ipa_size = _sha_file(root / IPA_RELATIVE_PATH, "retained IPA")
    external_sha = _sha(external_raw)
    field_sha = _sha(field_raw)
    inspection_sha = _sha(inspection_raw)

    _eq(external.get("schemaVersion"), 3, "external schema version")
    _eq(field.get("schemaVersion"), 1, "field schema version")
    _eq(inspection.get("schemaVersion"), 2, "inspection schema version")
    _eq(external.get("sourceCommitSHA"), source, "external source SHA")
    build = f"Capture Build V14-{source[:12]}"
    _eq(external.get("buildIdentifier"), build, "external build identifier")
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
    _eq(field.get("externalBuildRecordSHA256"), external_sha, "field external-record digest")
    _eq(inspection.get("externalBuildRecordSHA256"), external_sha, "inspection external-record digest")
    _eq(inspection.get("fieldBuildEvidenceRecordSHA256"), field_sha, "inspection field-record digest")
    _eq(field.get("signedInstallableSHA256"), ipa_sha, "field retained IPA digest")
    _eq(inspection.get("signedInstallableSHA256"), ipa_sha, "inspection retained IPA digest")
    _eq(field.get("signedInstallableKind"), "ipa", "field installable kind")
    _eq(inspection.get("signedInstallableKind"), "ipa", "inspection installable kind")
    _eq(inspection.get("ipaByteCount"), ipa_size, "inspection retained IPA byte count")
    _eq(inspection.get("authority"), "signed-field-artifact-inspection-not-field-authorization", "inspection authority")
    _eq(inspection.get("bundleIdentifier"), BUNDLE_ID, "inspection bundle identifier")
    _eq(inspection.get("platformName"), "iphoneos", "inspection platform")
    platforms = inspection.get("supportedPlatforms")
    if not isinstance(platforms, list) or "iPhoneOS" not in platforms or any(
        isinstance(item, str) and "simulator" in item.casefold() for item in platforms
    ):
        raise FinalGoError("signed inspection does not describe a physical iPhone installable")
    team = _shape(inspection.get("teamIdentifier"), TEAM, "inspection TeamIdentifier")
    _eq(inspection.get("provisioningApplicationIdentifier"), f"{team}.{BUNDLE_ID}", "inspection provisioning application identifier")
    profile_sha = _shape(inspection.get("provisioningProfileSHA256"), HEX64, "inspection provisioning profile SHA-256")
    profile_uuid = inspection.get("provisioningProfileUUID")
    if not isinstance(profile_uuid, str) or not profile_uuid.strip():
        raise FinalGoError("signed inspection lacks provisioning profile identity")
    expiry_text = inspection.get("provisioningProfileExpirationUTC")
    expiry = _parse_utc(expiry_text, "inspection provisioning profile expiration")
    if expiry <= now_utc:
        raise FinalGoError("provisioning profile expired before Final GO")
    authorities = inspection.get("signingAuthorities")
    if not isinstance(authorities, list) or not authorities or not all(isinstance(item, str) and item.strip() for item in authorities):
        raise FinalGoError("signed inspection lacks signing authority evidence")
    _shape(inspection.get("codeDirectoryHash"), CDHASH, "inspection CodeDirectory hash")

    output = {
        "buildIdentifier": build,
        "buildInstanceID": instance,
        "sourceCommitSHA": source,
        "retainedIPASHA256": ipa_sha,
        "retainedIPAByteCount": ipa_size,
        "externalBuildRecordSHA256": external_sha,
        "fieldBuildEvidenceRecordSHA256": field_sha,
        "signedArtifactInspectionSHA256": inspection_sha,
        "executableSHA256": executable,
        "infoPlistSHA256": info_plist,
        "teamIdentifier": team,
        "provisioningProfileSHA256": profile_sha,
        "provisioningProfileUUID": profile_uuid.strip(),
        "provisioningProfileExpirationUTC": expiry_text,
        "codeDirectoryHash": inspection["codeDirectoryHash"],
    }
    raw = {"external": external_sha, "field": field_sha, "inspection": inspection_sha}
    return output, raw


def _crosscheck_subject(
    path: Path,
    candidate: dict[str, Any],
    frozen_source_repo: Path,
    tooling_repo: Path,
) -> dict[str, Any]:
    raw, receipt = _json_file(path, "independent retained-candidate cross-check receipt", exact_keys=CROSSCHECK_KEYS)
    _eq(receipt.get("schemaVersion"), 1, "cross-check schema version")
    _eq(receipt.get("authority"), CROSSCHECK_AUTHORITY, "cross-check authority")
    _eq(receipt.get("status"), "PASS_NOT_FINAL_GO", "cross-check status")
    expected = {
        "sourceCommitSHA": candidate["sourceCommitSHA"],
        "buildIdentifier": candidate["buildIdentifier"],
        "buildInstanceID": candidate["buildInstanceID"],
        "experimentRecipeID": RECIPE,
        "procedureVersion": PROCEDURE,
        "researchCompileMode": RESEARCH_COMPILE_MODE,
        "researchCompileAuthority": RESEARCH_COMPILE_AUTHORITY,
        "researchCompileCondition": RESEARCH_COMPILE_CONDITION,
        "signedInstallableSHA256": candidate["retainedIPASHA256"],
        "signedInstallableByteCount": candidate["retainedIPAByteCount"],
        "externalBuildRecordSHA256": candidate["externalBuildRecordSHA256"],
        "fieldBuildEvidenceRecordSHA256": candidate["fieldBuildEvidenceRecordSHA256"],
        "signedFieldArtifactInspectionSHA256": candidate["signedArtifactInspectionSHA256"],
        "executableSHA256": candidate["executableSHA256"],
        "infoPlistSHA256": candidate["infoPlistSHA256"],
        "teamIdentifier": candidate["teamIdentifier"],
        "provisioningProfileSHA256": candidate["provisioningProfileSHA256"],
        "provisioningProfileUUID": candidate["provisioningProfileUUID"],
        "provisioningProfileExpirationUTC": candidate["provisioningProfileExpirationUTC"],
        "singleRetainedIPA": True,
        "crossRecordDigestLinksVerified": True,
        "researchCompileTupleVerified": True,
        "producerPhysicalAuthorizationRemainsNotGranted": True,
        "appleSigningInspectionRequired": True,
        "toolBlobClaimsRequireRepositoryCrossCheck": True,
        "exactRetainedIPAInstallHandoffRequired": True,
        "physicalExperimentAuthorization": "not-granted",
    }
    for key, value in expected.items():
        _eq(receipt.get(key), value, f"cross-check {key}")
    _shape(receipt.get("exportOptionsSHA256"), HEX64, "cross-check ExportOptions SHA-256")
    if receipt.get("allowProvisioningUpdates") not in {"0", "1"}:
        raise FinalGoError("cross-check allowProvisioningUpdates is not canonical")

    source = candidate["sourceCommitSHA"]
    _eq(_git(frozen_source_repo, "rev-parse", "--verify", f"{source}^{{commit}}"), source, "frozen source repository commit")
    private_blob = _shape(_git(frozen_source_repo, "rev-parse", f"{source}:{PRIVATE_RUNNER_PATH}"), GIT_OID, "private runner Git blob")
    inspector_blob = _shape(_git(frozen_source_repo, "rev-parse", f"{source}:{INSPECTOR_PATH}"), GIT_OID, "inspector Git blob")
    _eq(receipt.get("privateRunnerSourceGitBlobClaim"), private_blob, "cross-check private runner Git-blob claim")
    _eq(receipt.get("canonicalInspectorSourceGitBlobClaim"), inspector_blob, "cross-check inspector Git-blob claim")

    _eq(
        _git(tooling_repo, "rev-parse", "--verify", f"{PINNED_CROSSCHECK_COMMIT}^{{commit}}"),
        PINNED_CROSSCHECK_COMMIT,
        "pinned cross-check tooling commit",
    )
    tool_blob = _shape(
        _git(tooling_repo, "rev-parse", f"{PINNED_CROSSCHECK_COMMIT}:{CROSSCHECK_PATH}"),
        GIT_OID,
        "pinned cross-check tool Git blob",
    )
    _eq(tool_blob, PINNED_CROSSCHECK_BLOB, "pinned cross-check tool Git blob")
    return {
        "toolCommit": PINNED_CROSSCHECK_COMMIT,
        "toolGitBlob": tool_blob,
        "receiptSHA256": _sha(raw),
        "authority": CROSSCHECK_AUTHORITY,
        "status": "PASS_NOT_FINAL_GO",
        "privateRunnerSourceGitBlob": private_blob,
        "canonicalInspectorSourceGitBlob": inspector_blob,
        "researchCompileMode": RESEARCH_COMPILE_MODE,
        "researchCompileAuthority": RESEARCH_COMPILE_AUTHORITY,
        "researchCompileCondition": RESEARCH_COMPILE_CONDITION,
        "researchCompileTupleVerified": True,
        "physicalExperimentAuthorization": "not-granted",
    }


def _operator_attestation(path: Path, candidate: dict[str, Any], now_utc: datetime) -> dict[str, Any]:
    raw, attestation = _json_file(path, "operator field attestation", exact_keys=ATTESTATION_KEYS)
    _eq(attestation.get("schemaVersion"), 1, "operator attestation schema version")
    _eq(attestation.get("authority"), OPERATOR_AUTHORITY, "operator attestation authority")
    _shape(attestation.get("attestationID"), UUID, "operator attestation ID")
    observed_at = _parse_utc(attestation.get("recordedAtUTC"), "operator attestation time")
    if observed_at > now_utc + timedelta(minutes=5):
        raise FinalGoError("operator attestation time is implausibly in the future")
    if observed_at < now_utc - timedelta(minutes=30):
        raise FinalGoError("operator attestation is stale; charger/stationary preflight must be fresh")
    expected = {
        "simulatorArtifactReview": "INSPECTED_NO_TODAY_BLOCKER",
        "installationRoute": INSTALL_ROUTE,
        "preInstallRetainedIPASHA256": candidate["retainedIPASHA256"],
        "postInstallRetainedIPASHA256": candidate["retainedIPASHA256"],
        "installedWithoutRebuildOrSubstitution": True,
        "installedOnIntendedDevice": True,
        "observedDevice": BASELINE_DEVICE,
        "observedOS": BASELINE_OS,
        "runtimeVisibleSourceCommitSHA": candidate["sourceCommitSHA"],
        "runtimeVisibleBuildIdentifier": candidate["buildIdentifier"],
        "runtimeVisibleBuildInstanceID": candidate["buildInstanceID"],
        "runtimeVisibleRecipe": RECIPE,
        "runtimeResearchAdmission": "OBSERVED_AVAILABLE",
        "canonicalCoordinatorPermission": "OBSERVED_PERMITTED",
        "ordinaryGeneralBuildAuthority": "OBSERVED_NO_GO",
        "preflightHealth": "OBSERVED_READY",
        "chargerState": "DISCONNECTED",
        "motionState": "STATIONARY",
        "explicitOperatorActionRequired": True,
        "noApplicationWriteAuthorityReview": "REVIEWED_NO_APPLICATION_WRITE_OR_COMMAND_PATH",
    }
    for key, value in expected.items():
        _eq(attestation.get(key), value, f"operator attestation {key}")
    return {
        "recordSHA256": _sha(raw),
        "attestationID": attestation["attestationID"],
        "recordedAtUTC": attestation["recordedAtUTC"],
        "authority": OPERATOR_AUTHORITY,
        "classification": "human-observed-procedure-state-not-machine-or-physical-telemetry",
        "simulatorArtifactReview": attestation["simulatorArtifactReview"],
        "installationRoute": INSTALL_ROUTE,
        "preInstallRetainedIPASHA256": candidate["retainedIPASHA256"],
        "postInstallRetainedIPASHA256": candidate["retainedIPASHA256"],
        "runtimeRendezvousMatched": True,
        "packageResearchAdmissionObserved": True,
        "ordinaryGeneralBuildAuthority": "NO-GO",
        "preflightHealth": "READY",
        "chargerState": "DISCONNECTED",
        "motionState": "STATIONARY",
    }


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
    github_get_json: Callable[[str], tuple[bytes, dict[str, Any]]] = _api_get_json,
    now_utc: datetime | None = None,
) -> dict[str, Any]:
    now = (now_utc or datetime.now(timezone.utc)).astimezone(timezone.utc)
    source = _shape(expected_source_sha, HEX40, "expected source SHA")
    pr_number = _positive_int(expected_pr_number, "expected Capture PR number")
    candidate, _ = _candidate_subject(candidate_root, source, now)
    trusted = _trusted_xcode_subject(
        source=source,
        expected_pr_number=pr_number,
        run_id=_positive_int(trusted_xcode_run_id, "trusted Xcode run ID"),
        job_id=_positive_int(trusted_xcode_job_id, "trusted Xcode job ID"),
        artifact_id=_positive_int(trusted_xcode_artifact_id, "trusted Xcode artifact ID"),
        artifact_archive_path=trusted_xcode_artifact_archive,
        github_get_json=github_get_json,
    )
    crosscheck = _crosscheck_subject(
        independent_crosscheck_receipt,
        candidate,
        frozen_source_repo,
        tooling_repo,
    )
    attestation = _operator_attestation(operator_attestation, candidate, now)

    generated_at = now.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return {
        "schemaVersion": 3,
        "authority": "today-final-go-procedural-record-not-physical-result",
        "decision": "GO",
        "generatedAtUTC": generated_at,
        "acceptedSourceCommitSHA": source,
        "trustedXcodeAcceptance": trusted,
        "acceptedSignedFieldCandidate": candidate,
        "independentRetainedCandidateCrosscheck": crosscheck,
        "exactRetainedIPAInstallAndRuntimeAttestation": attestation,
        "procedureVersion": PROCEDURE,
        "experimentRecipeID": RECIPE,
        "baselineDevice": BASELINE_DEVICE,
        "baselineOS": BASELINE_OS,
        "ordinaryGeneralBuildAuthority": "NO-GO",
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
    libc = ctypes.CDLL(None, use_errno=True)
    source = os.fsencode(staging_path)
    destination = os.fsencode(output_path)
    if sys.platform == "darwin":
        rename_exclusive = libc.renamex_np
        rename_exclusive.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        rename_exclusive.restype = ctypes.c_int
        result = rename_exclusive(source, destination, 0x00000004)
    elif sys.platform.startswith("linux"):
        rename_exclusive = libc.renameat2
        rename_exclusive.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        rename_exclusive.restype = ctypes.c_int
        result = rename_exclusive(-100, source, -100, destination, 0x00000001)
    else:
        raise FinalGoError(f"atomic no-replace Final GO publication is unsupported on {sys.platform!r}")
    if result != 0:
        number = ctypes.get_errno()
        if number in (errno.EEXIST, errno.ENOTEMPTY):
            raise FinalGoError(f"refusing to replace existing Final GO record: {output_path}")
        raise OSError(number, os.strerror(number), str(output_path))


def publish_record_no_replace(
    output_path: Path,
    raw: bytes,
    *,
    publisher: Callable[[Path, Path], None] = _publish_file_no_replace,
) -> str:
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
        fd, staging_name = tempfile.mkstemp(prefix=f".{output.name}.", suffix=".staging", dir=parent)
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
        if _regular(staging, "staged Final GO record") != raw:
            raise FinalGoError("staged Final GO record bytes changed before publication")
        publisher(staging, output)
        published = True
        staging = None
        directory_fd = os.open(parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        if _regular(output, "published Final GO record") != raw:
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
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Compatibility CLI: the legacy filename can no longer exercise legacy GO authority."""
    arguments = sys.argv[1:] if argv is None else argv
    hardened_entrypoint = Path(__file__).resolve().with_name("es80_today_final_go_hardened.py")
    try:
        completed = subprocess.run(
            [sys.executable, str(hardened_entrypoint), *arguments],
            check=False,
        )
    except OSError as error:
        print(
            f"TODAY Final GO: NO-GO: hardened entrypoint unavailable: {error}",
            file=sys.stderr,
        )
        return 2
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
