#!/usr/bin/env python3
"""Verify the default-branch trusted Capture Xcode authority subject.

This module deliberately separates two authorities that GitHub represents with different SHAs:
- the default-branch workflow source that is allowed to schedule the self-hosted Mac job; and
- the exact Capture PR head whose retained evidence the trusted workflow validates.

It creates software acceptance evidence only. It does not authorize physical Experiment One,
Bluetooth writes, scooter identity, protocol semantics, or telemetry.
"""
from __future__ import annotations

import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import re
import stat
from typing import Any, Callable
import zipfile

REPOSITORY = "jonathangana131-lab/Nembra"
REPOSITORY_OWNER = "jonathangana131-lab"
DEFAULT_BRANCH = "main"
TRUSTED_WORKFLOW_NAME = "Capture Trusted Xcode 27 Exact-Head QA"
TRUSTED_WORKFLOW_PATH = ".github/workflows/capture-xcode27-trusted-command.yml"
TRUSTED_WORKFLOW_BLOB_SHA = "3dbcf115b92a45856acd6cae0ff6c4d1448d8efb"
TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_PATH = "scripts/ci/xcode27_simulator_capture.sh"
TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"
TRUSTED_JOB_NAME = "Build, test, and capture trusted exact Capture head"
TRUSTED_ARTIFACT_PREFIX = "nembra-capture-xcode27-"
EXTERNAL_RECORD_NAME = "NembraCaptureExternalBuildRecord.json"
RECIPE = "ES80-FINGERPRINT-v1"
PROCEDURE = "V14"
EXTERNAL_KEYS = {
    "schemaVersion",
    "buildIdentifier",
    "buildInstanceID",
    "sourceCommitSHA",
    "executableSHA256",
    "infoPlistSHA256",
    "experimentRecipeID",
    "procedureVersion",
}
REQUIRED_SUCCESSFUL_STEPS = (
    "Reject stale or detached Capture head before scarce Mac work",
    "Verify immutable trusted Capture head",
    "Verify trusted Simulator evidence-producer custody",
    "Build, test, and capture Simulator states",
    "Verify retained Capture evidence against trusted resolver authority",
    "Reject head movement before trusted acceptance completes",
)

_HEX40 = re.compile(r"^[0-9a-f]{40}$")
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


class TrustedCaptureXcodeError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise TrustedCaptureXcodeError(message)


def _positive_int(value: Any, label: str) -> int:
    _require(isinstance(value, int) and not isinstance(value, bool) and value > 0, f"invalid {label}")
    return value


def _normalized_sha(value: Any, label: str) -> str:
    _require(isinstance(value, str), f"missing {label}")
    lowered = value.lower()
    _require(_HEX40.fullmatch(lowered) is not None, f"invalid {label}")
    return lowered


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise TrustedCaptureXcodeError(
                f"trusted Xcode external build record contains duplicate key: {key}"
            )
        result[key] = value
    return result


def _read_archive_snapshot(path: Path) -> bytes:
    """Read one descriptor-bound regular-file subject exactly once.

    Digest, byte-count, and ZIP inspection are all derived from the returned bytes. The pathname
    is never re-opened after this function returns, so a later path replacement cannot mix two
    downloaded GitHub artifact generations into one Final GO subject. Descriptor metadata that
    changes on in-place writes is also bound across the read so same-inode mutation fails closed.
    """

    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW

    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise TrustedCaptureXcodeError(
            "trusted Xcode artifact archive is missing or unsafe"
        ) from error

    try:
        before = os.fstat(descriptor)
        _require(
            stat.S_ISREG(before.st_mode),
            "trusted Xcode artifact archive must be one regular file",
        )
        identity_before = (
            before.st_dev,
            before.st_ino,
            before.st_mode,
            before.st_uid,
            before.st_gid,
            before.st_size,
            before.st_mtime_ns,
            before.st_ctime_ns,
        )

        chunks: list[bytes] = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        raw = b"".join(chunks)

        after = os.fstat(descriptor)
        identity_after = (
            after.st_dev,
            after.st_ino,
            after.st_mode,
            after.st_uid,
            after.st_gid,
            after.st_size,
            after.st_mtime_ns,
            after.st_ctime_ns,
        )
        _require(
            identity_before == identity_after,
            "trusted Xcode artifact archive identity or contents changed while reading",
        )
        _require(
            len(raw) == before.st_size,
            "trusted Xcode artifact archive byte count changed while reading",
        )
        return raw
    finally:
        os.close(descriptor)


