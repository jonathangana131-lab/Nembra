#!/usr/bin/env python3
"""Fail-closed verifier for a signed ES80 Capture field-build artifact.

This tool verifies provenance/correlation facts for a candidate iPhone .ipa. It deliberately does
not mint physical GO authority. Final acceptance still requires independent attestation/review and
the definitive V14 runbook GO record.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

EXPECTED_BUNDLE_ID = "com.jonathangana131.nembra"
EXPECTED_RECIPE_ID = "ES80-FINGERPRINT-v1"
EXPECTED_PROCEDURE_VERSION = "V14"
EXTERNAL_RECORD_SCHEMA_VERSION = 3
EVIDENCE_SCHEMA_VERSION = 1
BUILD_IDENTIFIER_KEY = "NembraCaptureBuildIdentifier"
BUILD_INSTANCE_ID_KEY = "NembraCaptureBuildInstanceID"
SOURCE_COMMIT_SHA_KEY = "NembraCaptureBuildCommitSHA"
FORBIDDEN_EMBEDDED_RECORDS = {
    "NembraCaptureExternalBuildRecord.json",
    "NembraCaptureTrustedBuildRecord.json",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
DEVICE_UDID_RE = re.compile(r"^[A-Za-z0-9-]{8,128}$")


class VerificationError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_external_record(path: Path) -> tuple[dict[str, Any], bytes]:
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise VerificationError(f"cannot read external build record: {error}") from error
    try:
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise VerificationError("external build record is not valid JSON") from error
    if not isinstance(value, dict):
        raise VerificationError("external build record root must be an object")

    expected_keys = {
        "schemaVersion",
        "buildIdentifier",
        "buildInstanceID",
        "sourceCommitSHA",
        "executableSHA256",
        "infoPlistSHA256",
        "experimentRecipeID",
        "procedureVersion",
    }
    actual_keys = set(value)
    if actual_keys != expected_keys:
        extra = sorted(actual_keys - expected_keys)
        missing = sorted(expected_keys - actual_keys)
        raise VerificationError(
            f"external build record must use the exact schema-v3 key set; extra={extra}, missing={missing}"
        )
    if value["schemaVersion"] != EXTERNAL_RECORD_SCHEMA_VERSION:
        raise VerificationError("external build record schemaVersion must be 3")

    build_identifier = value["buildIdentifier"]
    if not isinstance(build_identifier, str) or not build_identifier or len(build_identifier.encode()) > 128:
        raise VerificationError("buildIdentifier is invalid")
    if build_identifier != build_identifier.strip() or any(ord(ch) < 32 or ord(ch) == 127 for ch in build_identifier):
        raise VerificationError("buildIdentifier is not canonical")

    build_instance_id = value["buildInstanceID"]
    if not isinstance(build_instance_id, str) or UUID_RE.fullmatch(build_instance_id) is None:
        raise VerificationError("buildInstanceID must be one canonical lowercase UUID")

    source_commit_sha = value["sourceCommitSHA"]
    if not isinstance(source_commit_sha, str) or COMMIT_SHA_RE.fullmatch(source_commit_sha) is None:
        raise VerificationError("sourceCommitSHA must be one canonical lowercase 40-hex commit")

    for key in ("executableSHA256", "infoPlistSHA256"):
        digest = value[key]
        if not isinstance(digest, str) or SHA256_RE.fullmatch(digest) is None:
            raise VerificationError(f"{key} must be one canonical lowercase SHA-256 digest")

    if value["experimentRecipeID"] != EXPECTED_RECIPE_ID:
        raise VerificationError(f"experimentRecipeID must be {EXPECTED_RECIPE_ID}")
    if value["procedureVersion"] != EXPECTED_PROCEDURE_VERSION:
        raise VerificationError(f"procedureVersion must be {EXPECTED_PROCEDURE_VERSION}")

    return value, raw


def safe_archive_members(archive: zipfile.ZipFile) -> list[zipfile.ZipInfo]:
    members = archive.infolist()
    if not members:
        raise VerificationError("field artifact archive is empty")

    exact_names: set[str] = set()
    folded_names: set[str] = set()
    for member in members:
        name = member.filename
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts:
            raise VerificationError(f"unsafe path in field artifact archive: {name}")
        if name in exact_names:
            raise VerificationError(f"duplicate path in field artifact archive: {name}")
        exact_names.add(name)
        folded = name.casefold()
        if folded in folded_names:
            raise VerificationError(f"case-colliding path in field artifact archive: {name}")
        folded_names.add(folded)
    return members


def discover_single_app_root(members: list[zipfile.ZipInfo]) -> str:
    app_roots: set[str] = set()
    for member in members:
        parts = PurePosixPath(member.filename).parts
        if len(parts) >= 2 and parts[0] == "Payload" and parts[1].endswith(".app"):
            app_roots.add(f"Payload/{parts[1]}")
    if len(app_roots) != 1:
        raise VerificationError(
            f"field artifact must contain exactly one Payload/*.app; found {sorted(app_roots)}"
        )
    return next(iter(app_roots))


def extract_archive(ipa_path: Path, destination: Path) -> Path:
    if ipa_path.suffix.lower() != ".ipa":
        raise VerificationError("field artifact must be an .ipa")
    if not ipa_path.is_file():
        raise VerificationError(f"field artifact does not exist: {ipa_path}")
    try:
        with zipfile.ZipFile(ipa_path, "r") as archive:
            members = safe_archive_members(archive)
            app_root = discover_single_app_root(members)
            archive.extractall(destination)
    except (RuntimeError, zipfile.BadZipFile) as error:
        raise VerificationError("field artifact is not a readable IPA/ZIP archive") from error
    return destination / app_root


def read_plist(path: Path) -> tuple[dict[str, Any], bytes]:
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise VerificationError(f"cannot read built Info.plist: {error}") from error
    try:
        value = plistlib.loads(raw)
    except Exception as error:
        raise VerificationError("built Info.plist is malformed") from error
    if not isinstance(value, dict):
        raise VerificationError("built Info.plist root must be a dictionary")
    return value, raw


def verify_static_artifact(
    *,
    ipa_path: Path,
    external_record_path: Path,
    expected_source_commit: str,
    extraction_root: Path,
) -> tuple[dict[str, Any], Path]:
    if COMMIT_SHA_RE.fullmatch(expected_source_commit) is None:
        raise VerificationError("--expected-source-commit must be one canonical lowercase 40-hex commit")

    record, record_raw = load_external_record(external_record_path)
    if record["sourceCommitSHA"] != expected_source_commit:
        raise VerificationError(
            "external build record sourceCommitSHA does not match the explicitly expected exact head"
        )

    app_path = extract_archive(ipa_path, extraction_root)
    if not app_path.is_dir():
        raise VerificationError("Payload app directory is missing after extraction")

    info_plist_path = app_path / "Info.plist"
    info, info_raw = read_plist(info_plist_path)

    if info.get("CFBundleIdentifier") != EXPECTED_BUNDLE_ID:
        raise VerificationError(f"CFBundleIdentifier must be {EXPECTED_BUNDLE_ID}")
    platform_name = info.get("DTPlatformName")
    supported_platforms = info.get("CFBundleSupportedPlatforms")
    is_iphoneos = platform_name == "iphoneos" or (
        isinstance(supported_platforms, list) and "iPhoneOS" in supported_platforms
    )
    if not is_iphoneos:
        raise VerificationError("field artifact is not identified as an iPhoneOS device build")

    embedded = {
        "buildIdentifier": info.get(BUILD_IDENTIFIER_KEY),
        "buildInstanceID": info.get(BUILD_INSTANCE_ID_KEY),
        "sourceCommitSHA": info.get(SOURCE_COMMIT_SHA_KEY),
    }
    for record_key, embedded_value in embedded.items():
        if embedded_value != record[record_key]:
            raise VerificationError(
                f"embedded {record_key} does not match the external build record"
            )

    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name or "/" in executable_name:
        raise VerificationError("CFBundleExecutable is missing or invalid")
    executable_path = app_path / executable_name
    if not executable_path.is_file():
        raise VerificationError("the app executable named by CFBundleExecutable is missing")

    executable_sha256 = sha256_file(executable_path)
    if executable_sha256 != record["executableSHA256"]:
        raise VerificationError("signed field executable bytes do not match executableSHA256")
    info_plist_sha256 = sha256_bytes(info_raw)
    if info_plist_sha256 != record["infoPlistSHA256"]:
        raise VerificationError("signed field Info.plist bytes do not match infoPlistSHA256")

    if not (app_path / "embedded.mobileprovision").is_file():
        raise VerificationError("signed iPhone field app is missing embedded.mobileprovision")
    if not (app_path / "_CodeSignature" / "CodeResources").is_file():
        raise VerificationError("signed iPhone field app is missing its code-signing resource seal")
    for forbidden in FORBIDDEN_EMBEDDED_RECORDS:
        if (app_path / forbidden).exists():
            raise VerificationError(
                f"self-referential/external authority record must not be embedded in Nembra.app: {forbidden}"
            )

    evidence = {
        "schemaVersion": EVIDENCE_SCHEMA_VERSION,
        "externalBuildRecordSHA256": sha256_bytes(record_raw),
        "signedInstallableSHA256": sha256_file(ipa_path),
        "signedInstallableKind": "ipa",
        "buildIdentifier": record["buildIdentifier"],
        "buildInstanceID": record["buildInstanceID"],
        "sourceCommitSHA": record["sourceCommitSHA"],
        "executableSHA256": executable_sha256,
        "infoPlistSHA256": info_plist_sha256,
        "experimentRecipeID": record["experimentRecipeID"],
        "procedureVersion": record["procedureVersion"],
    }
    return evidence, app_path


def verify_code_signature(app_path: Path) -> dict[str, str]:
    codesign = shutil.which("codesign")
    if not codesign:
        raise VerificationError("codesign is unavailable; signed-device verification requires macOS/Xcode")

    verify = subprocess.run(
        [codesign, "--verify", "--strict", "--all-architectures", "--verbose=4", str(app_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if verify.returncode != 0:
        detail = (verify.stderr or verify.stdout).strip()
        raise VerificationError(f"codesign verification failed: {detail}")

    display = subprocess.run(
        [codesign, "--display", "--verbose=4", str(app_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if display.returncode != 0:
        detail = (display.stderr or display.stdout).strip()
        raise VerificationError(f"cannot inspect code signature: {detail}")

    metadata: dict[str, str] = {}
    combined = "\n".join(part for part in (display.stdout, display.stderr) if part)
    for line in combined.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in {"Identifier", "TeamIdentifier", "Authority"} and value:
            if key == "Authority" and "authority" in metadata:
                continue
            metadata[key[0].lower() + key[1:]] = value
    if metadata.get("identifier") != EXPECTED_BUNDLE_ID:
        raise VerificationError("code signature identifier does not match Nembra's bundle identifier")
    if not metadata.get("teamIdentifier"):
        raise VerificationError("code signature does not expose a TeamIdentifier")
    return metadata


def verify_provisioning_profile(
    *,
    app_path: Path,
    expected_device_udid: str,
    code_signature: dict[str, str],
) -> dict[str, Any]:
    if DEVICE_UDID_RE.fullmatch(expected_device_udid) is None:
        raise VerificationError("--expected-device-udid is malformed")

    security = shutil.which("security")
    if not security:
        raise VerificationError("security is unavailable; provisioning verification requires macOS/Xcode")

    profile_path = app_path / "embedded.mobileprovision"
    decode = subprocess.run(
        [security, "cms", "-D", "-i", str(profile_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if decode.returncode != 0:
        detail = decode.stderr.decode("utf-8", errors="replace").strip()
        raise VerificationError(f"embedded provisioning profile cannot be decoded: {detail}")
    try:
        profile = plistlib.loads(decode.stdout)
    except Exception as error:
        raise VerificationError("decoded embedded provisioning profile is not a valid plist") from error
    if not isinstance(profile, dict):
        raise VerificationError("decoded embedded provisioning profile root must be a dictionary")

    platform = profile.get("Platform")
    if not isinstance(platform, list) or "iOS" not in platform:
        raise VerificationError("embedded provisioning profile is not an iOS profile")

    team_identifier = code_signature.get("teamIdentifier")
    profile_teams = profile.get("TeamIdentifier")
    if (
        not team_identifier
        or not isinstance(profile_teams, list)
        or team_identifier not in profile_teams
    ):
        raise VerificationError("code-sign TeamIdentifier does not match the provisioning profile")

    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        raise VerificationError("embedded provisioning profile has no entitlement dictionary")
    entitlement_team = entitlements.get("com.apple.developer.team-identifier")
    if entitlement_team != team_identifier:
        raise VerificationError("provisioning entitlement team does not match the code signature")

    prefixes = profile.get("ApplicationIdentifierPrefix")
    app_identifier = entitlements.get("application-identifier")
    if not isinstance(prefixes, list) or not prefixes or not isinstance(app_identifier, str):
        raise VerificationError("provisioning profile has no canonical application identifier")
    expected_app_identifiers = {
        f"{prefix}.{EXPECTED_BUNDLE_ID}" for prefix in prefixes if isinstance(prefix, str) and prefix
    }
    wildcard_identifiers = {
        f"{prefix}.*" for prefix in prefixes if isinstance(prefix, str) and prefix
    }
    if app_identifier not in expected_app_identifiers | wildcard_identifiers:
        raise VerificationError("provisioning profile does not authorize Nembra's bundle identifier")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise VerificationError("provisioning profile has no valid ExpirationDate")
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    else:
        expiration = expiration.astimezone(timezone.utc)
    if expiration <= datetime.now(timezone.utc):
        raise VerificationError("embedded provisioning profile is expired")

    provisioned_devices = profile.get("ProvisionedDevices")
    provisions_all_devices = profile.get("ProvisionsAllDevices") is True
    device_match = (
        isinstance(provisioned_devices, list) and expected_device_udid in provisioned_devices
    )
    if not device_match and not provisions_all_devices:
        raise VerificationError(
            "embedded provisioning profile does not authorize the explicitly expected field device"
        )

    return {
        "teamIdentifier": team_identifier,
        "profileExpirationUTC": expiration.isoformat().replace("+00:00", "Z"),
        "targetDeviceProvisioningMatched": True,
        "provisionsAllDevices": provisions_all_devices,
    }


def verify_field_artifact(
    *,
    ipa_path: Path,
    external_record_path: Path,
    expected_source_commit: str,
    expected_device_udid: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    with tempfile.TemporaryDirectory(prefix="nembra-field-artifact-") as temp_dir:
        evidence, app_path = verify_static_artifact(
            ipa_path=ipa_path,
            external_record_path=external_record_path,
            expected_source_commit=expected_source_commit,
            extraction_root=Path(temp_dir),
        )
        code_signature = verify_code_signature(app_path)
        provisioning = verify_provisioning_profile(
            app_path=app_path,
            expected_device_udid=expected_device_udid,
            code_signature=code_signature,
        )
        metadata = {
            "schemaVersion": 1,
            "authority": "verification-only-not-field-authorization",
            "fieldBuildEvidenceRecordSHA256": None,
            "bundleIdentifier": EXPECTED_BUNDLE_ID,
            "platform": "iPhoneOS",
            "codeSignature": code_signature,
            "provisioning": provisioning,
        }
        return evidence, metadata


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify a signed Nembra ES80 Capture iPhone IPA against its schema-v3 build record."
    )
    parser.add_argument("--ipa", required=True, type=Path, help="exact signed/installable .ipa to verify")
    parser.add_argument(
        "--external-build-record",
        required=True,
        type=Path,
        help="exact external NembraCaptureExternalBuildRecord.json produced for this build instance",
    )
    parser.add_argument(
        "--expected-source-commit",
        required=True,
        help="exact accepted 40-hex source commit expected for this candidate field build",
    )
    parser.add_argument(
        "--expected-device-udid",
        required=True,
        help="exact intended physical iPhone UDID; checked locally against embedded provisioning",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="path for the exact closed-world NembraCaptureFieldBuildEvidenceRecord.json",
    )
    parser.add_argument(
        "--metadata-output",
        type=Path,
        help="optional path for verification diagnostics; never a GO authority record",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        evidence, metadata = verify_field_artifact(
            ipa_path=args.ipa,
            external_record_path=args.external_build_record,
            expected_source_commit=args.expected_source_commit,
            expected_device_udid=args.expected_device_udid,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        evidence_bytes = (json.dumps(evidence, indent=2, sort_keys=True) + "\n").encode("utf-8")
        args.output.write_bytes(evidence_bytes)
        if args.metadata_output is not None:
            metadata["fieldBuildEvidenceRecordSHA256"] = sha256_bytes(evidence_bytes)
            args.metadata_output.parent.mkdir(parents=True, exist_ok=True)
            args.metadata_output.write_text(
                json.dumps(metadata, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
    except (OSError, VerificationError) as error:
        print(f"FIELD ARTIFACT NO-GO: {error}", file=sys.stderr)
        return 1

    print("FIELD ARTIFACT VERIFIED — evidence only; this does NOT authorize physical GO.")
    print(f"field_build_evidence={args.output}")
    if args.metadata_output is not None:
        print(f"verification_metadata={args.metadata_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
