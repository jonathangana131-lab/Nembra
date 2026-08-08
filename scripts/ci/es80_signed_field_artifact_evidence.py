#!/usr/bin/env python3
"""Produce fail-closed evidence for one exact signed Nembra field IPA.

This tool measures and preserves signed-device build evidence. It never authorizes physical
Experiment One; a later independently trusted acceptance step must attest/review these exact bytes.
"""

from __future__ import annotations

import argparse
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
import uuid
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Callable

RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
BUNDLE_ID = "com.jonathangana131.nembra"
EXTERNAL_RECORD_SCHEMA_VERSION = 3
FIELD_EVIDENCE_SCHEMA_VERSION = 2
AUTHORITY_LABEL = "signed-field-artifact-evidence-not-field-authorization"

SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
TEAM_RE = re.compile(r"^[A-Z0-9]{10}$")
CDHASH_RE = re.compile(r"^[0-9a-f]{40,64}$")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


class EvidenceError(RuntimeError):
    pass


@dataclass(frozen=True)
class SigningEvidence:
    team_identifier: str
    signing_authorities: list[str]
    code_directory_hash: str
    provisioning_profile_uuid: str
    provisioning_profile_expiration_utc: str


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
    return (
        bool(value)
        and len(value.encode("utf-8")) <= 128
        and value == value.strip()
        and not any(ord(character) < 32 or ord(character) == 127 for character in value)
    )


def expected_build_identifier(source_sha: str) -> str:
    return f"Capture Build V14-{source_sha[:12]}"


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n"


def _safe_member_path(name: str) -> PurePosixPath:
    # PurePosixPath normalizes repeated separators and dot segments. Reject those aliases from the
    # raw ZIP spelling before normalization so two distinct archive entries cannot name one Mac
    # extraction destination through different spellings.
    if not name or "\\" in name or "\x00" in name or name.startswith("/"):
        raise EvidenceError(f"IPA contains unsafe ZIP member path: {name!r}")
    raw_parts = name.split("/")
    if any(part in ("", ".", "..") for part in raw_parts):
        raise EvidenceError(f"IPA contains unsafe ZIP member path: {name!r}")
    path = PurePosixPath(name)
    if path.is_absolute() or path.as_posix() != name:
        raise EvidenceError(f"IPA contains noncanonical ZIP member path: {name!r}")
    return path


def extract_ipa_safely(ipa_path: Path, destination: Path) -> Path:
    try:
        archive = zipfile.ZipFile(ipa_path)
    except (OSError, zipfile.BadZipFile) as exc:
        raise EvidenceError("input is not a readable IPA/ZIP archive") from exc

    app_roots: set[str] = set()
    validated_members: list[tuple[zipfile.ZipInfo, PurePosixPath, int]] = []
    exact_destinations: set[str] = set()
    folded_destinations: dict[str, str] = {}

    # Validate the complete archive topology before writing the first extracted byte. The trusted
    # Mac is commonly case-insensitive, so exact duplicates and case-fold aliases are both
    # ambiguous evidence and fail closed.
    with archive:
        for info in archive.infolist():
            raw_name = info.filename[:-1] if info.filename.endswith("/") else info.filename
            member = _safe_member_path(raw_name)
            normalized = member.as_posix()
            folded = normalized.casefold()
            if normalized in exact_destinations:
                raise EvidenceError(f"IPA contains duplicate normalized ZIP member path: {normalized!r}")
            prior = folded_destinations.get(folded)
            if prior is not None:
                raise EvidenceError(
                    f"IPA contains case-colliding ZIP member paths: {prior!r} and {normalized!r}"
                )
            exact_destinations.add(normalized)
            folded_destinations[folded] = normalized

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
            validated_members.append((info, member, mode))

        if len(app_roots) != 1:
            raise EvidenceError(
                f"IPA must contain exactly one top-level Payload/*.app bundle; found {sorted(app_roots)!r}"
            )

        for info, member, mode in validated_members:
            target = destination.joinpath(*member.parts)
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info, "r") as source, target.open("wb") as sink:
                shutil.copyfileobj(source, sink)
            permissions = mode & 0o777
            if permissions:
                os.chmod(target, permissions)

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
    if not isinstance(supported, list) or not all(isinstance(item, str) for item in supported):
        raise EvidenceError("field IPA must carry a string CFBundleSupportedPlatforms array")
    if platform != "iphoneos":
        raise EvidenceError(f"field IPA must declare DTPlatformName=iphoneos; got {platform!r}")
    if "iPhoneOS" not in supported:
        raise EvidenceError(f"field IPA must declare iPhoneOS in CFBundleSupportedPlatforms; got {supported!r}")
    if any("Simulator" in item for item in supported):
        raise EvidenceError("Simulator platform declaration is forbidden in field IPA evidence")
    return platform, supported