def _single_external_record(archive_bytes: bytes, source: str) -> dict[str, Any]:
    try:
        with zipfile.ZipFile(BytesIO(archive_bytes), "r") as archive:
            names = [name for name in archive.namelist() if not name.endswith("/")]
            matches = [name for name in names if Path(name).name == EXTERNAL_RECORD_NAME]
            _require(
                len(matches) == 1,
                "trusted Xcode artifact must contain exactly one external build record",
            )
            raw = archive.read(matches[0])
    except (OSError, zipfile.BadZipFile, KeyError) as error:
        raise TrustedCaptureXcodeError(
            "trusted Xcode artifact is not a readable retained ZIP"
        ) from error

    try:
        decoded = json.loads(raw, object_pairs_hook=_reject_duplicate_pairs)
    except TrustedCaptureXcodeError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise TrustedCaptureXcodeError(
            "trusted Xcode external build record is not valid JSON"
        ) from error

    _require(
        isinstance(decoded, dict),
        "trusted Xcode external build record must be an object",
    )
    _require(
        set(decoded) == EXTERNAL_KEYS,
        "trusted Xcode external build record schema shape drifted",
    )
    _require(
        decoded.get("schemaVersion") == 3,
        "trusted Xcode external build record schema version drifted",
    )
    _require(
        decoded.get("sourceCommitSHA") == source,
        "trusted retained artifact is for a different Capture source",
    )
    _require(
        decoded.get("buildIdentifier") == f"Capture Build V14-{source[:12]}",
        "trusted external build identifier does not match exact Capture source",
    )
    _require(
        decoded.get("experimentRecipeID") == RECIPE,
        "trusted external build record recipe is not canonical",
    )
    _require(
        decoded.get("procedureVersion") == PROCEDURE,
        "trusted external build record procedure is not canonical V14",
    )
    build_instance = decoded.get("buildInstanceID")
    _require(
        isinstance(build_instance, str) and _UUID.fullmatch(build_instance) is not None,
        "trusted external build instance is not one canonical lowercase UUID",
    )
    executable_sha = decoded.get("executableSHA256")
    _require(
        isinstance(executable_sha, str) and _HEX64.fullmatch(executable_sha) is not None,
        "trusted external executable SHA-256 is not canonical",
    )
    info_plist_sha = decoded.get("infoPlistSHA256")
    _require(
        isinstance(info_plist_sha, str) and _HEX64.fullmatch(info_plist_sha) is not None,
        "trusted external Info.plist SHA-256 is not canonical",
    )
    return decoded


