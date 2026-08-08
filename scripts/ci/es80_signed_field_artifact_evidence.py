#!/usr/bin/env python3
"""Produce fail-closed evidence for an already-built signed Nembra field IPA.

This tool never authorizes physical Experiment One. It measures and preserves an exact
installable artifact, verifies its iPhone code signature and embedded Nembra build declarations,
and emits external evidence that a separate trusted acceptance step may attest/review.
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
import warnings
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
BUNDLE_ID = "com.jonathangana131.nembra"
EXTERNAL_RECORD_SCHEMA_VERSION = 3
FIELD_EVIDENCE_SCHEMA_VERSION = 1
AUTHORITY_LABEL = "signed-field-artifact-evidence-not-field-authorization"

SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
TEAM_IDENTIFIER_RE = re.compile(r"^[A-Z0-9]{10}$")


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
            member = _safe_member_path(info.filename.rstrip("/"))
            normalized_member = member.as_posix()
            if normalized_member in seen_members:
                raise EvidenceError(
                    f"IPA contains duplicate ZIP member path: {normalized_member!r}"
                )
            seen_members.add(normalized_member)

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


def validate_signing_contract(
    team_identifier: str,
    bundle_identifier: str,
    provisioning_profile: dict,
    signed_entitlements: dict,
    *,
    now: datetime | None = None,
) -> None:
    if not TEAM_IDENTIFIER_RE.fullmatch(team_identifier):
        raise EvidenceError("field IPA code signature TeamIdentifier is malformed")

    profile_teams = provisioning_profile.get("TeamIdentifier")
    if not isinstance(profile_teams, list) or team_identifier not in profile_teams:
        raise EvidenceError(
            "embedded provisioning profile TeamIdentifier does not match the code signature"
        )

    expiration = provisioning_profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise EvidenceError("embedded provisioning profile ExpirationDate is missing")
    if expiration.tzinfo is None:
        expiration_utc = expiration.replace(tzinfo=timezone.utc)
    else:
        expiration_utc = expiration.astimezone(timezone.utc)
    comparison_time = now or datetime.now(timezone.utc)
    if comparison_time.tzinfo is None:
        comparison_time = comparison_time.replace(tzinfo=timezone.utc)
    else:
        comparison_time = comparison_time.astimezone(timezone.utc)
    if expiration_utc <= comparison_time:
        raise EvidenceError("embedded provisioning profile is expired")

    profile_entitlements = provisioning_profile.get("Entitlements")
    if not isinstance(profile_entitlements, dict):
        raise EvidenceError("embedded provisioning profile Entitlements are missing")

    expected_application_identifier = f"{team_identifier}.{bundle_identifier}"
    if profile_entitlements.get("application-identifier") != expected_application_identifier:
        raise EvidenceError(
            "embedded provisioning profile application-identifier does not match the signed Nembra bundle"
        )
    if (
        profile_entitlements.get("com.apple.developer.team-identifier")
        != team_identifier
    ):
        raise EvidenceError(
            "embedded provisioning profile developer team entitlement does not match the code signature"
        )

    if signed_entitlements.get("application-identifier") != expected_application_identifier:
        raise EvidenceError(
            "signed app effective application-identifier does not match the code signature and bundle"
        )
    if signed_entitlements.get("com.apple.developer.team-identifier") != team_identifier:
        raise EvidenceError(
            "signed app effective developer team entitlement does not match the code signature"
        )


def run_codesign(app_path: Path, bundle_identifier: str) -> tuple[str, list[str]]:
    if sys.platform != "darwin":
        raise EvidenceError("signed field IPA inspection requires macOS code-signing tools")
    codesign = shutil.which("codesign")
    security = shutil.which("security")
    if not codesign:
        raise EvidenceError("codesign is not available")
    if not security:
        raise EvidenceError("security is not available")

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

    profile_path = app_path / "embedded.mobileprovision"
    if not profile_path.is_file():
        raise EvidenceError("signed field IPA is missing embedded.mobileprovision")
    decoded_profile = subprocess.run(
        [security, "cms", "-D", "-i", str(profile_path)],
        capture_output=True,
        check=False,
    )
    if decoded_profile.returncode != 0:
        detail = (decoded_profile.stderr or decoded_profile.stdout).decode(
            "utf-8", errors="replace"
        ).strip()
        raise EvidenceError(f"embedded provisioning profile could not be decoded: {detail}")
    try:
        provisioning_profile = plistlib.loads(decoded_profile.stdout)
    except Exception as exc:
        raise EvidenceError("decoded embedded provisioning profile is not a valid plist") from exc
    if not isinstance(provisioning_profile, dict):
        raise EvidenceError("decoded embedded provisioning profile root is not a dictionary")

    entitlements_result = subprocess.run(
        [codesign, "-d", "--entitlements", ":-", str(app_path)],
        capture_output=True,
        check=False,
    )
    if entitlements_result.returncode != 0:
        detail = (entitlements_result.stderr or entitlements_result.stdout).decode(
            "utf-8", errors="replace"
        ).strip()
        raise EvidenceError(f"signed app entitlements inspection failed: {detail}")
    try:
        signed_entitlements = plistlib.loads(entitlements_result.stdout)
    except Exception as exc:
        raise EvidenceError("signed app effective entitlements are not a readable plist") from exc
    if not isinstance(signed_entitlements, dict):
        raise EvidenceError("signed app effective entitlements root is not a dictionary")

    validate_signing_contract(
        team_identifier,
        bundle_identifier,
        provisioning_profile,
        signed_entitlements,
    )
    return team_identifier, authorities


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

        team_identifier, signing_authorities = run_codesign(app_path, bundle_id)
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

    with tempfile.TemporaryDirectory(prefix="nembra-field-self-test-") as temporary:
        duplicate_ipa = Path(temporary) / "duplicate.ipa"
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(duplicate_ipa, "w") as archive:
                archive.writestr("Payload/Nembra.app/Info.plist", b"first")
                archive.writestr("Payload/Nembra.app/Info.plist", b"second")
        try:
            extract_ipa_safely(duplicate_ipa, Path(temporary) / "extract")
        except EvidenceError as error:
            assert "duplicate ZIP member path" in str(error)
        else:
            raise AssertionError("duplicate ZIP member path must fail closed")

    team = "ABCDEFGHIJ"
    bundle = BUNDLE_ID
    expected_application_identifier = f"{team}.{bundle}"
    profile = {
        "TeamIdentifier": [team],
        "ExpirationDate": datetime(2100, 1, 1, tzinfo=timezone.utc),
        "Entitlements": {
            "application-identifier": expected_application_identifier,
            "com.apple.developer.team-identifier": team,
        },
    }
    signed_entitlements = {
        "application-identifier": expected_application_identifier,
        "com.apple.developer.team-identifier": team,
    }
    validate_signing_contract(
        team,
        bundle,
        profile,
        signed_entitlements,
        now=datetime(2099, 1, 1, tzinfo=timezone.utc),
    )
    try:
        validate_signing_contract(
            team,
            bundle,
            profile,
            {
                **signed_entitlements,
                "application-identifier": f"{team}.example.detached",
            },
            now=datetime(2099, 1, 1, tzinfo=timezone.utc),
        )
    except EvidenceError:
        pass
    else:
        raise AssertionError("detached signed application-identifier must fail closed")


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
