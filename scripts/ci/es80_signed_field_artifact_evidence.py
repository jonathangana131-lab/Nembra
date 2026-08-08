#!/usr/bin/env python3
"""Produce fail-closed evidence for an already-built signed Nembra field IPA.

This tool never authorizes physical Experiment One. It measures and preserves an exact
installable artifact, verifies its iPhone code signature, provisioning relationship, and embedded
Nembra build declarations, and emits external evidence that a separate trusted acceptance step may
attest/review.
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
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
BUNDLE_ID = "com.jonathangana131.nembra"
EXTERNAL_RECORD_SCHEMA_VERSION = 3
FIELD_EVIDENCE_SCHEMA_VERSION = 2
AUTHORITY_LABEL = "signed-field-artifact-evidence-not-field-authorization"

SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
TEAM_IDENTIFIER_RE = re.compile(r"^[A-Z0-9]{10}$")
CDHASH_RE = re.compile(r"^[0-9a-f]{40,64}$")


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


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n"


def _safe_member_path(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if not name or path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise EvidenceError(f"IPA contains unsafe ZIP member path: {name!r}")
    return path


def extract_ipa_safely(ipa_path: Path, destination: Path) -> Path:
    try:
        archive = zipfile.ZipFile(ipa_path)
    except (OSError, zipfile.BadZipFile) as exc:
        raise EvidenceError("input is not a readable IPA/ZIP archive") from exc

    app_roots: set[str] = set()
    seen_members: set[str] = set()
    with archive:
        for info in archive.infolist():
            member_name = info.filename.rstrip("/")
            member = _safe_member_path(member_name)
            canonical_member = str(member)
            if canonical_member in seen_members:
                raise EvidenceError(f"IPA contains duplicate ZIP member path: {info.filename}")
            seen_members.add(canonical_member)

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


def validate_provisioning_profile(
    profile: dict,
    *,
    team_identifier: str,
    bundle_identifier: str,
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
    )
    return profile_sha256, profile_uuid, expiration_utc, application_identifier


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

    field_evidence = {
        "schemaVersion": FIELD_EVIDENCE_SCHEMA_VERSION,
        "authority": AUTHORITY_LABEL,
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
        "ipaSHA256": ipa_sha,
        "ipaByteCount": ipa_size,
        "executableSHA256": executable_sha,
        "infoPlistSHA256": info_plist_sha,
        "externalBuildRecordSHA256": hashlib.sha256(external_bytes).hexdigest(),
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    return {
        "external_record": external_record,
        "external_bytes": external_bytes,
        "field_evidence": field_evidence,
    }


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
    actual_external_sha = sha256_file(external_path)
    if actual_external_sha != inspection["field_evidence"]["externalBuildRecordSHA256"]:
        raise EvidenceError("written external build record digest diverged from field evidence")

    field_path.write_bytes(canonical_json_bytes(inspection["field_evidence"]))
    return {
        "retained_ipa": retained_ipa,
        "external_record": external_path,
        "field_evidence": field_path,
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

    team = "ABCDE12345"
    expiry = datetime(2099, 1, 1, tzinfo=timezone.utc)
    valid_profile = {
        "TeamIdentifier": [team],
        "UUID": "PROFILE-UUID",
        "ExpirationDate": expiry,
        "Entitlements": {
            "application-identifier": f"{team}.{BUNDLE_ID}",
            "com.apple.developer.team-identifier": team,
        },
    }
    profile_uuid, expiration_utc, application_id = validate_provisioning_profile(
        valid_profile,
        team_identifier=team,
        bundle_identifier=BUNDLE_ID,
        now=datetime(2098, 1, 1, tzinfo=timezone.utc),
    )
    assert profile_uuid == "PROFILE-UUID"
    assert expiration_utc == "2099-01-01T00:00:00Z"
    assert application_id == f"{team}.{BUNDLE_ID}"

    for malformed in (
        {**valid_profile, "TeamIdentifier": ["OTHER12345"]},
        {**valid_profile, "ExpirationDate": datetime(2097, 1, 1, tzinfo=timezone.utc)},
        {
            **valid_profile,
            "Entitlements": {
                **valid_profile["Entitlements"],
                "application-identifier": f"{team}.com.example.other",
            },
        },
    ):
        try:
            validate_provisioning_profile(
                malformed,
                team_identifier=team,
                bundle_identifier=BUNDLE_ID,
                now=datetime(2098, 1, 1, tzinfo=timezone.utc),
            )
        except EvidenceError:
            pass
        else:
            raise AssertionError("invalid provisioning profile relationship was accepted")


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
        "sourceCommitSHA": inspection["field_evidence"]["sourceCommitSHA"],
        "buildInstanceID": inspection["field_evidence"]["buildInstanceID"],
        "ipaSHA256": inspection["field_evidence"]["ipaSHA256"],
        "teamIdentifier": inspection["field_evidence"]["teamIdentifier"],
        "provisioningProfileUUID": inspection["field_evidence"]["provisioningProfileUUID"],
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