def verify_trusted_capture_xcode_subject(
    *,
    source_commit_sha: str,
    expected_pr_number: int,
    run_id: int,
    job_id: int,
    artifact_id: int,
    artifact_archive_path: Path,
    github_get_json: Callable[[str], tuple[bytes, Any]],
    workflow_blob_sha_at_commit: Callable[[str, str], str],
) -> dict[str, Any]:
    """Return one closed trusted-Xcode subject or fail closed.

    `workflow_blob_sha_at_commit` must read Git object identity from a repository checkout that can
    resolve both the workflow run's default-branch commit and the exact candidate commit. Final GO
    binds not only the workflow implementation, but also the candidate-side Simulator evidence
    producer that the trusted workflow executes.
    """

    source = _normalized_sha(source_commit_sha, "candidate source commit SHA")
    pr_number = _positive_int(expected_pr_number, "PR number")
    run_id = _positive_int(run_id, "trusted Xcode run ID")
    job_id = _positive_int(job_id, "trusted Xcode job ID")
    artifact_id = _positive_int(artifact_id, "trusted Xcode artifact ID")

    _, pr = github_get_json(f"/pulls/{pr_number}")
    _require(isinstance(pr, dict), "GitHub PR payload must be an object")
    _require(pr.get("number") == pr_number, "GitHub PR number mismatch")
    _require(pr.get("state") == "open", "trusted Capture PR must still be open")
    head = pr.get("head") or {}
    base = pr.get("base") or {}
    _require(
        _normalized_sha(head.get("sha"), "live PR head SHA") == source,
        "live PR head no longer matches candidate source",
    )
    _require(
        (head.get("repo") or {}).get("full_name") == REPOSITORY,
        "trusted Capture PR head repository mismatch",
    )
    _require(
        (base.get("repo") or {}).get("full_name") == REPOSITORY,
        "trusted Capture PR base repository mismatch",
    )

    _, run = github_get_json(f"/actions/runs/{run_id}")
    _require(isinstance(run, dict), "GitHub run payload must be an object")
    _require(run.get("id") == run_id, "trusted Xcode run ID mismatch")
    _require(run.get("name") == TRUSTED_WORKFLOW_NAME, "wrong trusted Xcode workflow name")
    _require(run.get("path") == TRUSTED_WORKFLOW_PATH, "wrong trusted Xcode workflow path")
    _require(
        run.get("event") == "issue_comment",
        "trusted Xcode run must originate from default-branch issue_comment command",
    )
    _require(
        run.get("status") == "completed" and run.get("conclusion") == "success",
        "trusted Xcode run is not successful",
    )
    _require(
        (run.get("repository") or {}).get("full_name") == REPOSITORY,
        "trusted Xcode run repository mismatch",
    )
    _require(
        (run.get("head_repository") or {}).get("full_name") == REPOSITORY,
        "trusted Xcode run head repository mismatch",
    )
    _require(
        run.get("head_branch") == DEFAULT_BRANCH,
        "trusted Xcode workflow did not execute from the default branch",
    )
    _require(
        (run.get("actor") or {}).get("login") == REPOSITORY_OWNER,
        "trusted Xcode command actor is not repository owner",
    )
    _require(
        (run.get("triggering_actor") or {}).get("login") == REPOSITORY_OWNER,
        "trusted Xcode triggering actor is not repository owner",
    )

    workflow_source = _normalized_sha(run.get("head_sha"), "trusted workflow source SHA")
    workflow_blob = workflow_blob_sha_at_commit(workflow_source, TRUSTED_WORKFLOW_PATH).lower()
    _require(_HEX40.fullmatch(workflow_blob) is not None, "invalid trusted workflow blob SHA")
    _require(
        workflow_blob == TRUSTED_WORKFLOW_BLOB_SHA,
        "trusted Xcode workflow implementation blob is not pinned authority",
    )

    producer_blob = workflow_blob_sha_at_commit(
        source,
        TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_PATH,
    ).lower()
    _require(
        _HEX40.fullmatch(producer_blob) is not None,
        "invalid trusted Simulator evidence-producer Git blob SHA",
    )
    _require(
        producer_blob == TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA,
        "trusted Simulator evidence-producer Git blob is not pinned authority",
    )

    run_attempt = _positive_int(run.get("run_attempt"), "trusted Xcode run attempt")
    run_number = _positive_int(run.get("run_number"), "trusted Xcode run number")

    _, job = github_get_json(f"/actions/jobs/{job_id}")
    _require(isinstance(job, dict), "GitHub job payload must be an object")
    _require(job.get("id") == job_id, "trusted Xcode job ID mismatch")
    _require(job.get("run_id") == run_id, "trusted Xcode job belongs to a different run")
    _require(job.get("run_attempt") == run_attempt, "trusted Xcode job run-attempt mismatch")
    _require(job.get("workflow_name") == TRUSTED_WORKFLOW_NAME, "trusted Xcode job workflow mismatch")
    _require(job.get("name") == TRUSTED_JOB_NAME, "wrong trusted Xcode job name")
    _require(
        _normalized_sha(job.get("head_sha"), "trusted Xcode job workflow SHA") == workflow_source,
        "trusted Xcode job did not execute the trusted workflow source",
    )
    _require(
        job.get("status") == "completed" and job.get("conclusion") == "success",
        "trusted Xcode job is not successful",
    )
    labels = job.get("labels") or []
    _require("xcode-27" in labels, "trusted Xcode job did not run on xcode-27")

    steps = job.get("steps") or []
    successful_steps = {
        step.get("name")
        for step in steps
        if isinstance(step, dict) and step.get("conclusion") == "success"
    }
    for required in REQUIRED_SUCCESSFUL_STEPS:
        _require(
            required in successful_steps,
            f"trusted Xcode job did not successfully execute required step: {required}",
        )

    _, artifact = github_get_json(f"/actions/artifacts/{artifact_id}")
    _require(isinstance(artifact, dict), "GitHub artifact payload must be an object")
    _require(artifact.get("id") == artifact_id, "trusted Xcode artifact ID mismatch")
    expected_artifact_name = f"{TRUSTED_ARTIFACT_PREFIX}{pr_number}-{run_number}-{run_attempt}"
    _require(
        artifact.get("name") == expected_artifact_name,
        "trusted Xcode artifact name mismatch",
    )
    _require(artifact.get("expired") is False, "trusted Xcode artifact is expired")

    archive_bytes = _read_archive_snapshot(artifact_archive_path)
    archive_sha = hashlib.sha256(archive_bytes).hexdigest()
    archive_byte_count = len(archive_bytes)
    server_digest = artifact.get("digest")
    _require(
        isinstance(server_digest, str)
        and server_digest.lower() == f"sha256:{archive_sha}",
        "trusted Xcode artifact archive digest mismatch",
    )
    _require(
        artifact.get("size_in_bytes") == archive_byte_count,
        "trusted Xcode artifact archive size mismatch",
    )
    artifact_run = artifact.get("workflow_run") or {}
    _require(
        artifact_run.get("id") == run_id,
        "trusted Xcode artifact workflow-run mismatch",
    )
    _require(
        _normalized_sha(artifact_run.get("head_sha"), "trusted artifact workflow SHA")
        == workflow_source,
        "trusted Xcode artifact did not originate from the trusted workflow source",
    )

    external_record = _single_external_record(archive_bytes, source)

    return {
        "authority": "default-branch-owner-command-v1",
        "repository": REPOSITORY,
        "candidatePRNumber": pr_number,
        "candidateSourceCommitSHA": source,
        "workflowName": TRUSTED_WORKFLOW_NAME,
        "workflowPath": TRUSTED_WORKFLOW_PATH,
        "workflowSourceCommitSHA": workflow_source,
        "workflowBlobSHA": workflow_blob,
        "simulatorEvidenceProducerPath": TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_PATH,
        "simulatorEvidenceProducerBlobSHA": producer_blob,
        "runID": run_id,
        "runNumber": run_number,
        "runAttempt": run_attempt,
        "jobID": job_id,
        "artifactID": artifact_id,
        "artifactName": expected_artifact_name,
        "artifactArchiveSHA256": archive_sha,
        "artifactArchiveByteCount": archive_byte_count,
        "externalBuildRecord": external_record,
    }
