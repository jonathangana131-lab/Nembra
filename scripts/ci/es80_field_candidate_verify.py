#!/usr/bin/env python3
"""Fail-closed verification for one exact signed Nembra iOS field-build candidate.

The canonical output is the package-owned V14 field-build evidence schema plus the existing
schema-v3 external build record. Apple signing/provisioning facts are retained separately as
supporting evidence. Nothing produced here authorizes physical ES80 Experiment One.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Callable

EXTERNAL_SCHEMA_VERSION = 3
FIELD_EVIDENCE_SCHEMA_VERSION = 1
SIGNING_EVIDENCE_SCHEMA_VERSION = 1
RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
EXPECTED_BUNDLE_ID = "com.jonathangana131.nembra"
EXPECTED_PLATFORM_NAME = "iphoneos"
EXPECTED_SUPPORTED_PLATFORM = "iPhoneOS"
INSTALLABLE_KIND = "ipa"
SIGNING_STATUS = "signing-evidence-only-no-go"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
TEAM = re.compile(r"^[A-Z0-9]{10}$")
CDHASH = re.compile(r"^[0-9a-fA-F]{40,64}$")


class VerificationError(RuntimeError):
    pass


@dataclass(frozen=True)
class EmbeddedBuildIdentity:
    build_identifier: str
    build_instance_id: str
    source_commit_sha: str
    bundle_identifier: str
    executable_name: str
    platform_name: str
    supported_platforms: tuple[str, ...]


@dataclass(frozen=True)
class SigningEvidence:
    team_identifier: str
    code_directory_hash: str
    provisioning_profile_uuid: str
    provisioning_profile_expiration_utc: str
    provisioning_profile_sha256: str
    provisioning_profile_bytes: bytes


@dataclass(frozen=True)
class CandidateEvidence:
    identity: EmbeddedBuildIdentity
    signing: SigningEvidence
    ipa_sha256: str
    executable_sha256: str
    info_plist_sha256: str
    executable_bytes: bytes
    info_plist_bytes: bytes


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n"


def require_sha40(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA40.fullmatch(value):
        raise VerificationError(f"{label} must be one exact lowercase 40-hex Git SHA")
    return value


def require_uuid(value: object, label: str) -> str:
    if (
        not isinstance(value, str)
        or value != value.strip()
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
    ):
        raise VerificationError(f"{label} must be unpadded canonical lowercase UUID text")
    try:
        canonical = str(uuid.UUID(value))
    except (ValueError, AttributeError) as exc:
        raise VerificationError(f"{label} must be one canonical UUID") from exc
    if value != canonical:
        raise VerificationError(f"{label} must be canonical lowercase UUID text")
    return value


def expected_build_identifier(source_sha: str) -> str:
    return f"Capture Build V14-{source_sha[:12]}"


def require_build_identifier(value: object, source_sha: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip() or len(value.encode("utf-8")) > 128:
        raise VerificationError("NembraCaptureBuildIdentifier is blank, padded, or oversized")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise VerificationError("NembraCaptureBuildIdentifier contains control characters")
    expected = expected_build_identifier(source_sha)
    if value != expected:
        raise VerificationError(
            f"NembraCaptureBuildIdentifier does not match exact source: {value!r} != {expected!r}"
        )
    return value


def safe_member(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if not name or path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise VerificationError(f"IPA contains unsafe archive path: {name!r}")
    return path


def reject_symlink(info: zipfile.ZipInfo) -> None:
    mode = (info.external_attr >> 16) & 0xFFFF
    if (mode & 0o170000) == 0o120000:
        raise VerificationError(f"IPA contains unsupported symlink entry: {info.filename}")


def inspect_members(
    archive: zipfile.ZipFile,
    expected_source_sha: str,
) -> tuple[str, bytes, bytes, EmbeddedBuildIdentity]:
    files = [info for info in archive.infolist() if not info.is_dir()]
    names: list[str] = []
    for info in files:
        names.append(str(safe_member(info.filename)))
        reject_symlink(info)

    plists = [name for name in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
    if len(plists) != 1:
        raise VerificationError("IPA must contain exactly one Payload/<app>.app/Info.plist")

    info_name = plists[0]
    prefix = info_name[: -len("Info.plist")]
    info_bytes = archive.read(info_name)
    try:
        plist = plistlib.loads(info_bytes)
    except Exception as exc:
        raise VerificationError("IPA Info.plist is not a valid plist") from exc
    if not isinstance(plist, dict):
        raise VerificationError("IPA Info.plist root must be a dictionary")

    executable = plist.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable or "/" in executable or executable in {".", ".."}:
        raise VerificationError("CFBundleExecutable is missing or invalid")
    executable_member = f"{prefix}{executable}"
    if executable_member not in names:
        raise VerificationError("IPA does not contain the executable named by CFBundleExecutable")

    bundle_identifier = plist.get("CFBundleIdentifier")
    if bundle_identifier != EXPECTED_BUNDLE_ID:
        raise VerificationError(
            f"Field candidate bundle identifier must be {EXPECTED_BUNDLE_ID!r}; got {bundle_identifier!r}"
        )

    platform_name = plist.get("DTPlatformName")
    supported = plist.get("CFBundleSupportedPlatforms")
    supported_platforms = tuple(item for item in supported if isinstance(item, str)) if isinstance(supported, list) else ()
    if platform_name != EXPECTED_PLATFORM_NAME:
        raise VerificationError(
            f"Field candidate must declare DTPlatformName={EXPECTED_PLATFORM_NAME}; got {platform_name!r}"
        )
    if EXPECTED_SUPPORTED_PLATFORM not in supported_platforms or any(
        "Simulator" in item for item in supported_platforms
    ):
        raise VerificationError(
            f"Field candidate must support iPhoneOS and not Simulator; got {supported_platforms!r}"
        )

    embedded_source_sha = require_sha40(
        plist.get("NembraCaptureBuildCommitSHA"),
        "NembraCaptureBuildCommitSHA",
    )
    if embedded_source_sha != expected_source_sha:
        raise VerificationError(
            "Embedded NembraCaptureBuildCommitSHA does not equal the exact repository HEAD"
        )

    identity = EmbeddedBuildIdentity(
        build_identifier=require_build_identifier(
            plist.get("NembraCaptureBuildIdentifier"), expected_source_sha
        ),
        build_instance_id=require_uuid(
            plist.get("NembraCaptureBuildInstanceID"), "NembraCaptureBuildInstanceID"
        ),
        source_commit_sha=embedded_source_sha,
        bundle_identifier=bundle_identifier,
        executable_name=executable,
        platform_name=platform_name,
        supported_platforms=supported_platforms,
    )
    return prefix.rstrip("/"), info_bytes, archive.read(executable_member), identity


def extract_safe(archive: zipfile.ZipFile, root: Path) -> None:
    for info in archive.infolist():
        path = safe_member(info.filename.rstrip("/"))
        reject_symlink(info)
        destination = root.joinpath(*path.parts)
        if root.resolve() not in (destination.parent.resolve(), *destination.parent.resolve().parents):
            raise VerificationError(f"IPA member escapes extraction root: {info.filename!r}")
        if info.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(info) as source, destination.open("wb") as sink:
            shutil.copyfileobj(source, sink)
        permissions = ((info.external_attr >> 16) & 0xFFFF) & 0o777
        if permissions:
            os.chmod(destination, permissions)


def run(command: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        raise VerificationError(
            f"Command failed ({' '.join(command)}): {(result.stderr or result.stdout).strip()}"
        )
    return result


def probe_signing(app: Path, bundle_identifier: str) -> SigningEvidence:
    if (
        sys.platform != "darwin"
        or not Path("/usr/bin/codesign").exists()
        or not Path("/usr/bin/security").exists()
    ):
        raise VerificationError("codesign/provisioning verification requires macOS Apple signing tools")

    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=4", str(app)])
    detail = run(["/usr/bin/codesign", "-d", "--verbose=4", str(app)])
    text = f"{detail.stdout}\n{detail.stderr}"
    if re.search(r"(?m)^Signature=adhoc\s*$", text):
        raise VerificationError("Ad-hoc signatures cannot become a physical field-build candidate")

    team_match = re.search(r"^TeamIdentifier=([^\r\n]+)$", text, re.MULTILINE)
    cdhash_match = re.search(r"^CDHash=([^\r\n]+)$", text, re.MULTILINE)
    if not team_match or not cdhash_match:
        raise VerificationError("codesign output is missing TeamIdentifier or CDHash")
    team = team_match.group(1).strip()
    cdhash = cdhash_match.group(1).strip().lower()
    if not TEAM.fullmatch(team) or not CDHASH.fullmatch(cdhash):
        raise VerificationError("codesign identity is malformed")

    profile_path = app / "embedded.mobileprovision"
    if not profile_path.is_file():
        raise VerificationError("Signed field candidate is missing embedded.mobileprovision")
    profile_bytes = profile_path.read_bytes()
    decoded = run(["/usr/bin/security", "cms", "-D", "-i", str(profile_path)]).stdout.encode()
    try:
        profile = plistlib.loads(decoded)
    except Exception as exc:
        raise VerificationError("Could not decode embedded provisioning profile") from exc
    if (
        not isinstance(profile, dict)
        or not isinstance(profile.get("TeamIdentifier"), list)
        or team not in profile["TeamIdentifier"]
    ):
        raise VerificationError(
            "Provisioning profile TeamIdentifier does not match the code signature"
        )

    profile_uuid = profile.get("UUID")
    expiration = profile.get("ExpirationDate")
    entitlements = profile.get("Entitlements")
    if not isinstance(profile_uuid, str) or not profile_uuid:
        raise VerificationError("Provisioning profile UUID is missing")
    if not isinstance(expiration, datetime):
        raise VerificationError("Provisioning profile ExpirationDate is missing")
    expiration = expiration.astimezone(timezone.utc)
    if expiration <= datetime.now(timezone.utc):
        raise VerificationError("Provisioning profile is expired")
    if (
        not isinstance(entitlements, dict)
        or entitlements.get("application-identifier") != f"{team}.{bundle_identifier}"
    ):
        raise VerificationError(
            "Provisioning profile application-identifier does not match the signed Nembra bundle"
        )

    return SigningEvidence(
        team_identifier=team,
        code_directory_hash=cdhash,
        provisioning_profile_uuid=profile_uuid,
        provisioning_profile_expiration_utc=expiration.isoformat().replace("+00:00", "Z"),
        provisioning_profile_sha256=sha_bytes(profile_bytes),
        provisioning_profile_bytes=profile_bytes,
    )


def reject_embedded_external_authority(app: Path) -> None:
    forbidden = {
        "NembraCaptureTrustedBuildRecord.json",
        "NembraCaptureExternalBuildRecord.json",
        "NembraCaptureFieldBuildEvidenceRecord.json",
        "NembraCaptureSignedFieldArtifactEvidence.json",
    }
    hits = sorted(path.name for path in app.rglob("*") if path.is_file() and path.name in forbidden)
    if hits:
        raise VerificationError(
            "Final artifact/build-acceptance evidence must remain outside the signed app bundle; "
            f"found {hits!r}"
        )


def inspect_candidate(
    ipa: Path,
    expected_source_sha: str,
    *,
    signing_probe: Callable[[Path, str], SigningEvidence] = probe_signing,
) -> CandidateEvidence:
    expected_source_sha = require_sha40(expected_source_sha, "exact repository HEAD")
    if not ipa.is_file() or ipa.suffix.lower() != ".ipa":
        raise VerificationError("--ipa must name one existing .ipa file")

    try:
        with zipfile.ZipFile(ipa) as archive:
            prefix, info_bytes, executable_bytes, identity = inspect_members(
                archive, expected_source_sha
            )
            with tempfile.TemporaryDirectory(prefix="nembra-field-candidate-") as temporary:
                root = Path(temporary)
                extract_safe(archive, root)
                app = root.joinpath(*PurePosixPath(prefix).parts)
                if not app.is_dir():
                    raise VerificationError("Extracted Nembra .app bundle is missing")
                reject_embedded_external_authority(app)
                signing = signing_probe(app, identity.bundle_identifier)
    except zipfile.BadZipFile as exc:
        raise VerificationError("IPA is not a valid ZIP archive") from exc

    return CandidateEvidence(
        identity=identity,
        signing=signing,
        ipa_sha256=sha_file(ipa),
        executable_sha256=sha_bytes(executable_bytes),
        info_plist_sha256=sha_bytes(info_bytes),
        executable_bytes=executable_bytes,
        info_plist_bytes=info_bytes,
    )


def external_build_record(evidence: CandidateEvidence) -> dict[str, object]:
    return {
        "schemaVersion": EXTERNAL_SCHEMA_VERSION,
        "buildIdentifier": evidence.identity.build_identifier,
        "buildInstanceID": evidence.identity.build_instance_id,
        "sourceCommitSHA": evidence.identity.source_commit_sha,
        "executableSHA256": evidence.executable_sha256,
        "infoPlistSHA256": evidence.info_plist_sha256,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }


def field_build_evidence_record(
    evidence: CandidateEvidence,
    exact_external_record_bytes: bytes,
) -> dict[str, object]:
    return {
        "schemaVersion": FIELD_EVIDENCE_SCHEMA_VERSION,
        "externalBuildRecordSHA256": sha_bytes(exact_external_record_bytes),
        "signedInstallableSHA256": evidence.ipa_sha256,
        "signedInstallableKind": INSTALLABLE_KIND,
        "buildIdentifier": evidence.identity.build_identifier,
        "buildInstanceID": evidence.identity.build_instance_id,
        "sourceCommitSHA": evidence.identity.source_commit_sha,
        "executableSHA256": evidence.executable_sha256,
        "infoPlistSHA256": evidence.info_plist_sha256,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }


def signing_evidence_record(evidence: CandidateEvidence) -> dict[str, object]:
    return {
        "schemaVersion": SIGNING_EVIDENCE_SCHEMA_VERSION,
        "status": SIGNING_STATUS,
        "bundleIdentifier": evidence.identity.bundle_identifier,
        "platformName": evidence.identity.platform_name,
        "supportedPlatforms": list(evidence.identity.supported_platforms),
        "teamIdentifier": evidence.signing.team_identifier,
        "codeDirectoryHash": evidence.signing.code_directory_hash,
        "provisioningProfileUUID": evidence.signing.provisioning_profile_uuid,
        "provisioningProfileExpirationUTC": evidence.signing.provisioning_profile_expiration_utc,
        "provisioningProfileSHA256": evidence.signing.provisioning_profile_sha256,
        "signedInstallableSHA256": evidence.ipa_sha256,
        "buildInstanceID": evidence.identity.build_instance_id,
        "sourceCommitSHA": evidence.identity.source_commit_sha,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }


def exact_head(root: Path) -> str:
    return require_sha40(
        run(["git", "rev-parse", "--verify", "HEAD^{commit}"], root).stdout.strip(),
        "repository HEAD",
    )


def require_pristine(root: Path) -> None:
    if run(["git", "status", "--porcelain=v1", "--untracked-files=all"], root).stdout:
        raise VerificationError(
            "Field candidate verification refuses tracked or non-ignored untracked repository inputs"
        )


def retain_candidate(ipa: Path, output: Path, evidence: CandidateEvidence) -> dict[str, Path]:
    output.mkdir(parents=True, exist_ok=True)
    retained_dir = output / "build-evidence"
    retained_dir.mkdir(parents=True, exist_ok=True)

    retained_ipa = retained_dir / "NembraField.ipa"
    retained_executable = retained_dir / "Nembra"
    retained_info = retained_dir / "Info.plist"
    retained_profile = retained_dir / "embedded.mobileprovision"
    external_record_path = output / "NembraCaptureExternalBuildRecord.json"
    field_record_path = output / "NembraCaptureFieldBuildEvidenceRecord.json"
    signing_record_path = output / "NembraCaptureFieldSigningEvidence.json"
    boundary_path = output / "PHYSICAL_NO_GO.txt"

    targets = (
        retained_ipa,
        retained_executable,
        retained_info,
        retained_profile,
        external_record_path,
        field_record_path,
        signing_record_path,
        boundary_path,
    )
    existing = [str(path) for path in targets if path.exists()]
    if existing:
        raise VerificationError(f"refusing to overwrite existing field evidence: {existing!r}")

    external_bytes = canonical_json_bytes(external_build_record(evidence))
    field_bytes = canonical_json_bytes(field_build_evidence_record(evidence, external_bytes))
    signing_bytes = canonical_json_bytes(signing_evidence_record(evidence))

    shutil.copyfile(ipa, retained_ipa)
    retained_executable.write_bytes(evidence.executable_bytes)
    retained_info.write_bytes(evidence.info_plist_bytes)
    retained_profile.write_bytes(evidence.signing.provisioning_profile_bytes)
    external_record_path.write_bytes(external_bytes)
    field_record_path.write_bytes(field_bytes)
    signing_record_path.write_bytes(signing_bytes)
    boundary_path.write_text(
        "PHYSICAL EXPERIMENT ONE: NO-GO.\n"
        "Signed-device field-build evidence only. Not independent acceptance, not a GO record, "
        "and not authorization to run the ES80 procedure.\n",
        encoding="utf-8",
    )

    expected_hashes = {
        retained_ipa: evidence.ipa_sha256,
        retained_executable: evidence.executable_sha256,
        retained_info: evidence.info_plist_sha256,
        retained_profile: evidence.signing.provisioning_profile_sha256,
        external_record_path: sha_bytes(external_bytes),
        field_record_path: sha_bytes(field_bytes),
        signing_record_path: sha_bytes(signing_bytes),
    }
    for path, expected in expected_hashes.items():
        actual = sha_file(path)
        if actual != expected:
            raise VerificationError(
                f"Retained field evidence diverged after write for {path.name}: {actual} != {expected}"
            )

    decoded_field = json.loads(field_record_path.read_text(encoding="utf-8"))
    if decoded_field.get("externalBuildRecordSHA256") != sha_file(external_record_path):
        raise VerificationError("Field-build evidence no longer binds the exact external record bytes")
    if decoded_field.get("signedInstallableSHA256") != sha_file(retained_ipa):
        raise VerificationError("Field-build evidence no longer binds the exact retained IPA bytes")

    return {
        "retainedIPA": retained_ipa,
        "externalBuildRecord": external_record_path,
        "fieldBuildEvidenceRecord": field_record_path,
        "signingEvidence": signing_record_path,
        "boundary": boundary_path,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("Artifacts/ES80FieldCandidate"),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    root = Path(__file__).resolve().parents[2]
    try:
        require_pristine(root)
        head = exact_head(root)
        evidence = inspect_candidate(args.ipa.resolve(), head)
        outputs = retain_candidate(args.ipa.resolve(), args.output_dir.resolve(), evidence)
    except VerificationError as exc:
        print(f"ES80 field candidate verification FAILED: {exc}", file=sys.stderr)
        return 2

    print(
        json.dumps(
            {
                "status": "EVIDENCE_ONLY_NOT_FIELD_AUTHORIZATION",
                "sourceCommitSHA": head,
                "buildInstanceID": evidence.identity.build_instance_id,
                "signedInstallableSHA256": evidence.ipa_sha256,
                **{key: str(value) for key, value in outputs.items()},
            },
            indent=2,
            sort_keys=True,
        )
    )
    print("PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
