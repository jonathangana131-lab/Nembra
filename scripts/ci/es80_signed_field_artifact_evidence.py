#!/usr/bin/env python3
"""Produce fail-closed evidence for an already-built signed Nembra field IPA.

This tool never authorizes physical Experiment One. It measures and preserves an exact
installable artifact, verifies its iPhone code signature, provisioning relationship, and embedded
Nembra build declarations, and emits external evidence that a separate trusted acceptance step may
attest/review.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unicodedata
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
BUNDLE_ID = "com.jonathangana131.nembra"
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
TEAM_IDENTIFIER_RE = re.compile(r"^[A-Z0-9]{10}$")
CDHASH_RE = re.compile(r"^[0-9a-f]{40,64}$")


class EvidenceError(RuntimeError):
    pass


def publish_directory_no_replace(staging_dir: Path, output_dir: Path) -> None:
    """Atomically rename a complete directory while refusing any existing destination."""
    libc = ctypes.CDLL(None, use_errno=True)
    source = os.fsencode(staging_dir)
    destination = os.fsencode(output_dir)

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
        raise EvidenceError(
            f"atomic no-replace evidence publication is unsupported on {sys.platform!r}"
        )

    if result != 0:
        error_number = ctypes.get_errno()
        if error_number in (errno.EEXIST, errno.ENOTEMPTY):
            raise EvidenceError(
                f"refusing to overwrite concurrently created field evidence: {output_dir}"
            )
        raise OSError(error_number, os.strerror(error_number), str(output_dir))


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


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n"


def _safe_member_path(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if not name or path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise EvidenceError(f"IPA contains unsafe ZIP member path: {name!r}")
    return path


def _filesystem_collision_key(path: PurePosixPath) -> tuple[str, ...]:
    return tuple(unicodedata.normalize("NFC", part).casefold() for part in path.parts)


def _validated_unique_member_paths(infos: list[zipfile.ZipInfo]) -> dict[str, PurePosixPath]:
    """Reject archive ambiguity before any member is read or extracted.

    Exact duplicate member names are ambiguous to zip readers. Distinct ZIP names can also alias
    on normal case-insensitive, Unicode-normalizing macOS filesystems. Validate every path prefix,
    not only each complete filename, so differently-spelled parent directories cannot merge during
    extraction before code-signing verification.
    """
    exact: set[str] = set()
    filesystem_paths: dict[tuple[str, ...], PurePosixPath] = {}
    result: dict[str, PurePosixPath] = {}
    for info in infos:
        raw_name = info.filename.rstrip("/")
        member = _safe_member_path(raw_name)
        canonical = str(member)
        if canonical in exact:
            raise EvidenceError(f"IPA contains duplicate ZIP member path: {canonical!r}")
        exact.add(canonical)

        parts = member.parts
        for depth in range(1, len(parts) + 1):
            prefix = PurePosixPath(*parts[:depth])
            collision_key = _filesystem_collision_key(prefix)
            previous = filesystem_paths.get(collision_key)
            if previous is not None and previous != prefix:
                raise EvidenceError(
                    "IPA contains filesystem-aliasing ZIP member paths: "
                    f"{str(previous)!r} and {str(prefix)!r}"
                )
            filesystem_paths[collision_key] = prefix

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
    if not isinstance(supported, list) or not supported or not all(isinstance(item, str) for item in supported):
        raise EvidenceError("field IPA must carry a non-empty string CFBundleSupportedPlatforms array")
    if len(set(supported)) != len(supported):
        raise EvidenceError("field IPA CFBundleSupportedPlatforms must not contain duplicate values")
    for item in supported:
        if (
            not item
            or len(item.encode("utf-8")) > 256
            or item != item.strip()
            or any(ord(character) < 32 or ord(character) == 127 for character in item)
        ):
            raise EvidenceError("field IPA CFBundleSupportedPlatforms contains a malformed value")
    if platform != "iphoneos":
        raise EvidenceError(f"field IPA must declare DTPlatformName=iphoneos; got {platform!r}")
    if "iPhoneOS" not in supported:
        raise EvidenceError(f"field IPA must declare iPhoneOS in CFBundleSupportedPlatforms; got {supported!r}")
    if any("simulator" in item.casefold() for item in supported):
        raise EvidenceError("Simulator platform declaration is forbidden in field IPA evidence")
    return platform, supported


def _run_text(command: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise EvidenceError(f"command failed ({' '.join(command)}): {detail}")
    return result


def run_codesign(app_path: Path) -> tuple[str, list[str], str]:
    if sys.platform != "darwin":
        raise EvidenceError("signed field IPA inspection requires macOS code-signing tools")
    codesign = shutil.which("codesign")
    if not codesign:
        raise EvidenceError("codesign is not available")

    _run_text(
        [
            codesign,
            "--verify",
            "--deep",
            "--strict",
            "--all-architectures",
            "--verbose=4",
            str(app_path),
        ]
    )
    display = _run_text([codesign, "-d", "--verbose=4", str(app_path)])

    metadata = "\n".join(part for part in (display.stdout, display.stderr) if part)
    if re.search(r"(?m)^Signature=adhoc\s*$", metadata):
        raise EvidenceError("ad-hoc signature cannot become signed field artifact evidence")

    identifier_match = re.search(r"(?m)^Identifier=([^\r\n]+)$", metadata)
    if not identifier_match or identifier_match.group(1).strip() != BUNDLE_ID:
        raise EvidenceError("code-signing identifier does not match Nembra bundle identifier")

    team_match = re.search(r"(?m)^TeamIdentifier=([^\r\n]+)$", metadata)
    if not team_match:
        raise EvidenceError("codesign metadata does not contain TeamIdentifier")
    team_identifier = team_match.group(1).strip()
    if not TEAM_IDENTIFIER_RE.fullmatch(team_identifier):
        raise EvidenceError("field IPA does not carry a canonical Apple TeamIdentifier")

    cdhash_match = re.search(r"(?m)^CDHash=([^\r\n]+)$", metadata)
    if not cdhash_match:
        raise EvidenceError("codesign metadata does not contain CDHash")
    code_directory_hash = cdhash_match.group(1).strip().lower()
    if not CDHASH_RE.fullmatch(code_directory_hash):
        raise EvidenceError("codesign CDHash is malformed")

    authorities = [match.group(1).strip() for match in re.finditer(r"(?m)^Authority=([^\r\n]+)$", metadata)]
    if not authorities or any(not authority for authority in authorities):
        raise EvidenceError("codesign metadata does not contain a complete signing authority chain")
    return team_identifier, authorities, code_directory_hash


def _normalized_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _codesign_tool() -> str:
    if sys.platform != "darwin":
        raise EvidenceError("signed field IPA inspection requires macOS Apple signing tools")
    codesign = shutil.which("codesign")
    if not codesign:
        raise EvidenceError("codesign is not available")
    return codesign


def _decode_codesign_entitlements(result: subprocess.CompletedProcess[str]) -> dict:
    for output in (result.stdout, result.stderr):
        start = output.find("<?xml")
        end = output.rfind("</plist>")
        if start < 0 or end < start:
            continue
        payload = output[start : end + len("</plist>")].encode("utf-8")
        try:
            value = plistlib.loads(payload)
        except Exception:
            continue
        if isinstance(value, dict):
            return value
    raise EvidenceError("could not decode effective entitlements sealed into signed app")


def read_effective_signed_entitlements(app_path: Path) -> dict:
    result = _run_text(
        [_codesign_tool(), "-d", "--entitlements", ":-", "--xml", str(app_path)]
    )
    return _decode_codesign_entitlements(result)


def read_leaf_signing_certificate_der(app_path: Path) -> bytes:
    codesign = _codesign_tool()
    with tempfile.TemporaryDirectory(prefix="nembra-field-cert-") as temporary:
        prefix = Path(temporary) / "signing-cert"
        _run_text([codesign, "-d", "--extract-certificates", str(prefix), str(app_path)])
        leaf = Path(f"{prefix}0")
        if not leaf.is_file():
            raise EvidenceError("codesign did not expose the leaf signing certificate")
        data = leaf.read_bytes()
        if not data:
            raise EvidenceError("leaf signing certificate is empty")
        return data


def _profile_value_authorizes(profile_value: object, signed_value: object) -> bool:
    if isinstance(signed_value, str):
        if isinstance(profile_value, str):
            if profile_value.endswith("*"):
                return signed_value.startswith(profile_value[:-1])
            return signed_value == profile_value
        if isinstance(profile_value, list):
            return any(_profile_value_authorizes(candidate, signed_value) for candidate in profile_value)
        return False
    if isinstance(signed_value, list):
        if not isinstance(profile_value, list):
            return False
        return all(
            any(_profile_value_authorizes(candidate, item) for candidate in profile_value)
            for item in signed_value
        )
    if isinstance(signed_value, dict):
        if not isinstance(profile_value, dict):
            return False
        return all(
            key in profile_value and _profile_value_authorizes(profile_value[key], value)
            for key, value in signed_value.items()
        )
    return profile_value == signed_value


def _valid_intended_device_udid(value: str | None) -> bool:
    if value is None or not value or len(value.encode("utf-8")) > 128 or value != value.strip():
        return False
    return not any(ord(character) < 33 or ord(character) == 127 for character in value)


def validate_provisioning_profile(
    profile: dict,
    *,
    team_identifier: str,
    bundle_identifier: str,
    signed_entitlements: dict,
    signing_certificate_der: bytes,
    intended_device_udid: str,
    now: datetime | None = None,
) -> tuple[str, str, str]:
    profile_teams = profile.get("TeamIdentifier")
    if not isinstance(profile_teams, list) or team_identifier not in profile_teams:
        raise EvidenceError("provisioning profile TeamIdentifier does not match the code signature")

    profile_uuid = profile.get("UUID")
    if not isinstance(profile_uuid, str) or not profile_uuid.strip():
        raise EvidenceError("provisioning profile UUID is missing")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise EvidenceError("provisioning profile ExpirationDate is missing")
    expiration_utc = _normalized_utc(expiration)
    current_utc = _normalized_utc(now or datetime.now(timezone.utc))
    if expiration_utc <= current_utc:
        raise EvidenceError("provisioning profile is expired")

    developer_certificates = profile.get("DeveloperCertificates")
    if (
        not isinstance(developer_certificates, list)
        or not developer_certificates
        or not all(isinstance(certificate, bytes) and certificate for certificate in developer_certificates)
        or signing_certificate_der not in developer_certificates
    ):
        raise EvidenceError("provisioning profile does not authorize the leaf signing certificate")

    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        raise EvidenceError("provisioning profile Entitlements are missing")
    expected_application_identifier = f"{team_identifier}.{bundle_identifier}"
    if entitlements.get("application-identifier") != expected_application_identifier:
        raise EvidenceError(
            "provisioning profile application-identifier does not match the signed Nembra bundle"
        )
    entitlement_team = entitlements.get("com.apple.developer.team-identifier")
    if entitlement_team is not None and entitlement_team != team_identifier:
        raise EvidenceError("provisioning profile entitlement TeamIdentifier does not match code signing")

    if signed_entitlements.get("application-identifier") != expected_application_identifier:
        raise EvidenceError("effective signed application-identifier does not match Nembra bundle")
    if signed_entitlements.get("com.apple.developer.team-identifier") != team_identifier:
        raise EvidenceError("effective signed TeamIdentifier does not match code signing")
    for key, value in signed_entitlements.items():
        if key not in entitlements or not _profile_value_authorizes(entitlements[key], value):
            raise EvidenceError(
                f"effective signed entitlement is not authorized by provisioning profile: {key}"
            )

    if not _valid_intended_device_udid(intended_device_udid):
        raise EvidenceError("one valid intended field-device UDID is required for provisioning verification")
    if profile.get("ProvisionsAllDevices") is not True:
        provisioned_devices = profile.get("ProvisionedDevices")
        if (
            not isinstance(provisioned_devices, list)
            or not all(isinstance(device, str) for device in provisioned_devices)
            or intended_device_udid not in provisioned_devices
        ):
            raise EvidenceError("provisioning profile does not include the intended field device")

    return (
        profile_uuid.strip(),
        expiration_utc.isoformat().replace("+00:00", "Z"),
        expected_application_identifier,
    )


def verify_provisioning_profile(
    app_path: Path,
    *,
    team_identifier: str,
    bundle_identifier: str,
    intended_device_udid: str,
) -> tuple[str, str, str, str]:
    if sys.platform != "darwin":
        raise EvidenceError("provisioning verification requires macOS Apple signing tools")
    security = shutil.which("security")
    if not security:
        raise EvidenceError("security is not available for provisioning-profile verification")

    profile_path = app_path / "embedded.mobileprovision"
    if not profile_path.is_file():
        raise EvidenceError("signed field IPA is missing embedded.mobileprovision")
    profile_sha256 = sha256_file(profile_path)

    result = subprocess.run(
        [security, "cms", "-D", "-i", str(profile_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise EvidenceError(f"could not decode embedded provisioning profile: {detail}")
    try:
        profile = plistlib.loads(result.stdout)
    except Exception as exc:
        raise EvidenceError("decoded embedded provisioning profile is not a valid plist") from exc
    if not isinstance(profile, dict):
        raise EvidenceError("decoded embedded provisioning profile root is not a dictionary")

    profile_uuid, expiration_utc, application_identifier = validate_provisioning_profile(
        profile,
        team_identifier=team_identifier,
        bundle_identifier=bundle_identifier,
        signed_entitlements=read_effective_signed_entitlements(app_path),
        signing_certificate_der=read_leaf_signing_certificate_der(app_path),
        intended_device_udid=intended_device_udid,
    )
    return profile_sha256, profile_uuid, expiration_utc, application_identifier


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


def inspect_ipa(ipa_path: Path, expected_source_sha: str, *, intended_device_udid: str) -> dict:
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

        executable_name = plist_string(info, "CFBundleExecutable")
        if "/" in executable_name or executable_name in {".", ".."}:
            raise EvidenceError("CFBundleExecutable is not a safe bundle-local filename")
        executable_path = app_path / executable_name
        if not executable_path.is_file():
            raise EvidenceError("signed app executable is missing")

        team_identifier, signing_authorities, code_directory_hash = run_codesign(app_path)
        (
            provisioning_profile_sha256,
            provisioning_profile_uuid,
            provisioning_profile_expiration_utc,
            provisioning_application_identifier,
        ) = verify_provisioning_profile(
            app_path,
            team_identifier=team_identifier,
            bundle_identifier=bundle_id,
            intended_device_udid=intended_device_udid,
        )
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
        "codeDirectoryHash": code_directory_hash,
        "provisioningProfileSHA256": provisioning_profile_sha256,
        "provisioningProfileUUID": provisioning_profile_uuid,
        "provisioningProfileExpirationUTC": provisioning_profile_expiration_utc,
        "provisioningApplicationIdentifier": provisioning_application_identifier,
        "executableSHA256": executable_sha,
        "infoPlistSHA256": info_plist_sha,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    return {
        "external_record": external_record,
        "external_bytes": external_bytes,
        "field_build_record": field_build_record,
        "field_build_bytes": field_build_bytes,
        "signing_inspection": signing_inspection,
    }


def write_outputs(ipa_path: Path, output_dir: Path, inspection: dict) -> dict[str, Path]:
    output_parent = output_dir.parent
    output_parent.mkdir(parents=True, exist_ok=True)
    if output_dir.exists() or output_dir.is_symlink():
        raise EvidenceError(f"refusing to overwrite existing field evidence directory: {output_dir}")

    staging_dir = Path(
        tempfile.mkdtemp(prefix=f".{output_dir.name}.staging-", dir=output_parent)
    )
    published = False
    try:
        retained_dir = staging_dir / "build-evidence"
        retained_dir.mkdir()

        retained_ipa = retained_dir / "NembraField.ipa"
        external_path = staging_dir / "NembraCaptureExternalBuildRecord.json"
        field_build_path = staging_dir / "NembraCaptureFieldBuildEvidenceRecord.json"
        signing_inspection_path = staging_dir / "NembraCaptureSignedFieldArtifactInspection.json"

        shutil.copy2(ipa_path, retained_ipa)
        if sha256_file(retained_ipa) != inspection["field_build_record"]["signedInstallableSHA256"]:
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
        publish_directory_no_replace(staging_dir, output_dir)
        published = True
    finally:
        if not published:
            shutil.rmtree(staging_dir, ignore_errors=True)

    return {
        "retained_ipa": output_dir / "build-evidence" / "NembraField.ipa",
        "external_record": output_dir / "NembraCaptureExternalBuildRecord.json",
        "field_build_record": output_dir / "NembraCaptureFieldBuildEvidenceRecord.json",
        "signing_inspection": output_dir / "NembraCaptureSignedFieldArtifactInspection.json",
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

    with tempfile.TemporaryDirectory(prefix="nembra-field-publish-self-test-") as temporary:
        root = Path(temporary)
        ipa_path = root / "candidate.ipa"
        ipa_path.write_bytes(b"exact retained ipa")
        external_bytes = canonical_json_bytes({"schemaVersion": 3})
        field_build_record = {
            "signedInstallableSHA256": sha256_file(ipa_path),
            "externalBuildRecordSHA256": hashlib.sha256(external_bytes).hexdigest(),
        }
        field_build_bytes = canonical_json_bytes(field_build_record)
        signing_inspection = {
            "fieldBuildEvidenceRecordSHA256": hashlib.sha256(field_build_bytes).hexdigest(),
        }
        inspection = {
            "external_bytes": external_bytes,
            "field_build_record": field_build_record,
            "field_build_bytes": field_build_bytes,
            "signing_inspection": signing_inspection,
        }

        failed_output = root / "failed-evidence"
        mismatched = {
            **inspection,
            "signing_inspection": {
                "fieldBuildEvidenceRecordSHA256": "0" * 64,
            },
        }
        try:
            write_outputs(ipa_path, failed_output, mismatched)
        except EvidenceError:
            pass
        else:
            raise AssertionError("late evidence digest mismatch must fail publication")
        assert not failed_output.exists()
        assert not list(root.glob(".failed-evidence.staging-*"))

        published_output = root / "published-evidence"
        paths = write_outputs(ipa_path, published_output, inspection)
        assert paths["retained_ipa"].read_bytes() == ipa_path.read_bytes()
        assert paths["external_record"].read_bytes() == external_bytes
        assert paths["field_build_record"].read_bytes() == field_build_bytes
        assert paths["signing_inspection"].read_bytes() == canonical_json_bytes(signing_inspection)
        assert not list(root.glob(".published-evidence.staging-*"))

        try:
            write_outputs(ipa_path, published_output, inspection)
        except EvidenceError:
            pass
        else:
            raise AssertionError("existing evidence directory must never be overwritten")

        competing_staging = root / ".competing.staging"
        competing_staging.mkdir()
        (competing_staging / "complete").write_text("candidate", encoding="utf-8")
        competing_output = root / "competing-output"
        competing_output.mkdir()
        (competing_output / "owner").write_text("incumbent", encoding="utf-8")
        try:
            publish_directory_no_replace(competing_staging, competing_output)
        except EvidenceError:
            pass
        else:
            raise AssertionError("no-replace publication must reject a competing destination")
        assert (competing_output / "owner").read_text(encoding="utf-8") == "incumbent"
        assert (competing_staging / "complete").read_text(encoding="utf-8") == "candidate"

    duplicate = [zipfile.ZipInfo("Payload/Nembra.app/Nembra"), zipfile.ZipInfo("Payload/Nembra.app/Nembra")]
    try:
        _validated_unique_member_paths(duplicate)
    except EvidenceError:
        pass
    else:
        raise AssertionError("duplicate ZIP member path must fail closed")

    def assert_alias_rejected(first: str, second: str) -> None:
        infos = [zipfile.ZipInfo(first), zipfile.ZipInfo(second)]
        try:
            _validated_unique_member_paths(infos)
        except EvidenceError as error:
            assert "filesystem-aliasing" in str(error)
        else:
            raise AssertionError(f"filesystem-aliasing ZIP paths must fail closed: {first!r}, {second!r}")

    assert_alias_rejected(
        "Payload/Nembra.app/Info.plist",
        "Payload/Nembra.app/info.plist",
    )
    assert_alias_rejected(
        "Payload/Nembra.app/Nembra",
        "Payload/Nembra.app/nembra",
    )
    assert_alias_rejected(
        "Payload/Nembra.app/Info.plist",
        "Payload/nembra.app/Other",
    )
    assert_alias_rejected(
        "Payload/Nembra.app/Caf\u00e9",
        "Payload/Nembra.app/Cafe\u0301",
    )

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

    team = "ABCDE12345"
    device = "00008101-001234567890001E"
    leaf_certificate = b"leaf-signing-certificate-der"
    expiry = datetime(2099, 1, 1, tzinfo=timezone.utc)
    valid_entitlements = {
        "application-identifier": f"{team}.{BUNDLE_ID}",
        "com.apple.developer.team-identifier": team,
        "get-task-allow": False,
        "keychain-access-groups": [f"{team}.{BUNDLE_ID}"],
    }
    valid_profile = {
        "TeamIdentifier": [team],
        "UUID": "PROFILE-UUID",
        "ExpirationDate": expiry,
        "DeveloperCertificates": [leaf_certificate],
        "ProvisionedDevices": [device],
        "Entitlements": {
            "application-identifier": f"{team}.{BUNDLE_ID}",
            "com.apple.developer.team-identifier": team,
            "get-task-allow": False,
            "keychain-access-groups": [f"{team}.*"],
        },
    }
    profile_uuid, expiration_utc, application_id = validate_provisioning_profile(
        valid_profile,
        team_identifier=team,
        bundle_identifier=BUNDLE_ID,
        signed_entitlements=valid_entitlements,
        signing_certificate_der=leaf_certificate,
        intended_device_udid=device,
        now=datetime(2098, 1, 1, tzinfo=timezone.utc),
    )
    assert profile_uuid == "PROFILE-UUID"
    assert expiration_utc == "2099-01-01T00:00:00Z"
    assert application_id == f"{team}.{BUNDLE_ID}"

    bad_profiles = (
        {**valid_profile, "TeamIdentifier": ["OTHER12345"]},
        {**valid_profile, "ExpirationDate": datetime(2097, 1, 1, tzinfo=timezone.utc)},
        {**valid_profile, "DeveloperCertificates": [b"different-certificate"]},
    )
    for malformed in bad_profiles:
        try:
            validate_provisioning_profile(
                malformed,
                team_identifier=team,
                bundle_identifier=BUNDLE_ID,
                signed_entitlements=valid_entitlements,
                signing_certificate_der=leaf_certificate,
                intended_device_udid=device,
                now=datetime(2098, 1, 1, tzinfo=timezone.utc),
            )
        except EvidenceError:
            pass
        else:
            raise AssertionError("invalid provisioning profile relationship was accepted")

    bad_signed_entitlements = (
        {**valid_entitlements, "application-identifier": f"{team}.com.example.other"},
        {**valid_entitlements, "com.apple.developer.team-identifier": "OTHER12345"},
        {**valid_entitlements, "get-task-allow": True},
        {**valid_entitlements, "com.apple.developer.healthkit": True},
    )
    for malformed in bad_signed_entitlements:
        try:
            validate_provisioning_profile(
                valid_profile,
                team_identifier=team,
                bundle_identifier=BUNDLE_ID,
                signed_entitlements=malformed,
                signing_certificate_der=leaf_certificate,
                intended_device_udid=device,
                now=datetime(2098, 1, 1, tzinfo=timezone.utc),
            )
        except EvidenceError:
            pass
        else:
            raise AssertionError("unauthorized effective signed entitlement was accepted")

    try:
        validate_provisioning_profile(
            valid_profile,
            team_identifier=team,
            bundle_identifier=BUNDLE_ID,
            signed_entitlements=valid_entitlements,
            signing_certificate_der=leaf_certificate,
            intended_device_udid="00008101-NOT-PROVISIONED",
            now=datetime(2098, 1, 1, tzinfo=timezone.utc),
        )
    except EvidenceError:
        pass
    else:
        raise AssertionError("unprovisioned intended field device was accepted")

    all_devices_profile = {**valid_profile, "ProvisionsAllDevices": True}
    all_devices_profile.pop("ProvisionedDevices", None)
    validate_provisioning_profile(
        all_devices_profile,
        team_identifier=team,
        bundle_identifier=BUNDLE_ID,
        signed_entitlements=valid_entitlements,
        signing_certificate_der=leaf_certificate,
        intended_device_udid=device,
        now=datetime(2098, 1, 1, tzinfo=timezone.utc),
    )

    verify_device_platform({
        "DTPlatformName": "iphoneos",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
    })
    invalid_platforms = (
        {"DTPlatformName": "iphoneos", "CFBundleSupportedPlatforms": ["iPhoneOS", "iPhoneOS"]},
        {"DTPlatformName": "iphoneos", "CFBundleSupportedPlatforms": ["iPhoneOS", "iphonesimulator"]},
        {"DTPlatformName": "iphoneos", "CFBundleSupportedPlatforms": ["iPhoneOS", 7]},
        {"DTPlatformName": "iphoneos", "CFBundleSupportedPlatforms": ["iPhoneOS", " WatchOS"]},
    )
    for malformed in invalid_platforms:
        try:
            verify_device_platform(malformed)
        except EvidenceError:
            pass
        else:
            raise AssertionError("consumer-incompatible platform declaration was accepted")

    xml = plistlib.dumps(valid_entitlements, fmt=plistlib.FMT_XML).decode("utf-8")
    decoded = _decode_codesign_entitlements(
        subprocess.CompletedProcess(args=["codesign"], returncode=0, stdout=xml, stderr="")
    )
    assert decoded == valid_entitlements
    try:
        _decode_codesign_entitlements(
            subprocess.CompletedProcess(args=["codesign"], returncode=0, stdout="noise", stderr="")
        )
    except EvidenceError:
        pass
    else:
        raise AssertionError("missing effective signed entitlements were accepted")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, help="exact already-produced signed Nembra .ipa")
    parser.add_argument("--output-dir", type=Path, help="directory for immutable external evidence")
    parser.add_argument(
        "--expected-source-sha",
        help="exact accepted lowercase 40-hex source commit expected inside the field build",
    )
    parser.add_argument(
        "--intended-device-udid",
        help="verification-only UDID of the intended field iPhone; never persisted or printed",
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
            ("--intended-device-udid", args.intended_device_udid),
        )
        if value is None
    ]
    if missing:
        raise EvidenceError(f"required arguments missing: {', '.join(missing)}")

    inspection = inspect_ipa(
        args.ipa.resolve(),
        args.expected_source_sha,
        intended_device_udid=args.intended_device_udid,
    )
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