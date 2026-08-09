#!/usr/bin/env python3
"""Independently cross-check a retained ES80 TODAY field candidate evidence set.

This tool is intentionally outside the signed candidate producer lineage. It re-hashes the
published candidate bytes and validates the canonical evidence-record linkage used by the TODAY
private field handoff. It does NOT repeat Apple's codesign/provisioning inspection and it never
authorizes physical Experiment One.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
BUNDLE_ID = "com.jonathangana131.nembra"
INSPECTION_AUTHORITY = "signed-field-artifact-inspection-not-field-authorization"
CROSSCHECK_AUTHORITY = "independent-retained-candidate-evidence-crosscheck-not-final-go"

SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_OID_RE = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
TEAM_RE = re.compile(r"^[A-Z0-9]{10}$")
CDHASH_RE = re.compile(r"^[0-9a-f]{40,64}$")
XCODE_27_RE = re.compile(r"^Xcode 27(?:\.[0-9]+)*(?: .+)?$")
XCODE_BUILD_RE = re.compile(r"^Build version \S+$")

EXTERNAL_KEYS = {
    "schemaVersion", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "executableSHA256", "infoPlistSHA256", "experimentRecipeID", "procedureVersion",
}
FIELD_KEYS = {
    "schemaVersion", "externalBuildRecordSHA256", "signedInstallableSHA256",
    "signedInstallableKind", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "executableSHA256", "infoPlistSHA256", "experimentRecipeID", "procedureVersion",
}
INSPECTION_KEYS = {
    "schemaVersion", "authority", "fieldBuildEvidenceRecordSHA256",
    "externalBuildRecordSHA256", "signedInstallableSHA256", "signedInstallableKind",
    "ipaByteCount", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
    "bundleIdentifier", "platformName", "supportedPlatforms", "teamIdentifier",
    "signingAuthorities", "codeDirectoryHash", "provisioningProfileSHA256",
    "provisioningProfileUUID", "provisioningProfileExpirationUTC",
    "provisioningApplicationIdentifier", "executableSHA256", "infoPlistSHA256",
    "experimentRecipeID", "procedureVersion",
}


class CrosscheckError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_regular_file(path: Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except OSError as exc:
        raise CrosscheckError(f"{label} is missing: {path}") from exc
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise CrosscheckError(f"{label} must be one regular non-symlink file: {path}")
    if metadata.st_size <= 0:
        raise CrosscheckError(f"{label} must be non-empty: {path}")


def reject_duplicate_object_pairs(pairs: Iterable[tuple[str, object]]) -> dict:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise CrosscheckError(f"JSON contains duplicate object key: {key}")
        result[key] = value
    return result


def load_exact_json(path: Path, *, label: str, expected_keys: set[str]) -> tuple[dict, bytes]:
    require_regular_file(path, label)
    data = path.read_bytes()
    try:
        decoded = json.loads(data, object_pairs_hook=reject_duplicate_object_pairs)
    except CrosscheckError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CrosscheckError(f"{label} is not valid UTF-8 JSON") from exc
    if not isinstance(decoded, dict):
        raise CrosscheckError(f"{label} root must be one JSON object")
    if set(decoded) != expected_keys:
        raise CrosscheckError(f"{label} schema shape drifted: {sorted(decoded)!r}")
    return decoded, data


def canonical_sha40(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA40_RE.fullmatch(value):
        raise CrosscheckError(f"{label} must be one lowercase 40-hex SHA")
    return value


def canonical_sha256(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        raise CrosscheckError(f"{label} must be one lowercase SHA-256")
    return value


def canonical_git_oid(value: object, label: str) -> str:
    if not isinstance(value, str) or not GIT_OID_RE.fullmatch(value):
        raise CrosscheckError(f"{label} must be one canonical lowercase Git object ID")
    return value


def canonical_uuid(value: object, label: str) -> str:
    if not isinstance(value, str) or not UUID_RE.fullmatch(value):
        raise CrosscheckError(f"{label} must be one canonical lowercase UUID")
    try:
        parsed = uuid.UUID(value)
    except ValueError as exc:
        raise CrosscheckError(f"{label} is not a valid UUID") from exc
    if str(parsed) != value:
        raise CrosscheckError(f"{label} is not canonical lowercase UUID text")
    return value


def parse_environment(path: Path) -> tuple[dict[str, str], str, str]:
    require_regular_file(path, "field candidate environment")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise CrosscheckError("field candidate environment is not readable UTF-8 text") from exc

    values: dict[str, str] = {}
    footer: list[str] = []
    for raw_line in lines:
        if "=" not in raw_line:
            if raw_line:
                footer.append(raw_line)
            continue
        key, value = raw_line.split("=", 1)
        if not key:
            raise CrosscheckError("field candidate environment contains an empty key")
        if key in values:
            raise CrosscheckError(f"field candidate environment contains duplicate key: {key}")
        values[key] = value

    if len(footer) != 2 or not XCODE_27_RE.fullmatch(footer[0]) or not XCODE_BUILD_RE.fullmatch(footer[1]):
        raise CrosscheckError(
            "field candidate environment must retain exactly one Xcode 27 version/build tuple"
        )
    return values, footer[0], footer[1]


def parse_expiration(value: object) -> datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise CrosscheckError("provisioningProfileExpirationUTC must be normalized UTC text")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise CrosscheckError("provisioningProfileExpirationUTC is malformed") from exc
    return parsed.astimezone(timezone.utc)


def candidate_paths(candidate_dir: Path) -> dict[str, Path]:
    return {
        "ipa": candidate_dir / "inspection" / "build-evidence" / "NembraField.ipa",
        "external": candidate_dir / "inspection" / "NembraCaptureExternalBuildRecord.json",
        "field": candidate_dir / "inspection" / "NembraCaptureFieldBuildEvidenceRecord.json",
        "inspection": candidate_dir / "inspection" / "NembraCaptureSignedFieldArtifactInspection.json",
        "environment": candidate_dir / "field-candidate-environment.txt",
        "export_options": candidate_dir / "ExportOptions.plist",
        "archive_log": candidate_dir / "logs" / "xcodebuild-archive.log",
        "export_log": candidate_dir / "logs" / "xcodebuild-export.log",
    }


def _all_ipas_and_reject_symlinks(candidate_dir: Path) -> list[Path]:
    result: list[Path] = []
    for root, dirs, files in os.walk(candidate_dir, followlinks=False):
        root_path = Path(root)
        for name in dirs:
            child = root_path / name
            if child.is_symlink():
                raise CrosscheckError(f"candidate contains symlink directory: {child}")
        for name in files:
            child = root_path / name
            if child.is_symlink():
                raise CrosscheckError(f"candidate contains symlink file: {child}")
            if name.lower().endswith(".ipa"):
                result.append(child)
    return sorted(result)


def crosscheck(candidate_dir: Path, *, expected_source_sha: str, now: datetime | None = None) -> dict:
    expected_source_sha = canonical_sha40(expected_source_sha, "expected source SHA")
    try:
        root_stat = candidate_dir.lstat()
    except OSError as exc:
        raise CrosscheckError(f"candidate directory is missing: {candidate_dir}") from exc
    if stat.S_ISLNK(root_stat.st_mode) or not stat.S_ISDIR(root_stat.st_mode):
        raise CrosscheckError("candidate directory must be one real non-symlink directory")

    paths = candidate_paths(candidate_dir)
    for key in ("ipa", "environment", "export_options", "archive_log", "export_log"):
        require_regular_file(paths[key], key.replace("_", " "))

    ipas = _all_ipas_and_reject_symlinks(candidate_dir)
    if ipas != [paths["ipa"]]:
        raise CrosscheckError(
            "candidate must contain exactly one IPA at inspection/build-evidence/NembraField.ipa; "
            f"found {[str(path.relative_to(candidate_dir)) for path in ipas]!r}"
        )

    external, external_bytes = load_exact_json(paths["external"], label="external build record", expected_keys=EXTERNAL_KEYS)
    field, field_bytes = load_exact_json(paths["field"], label="field-build evidence record", expected_keys=FIELD_KEYS)
    inspection, inspection_bytes = load_exact_json(paths["inspection"], label="signed-field artifact inspection", expected_keys=INSPECTION_KEYS)

    if external.get("schemaVersion") != 3:
        raise CrosscheckError("external build record schemaVersion must be 3")
    if field.get("schemaVersion") != 1:
        raise CrosscheckError("field-build evidence schemaVersion must be 1")
    if inspection.get("schemaVersion") != 2:
        raise CrosscheckError("signing inspection schemaVersion must be 2")

    build_instance = canonical_uuid(external.get("buildInstanceID"), "buildInstanceID")
    build_identifier = f"Capture Build V14-{expected_source_sha[:12]}"
    shared = {
        "sourceCommitSHA": expected_source_sha,
        "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    for record_name, record in (
        ("external build record", external),
        ("field-build evidence", field),
        ("signing inspection", inspection),
    ):
        for key, expected in shared.items():
            if record.get(key) != expected:
                raise CrosscheckError(f"{record_name} mismatch for {key}: {record.get(key)!r} != {expected!r}")

    for record_name, record in (("field-build evidence", field), ("signing inspection", inspection)):
        if record.get("signedInstallableKind") != "ipa":
            raise CrosscheckError(f"{record_name} must describe exactly one IPA installable")

    if inspection.get("authority") != INSPECTION_AUTHORITY:
        raise CrosscheckError("signing inspection authority boundary changed")
    if inspection.get("bundleIdentifier") != BUNDLE_ID:
        raise CrosscheckError("signing inspection bundle identifier changed")
    supported = inspection.get("supportedPlatforms")
    if (
        inspection.get("platformName") != "iphoneos"
        or not isinstance(supported, list)
        or "iPhoneOS" not in supported
        or any(not isinstance(item, str) for item in supported)
        or any("simulator" in item.casefold() for item in supported if isinstance(item, str))
    ):
        raise CrosscheckError("signing inspection does not describe a physical iPhone build")

    team = inspection.get("teamIdentifier")
    if not isinstance(team, str) or not TEAM_RE.fullmatch(team):
        raise CrosscheckError("signing inspection TeamIdentifier is malformed")
    if inspection.get("provisioningApplicationIdentifier") != f"{team}.{BUNDLE_ID}":
        raise CrosscheckError("provisioning application identifier disagrees with TeamIdentifier/bundle")
    canonical_sha256(inspection.get("provisioningProfileSHA256"), "provisioning profile SHA-256")
    if not isinstance(inspection.get("provisioningProfileUUID"), str) or not inspection["provisioningProfileUUID"].strip():
        raise CrosscheckError("provisioning profile UUID is missing")
    authorities = inspection.get("signingAuthorities")
    if not isinstance(authorities, list) or not authorities or not all(isinstance(item, str) and item.strip() for item in authorities):
        raise CrosscheckError("signing authority chain is missing")
    cdhash = inspection.get("codeDirectoryHash")
    if not isinstance(cdhash, str) or not CDHASH_RE.fullmatch(cdhash):
        raise CrosscheckError("CodeDirectory hash is malformed")

    expiry = parse_expiration(inspection.get("provisioningProfileExpirationUTC"))
    current = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    if expiry <= current:
        raise CrosscheckError("retained signing inspection describes an expired provisioning profile")

    ipa_sha = sha256_file(paths["ipa"])
    external_sha = hashlib.sha256(external_bytes).hexdigest()
    field_sha = hashlib.sha256(field_bytes).hexdigest()
    inspection_sha = hashlib.sha256(inspection_bytes).hexdigest()
    for label, value in (
        ("retained IPA SHA-256", ipa_sha),
        ("external record SHA-256", external_sha),
        ("field-build record SHA-256", field_sha),
        ("inspection SHA-256", inspection_sha),
    ):
        canonical_sha256(value, label)

    if field.get("externalBuildRecordSHA256") != external_sha:
        raise CrosscheckError("field-build evidence is not bound to exact external-record bytes")
    if inspection.get("externalBuildRecordSHA256") != external_sha:
        raise CrosscheckError("signing inspection is not bound to exact external-record bytes")
    if inspection.get("fieldBuildEvidenceRecordSHA256") != field_sha:
        raise CrosscheckError("signing inspection is not bound to exact field-build record bytes")
    if field.get("signedInstallableSHA256") != ipa_sha or inspection.get("signedInstallableSHA256") != ipa_sha:
        raise CrosscheckError("retained IPA bytes do not match canonical field/signing evidence")
    if inspection.get("ipaByteCount") != paths["ipa"].stat().st_size:
        raise CrosscheckError("retained IPA byte count disagrees with signing inspection")

    for key in ("executableSHA256", "infoPlistSHA256"):
        canonical_sha256(external.get(key), f"external {key}")
        if field.get(key) != external.get(key) or inspection.get(key) != external.get(key):
            raise CrosscheckError(f"evidence records disagree on exact {key}")

    environment, xcode_version, xcode_build = parse_environment(paths["environment"])
    required_environment = {
        "source_commit_sha": expected_source_sha,
        "build_identifier": build_identifier,
        "build_instance_id": build_instance,
        "field_launch_recipe_id": RECIPE_ID,
        "experiment_recipe_id": RECIPE_ID,
        "export_options_file": "ExportOptions.plist",
        "archive_log": "logs/xcodebuild-archive.log",
        "export_log": "logs/xcodebuild-export.log",
        "inspection_directory": "inspection",
        "procedure_version": PROCEDURE_VERSION,
        "signing_inspection_authority": INSPECTION_AUTHORITY,
        "physical_authorization": "not-granted",
    }
    for key, expected in required_environment.items():
        if environment.get(key) != expected:
            raise CrosscheckError(
                f"field candidate environment mismatch for {key}: {environment.get(key)!r} != {expected!r}"
            )
    if environment.get("development_team") != team:
        raise CrosscheckError("field candidate environment TeamIdentifier disagrees with signing inspection")
    if environment.get("allow_provisioning_updates") not in {"0", "1"}:
        raise CrosscheckError("allow_provisioning_updates must be exactly 0 or 1")

    private_runner_blob = canonical_git_oid(
        environment.get("private_runner_source_git_blob"), "private runner source Git blob"
    )
    inspector_blob = canonical_git_oid(
        environment.get("canonical_inspector_source_git_blob"), "canonical inspector source Git blob"
    )
    export_sha = sha256_file(paths["export_options"])
    if environment.get("export_options_sha256") != export_sha:
        raise CrosscheckError("retained ExportOptions.plist digest disagrees with producer environment record")

    return {
        "schemaVersion": 1,
        "authority": CROSSCHECK_AUTHORITY,
        "status": "PASS_NOT_FINAL_GO",
        "sourceCommitSHA": expected_source_sha,
        "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
        "signedInstallableSHA256": ipa_sha,
        "signedInstallableByteCount": paths["ipa"].stat().st_size,
        "externalBuildRecordSHA256": external_sha,
        "fieldBuildEvidenceRecordSHA256": field_sha,
        "signedFieldArtifactInspectionSHA256": inspection_sha,
        "executableSHA256": external["executableSHA256"],
        "infoPlistSHA256": external["infoPlistSHA256"],
        "exportOptionsSHA256": export_sha,
        "teamIdentifier": team,
        "allowProvisioningUpdates": environment["allow_provisioning_updates"],
        "privateRunnerSourceGitBlobClaim": private_runner_blob,
        "canonicalInspectorSourceGitBlobClaim": inspector_blob,
        "xcodeVersion": xcode_version,
        "xcodeBuildVersion": xcode_build,
        "provisioningProfileSHA256": inspection["provisioningProfileSHA256"],
        "provisioningProfileUUID": inspection["provisioningProfileUUID"],
        "provisioningProfileExpirationUTC": inspection["provisioningProfileExpirationUTC"],
        "singleRetainedIPA": True,
        "crossRecordDigestLinksVerified": True,
        "producerPhysicalAuthorizationRemainsNotGranted": True,
        "appleSigningInspectionRequired": True,
        "toolBlobClaimsRequireRepositoryCrossCheck": True,
        "exactRetainedIPAInstallHandoffRequired": True,
        "physicalExperimentAuthorization": "not-granted",
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate-dir", required=True, type=Path)
    parser.add_argument("--expected-source-sha", required=True)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    receipt = crosscheck(args.candidate_dir.expanduser().absolute(), expected_source_sha=args.expected_source_sha)
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except CrosscheckError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
