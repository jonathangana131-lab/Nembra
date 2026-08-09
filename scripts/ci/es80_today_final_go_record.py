#!/usr/bin/env python3
"""Build the external V14 TODAY Final GO record from retained, exact candidate evidence.

This is procedural authority only. It never creates physical evidence, identifies an ES80, or grants
Bluetooth write authority. Missing, stale, substituted, expired, or unconfirmed evidence is NO-GO.

The tool intentionally separates mechanically bound retained subjects from operator declarations.
GitHub/Xcode terminal acceptance is still an externally inspected fact; this offline tool records
the exact run/job/artifact subject but does not pretend to query or re-authorize GitHub itself.
"""
from __future__ import annotations

import argparse
import io
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any
import zipfile

RECIPE = "ES80-FINGERPRINT-v1"
PROCEDURE = "V14"
BASELINE_DEVICE = "iPhone 12"
BASELINE_OS = "iOS 27"
BUNDLE_ID = "com.jonathangana131.nembra"
INSTALL_ROUTE = "exact-retained-ipa-via-xcode-device-management"
EXTERNAL_RECORD_NAME = "NembraCaptureExternalBuildRecord.json"
FIELD_RECORD_NAME = "NembraCaptureFieldBuildEvidenceRecord.json"
INSPECTION_NAME = "NembraCaptureSignedFieldArtifactInspection.json"
IPA_RELATIVE_PATH = Path("build-evidence/NembraField.ipa")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
TEAM = re.compile(r"^[A-Z0-9]{10}$")
CDHASH = re.compile(r"^[0-9a-f]{40,64}$")
EXTERNAL_KEYS = frozenset({
    "schemaVersion", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "executableSHA256", "infoPlistSHA256", "experimentRecipeID", "procedureVersion",
})
FIELD_KEYS = frozenset({
    "schemaVersion", "externalBuildRecordSHA256", "signedInstallableSHA256",
    "signedInstallableKind", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "executableSHA256", "infoPlistSHA256", "experimentRecipeID", "procedureVersion",
})
INSPECTION_KEYS = frozenset({
    "schemaVersion", "authority", "fieldBuildEvidenceRecordSHA256",
    "externalBuildRecordSHA256", "signedInstallableSHA256", "signedInstallableKind",
    "ipaByteCount", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "bundleIdentifier", "platformName", "supportedPlatforms", "teamIdentifier",
    "signingAuthorities", "codeDirectoryHash", "provisioningProfileSHA256",
    "provisioningProfileUUID", "provisioningProfileExpirationUTC",
    "provisioningApplicationIdentifier", "executableSHA256", "infoPlistSHA256",
    "experimentRecipeID", "procedureVersion",
})


class FinalGoError(RuntimeError):
    pass


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _regular(path: Path, label: str) -> bytes:
    if not path.is_file() or path.is_symlink():
        raise FinalGoError(f"{label} must be one regular non-symlink file: {path}")
    return path.read_bytes()


