#!/usr/bin/env python3
"""Verify GitHub-owner custody for the V14 Final GO operator observation record.

The local operator JSON remains a human observation/declaration. It is never promoted to machine
telemetry merely because it has the expected values. Canonical Final GO accepts it only when a
fresh, unedited GitHub issue comment from the repository OWNER binds the exact parsed record digest,
attestation identity, candidate source, build instance, retained IPA digest, recipe, and procedure.

This module does not create physical evidence and does not prove the human observations true. It
proves only that the repository owner explicitly attested to those exact bytes for the exact
candidate/PR inside the bounded field window. Machine-verifiable candidate/signing/Xcode facts remain
separate subjects in the Final GO record.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import re
from typing import Any, Callable

REPOSITORY = "jonathangana131-lab/Nembra"
REPOSITORY_OWNER = "jonathangana131-lab"
RECIPE = "ES80-FINGERPRINT-v1"
PROCEDURE = "V14"
AUTHORITY = "github-owner-attested-operator-observation-v1"
CLASSIFICATION = "owner-authenticated-human-observation-not-machine-or-physical-telemetry"
COMMENT_HEADER = "NEMBRA FINAL GO OPERATOR OBSERVATION V1"

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


class TrustedOperatorAttestationError(RuntimeError):
    pass


def _positive_int(value: Any, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise TrustedOperatorAttestationError(f"{label} must be one positive integer")
    return value


def _canonical(value: Any, pattern: re.Pattern[str], label: str) -> str:
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise TrustedOperatorAttestationError(f"{label} is not canonical")
    return value


def _utc(value: Any, label: str) -> datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise TrustedOperatorAttestationError(f"{label} must be normalized UTC text")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise TrustedOperatorAttestationError(f"{label} is malformed") from error
    return parsed.astimezone(timezone.utc)


def expected_comment_body(
    parsed_subject: dict[str, Any],
    candidate: dict[str, Any],
) -> str:
    record_sha = _canonical(
        parsed_subject.get("recordSHA256"), HEX64, "operator observation record SHA-256"
    )
    attestation_id = _canonical(
        parsed_subject.get("attestationID"), UUID, "operator observation attestation ID"
    )
    source = _canonical(candidate.get("sourceCommitSHA"), HEX40, "candidate source SHA")
    retained_ipa = _canonical(
        candidate.get("retainedIPASHA256"), HEX64, "candidate retained IPA SHA-256"
    )
    build_instance = _canonical(
        candidate.get("buildInstanceID"), UUID, "candidate build-instance ID"
    )
    return "\n".join(
        [
            COMMENT_HEADER,
            f"record-sha256: {record_sha}",
            f"attestation-id: {attestation_id}",
            f"source-commit: {source}",
            f"build-instance: {build_instance}",
            f"retained-ipa-sha256: {retained_ipa}",
            f"recipe: {RECIPE}",
            f"procedure: {PROCEDURE}",
        ]
    )


def verify_trusted_operator_attestation_subject(
    *,
    parsed_subject: dict[str, Any],
    candidate: dict[str, Any],
    expected_pr_number: int,
    comment_id: int,
    github_get_json: Callable[[str], tuple[bytes, dict[str, Any]]],
    now_utc: datetime,
) -> dict[str, Any]:
    """Bind a validated human observation record to one fresh owner-authenticated GitHub comment."""

    pr_number = _positive_int(expected_pr_number, "expected Capture PR number")
    trusted_comment_id = _positive_int(comment_id, "operator attestation comment ID")
    now = now_utc.astimezone(timezone.utc)

    record_sha = _canonical(
        parsed_subject.get("recordSHA256"), HEX64, "operator observation record SHA-256"
    )
    attestation_id = _canonical(
        parsed_subject.get("attestationID"), UUID, "operator observation attestation ID"
    )
    recorded_at_text = parsed_subject.get("recordedAtUTC")
    recorded_at = _utc(recorded_at_text, "operator observation time")

    raw, comment = github_get_json(f"/issues/comments/{trusted_comment_id}")
    if not isinstance(raw, bytes) or not raw:
        raise TrustedOperatorAttestationError("GitHub operator-attestation response bytes are unavailable")
    if not isinstance(comment, dict):
        raise TrustedOperatorAttestationError("GitHub operator-attestation response is not one object")
    if _positive_int(comment.get("id"), "GitHub operator-attestation comment ID") != trusted_comment_id:
        raise TrustedOperatorAttestationError("GitHub operator-attestation comment ID mismatch")

    expected_issue_url = f"https://api.github.com/repos/{REPOSITORY}/issues/{pr_number}"
    if comment.get("issue_url") != expected_issue_url:
        raise TrustedOperatorAttestationError(
            "GitHub operator attestation is not attached to the expected Capture PR"
        )

    user = comment.get("user")
    if not isinstance(user, dict) or user.get("login") != REPOSITORY_OWNER or user.get("type") != "User":
        raise TrustedOperatorAttestationError(
            "GitHub operator attestation was not authored by the repository owner"
        )
    if comment.get("author_association") != "OWNER":
        raise TrustedOperatorAttestationError(
            "GitHub operator attestation lacks repository OWNER association"
        )

    created_at_text = comment.get("created_at")
    updated_at_text = comment.get("updated_at")
    created_at = _utc(created_at_text, "GitHub operator-attestation creation time")
    updated_at = _utc(updated_at_text, "GitHub operator-attestation update time")
    if updated_at != created_at:
        raise TrustedOperatorAttestationError(
            "GitHub operator attestation was edited after creation; create a fresh immutable comment"
        )
    if created_at > now + timedelta(minutes=5):
        raise TrustedOperatorAttestationError(
            "GitHub operator-attestation time is implausibly in the future"
        )
    if created_at < now - timedelta(minutes=30):
        raise TrustedOperatorAttestationError(
            "GitHub operator attestation is stale; create a fresh field-window attestation"
        )
    if created_at < recorded_at:
        raise TrustedOperatorAttestationError(
            "GitHub owner attestation predates the local operator observation record"
        )
    if created_at > recorded_at + timedelta(minutes=10):
        raise TrustedOperatorAttestationError(
            "GitHub owner attestation is too far removed from the local operator observation"
        )

    expected_body = expected_comment_body(parsed_subject, candidate)
    if comment.get("body") != expected_body:
        raise TrustedOperatorAttestationError(
            "GitHub owner comment does not bind the exact operator observation/candidate subject"
        )

    source = _canonical(candidate.get("sourceCommitSHA"), HEX40, "candidate source SHA")
    retained_ipa = _canonical(
        candidate.get("retainedIPASHA256"), HEX64, "candidate retained IPA SHA-256"
    )
    build_instance = _canonical(
        candidate.get("buildInstanceID"), UUID, "candidate build-instance ID"
    )

    return {
        "authority": AUTHORITY,
        "classification": CLASSIFICATION,
        "operatorObservationRecordSHA256": record_sha,
        "attestationID": attestation_id,
        "recordedAtUTC": recorded_at_text,
        "githubOwnerAttestation": {
            "repository": REPOSITORY,
            "prNumber": pr_number,
            "commentID": trusted_comment_id,
            "ownerLogin": REPOSITORY_OWNER,
            "createdAtUTC": created_at_text,
            "apiResponseSHA256": hashlib.sha256(raw).hexdigest(),
            "commentBodySHA256": hashlib.sha256(expected_body.encode("utf-8")).hexdigest(),
        },
        "candidateBinding": {
            "sourceCommitSHA": source,
            "buildInstanceID": build_instance,
            "retainedIPASHA256": retained_ipa,
            "recipe": RECIPE,
            "procedure": PROCEDURE,
        },
        "operatorDeclaredProcedureState": {
            "simulatorArtifactReview": parsed_subject.get("simulatorArtifactReview"),
            "installationRoute": parsed_subject.get("installationRoute"),
            "preInstallRetainedIPASHA256": parsed_subject.get("preInstallRetainedIPASHA256"),
            "postInstallRetainedIPASHA256": parsed_subject.get("postInstallRetainedIPASHA256"),
            "runtimeRendezvous": "OPERATOR_OBSERVED_MATCHED",
            "packageResearchAdmission": "OPERATOR_OBSERVED_AVAILABLE",
            "ordinaryGeneralBuildAuthority": "NO-GO",
            "preflightHealth": "OPERATOR_OBSERVED_READY",
            "chargerState": "OPERATOR_DECLARED_DISCONNECTED",
            "motionState": "OPERATOR_DECLARED_STATIONARY",
        },
        "machineTruthBoundary": (
            "owner authentication proves authorship/custody of the declaration only; signed candidate, "
            "Xcode acceptance, and retained-artifact subjects remain the separate machine-verifiable facts"
        ),
    }