def _run(command: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise EvidenceError(f"command failed ({' '.join(command)}): {detail}")
    return result


def _plist_from_codesign_entitlements(result: subprocess.CompletedProcess[str]) -> dict:
    # Depending on codesign/Xcode revision, entitlement XML may be emitted on stdout or stderr.
    # Isolate only the plist document so ordinary codesign diagnostics cannot be interpreted as
    # entitlement data.
    for text in (result.stdout, result.stderr):
        if not text:
            continue
        start = text.find("<?xml")
        end = text.rfind("</plist>")
        if start == -1 or end == -1:
            continue
        payload = text[start : end + len("</plist>")].encode("utf-8")
        try:
            value = plistlib.loads(payload)
        except Exception:
            continue
        if isinstance(value, dict):
            return value
    raise EvidenceError("codesign did not expose a readable signed-entitlements plist")


def _validate_signing_contract(
    *,
    team_identifier: str,
    bundle_id: str,
    profile: dict,
    signed_entitlements: dict,
) -> tuple[str, str]:
    profile_teams = profile.get("TeamIdentifier")
    if not isinstance(profile_teams, list) or team_identifier not in profile_teams:
        raise EvidenceError("provisioning profile TeamIdentifier does not match code signature")
    profile_uuid = profile.get("UUID")
    if not isinstance(profile_uuid, str) or not profile_uuid.strip():
        raise EvidenceError("provisioning profile UUID is missing")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise EvidenceError("provisioning profile ExpirationDate is missing")
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    else:
        expiration = expiration.astimezone(timezone.utc)
    if expiration <= datetime.now(timezone.utc):
        raise EvidenceError("provisioning profile is expired")

    expected_application_identifier = f"{team_identifier}.{bundle_id}"
    profile_entitlements = profile.get("Entitlements")
    if not isinstance(profile_entitlements, dict):
        raise EvidenceError("provisioning profile Entitlements dictionary is missing")
    if profile_entitlements.get("application-identifier") != expected_application_identifier:
        raise EvidenceError("provisioning profile application-identifier does not match signed Nembra bundle")
    if profile_entitlements.get("com.apple.developer.team-identifier") != team_identifier:
        raise EvidenceError("provisioning profile developer-team entitlement does not match code signature")

    if signed_entitlements.get("application-identifier") != expected_application_identifier:
        raise EvidenceError("signed app application-identifier entitlement does not match profile/team/bundle")
    if signed_entitlements.get("com.apple.developer.team-identifier") != team_identifier:
        raise EvidenceError("signed app developer-team entitlement does not match profile/code signature")

    return profile_uuid.strip(), expiration.isoformat().replace("+00:00", "Z")


def verify_signing(app_path: Path, bundle_id: str) -> SigningEvidence:
    if sys.platform != "darwin":
        raise EvidenceError("signed field IPA inspection requires macOS Apple signing tools")
    codesign = shutil.which("codesign")
    security = shutil.which("security")
    if not codesign or not security:
        raise EvidenceError("codesign and security are required")

    _run([codesign, "--verify", "--deep", "--strict", "--verbose=4", str(app_path)])
    display = _run([codesign, "-d", "--verbose=4", str(app_path)])
    metadata = "\n".join(part for part in (display.stdout, display.stderr) if part)
    if re.search(r"(?m)^Signature=adhoc\s*$", metadata):
        raise EvidenceError("ad-hoc signature cannot become signed field artifact evidence")

    team_match = re.search(r"(?m)^TeamIdentifier=([^\r\n]+)$", metadata)
    cdhash_match = re.search(r"(?m)^CDHash=([^\r\n]+)$", metadata)
    if not team_match or not cdhash_match:
        raise EvidenceError("codesign metadata must contain TeamIdentifier and CDHash")
    team_identifier = team_match.group(1).strip()
    code_directory_hash = cdhash_match.group(1).strip().lower()
    if not TEAM_RE.fullmatch(team_identifier):
        raise EvidenceError("codesign TeamIdentifier is malformed")
    if not CDHASH_RE.fullmatch(code_directory_hash):
        raise EvidenceError("codesign CDHash is malformed")

    authorities = [match.group(1).strip() for match in re.finditer(r"(?m)^Authority=([^\r\n]+)$", metadata)]
    if not authorities or any(not authority for authority in authorities):
        raise EvidenceError("codesign metadata does not contain a signing authority chain")

    profile_path = app_path / "embedded.mobileprovision"
    if not profile_path.is_file():
        raise EvidenceError("signed field app is missing embedded.mobileprovision")
    decoded = _run([security, "cms", "-D", "-i", str(profile_path)]).stdout.encode("utf-8")
    try:
        profile = plistlib.loads(decoded)
    except Exception as exc:
        raise EvidenceError("could not decode embedded provisioning profile") from exc
    if not isinstance(profile, dict):
        raise EvidenceError("embedded provisioning profile root is not a dictionary")

    signed_entitlements_result = _run([codesign, "-d", "--entitlements", ":-", str(app_path)])
    signed_entitlements = _plist_from_codesign_entitlements(signed_entitlements_result)
    profile_uuid, expiration_utc = _validate_signing_contract(
        team_identifier=team_identifier,
        bundle_id=bundle_id,
        profile=profile,
        signed_entitlements=signed_entitlements,
    )

    return SigningEvidence(
        team_identifier=team_identifier,
        signing_authorities=authorities,
        code_directory_hash=code_directory_hash,
        provisioning_profile_uuid=profile_uuid,
        provisioning_profile_expiration_utc=expiration_utc,
    )


def reject_embedded_external_authority(app_path: Path) -> None:
    forbidden = {
        "NembraCaptureTrustedBuildRecord.json",
        "NembraCaptureExternalBuildRecord.json",
        "NembraCaptureSignedFieldArtifactEvidence.json",
    }
    hits = sorted(path.name for path in app_path.rglob("*") if path.is_file() and path.name in forbidden)
    if hits:
        raise EvidenceError(
            "final executable-digest/field-acceptance evidence must stay outside the signed app bundle; "
            f"found {hits!r}"
        )


def inspect_ipa(
    ipa_path: Path,
    expected_source_sha: str,
    *,
    signing_probe: Callable[[Path, str], SigningEvidence] = verify_signing,
) -> dict:
    source_sha = canonical_sha40(expected_source_sha)
    if not ipa_path.is_file() or ipa_path.suffix.lower() != ".ipa":
        raise EvidenceError("--ipa must name one existing .ipa file")

    ipa_sha = sha256_file(ipa_path)
    ipa_size = ipa_path.stat().st_size
    with tempfile.TemporaryDirectory(prefix="nembra-field-ipa-") as temporary:
        app_path = extract_ipa_safely(ipa_path, Path(temporary))
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
            raise EvidenceError("embedded source commit does not match accepted source")

        executable_name = plist_string(info, "CFBundleExecutable")
        if "/" in executable_name or executable_name in {".", ".."}:
            raise EvidenceError("CFBundleExecutable is not a safe bundle-local filename")
        executable_path = app_path / executable_name
        if not executable_path.is_file():
            raise EvidenceError("signed app executable is missing")

        signing = signing_probe(app_path, bundle_id)
        executable_sha = sha256_file(executable_path)
        info_plist_sha = sha256_file(info_path)
        if not SHA256_RE.fullmatch(ipa_sha) or not SHA256_RE.fullmatch(executable_sha) or not SHA256_RE.fullmatch(info_plist_sha):
            raise EvidenceError("could not derive canonical build SHA-256 evidence")

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
    field_evidence = {
        "schemaVersion": FIELD_EVIDENCE_SCHEMA_VERSION,
        "authority": AUTHORITY_LABEL,
        "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance_id,
        "sourceCommitSHA": source_sha,
        "bundleIdentifier": bundle_id,
        "platformName": platform_name,
        "supportedPlatforms": supported_platforms,
        "teamIdentifier": signing.team_identifier,
        "signingAuthorities": signing.signing_authorities,
        "codeDirectoryHash": signing.code_directory_hash,
        "provisioningProfileUUID": signing.provisioning_profile_uuid,
        "provisioningProfileExpirationUTC": signing.provisioning_profile_expiration_utc,
        "ipaSHA256": ipa_sha,
        "ipaByteCount": ipa_size,
        "executableSHA256": executable_sha,
        "infoPlistSHA256": info_plist_sha,
        "externalBuildRecordSHA256": hashlib.sha256(external_bytes).hexdigest(),
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    return {"external_record": external_record, "external_bytes": external_bytes, "field_evidence": field_evidence}


def write_outputs(ipa_path: Path, output_dir: Path, inspection: dict) -> dict[str, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    retained_dir = output_dir / "build-evidence"
    retained_dir.mkdir(parents=True, exist_ok=True)
    retained_ipa = retained_dir / "NembraField.ipa"
    external_path = output_dir / "NembraCaptureExternalBuildRecord.json"
    field_path = output_dir / "NembraCaptureSignedFieldArtifactEvidence.json"
    targets = (retained_ipa, external_path, field_path)
    existing = [str(path) for path in targets if path.exists()]
    if existing:
        raise EvidenceError(f"refusing to overwrite existing field evidence: {existing!r}")

    shutil.copy2(ipa_path, retained_ipa)
    if sha256_file(retained_ipa) != inspection["field_evidence"]["ipaSHA256"]:
        retained_ipa.unlink(missing_ok=True)
        raise EvidenceError("retained IPA bytes diverged from inspected input")
    external_path.write_bytes(inspection["external_bytes"])
    if sha256_file(external_path) != inspection["field_evidence"]["externalBuildRecordSHA256"]:
        raise EvidenceError("written external build record digest diverged from field evidence")
    field_path.write_bytes(canonical_json_bytes(inspection["field_evidence"]))
    return {"retained_ipa": retained_ipa, "external_record": external_path, "field_evidence": field_path}


def self_test() -> None:
    sha = "a" * 40
    assert canonical_sha40(sha) == sha
    assert expected_build_identifier(sha) == "Capture Build V14-aaaaaaaaaaaa"
    assert canonical_uuid("12345678-1234-4abc-8def-1234567890ab") == "12345678-1234-4abc-8def-1234567890ab"
    assert valid_build_identifier("Capture Build V14-aaaaaaaaaaaa")
    assert not valid_build_identifier(" Capture Build V14-aaaaaaaaaaaa")
    for bad in (
        "../Payload/Nembra.app",
        "/Payload/Nembra.app",
        "Payload/../Nembra.app",
        "Payload//Nembra.app/Info.plist",
        "Payload/./Nembra.app/Info.plist",
        "Payload\\Nembra.app\\Info.plist",
    ):
        try:
            _safe_member_path(bad)
        except EvidenceError:
            pass
        else:
            raise AssertionError(f"unsafe ZIP member was accepted: {bad}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, help="exact already-produced signed Nembra .ipa")
    parser.add_argument("--output-dir", type=Path, help="directory for immutable external evidence")
    parser.add_argument("--expected-source-sha", help="exact accepted lowercase 40-hex source commit expected inside the field build")
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
        for name, value in (("--ipa", args.ipa), ("--output-dir", args.output_dir), ("--expected-source-sha", args.expected_source_sha))
        if value is None
    ]
    if missing:
        raise EvidenceError(f"required arguments missing: {', '.join(missing)}")

    inspection = inspect_ipa(args.ipa.resolve(), args.expected_source_sha)
    paths = write_outputs(args.ipa.resolve(), args.output_dir.resolve(), inspection)
    summary = {
        "status": "EVIDENCE_ONLY_NOT_FIELD_AUTHORIZATION",
        "sourceCommitSHA": inspection["field_evidence"]["sourceCommitSHA"],
        "buildInstanceID": inspection["field_evidence"]["buildInstanceID"],
        "ipaSHA256": inspection["field_evidence"]["ipaSHA256"],
        "externalBuildRecord": str(paths["external_record"]),
        "signedFieldArtifactEvidence": str(paths["field_evidence"]),
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