def _decode_json(raw: bytes, label: str) -> dict[str, Any]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise FinalGoError(f"{label} contains duplicate JSON key: {key}")
            value[key] = item
        return value

    try:
        value = json.loads(raw, object_pairs_hook=reject_duplicates)
    except FinalGoError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FinalGoError(f"{label} is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise FinalGoError(f"{label} root must be an object")
    return value


def _json(path: Path, label: str) -> tuple[bytes, dict[str, Any]]:
    raw = _regular(path, label)
    return raw, _decode_json(raw, label)


def _require_keys(record: dict[str, Any], expected: frozenset[str], label: str) -> None:
    if set(record) != expected:
        missing = sorted(expected - set(record))
        extra = sorted(set(record) - expected)
        raise FinalGoError(f"{label} is not the exact closed-world schema; missing={missing}, extra={extra}")


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


def _inspect_xcode_artifact(path: Path, expected_source_sha: str) -> tuple[str, str]:
    raw = _regular(path, "trusted Xcode retained artifact")
    artifact_sha = _sha(raw)
    try:
        with zipfile.ZipFile(io.BytesIO(raw), "r") as archive:
            candidates = [
                info for info in archive.infolist()
                if not info.is_dir()
                and info.filename.rsplit("/", 1)[-1] == EXTERNAL_RECORD_NAME
            ]
            if len(candidates) != 1:
                raise FinalGoError(
                    "trusted Xcode retained artifact must contain exactly one Capture external build record"
                )
            info = candidates[0]
            if info.file_size <= 0 or info.file_size > 1024 * 1024:
                raise FinalGoError("trusted Xcode external build record has invalid byte count")
            record_raw = archive.read(info)
    except (zipfile.BadZipFile, OSError, RuntimeError) as error:
        if isinstance(error, FinalGoError):
            raise
        raise FinalGoError("trusted Xcode retained artifact is not one readable ZIP") from error

    record = _decode_json(record_raw, "trusted Xcode external build record")
    _require_keys(record, EXTERNAL_KEYS, "trusted Xcode external build record")
    _eq(record.get("schemaVersion"), 3, "trusted Xcode external schema version")
    _eq(record.get("sourceCommitSHA"), expected_source_sha, "trusted Xcode accepted source SHA")
    _eq(
        record.get("buildIdentifier"),
        f"Capture Build V14-{expected_source_sha[:12]}",
        "trusted Xcode build identifier",
    )
    _eq(record.get("experimentRecipeID"), RECIPE, "trusted Xcode recipe")
    _eq(record.get("procedureVersion"), PROCEDURE, "trusted Xcode procedure")
    _shape(record.get("buildInstanceID"), UUID, "trusted Xcode build-instance ID")
    _shape(record.get("executableSHA256"), HEX64, "trusted Xcode executable SHA-256")
    _shape(record.get("infoPlistSHA256"), HEX64, "trusted Xcode Info.plist SHA-256")
    return artifact_sha, _sha(record_raw)


def build_final_go_record(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    trusted_xcode_run_id: int,
    trusted_xcode_job_id: int,
    trusted_xcode_artifact: Path,
    pre_install_ipa_sha256: str,
    post_install_ipa_sha256: str,
    installation_route: str,
    expected_development_team: str,
    visible_recipe: str,
    visible_build_identifier: str,
    visible_source_sha: str,
    visible_build_instance_id: str,
    installed_without_rebuild: bool,
    terminal_software_acceptance: bool,
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
    xcode_run_id = _positive_int(trusted_xcode_run_id, "trusted Xcode run ID")
    xcode_job_id = _positive_int(trusted_xcode_job_id, "trusted Xcode job ID")
    xcode_artifact_sha, xcode_build_record_sha = _inspect_xcode_artifact(
        trusted_xcode_artifact,
        source,
    )
    pre_install_ipa = _shape(pre_install_ipa_sha256, HEX64, "pre-install IPA SHA-256")
    post_install_ipa = _shape(post_install_ipa_sha256, HEX64, "post-install IPA SHA-256")
    _eq(installation_route, INSTALL_ROUTE, "retained-IPA installation route")
    _shape(expected_development_team, TEAM, "expected development TeamIdentifier")
    _eq(observed_device, BASELINE_DEVICE, "observed baseline device")
    _eq(observed_os, BASELINE_OS, "observed baseline OS")

    root = candidate_root.resolve(strict=True) / "inspection"
    external_raw, external = _json(root / EXTERNAL_RECORD_NAME, "external build record")
    field_raw, field = _json(root / FIELD_RECORD_NAME, "field-build evidence record")
    inspection_raw, inspection = _json(root / INSPECTION_NAME, "signed artifact inspection")
    ipa_raw = _regular(root / IPA_RELATIVE_PATH, "retained IPA")
    ipa_sha = _sha(ipa_raw)
    external_sha, field_sha, inspection_sha = _sha(external_raw), _sha(field_raw), _sha(inspection_raw)

    _require_keys(external, EXTERNAL_KEYS, "external build record")
    _require_keys(field, FIELD_KEYS, "field-build evidence record")
    _require_keys(inspection, INSPECTION_KEYS, "signed artifact inspection")

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
    _eq(pre_install_ipa, ipa_sha, "pre-install retained IPA digest")
    _eq(post_install_ipa, ipa_sha, "post-install retained IPA digest")
    _eq(field.get("signedInstallableKind"), "ipa", "field installable kind")
    _eq(inspection.get("signedInstallableKind"), "ipa", "inspection installable kind")
    _eq(
        inspection.get("authority"),
        "signed-field-artifact-inspection-not-field-authorization",
        "inspection authority boundary",
    )
    _eq(inspection.get("bundleIdentifier"), BUNDLE_ID, "inspection bundle identifier")
    _eq(inspection.get("platformName"), "iphoneos", "inspection platform")
    _eq(inspection.get("ipaByteCount"), len(ipa_raw), "inspection IPA byte count")
    _shape(inspection.get("codeDirectoryHash"), CDHASH, "inspection code-directory hash")
    platforms = inspection.get("supportedPlatforms")
    if not isinstance(platforms, list) or "iPhoneOS" not in platforms:
        raise FinalGoError("signed inspection does not describe an iPhoneOS installable")
    _eq(inspection.get("teamIdentifier"), expected_development_team, "inspection team identifier")
    _eq(
        inspection.get("provisioningApplicationIdentifier"),
        f"{expected_development_team}.{BUNDLE_ID}",
        "inspection provisioning application identifier",
    )
    provisioning_profile_sha = _shape(
        inspection.get("provisioningProfileSHA256"),
        HEX64,
        "inspection provisioning profile SHA-256",
    )
    profile_uuid = inspection.get("provisioningProfileUUID")
    if not isinstance(profile_uuid, str) or not profile_uuid.strip():
        raise FinalGoError("signed inspection lacks provisioning profile identity")
    expiration = inspection.get("provisioningProfileExpirationUTC")
    if not isinstance(expiration, str) or not expiration.endswith("Z"):
        raise FinalGoError("signed inspection lacks normalized provisioning profile expiration")
    try:
        expiration_utc = datetime.fromisoformat(expiration[:-1] + "+00:00")
    except ValueError as error:
        raise FinalGoError("signed inspection provisioning profile expiration is malformed") from error
    now_utc = datetime.now(timezone.utc)
    if expiration_utc <= now_utc:
        raise FinalGoError("provisioning profile expired before Final GO")
    authorities = inspection.get("signingAuthorities")
    if (
        not isinstance(authorities, list)
        or not authorities
        or not all(isinstance(authority, str) and authority.strip() for authority in authorities)
    ):
        raise FinalGoError("signed inspection lacks signing authority evidence")

    for actual, expected, label in (
        (visible_recipe, RECIPE, "visible pre-scan recipe"),
        (visible_build_identifier, build, "visible pre-scan build identifier"),
        (visible_source_sha, source, "visible pre-scan source SHA"),
        (visible_build_instance_id, instance, "visible pre-scan build-instance ID"),
    ):
        _eq(actual, expected, label)

    # These are deliberately classified as operator declarations. The exact retained byte subjects
    # they refer to are recorded separately below; a Boolean is never presented as proof by itself.
    declarations = {
        "terminalSoftwareAcceptanceForRecordedXcodeSubject": terminal_software_acceptance,
        "retainedAppEvidenceInspectedForRecordedXcodeSubject": retained_app_evidence_inspected,
        "independentIntendedDeviceMembershipAcceptedForRecordedInspection": intended_device_membership_accepted,
        "noApplicationCharacteristicWriteAuthority": no_application_write_authority,
        "installedWithoutRebuildOrSubstitution": installed_without_rebuild,
        "privateResearchAdmissionLive": research_admission_live,
        "canonicalCoordinatorPermittedProcedure": canonical_coordinator_permitted,
        "preflightHealthyBeforeScan": preflight_healthy,
        "chargerFreshlyDeclaredDisconnected": charger_disconnected,
        "stationaryForSetup": stationary,
    }
    missing = [key for key, value in declarations.items() if value is not True]
    if missing:
        raise FinalGoError("required GO declarations are not all true: " + ", ".join(missing))

    generated_at = now_utc.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return {
        "schemaVersion": 2,
        "authority": "today-final-go-procedural-record-not-physical-result",
        "decision": "GO",
        "generatedAtUTC": generated_at,
        "acceptedSourceCommitSHA": source,
        "acceptedBuildIdentifier": build,
        "acceptedBuildInstanceID": instance,
        "trustedXcodeAcceptanceSubject": {
            "runID": xcode_run_id,
            "jobID": xcode_job_id,
            "retainedArtifactSHA256": xcode_artifact_sha,
            "retainedExternalBuildRecordSHA256": xcode_build_record_sha,
            "acceptedSourceCommitSHA": source,
            "classification": "externally-inspected-terminal-software-acceptance-subject",
        },
        "signedFieldInspectionSubject": {
            "inspectionRecordSHA256": inspection_sha,
            "provisioningProfileSHA256": provisioning_profile_sha,
            "provisioningProfileUUID": profile_uuid.strip(),
            "provisioningProfileExpirationUTC": expiration,
            "classification": "independently-inspected-signed-installable-evidence-not-field-authorization",
        },
        "retainedIPAInstallHandoff": {
            "preInstallRetainedIPASHA256": pre_install_ipa,
            "installationRoute": INSTALL_ROUTE,
            "postInstallRetainedIPASHA256": post_install_ipa,
            "installedWithoutRebuildOrSubstitution": True,
        },
        "retainedIPASHA256": ipa_sha,
        "externalBuildRecordSHA256": external_sha,
        "fieldBuildEvidenceRecordSHA256": field_sha,
        "signedArtifactInspectionRecordSHA256": inspection_sha,
        "retainedExecutableSHA256": executable,
        "retainedInfoPlistSHA256": info_plist,
        "procedureVersion": PROCEDURE,
        "experimentRecipeID": RECIPE,
        "baselineDevice": BASELINE_DEVICE,
        "baselineOS": BASELINE_OS,
        "developmentTeam": expected_development_team,
        "verifiedBindings": {
            "retainedCandidateTupleMatched": True,
            "preAndPostInstallDigestsMatchedRetainedIPA": True,
            "visibleRendezvousMatchedRetainedEvidence": True,
            "provisioningProfileUnexpiredAtRecordCreation": True,
        },
        "operatorDeclarations": declarations,
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


def _args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    path_flags = ("candidate-root", "trusted-xcode-artifact")
    string_flags = (
        "expected-source-sha",
        "pre-install-ipa-sha256",
        "post-install-ipa-sha256",
        "installation-route",
        "expected-development-team",
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
    p.add_argument("--trusted-xcode-run-id", required=True, type=int)
    p.add_argument("--trusted-xcode-job-id", required=True, type=int)
    for flag in (
        "installed-without-rebuild",
        "terminal-software-acceptance",
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
    try:
        record = build_final_go_record(**{key: value for key, value in vars(args).items() if key != "output"})
    except (FinalGoError, FileNotFoundError) as error:
        print(f"TODAY Final GO: NO-GO: {error}", file=sys.stderr)
        return 2
    output = args.output.resolve(strict=False)
    if output.exists() or output.is_symlink():
        print(f"TODAY Final GO: NO-GO: output already exists: {output}", file=sys.stderr)
        return 3
    output.parent.mkdir(parents=True, exist_ok=True)
    raw = (json.dumps(record, indent=2, sort_keys=True) + "\n").encode()
    try:
        with output.open("xb") as handle:
            handle.write(raw)
    except OSError as error:
        print(f"TODAY Final GO: NO-GO: could not write record: {error}", file=sys.stderr)
        return 4
    print(f"TODAY Final GO record: {output}")
    print(f"record_sha256={_sha(raw)}")
    print("PHYSICAL RESULT COLLECTED: NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
