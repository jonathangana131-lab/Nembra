#!/usr/bin/env python3
"""Build the external V14 TODAY Final GO record from retained, exact candidate evidence.

This is procedural authority only. It never creates physical evidence, identifies an ES80, or grants
Bluetooth write authority. Missing, stale, substituted, expired, or unconfirmed evidence is NO-GO.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any

RECIPE = "ES80-FINGERPRINT-v1"
PROCEDURE = "V14"
BASELINE_DEVICE = "iPhone 12"
BASELINE_OS = "iOS 27"
BUNDLE_ID = "com.jonathangana131.nembra"
EXTERNAL_RECORD_NAME = "NembraCaptureExternalBuildRecord.json"
FIELD_RECORD_NAME = "NembraCaptureFieldBuildEvidenceRecord.json"
INSPECTION_NAME = "NembraCaptureSignedFieldArtifactInspection.json"
IPA_RELATIVE_PATH = Path("build-evidence/NembraField.ipa")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
TEAM = re.compile(r"^[A-Z0-9]{10}$")


class FinalGoError(RuntimeError):
    pass


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _regular(path: Path, label: str) -> bytes:
    if not path.is_file() or path.is_symlink():
        raise FinalGoError(f"{label} must be one regular non-symlink file: {path}")
    return path.read_bytes()


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


def build_final_go_record(
    *, candidate_root: Path, expected_source_sha: str, installed_ipa_sha256: str,
    expected_development_team: str, visible_recipe: str, visible_build_identifier: str,
    visible_source_sha: str, visible_build_instance_id: str, installed_without_rebuild: bool,
    terminal_software_acceptance: bool, retained_app_evidence_inspected: bool,
    intended_device_membership_accepted: bool, no_application_write_authority: bool,
    observed_device: str, observed_os: str, research_admission_live: bool,
    canonical_coordinator_permitted: bool, preflight_healthy: bool,
    charger_disconnected: bool, stationary: bool,
) -> dict[str, Any]:
    source = _shape(expected_source_sha, HEX40, "expected source SHA")
    installed_ipa = _shape(installed_ipa_sha256, HEX64, "installed IPA SHA-256")
    _shape(expected_development_team, TEAM, "expected development TeamIdentifier")
    _eq(observed_device, BASELINE_DEVICE, "observed baseline device")
    _eq(observed_os, BASELINE_OS, "observed baseline OS")

    root = candidate_root.resolve(strict=True) / "inspection"
    external_raw, external = _json(root / EXTERNAL_RECORD_NAME, "external build record")
    field_raw, field = _json(root / FIELD_RECORD_NAME, "field-build evidence record")
    _, inspection = _json(root / INSPECTION_NAME, "signed artifact inspection")
    ipa_sha = _sha(_regular(root / IPA_RELATIVE_PATH, "retained IPA"))
    external_sha, field_sha = _sha(external_raw), _sha(field_raw)

    for record, version, label in ((external, 3, "external"), (field, 1, "field"), (inspection, 2, "inspection")):
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
        "buildIdentifier": build, "buildInstanceID": instance, "sourceCommitSHA": source,
        "executableSHA256": executable, "infoPlistSHA256": info_plist,
        "experimentRecipeID": RECIPE, "procedureVersion": PROCEDURE,
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
    _eq(installed_ipa, ipa_sha, "installed IPA digest")
    _eq(field.get("signedInstallableKind"), "ipa", "field installable kind")
    _eq(inspection.get("signedInstallableKind"), "ipa", "inspection installable kind")
    _eq(inspection.get("authority"), "signed-field-artifact-inspection-not-field-authorization", "inspection authority boundary")
    _eq(inspection.get("bundleIdentifier"), BUNDLE_ID, "inspection bundle identifier")
    _eq(inspection.get("platformName"), "iphoneos", "inspection platform")
    platforms = inspection.get("supportedPlatforms")
    if not isinstance(platforms, list) or "iPhoneOS" not in platforms:
        raise FinalGoError("signed inspection does not describe an iPhoneOS installable")
    _eq(inspection.get("teamIdentifier"), expected_development_team, "inspection team identifier")
    _eq(inspection.get("provisioningApplicationIdentifier"), f"{expected_development_team}.{BUNDLE_ID}", "inspection provisioning application identifier")
    _shape(inspection.get("provisioningProfileSHA256"), HEX64, "inspection provisioning profile SHA-256")
    if not isinstance(inspection.get("provisioningProfileUUID"), str) or not inspection["provisioningProfileUUID"].strip():
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

    confirmations = {
        "terminalSoftwareAcceptanceForExactSource": terminal_software_acceptance,
        "retainedAppEvidenceInspected": retained_app_evidence_inspected,
        "independentIntendedDeviceMembershipAccepted": intended_device_membership_accepted,
        "noApplicationCharacteristicWriteAuthority": no_application_write_authority,
        "installedWithoutRebuildOrSubstitution": installed_without_rebuild,
        "observedBaselineDeviceAndOSMatched": True,
        "visibleRendezvousMatchedRetainedEvidence": True,
        "privateResearchAdmissionLive": research_admission_live,
        "canonicalCoordinatorPermittedProcedure": canonical_coordinator_permitted,
        "preflightHealthyBeforeScan": preflight_healthy,
        "chargerFreshlyDeclaredDisconnected": charger_disconnected,
        "stationaryForSetup": stationary,
    }
    missing = [key for key, value in confirmations.items() if value is not True]
    if missing:
        raise FinalGoError("required GO confirmations are not all true: " + ", ".join(missing))

    return {
        "schemaVersion": 1, "authority": "today-final-go-procedural-record-not-physical-result",
        "decision": "GO", "acceptedSourceCommitSHA": source, "acceptedBuildIdentifier": build,
        "acceptedBuildInstanceID": instance, "retainedIPASHA256": ipa_sha,
        "externalBuildRecordSHA256": external_sha, "fieldBuildEvidenceRecordSHA256": field_sha,
        "retainedExecutableSHA256": executable, "retainedInfoPlistSHA256": info_plist,
        "procedureVersion": PROCEDURE, "experimentRecipeID": RECIPE,
        "baselineDevice": BASELINE_DEVICE, "baselineOS": BASELINE_OS,
        "developmentTeam": expected_development_team, "confirmations": confirmations,
        "expectedOutput": "exact raw Nembra Capture Share artifact for Experiment One",
        "stopConditions": [
            "foreground loss or app lifecycle invalidation", "build/provenance/rendezvous mismatch",
            "charger not disconnected or setup not stationary", "correlation ambiguity or target identity loss",
            "continuity, chronology, Horizon, seal, or integrity failure",
            "export/share failure or artifact substitution",
            "any application characteristic write or scooter command authority",
        ],
        "physicalResultCollected": False,
    }


def _args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    for flag in ("candidate-root", "expected-source-sha", "installed-ipa-sha256", "expected-development-team",
                 "visible-recipe", "visible-build-identifier", "visible-source-sha", "visible-build-instance-id",
                 "observed-device", "observed-os"):
        p.add_argument(f"--{flag}", required=True, type=Path if flag == "candidate-root" else str)
    for flag in ("installed-without-rebuild", "terminal-software-acceptance", "retained-app-evidence-inspected",
                 "intended-device-membership-accepted", "no-application-write-authority", "research-admission-live",
                 "canonical-coordinator-permitted", "preflight-healthy", "charger-disconnected", "stationary"):
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
