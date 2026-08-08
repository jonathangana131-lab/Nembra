#!/usr/bin/env python3
"""Produce fail-closed evidence for an already-built signed Nembra field IPA.

This tool never authorizes physical Experiment One. It measures and preserves an exact
installable artifact, verifies its iPhone code signature and embedded Nembra build declarations,
and emits external evidence that a separate trusted acceptance step may attest/review.
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
import uuid
import zipfile
from pathlib import Path, PurePosixPath

RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
BUNDLE_ID = "com.jonathangana131.nembra"
EXTERNAL_RECORD_SCHEMA_VERSION = 3
FIELD_BUILD_EVIDENCE_SCHEMA_VERSION = 1
SIGNING_INSPECTION_SCHEMA_VERSION = 1
SIGNED_INSTALLABLE_KIND = "ipa"
INSPECTION_AUTHORITY_LABEL = "signed-field-artifact-inspection-not-field-authorization"

SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)


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
