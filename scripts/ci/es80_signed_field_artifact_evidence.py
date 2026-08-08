#!/usr/bin/env python3
"""Produce fail-closed evidence for an already-built signed Nembra field IPA.

This tool never authorizes physical Experiment One. It measures and preserves an exact
installable artifact, verifies its iPhone code signature and embedded Nembra build declarations,
and emits external evidence that a separate trusted acceptance step may attest/review.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path, PurePosixPath

RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
BUNDLE_ID = "com.jonathangana131.nembra"
FIELD_RECIPE_INFO_KEY = "NembraCaptureFieldRecipe"
EXTERNAL_RECORD_SCHEMA_VERSION = 3
FIELD_BUILD_EVIDENCE_SCHEMA_VERSION = 1
SIGNING_INSPECTION_SCHEMA_VERSION = 2
SIGNED_INSTALLABLE_KIND = "ipa"
INSPECTION_AUTHORITY_LABEL = "signed-field-artifact-inspection-not-field-authorization"

SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)


class EvidenceError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_sha40(value: str) -> str:
    if not SHA40_RE.fullmatch(value):
        raise EvidenceError("expected source SHA must be one canonical lowercase 40-hex Git commit")
    return value


def canonical_uuid(value: str) -> str:
    if not UUID_RE.fullmatch(value):
        raise EvidenceError("buildInstanceID must be one canonical lowercase UUID-shaped value")
    try:
        parsed = uuid.UUID(value)
    except ValueError as exc:
        raise EvidenceError("buildInstanceID is not a valid UUID") from exc
    if str(parsed) != value:
        raise EvidenceError("buildInstanceID is not canonical lowercase UUID text")
    return value


def valid_build_identifier(value: str) -> bool:
    if not value or len(value.encode("utf-8")) > 128:
        return False
    if value != value.strip():
        return False
    return not any(ord(character) < 32 or ord(character) == 127 for character in value)


def expected_build_identifier(source_sha: str) -> str:
    return f"Capture Build V14-{source_sha[:12]}"


def validate_field_recipe(value: str) -> str:
    if value != RECIPE_ID:
        raise EvidenceError(
            f"signed field app must declare {FIELD_RECIPE_INFO_KEY}={RECIPE_ID}; got {value!r}"
        )
    return value


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n"


def _safe_member_path(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if not name or path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise EvidenceError(f"IPA contains unsafe ZIP member path: {name!r}")
    return path


def _validated_unique_member_paths(infos: list[zipfile.ZipInfo]) -> dict[str, PurePosixPath]:
    """Reject archive ambiguity before any member is read or extracted.

    Exact duplicate member names are ambiguous to zip readers, while case-fold collisions can
    overwrite one another on the default case-insensitive filesystems commonly used by macOS.
    """
    exact: set[str] = set()
    folded: dict[str, str] = {}
    result: dict[str, PurePosixPath] = {}
    for info in infos:
        raw_name = info.filename.rstrip("/")
        member = _safe_member_path(raw_name)
        canonical = str(member)
        if canonical in exact:
            raise EvidenceError(f"IPA contains duplicate ZIP member path: {canonical!r}")
        exact.add(canonical)
        casefolded = canonical.casefold()
        previous = folded.get(casefolded)
        if previous is not None and previous != canonical:
            raise EvidenceError(
                f"IPA contains case-fold-colliding ZIP member paths: {previous!r} and {canonical!r}"
            )
        folded[casefolded] = canonical
        result[info.filename] = member
    return result


def extract_ipa_safely(ipa_path: Path, destination: Path) -> Path:
    try:
        archive = zipfile.ZipFile(ipa_path)
    except (OSError, zipfile.BadZipFile) as exc:
        raise EvidenceError("input is not a readable IPA/ZIP archive") from exc

    app_roots: set[str] = set()
    with archive:
        infos = archive.infolist()
        validated_paths = _validated_unique_member_paths(infos)
        for info in infos:
            member = validated_paths[info.filename]
            mode = (info.external_attr >> 16) & 0o177777
            if stat.S_ISLNK(mode):
                raise EvidenceError(f"IPA contains unsupported symbolic-link member: {info.filename}")

            parts = member.parts
            if len(parts) >= 2 and parts[0] == "Payload" and parts[1].endswith(".app"):
                app_roots.add(parts[1])

            target = destination.joinpath(*parts)
            resolved_parent = target.parent.resolve()
            if destination.resolve() not in (resolved_parent, *resolved_parent.parents):
                raise EvidenceError(f"IPA member escapes extraction root: {info.filename}")

            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue

            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info, "r") as source, target.open("wb") as sink:
                shutil.copyfileobj(source, sink)
            permissions = mode & 0o777
            if permissions:
                target.chmod(permissions)

    if len(app_roots) != 1:
        raise EvidenceError(
            f"IPA must contain exactly one top-level Payload/*.app bundle; found {sorted(app_roots)!r}"
        )
    app_path = destination / "Payload" / next(iter(app_roots))
    if not app_path.is_dir():
        raise EvidenceError("IPA app bundle was not extracted as a directory")
    return app_path


def read_info_plist(app_path: Path) -> tuple[dict, Path]:
    info_path = app_path / "Info.plist"
    try:
        with info_path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as exc:
        raise EvidenceError("signed app does not contain a readable Info.plist") from exc
    if not isinstance(value, dict):
        raise EvidenceError("signed app Info.plist root is not a dictionary")
    return value, info_path


def plist_string(info: dict, key: str) -> str:
    value = info.get(key)
    if not isinstance(value, str) or not value:
        raise EvidenceError(f"signed app Info.plist is missing required string {key}")
    return value


def verify_device_platform(info: dict) -> tuple[str, list[str]]:
    platform = info.get("DTPlatformName")
    supported = info.get("CFBundleSupportedPlatforms")
    supported_values = [item for item in supported if isinstance(item, str)] if isinstance(supported, list) else []

    if platform != "iphoneos":
        raise EvidenceError(f"field IPA must declare DTPlatformName=iphoneos; got {platform!r}")
    if "iPhoneOS" not in supported_values:
        raise EvidenceError(
            f"field IPA must declare iPhoneOS in CFBundleSupportedPlatforms; got {supported_values!r}"
        )
    if any("Simulator" in item for item in supported_values):
        raise EvidenceError("Simulator platform declaration is forbidden in field IPA evidence")
    return platform, supported_values


def run_codesign(app_path: Path) -> tuple[str, list[str]]:
    if sys.platform != "darwin":
        raise EvidenceError("signed field IPA inspection requires macOS code-signing tools")
    codesign = shutil.which("codesign")
    if not codesign:
        raise EvidenceError("codesign is not available")

    verify = subprocess.run(
        [codesign, "--verify", "--deep", "--strict", "--verbose=4", str(app_path)],
        text=True,
        capture_output=True,
        check=False,
    )
    if verify.returncode != 0:
        detail = (verify.stderr or verify.stdout).strip()
        raise EvidenceError(f"codesign verification failed: {detail}")

    display = subprocess.run(
        [codesign, "-d", "--verbose=4", str(app_path)],
        text=True,
        capture_output=True,
        check=False,
    )
    if display.returncode != 0:
        detail = (display.stderr or display.stdout).strip()
        raise EvidenceError(f"codesign metadata inspection failed: {detail}")

    metadata = "\n".join(part for part in (display.stdout, display.stderr) if part)
    if re.search(r"(?m)^Signature=adhoc\s*$", metadata):
        raise EvidenceError("ad-hoc signature cannot become signed field artifact evidence")

    team_match = re.search(r"(?m)^TeamIdentifier=([^\r\n]+)$", metadata)
    if not team_match:
        raise EvidenceError("codesign metadata does not contain TeamIdentifier")
    team_identifier = team_match.group(1).strip()
    if not team_identifier or team_identifier.lower() in {"not set", "none", "-"}:
        raise EvidenceError("field IPA does not carry a concrete signing TeamIdentifier")

    authorities = [match.group(1).strip() for match in re.finditer(r"(?m)^Authority=([^\r\n]+)$", metadata)]
    if not authorities:
        raise EvidenceError("codesign metadata does not contain a signing authority chain")
    return team_identifier, authorities


def validate_provisioning_profile(
    profile: dict,
    expected_team_identifier: str,
    now: datetime,
) -> dict:
    team_identifiers = profile.get("TeamIdentifier")
    if not isinstance(team_identifiers, list) or team_identifiers != [expected_team_identifier]:
        raise EvidenceError(
            "embedded provisioning profile TeamIdentifier must exactly match the app code-signing team"
        )

    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        raise EvidenceError("embedded provisioning profile has no entitlement dictionary")

    entitlement_team_identifier = entitlements.get("com.apple.developer.team-identifier")
    if entitlement_team_identifier != expected_team_identifier:
        raise EvidenceError(
            "embedded provisioning profile entitlement team does not match the app code-signing team"
        )

    application_identifier = entitlements.get("application-identifier")
    if not isinstance(application_identifier, str) or not application_identifier.endswith(f".{BUNDLE_ID}"):
        raise EvidenceError(
            "embedded provisioning profile application-identifier does not bind the Nembra bundle identifier"
        )

    provisioned_devices = profile.get("ProvisionedDevices")
    if not isinstance(provisioned_devices, list) or not provisioned_devices:
        raise EvidenceError(
            "field IPA must use a provisioning profile containing at least one registered device"
        )
    if any(not isinstance(device, str) or not device for device in provisioned_devices):
        raise EvidenceError("embedded provisioning profile contains a malformed registered-device entry")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise EvidenceError("embedded provisioning profile has no valid ExpirationDate")
    expiration_utc = expiration if expiration.tzinfo else expiration.replace(tzinfo=timezone.utc)
    now_utc = now if now.tzinfo else now.replace(tzinfo=timezone.utc)
    if expiration_utc <= now_utc:
        raise EvidenceError("embedded provisioning profile is expired")

    return {
        "provisioningApplicationIdentifier": application_identifier,
        "provisioningTeamIdentifier": expected_team_identifier,
        "provisionedDeviceCount": len(provisioned_devices),
        "provisioningExpirationUTC": expiration_utc.astimezone(timezone.utc)
        .isoformat()
        .replace("+00:00", "Z"),
    }


def inspect_provisioning_profile(app_path: Path, expected_team_identifier: str) -> dict:
    if sys.platform != "darwin":
        raise EvidenceError("signed field IPA inspection requires macOS provisioning tools")
    security = shutil.which("security")
    if not security:
        raise EvidenceError("security is not available")

    profile_path = app_path / "embedded.mobileprovision"
    if not profile_path.is_file():
        raise EvidenceError("field IPA does not contain embedded.mobileprovision")

    decoded = subprocess.run(
        [security, "cms", "-D", "-i", str(profile_path)],
        capture_output=True,
        check=False,
    )
    if decoded.returncode != 0:
        detail = decoded.stderr.decode("utf-8", errors="replace").strip()
        raise EvidenceError(f"embedded provisioning profile could not be decoded: {detail}")
    try:
        profile = plistlib.loads(decoded.stdout)
    except plistlib.InvalidFileException as exc:
        raise EvidenceError("decoded provisioning profile is not a valid plist") from exc
    if not isinstance(profile, dict):
        raise EvidenceError("decoded provisioning profile root is not a dictionary")

    evidence = validate_provisioning_profile(
        profile,
        expected_team_identifier,
        datetime.now(timezone.utc),
    )
    evidence["embeddedMobileProvisionSHA256"] = sha256_file(profile_path)
    return evidence


def reject_embedded_external_authority(app_path: Path) -> None:
    forbidden = {
        "NembraCaptureTrustedBuildRecord.json",
        "NembraCaptureExternalBuildRecord.json",
        "NembraCaptureFieldBuildEvidenceRecord.json",
        "NembraCaptureSignedFieldArtifactEvidence.json",
        "NembraCaptureSignedFieldArtifactInspection.json",
    }
    hits = sorted(path.name for path in app_path.rglob("*") if path.is_file() and path.name in forbidden)
    if hits:
        raise EvidenceError(
            "final executable-digest/field-acceptance evidence must stay outside the signed app bundle; "
            f"found {hits!r}"
        )


def inspect_ipa(ipa_path: Path, expected_source_sha: str) -> dict:
    source_sha = canonical_sha40(expected_source_sha)
    if not ipa_path.is_file():
        raise EvidenceError(f"IPA does not exist as a file: {ipa_path}")

    ipa_sha = sha256_file(ipa_path)
    ipa_size = ipa_path.stat().st_size
    if not SHA256_RE.fullmatch(ipa_sha):
        raise EvidenceError("could not derive canonical IPA SHA-256")

    with tempfile.TemporaryDirectory(prefix="nembra-field-ipa-") as temporary:
        root = Path(temporary)
        app_path = extract_ipa_safely(ipa_path, root)
        reject_embedded_external_authority(app_path)
        info, info_path = read_info_plist(app_path)

        bundle_id = plist_string(info, "CFBundleIdentifier")
        if bundle_id != BUNDLE_ID:
            raise EvidenceError(f"unexpected field app bundle identifier: {bundle_id!r}")

        platform_name, supported_platforms = verify_device_platform(info)

        build_identifier = plist_string(info, "NembraCaptureBuildIdentifier")
        if not valid_build_identifier(build_identifier):
            raise EvidenceError("embedded NembraCaptureBuildIdentifier is malformed")
        expected_identifier = expected_build_identifier(source_sha)
        if build_identifier != expected_identifier:
            raise EvidenceError(
                f"embedded build identifier does not match accepted source: {build_identifier!r} != {expected_identifier!r}"
            )

        build_instance_id = canonical_uuid(plist_string(info, "NembraCaptureBuildInstanceID"))
        embedded_source_sha = canonical_sha40(plist_string(info, "NembraCaptureBuildCommitSHA"))
        if embedded_source_sha != source_sha:
            raise EvidenceError(
                f"embedded source commit does not match accepted source: {embedded_source_sha} != {source_sha}"
            )
        field_recipe = validate_field_recipe(plist_string(info, FIELD_RECIPE_INFO_KEY))

        executable_name = plist_string(info, "CFBundleExecutable")
        if "/" in executable_name or executable_name in {".", ".."}:
            raise EvidenceError("CFBundleExecutable is not a safe bundle-local filename")
        executable_path = app_path / executable_name
        if not executable_path.is_file():
            raise EvidenceError("signed app executable is missing")

        team_identifier, signing_authorities = run_codesign(app_path)
        provisioning_evidence = inspect_provisioning_profile(app_path, team_identifier)
        executable_sha = sha256_file(executable_path)
        info_plist_sha = sha256_file(info_path)
        if not SHA256_RE.fullmatch(executable_sha) or not SHA256_RE.fullmatch(info_plist_sha):
            raise EvidenceError("could not derive canonical executable/Info.plist SHA-256")

    external_record = {
        "schemaVersion": EXTERNAL_RECORD_SCHEMA_VERSION,
        "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance_id,
        "sourceCommitSHA": source_sha,
        "executableSHA256": executable_sha,
        "infoPlistSHA256": info_plist_sha,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    external_bytes = canonical_json_bytes(external_record)
    external_sha = hashlib.sha256(external_bytes).hexdigest()

    # This record intentionally matches PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON's
    # closed-world schema exactly. Signing/platform diagnostics live in the separate inspection
    # companion below so the package rendezvous has one unambiguous machine-readable contract.
    field_build_record = {
        "schemaVersion": FIELD_BUILD_EVIDENCE_SCHEMA_VERSION,
        "externalBuildRecordSHA256": external_sha,
        "signedInstallableSHA256": ipa_sha,
        "signedInstallableKind": SIGNED_INSTALLABLE_KIND,
        "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance_id,
        "sourceCommitSHA": source_sha,
        "executableSHA256": executable_sha,
        "infoPlistSHA256": info_plist_sha,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    field_build_bytes = canonical_json_bytes(field_build_record)

    signing_inspection = {
        "schemaVersion": SIGNING_INSPECTION_SCHEMA_VERSION,
        "authority": INSPECTION_AUTHORITY_LABEL,
        "fieldBuildEvidenceRecordSHA256": hashlib.sha256(field_build_bytes).hexdigest(),
        "externalBuildRecordSHA256": external_sha,
        "signedInstallableSHA256": ipa_sha,
        "signedInstallableKind": SIGNED_INSTALLABLE_KIND,
        "ipaByteCount": ipa_size,
        "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance_id,
        "sourceCommitSHA": source_sha,
        "bundleIdentifier": bundle_id,
        "platformName": platform_name,
        "supportedPlatforms": supported_platforms,
        "teamIdentifier": team_identifier,
        "signingAuthorities": signing_authorities,
        "fieldLaunchRecipeID": field_recipe,
        "executableSHA256": executable_sha,
        "infoPlistSHA256": info_plist_sha,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
        **provisioning_evidence,
    }
    return {
        "external_record": external_record,
        "external_bytes": external_bytes,
        "field_build_record": field_build_record,
        "field_build_bytes": field_build_bytes,
        "signing_inspection": signing_inspection,
    }


def write_outputs(ipa_path: Path, output_dir: Path, inspection: dict) -> dict[str, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    retained_dir = output_dir / "build-evidence"
    retained_dir.mkdir(parents=True, exist_ok=True)

    retained_ipa = retained_dir / "NembraField.ipa"
    external_path = output_dir / "NembraCaptureExternalBuildRecord.json"
    field_build_path = output_dir / "NembraCaptureFieldBuildEvidenceRecord.json"
    signing_inspection_path = output_dir / "NembraCaptureSignedFieldArtifactInspection.json"
    targets = (retained_ipa, external_path, field_build_path, signing_inspection_path)
    existing = [str(path) for path in targets if path.exists()]
    if existing:
        raise EvidenceError(f"refusing to overwrite existing field evidence: {existing!r}")

    shutil.copy2(ipa_path, retained_ipa)
    if sha256_file(retained_ipa) != inspection["field_build_record"]["signedInstallableSHA256"]:
        retained_ipa.unlink(missing_ok=True)
        raise EvidenceError("retained IPA bytes diverged from inspected input")

    external_path.write_bytes(inspection["external_bytes"])
    actual_external_sha = sha256_file(external_path)
    if actual_external_sha != inspection["field_build_record"]["externalBuildRecordSHA256"]:
        raise EvidenceError("written external build record digest diverged from field-build evidence")

    field_build_path.write_bytes(inspection["field_build_bytes"])
    actual_field_build_sha = sha256_file(field_build_path)
    if actual_field_build_sha != inspection["signing_inspection"]["fieldBuildEvidenceRecordSHA256"]:
        raise EvidenceError("written field-build evidence digest diverged from signing inspection")

    signing_inspection_path.write_bytes(canonical_json_bytes(inspection["signing_inspection"]))
    return {
        "retained_ipa": retained_ipa,
        "external_record": external_path,
        "field_build_record": field_build_path,
        "signing_inspection": signing_inspection_path,
    }


def self_test() -> None:
    sha = "a" * 40
    assert canonical_sha40(sha) == sha
    assert expected_build_identifier(sha) == "Capture Build V14-aaaaaaaaaaaa"
    good_uuid = "12345678-1234-4abc-8def-1234567890ab"
    assert canonical_uuid(good_uuid) == good_uuid
    assert valid_build_identifier("Capture Build V14-aaaaaaaaaaaa")
    assert not valid_build_identifier(" Capture Build V14-aaaaaaaaaaaa")
    assert not valid_build_identifier("Capture\nBuild")
    assert validate_field_recipe(RECIPE_ID) == RECIPE_ID
    try:
        validate_field_recipe("ES80-FINGERPRINT-v999")
    except EvidenceError:
        pass
    else:
        raise AssertionError("unknown field launch recipe must fail")
    try:
        canonical_sha40("A" * 40)
    except EvidenceError:
        pass
    else:
        raise AssertionError("uppercase SHA must fail canonicalization")
    for bad in ("../Payload/Nembra.app", "/Payload/Nembra.app", "Payload/../Nembra.app"):
        try:
            _safe_member_path(bad)
        except EvidenceError:
            pass
        else:
            raise AssertionError(f"unsafe ZIP member was accepted: {bad}")

    duplicate = [zipfile.ZipInfo("Payload/Nembra.app/Nembra"), zipfile.ZipInfo("Payload/Nembra.app/Nembra")]
    try:
        _validated_unique_member_paths(duplicate)
    except EvidenceError:
        pass
    else:
        raise AssertionError("duplicate ZIP member path must fail closed")

    case_collision = [
        zipfile.ZipInfo("Payload/Nembra.app/Info.plist"),
        zipfile.ZipInfo("payload/nembra.app/info.plist"),
    ]
    try:
        _validated_unique_member_paths(case_collision)
    except EvidenceError:
        pass
    else:
        raise AssertionError("case-fold-colliding ZIP member paths must fail closed")

    exact_field_keys = {
        "schemaVersion",
        "externalBuildRecordSHA256",
        "signedInstallableSHA256",
        "signedInstallableKind",
        "buildIdentifier",
        "buildInstanceID",
        "sourceCommitSHA",
        "executableSHA256",
        "infoPlistSHA256",
        "experimentRecipeID",
        "procedureVersion",
    }
    fixture_external = {
        "schemaVersion": EXTERNAL_RECORD_SCHEMA_VERSION,
        "buildIdentifier": expected_build_identifier(sha),
        "buildInstanceID": good_uuid,
        "sourceCommitSHA": sha,
        "executableSHA256": "b" * 64,
        "infoPlistSHA256": "c" * 64,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    fixture_external_sha = hashlib.sha256(canonical_json_bytes(fixture_external)).hexdigest()
    fixture_field = {
        "schemaVersion": FIELD_BUILD_EVIDENCE_SCHEMA_VERSION,
        "externalBuildRecordSHA256": fixture_external_sha,
        "signedInstallableSHA256": "d" * 64,
        "signedInstallableKind": SIGNED_INSTALLABLE_KIND,
        "buildIdentifier": expected_build_identifier(sha),
        "buildInstanceID": good_uuid,
        "sourceCommitSHA": sha,
        "executableSHA256": "b" * 64,
        "infoPlistSHA256": "c" * 64,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    assert set(fixture_field) == exact_field_keys
    assert "physicalGO" not in fixture_field
    assert "authorized" not in fixture_field

    sample_profile = {
        "TeamIdentifier": ["TEAM123"],
        "ExpirationDate": datetime(2099, 1, 1, tzinfo=timezone.utc),
        "ProvisionedDevices": ["redacted-test-device"],
        "Entitlements": {
            "application-identifier": f"TEAM123.{BUNDLE_ID}",
            "com.apple.developer.team-identifier": "TEAM123",
        },
    }
    sample_evidence = validate_provisioning_profile(
        sample_profile,
        "TEAM123",
        datetime(2026, 1, 1, tzinfo=timezone.utc),
    )
    assert sample_evidence["provisionedDeviceCount"] == 1
    assert sample_evidence["provisioningApplicationIdentifier"] == f"TEAM123.{BUNDLE_ID}"
    try:
        validate_provisioning_profile(
            {**sample_profile, "ProvisionedDevices": []},
            "TEAM123",
            datetime(2026, 1, 1, tzinfo=timezone.utc),
        )
    except EvidenceError:
        pass
    else:
        raise AssertionError("profile with no registered devices must fail")
    try:
        validate_provisioning_profile(
            {**sample_profile, "ExpirationDate": datetime(2025, 1, 1, tzinfo=timezone.utc)},
            "TEAM123",
            datetime(2026, 1, 1, tzinfo=timezone.utc),
        )
    except EvidenceError:
        pass
    else:
        raise AssertionError("expired profile must fail")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, help="exact already-produced signed Nembra .ipa")
    parser.add_argument("--output-dir", type=Path, help="directory for immutable external evidence")
    parser.add_argument(
        "--expected-source-sha",
        help="exact accepted lowercase 40-hex source commit expected inside the field build",
    )
    parser.add_argument("--self-test", action="store_true", help="run platform-independent contract checks")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        self_test()
        print("signed-field artifact evidence self-test: PASS")
        return 0

    missing = [
        name
        for name, value in (
            ("--ipa", args.ipa),
            ("--output-dir", args.output_dir),
            ("--expected-source-sha", args.expected_source_sha),
        )
        if value is None
    ]
    if missing:
        raise EvidenceError(f"required arguments missing: {', '.join(missing)}")

    inspection = inspect_ipa(args.ipa.resolve(), args.expected_source_sha)
    paths = write_outputs(args.ipa.resolve(), args.output_dir.resolve(), inspection)
    summary = {
        "status": "EVIDENCE_ONLY_NOT_FIELD_AUTHORIZATION",
        "sourceCommitSHA": inspection["field_build_record"]["sourceCommitSHA"],
        "buildInstanceID": inspection["field_build_record"]["buildInstanceID"],
        "signedInstallableSHA256": inspection["field_build_record"]["signedInstallableSHA256"],
        "externalBuildRecord": str(paths["external_record"]),
        "fieldBuildEvidenceRecord": str(paths["field_build_record"]),
        "signedFieldArtifactInspection": str(paths["signing_inspection"]),
        "retainedIPA": str(paths["retained_ipa"]),
    }
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except EvidenceError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
