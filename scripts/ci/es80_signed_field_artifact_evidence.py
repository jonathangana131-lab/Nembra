#!/usr/bin/env python3
"""Produce fail-closed evidence for an already-built signed Nembra field IPA.

This tool never authorizes physical Experiment One. It measures and preserves one exact
installable artifact, verifies its iPhone code signature and embedded Nembra build declarations,
and emits:
1. the canonical package-consumable signed-field build-evidence record; and
2. separate non-authorizing signing/platform inspection metadata.

The final evidence directory is published only after the complete staged set re-verifies.
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
from pathlib import Path, PurePosixPath

RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
BUNDLE_ID = "com.jonathangana131.nembra"
EXTERNAL_RECORD_SCHEMA_VERSION = 3
FIELD_BUILD_EVIDENCE_SCHEMA_VERSION = 1
SIGNED_INSTALLABLE_KIND = "ipa"
SIGNING_INSPECTION_SCHEMA_VERSION = 1
SIGNING_INSPECTION_AUTHORITY = "signed-field-artifact-inspection-not-field-authorization"

EXTERNAL_RECORD_FILENAME = "NembraCaptureExternalBuildRecord.json"
FIELD_BUILD_EVIDENCE_FILENAME = "NembraCaptureFieldBuildEvidenceRecord.json"
SIGNING_INSPECTION_FILENAME = "NembraCaptureSignedFieldArtifactInspection.json"
RETAINED_IPA_RELATIVE_PATH = Path("build-evidence") / "NembraField.ipa"

FIELD_BUILD_EVIDENCE_FIELDS = {
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

SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)


class EvidenceError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


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
    seen_casefolded_members: set[str] = set()
    destination_root = destination.resolve()

    with archive:
        for info in archive.infolist():
            normalized_name = info.filename.rstrip("/")
            member = _safe_member_path(normalized_name)
            canonical_name = member.as_posix()
            folded_name = canonical_name.casefold()
            if canonical_name in seen_members or folded_name in seen_casefolded_members:
                raise EvidenceError(
                    f"IPA contains duplicate or case-colliding ZIP member path: {info.filename!r}"
                )
            seen_members.add(canonical_name)
            seen_casefolded_members.add(folded_name)

            mode = (info.external_attr >> 16) & 0o177777
            if stat.S_ISLNK(mode):
                raise EvidenceError(f"IPA contains unsupported symbolic-link member: {info.filename}")

            parts = member.parts
            if len(parts) >= 2 and parts[0] == "Payload" and parts[1].endswith(".app"):
                app_roots.add(parts[1])

            target = destination.joinpath(*parts)
            resolved_parent = target.parent.resolve()
            if destination_root not in (resolved_parent, *resolved_parent.parents):
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

    authorities = [
        match.group(1).strip()
        for match in re.finditer(r"(?m)^Authority=([^\r\n]+)$", metadata)
    ]
    if not authorities:
        raise EvidenceError("codesign metadata does not contain a signing authority chain")
    return team_identifier, authorities


def reject_embedded_external_authority(app_path: Path) -> None:
    forbidden = {
        "NembraCaptureTrustedBuildRecord.json",
        EXTERNAL_RECORD_FILENAME,
        FIELD_BUILD_EVIDENCE_FILENAME,
        SIGNING_INSPECTION_FILENAME,
        "NembraCaptureSignedFieldArtifactEvidence.json",
        "NembraCaptureFieldBuildCandidateRecord.json",
    }
    hits = sorted(path.name for path in app_path.rglob("*") if path.is_file() and path.name in forbidden)
    if hits:
        raise EvidenceError(
            "final executable-digest/field-acceptance evidence must stay outside the signed app bundle; "
            f"found {hits!r}"
        )


def make_external_build_record(
    *,
    build_identifier: str,
    build_instance_id: str,
    source_sha: str,
    executable_sha: str,
    info_plist_sha: str,
) -> dict[str, object]:
    return {
        "schemaVersion": EXTERNAL_RECORD_SCHEMA_VERSION,
        "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance_id,
        "sourceCommitSHA": source_sha,
        "executableSHA256": executable_sha,
        "infoPlistSHA256": info_plist_sha,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }


def make_field_build_evidence_record(
    *,
    external_record_bytes: bytes,
    signed_installable_sha: str,
    build_identifier: str,
    build_instance_id: str,
    source_sha: str,
    executable_sha: str,
    info_plist_sha: str,
) -> dict[str, object]:
    record = {
        "schemaVersion": FIELD_BUILD_EVIDENCE_SCHEMA_VERSION,
        "externalBuildRecordSHA256": sha256_bytes(external_record_bytes),
        "signedInstallableSHA256": signed_installable_sha,
        "signedInstallableKind": SIGNED_INSTALLABLE_KIND,
        "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance_id,
        "sourceCommitSHA": source_sha,
        "executableSHA256": executable_sha,
        "infoPlistSHA256": info_plist_sha,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    if set(record) != FIELD_BUILD_EVIDENCE_FIELDS:
        raise EvidenceError("internal field-build evidence schema drifted from the package contract")
    return record


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
                f"embedded build identifier does not match accepted source: "
                f"{build_identifier!r} != {expected_identifier!r}"
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

        team_identifier, signing_authorities = run_codesign(app_path)
        executable_sha = sha256_file(executable_path)
        info_plist_sha = sha256_file(info_path)
        if not SHA256_RE.fullmatch(executable_sha) or not SHA256_RE.fullmatch(info_plist_sha):
            raise EvidenceError("could not derive canonical executable/Info.plist SHA-256")

    external_record = make_external_build_record(
        build_identifier=build_identifier,
        build_instance_id=build_instance_id,
        source_sha=source_sha,
        executable_sha=executable_sha,
        info_plist_sha=info_plist_sha,
    )
    external_bytes = canonical_json_bytes(external_record)

    field_build_record = make_field_build_evidence_record(
        external_record_bytes=external_bytes,
        signed_installable_sha=ipa_sha,
        build_identifier=build_identifier,
        build_instance_id=build_instance_id,
        source_sha=source_sha,
        executable_sha=executable_sha,
        info_plist_sha=info_plist_sha,
    )
    field_build_bytes = canonical_json_bytes(field_build_record)

    signing_inspection = {
        "schemaVersion": SIGNING_INSPECTION_SCHEMA_VERSION,
        "authority": SIGNING_INSPECTION_AUTHORITY,
        "fieldBuildEvidenceRecordSHA256": sha256_bytes(field_build_bytes),
        "externalBuildRecordSHA256": sha256_bytes(external_bytes),
        "signedInstallableSHA256": ipa_sha,
        "ipaByteCount": ipa_size,
        "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance_id,
        "sourceCommitSHA": source_sha,
        "bundleIdentifier": bundle_id,
        "platformName": platform_name,
        "supportedPlatforms": supported_platforms,
        "teamIdentifier": team_identifier,
        "signingAuthorities": signing_authorities,
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


def _validate_staged_inputs(ipa_path: Path, inspection: dict) -> None:
    field_record = inspection.get("field_build_record")
    external_bytes = inspection.get("external_bytes")
    field_bytes = inspection.get("field_build_bytes")
    signing_inspection = inspection.get("signing_inspection")

    if not isinstance(field_record, dict) or set(field_record) != FIELD_BUILD_EVIDENCE_FIELDS:
        raise EvidenceError("field-build evidence record does not match the canonical package schema")
    if not isinstance(external_bytes, bytes) or not isinstance(field_bytes, bytes):
        raise EvidenceError("evidence bytes are missing")
    if field_bytes != canonical_json_bytes(field_record):
        raise EvidenceError("field-build evidence bytes are not canonical for the declared record")
    if sha256_file(ipa_path) != field_record["signedInstallableSHA256"]:
        raise EvidenceError("input IPA digest diverged after inspection")
    if sha256_bytes(external_bytes) != field_record["externalBuildRecordSHA256"]:
        raise EvidenceError("external build record digest diverged from field-build evidence")
    if not isinstance(signing_inspection, dict):
        raise EvidenceError("signing inspection metadata is missing")
    if signing_inspection.get("fieldBuildEvidenceRecordSHA256") != sha256_bytes(field_bytes):
        raise EvidenceError("signing inspection is not bound to the exact field-build evidence bytes")
    if signing_inspection.get("externalBuildRecordSHA256") != sha256_bytes(external_bytes):
        raise EvidenceError("signing inspection is not bound to the exact external build record bytes")
    if signing_inspection.get("signedInstallableSHA256") != field_record["signedInstallableSHA256"]:
        raise EvidenceError("signing inspection is not bound to the exact signed installable")


def write_outputs(ipa_path: Path, output_dir: Path, inspection: dict) -> dict[str, Path]:
    """Failure-atomically publish one complete evidence directory.

    All bytes are written and re-verified in a hidden sibling staging directory on the same
    filesystem. The final output path does not appear until the complete set passes every check.
    A crash before the final rename may leave only a hidden staging directory, which never becomes
    the requested evidence directory and therefore does not block a clean rerun.
    """

    ipa_path = ipa_path.resolve()
    output_dir = output_dir.resolve()
    if output_dir.exists():
        raise EvidenceError(f"refusing to overwrite existing field evidence directory: {output_dir}")

    _validate_staged_inputs(ipa_path, inspection)

    parent = output_dir.parent
    parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix=f".{output_dir.name}.staging-", dir=str(parent))
    )

    try:
        retained_ipa = staging / RETAINED_IPA_RELATIVE_PATH
        retained_ipa.parent.mkdir(parents=True, exist_ok=True)
        external_path = staging / EXTERNAL_RECORD_FILENAME
        field_path = staging / FIELD_BUILD_EVIDENCE_FILENAME
        inspection_path = staging / SIGNING_INSPECTION_FILENAME

        shutil.copy2(ipa_path, retained_ipa)
        external_path.write_bytes(inspection["external_bytes"])
        field_path.write_bytes(inspection["field_build_bytes"])
        inspection_bytes = canonical_json_bytes(inspection["signing_inspection"])
        inspection_path.write_bytes(inspection_bytes)

        field_record = inspection["field_build_record"]
        if sha256_file(retained_ipa) != field_record["signedInstallableSHA256"]:
            raise EvidenceError("retained IPA bytes diverged from inspected input")
        if sha256_file(external_path) != field_record["externalBuildRecordSHA256"]:
            raise EvidenceError("written external build record digest diverged from field-build evidence")
        if sha256_file(field_path) != inspection["signing_inspection"]["fieldBuildEvidenceRecordSHA256"]:
            raise EvidenceError("written field-build evidence digest diverged from signing inspection")
        if sha256_file(inspection_path) != sha256_bytes(inspection_bytes):
            raise EvidenceError("written signing inspection bytes failed exact re-verification")

        if output_dir.exists():
            raise EvidenceError(f"field evidence directory appeared during staging: {output_dir}")
        staging.rename(output_dir)
    except Exception:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
        raise

    return {
        "retained_ipa": output_dir / RETAINED_IPA_RELATIVE_PATH,
        "external_record": output_dir / EXTERNAL_RECORD_FILENAME,
        "field_build_evidence": output_dir / FIELD_BUILD_EVIDENCE_FILENAME,
        "signing_inspection": output_dir / SIGNING_INSPECTION_FILENAME,
    }


def _expect_evidence_error(operation, expected_fragment: str) -> None:
    try:
        operation()
    except EvidenceError as error:
        if expected_fragment not in str(error):
            raise AssertionError(
                f"expected EvidenceError containing {expected_fragment!r}; got {error!r}"
            ) from error
    else:
        raise AssertionError(f"expected EvidenceError containing {expected_fragment!r}")


def self_test() -> None:
    sha = "a" * 40
    build_identifier = expected_build_identifier(sha)
    build_instance_id = "12345678-1234-4abc-8def-1234567890ab"
    executable_sha = "b" * 64
    info_plist_sha = "c" * 64
    ipa_bytes = b"nembra-signed-field-ipa-self-test"
    ipa_sha = sha256_bytes(ipa_bytes)

    assert canonical_sha40(sha) == sha
    assert build_identifier == "Capture Build V14-aaaaaaaaaaaa"
    assert canonical_uuid(build_instance_id) == build_instance_id
    assert valid_build_identifier(build_identifier)
    assert not valid_build_identifier(f" {build_identifier}")
    assert not valid_build_identifier("Capture\nBuild")
    _expect_evidence_error(lambda: canonical_sha40("A" * 40), "canonical lowercase")

    for bad in ("../Payload/Nembra.app", "/Payload/Nembra.app", "Payload/../Nembra.app"):
        _expect_evidence_error(lambda bad=bad: _safe_member_path(bad), "unsafe ZIP member")

    with tempfile.TemporaryDirectory(prefix="nembra-field-evidence-self-test-") as temporary:
        root = Path(temporary)

        duplicate_ipa = root / "duplicate.ipa"
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(duplicate_ipa, "w") as archive:
                archive.writestr("Payload/Nembra.app/Info.plist", b"first")
                archive.writestr("Payload/Nembra.app/Info.plist", b"second")
        _expect_evidence_error(
            lambda: extract_ipa_safely(duplicate_ipa, root / "duplicate-extract"),
            "duplicate or case-colliding",
        )

        external_record = make_external_build_record(
            build_identifier=build_identifier,
            build_instance_id=build_instance_id,
            source_sha=sha,
            executable_sha=executable_sha,
            info_plist_sha=info_plist_sha,
        )
        external_bytes = canonical_json_bytes(external_record)
        field_record = make_field_build_evidence_record(
            external_record_bytes=external_bytes,
            signed_installable_sha=ipa_sha,
            build_identifier=build_identifier,
            build_instance_id=build_instance_id,
            source_sha=sha,
            executable_sha=executable_sha,
            info_plist_sha=info_plist_sha,
        )
        assert set(field_record) == FIELD_BUILD_EVIDENCE_FIELDS
        assert "authority" not in field_record
        assert "accepted" not in field_record
        assert "physicalGO" not in field_record
        assert field_record["signedInstallableKind"] == "ipa"

        field_bytes = canonical_json_bytes(field_record)
        inspection_record = {
            "schemaVersion": SIGNING_INSPECTION_SCHEMA_VERSION,
            "authority": SIGNING_INSPECTION_AUTHORITY,
            "fieldBuildEvidenceRecordSHA256": sha256_bytes(field_bytes),
            "externalBuildRecordSHA256": sha256_bytes(external_bytes),
            "signedInstallableSHA256": ipa_sha,
        }
        inspection = {
            "external_record": external_record,
            "external_bytes": external_bytes,
            "field_build_record": field_record,
            "field_build_bytes": field_bytes,
            "signing_inspection": inspection_record,
        }

        fake_ipa = root / "candidate.ipa"
        fake_ipa.write_bytes(ipa_bytes)

        bad_inspection = dict(inspection)
        bad_signing = dict(inspection_record)
        bad_signing["fieldBuildEvidenceRecordSHA256"] = "d" * 64
        bad_inspection["signing_inspection"] = bad_signing
        failed_output = root / "failed-final"
        _expect_evidence_error(
            lambda: write_outputs(fake_ipa, failed_output, bad_inspection),
            "not bound to the exact field-build evidence bytes",
        )
        assert not failed_output.exists(), "failed publication must not expose a final evidence directory"

        final_output = root / "complete-final"
        paths = write_outputs(fake_ipa, final_output, inspection)
        assert final_output.is_dir()
        assert all(path.is_file() for path in paths.values())
        assert sha256_file(paths["retained_ipa"]) == ipa_sha
        assert sha256_file(paths["external_record"]) == field_record["externalBuildRecordSHA256"]
        assert sha256_file(paths["field_build_evidence"]) == sha256_bytes(field_bytes)

        _expect_evidence_error(
            lambda: write_outputs(fake_ipa, final_output, inspection),
            "refusing to overwrite existing field evidence directory",
        )


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
        "fieldBuildEvidenceRecord": str(paths["field_build_evidence"]),
        "signingInspection": str(paths["signing_inspection"]),
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
