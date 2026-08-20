#!/usr/bin/env python3
"""Validate the retained signed-IPA manifest for authenticated stationary Capture.

This tool is intentionally non-authorizing. It verifies that one immutable manifest binds the
exact retained IPA and the public evidence subjects that a future private installer must consume.
It does not install an app, inspect a device, verify the per-attempt authorization envelope, grant
OFF1, or establish any physical ES80 truth.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Iterable

SCHEMA_VERSION = 1
AUTHORITY = "retained-signed-ipa-install-manifest-not-physical-authorization"
PROCEDURE_ID = "ES80-AUTHENTICATED-STATIONARY-v1"
SIGNED_INSTALLABLE_KIND = "ipa"
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_IPA_BYTES = 1024 * 1024 * 1024

SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")

MANIFEST_KEYS = {
    "schemaVersion",
    "authority",
    "procedureID",
    "sourceCommitSHA",
    "buildIdentifier",
    "buildInstanceID",
    "signedInstallableKind",
    "signedInstallableSHA256",
    "externalBuildRecordSHA256",
    "fieldBuildEvidenceRecordSHA256",
    "signedArtifactInspectionSHA256",
    "acceptedBuildSubjectSHA256",
    "acceptedEvidenceSubjectSHA256",
    "acceptedFinalGOSubjectSHA256",
    "acceptedTuyaLockSubjectSHA256",
}


class InstallManifestError(RuntimeError):
    pass


def _reject_duplicate_pairs(pairs: Iterable[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise InstallManifestError(f"manifest contains duplicate object key: {key}")
        result[key] = value
    return result


def _regular_file(path: Path, *, label: str, maximum_bytes: int) -> os.stat_result:
    try:
        metadata = path.lstat()
    except OSError as exc:
        raise InstallManifestError(f"{label} is missing: {path}") from exc
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise InstallManifestError(f"{label} must be one regular non-symlink file: {path}")
    if metadata.st_nlink != 1:
        raise InstallManifestError(f"{label} must have exactly one hard link: {path}")
    if metadata.st_size <= 0 or metadata.st_size > maximum_bytes:
        raise InstallManifestError(
            f"{label} size must be within 1...{maximum_bytes} bytes: {metadata.st_size}"
        )
    return metadata


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_sha40(value: object, *, label: str) -> str:
    if not isinstance(value, str) or SHA40_RE.fullmatch(value) is None:
        raise InstallManifestError(f"{label} must be one lowercase 40-hex SHA")
    return value


def _canonical_sha256(value: object, *, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise InstallManifestError(f"{label} must be one lowercase SHA-256")
    return value


def _canonical_uuid(value: object, *, label: str) -> str:
    if not isinstance(value, str):
        raise InstallManifestError(f"{label} must be one canonical lowercase UUID")
    try:
        parsed = uuid.UUID(value)
    except ValueError as exc:
        raise InstallManifestError(f"{label} must be one canonical lowercase UUID") from exc
    if str(parsed) != value:
        raise InstallManifestError(f"{label} must be one canonical lowercase UUID")
    return value


def _canonical_json_bytes(value: dict[str, object]) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode(
        "utf-8"
    )


def load_manifest(path: Path) -> tuple[dict[str, object], bytes]:
    _regular_file(path, label="install manifest", maximum_bytes=MAX_MANIFEST_BYTES)
    try:
        raw = path.read_bytes()
        decoded = json.loads(raw, object_pairs_hook=_reject_duplicate_pairs)
    except InstallManifestError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InstallManifestError("install manifest must be valid UTF-8 JSON") from exc

    if not isinstance(decoded, dict):
        raise InstallManifestError("install manifest root must be one JSON object")
    if set(decoded) != MANIFEST_KEYS:
        raise InstallManifestError(
            f"install manifest schema shape drifted: {sorted(decoded)!r}"
        )
    canonical = _canonical_json_bytes(decoded)
    if raw != canonical:
        raise InstallManifestError("install manifest bytes must use canonical sorted compact JSON")
    return decoded, raw


def validate_manifest(
    manifest_path: Path,
    retained_ipa_path: Path,
    *,
    expected_source_sha: str,
) -> dict[str, object]:
    expected_source_sha = _canonical_sha40(expected_source_sha, label="expected source SHA")
    manifest, manifest_bytes = load_manifest(manifest_path)
    ipa_before = _regular_file(
        retained_ipa_path,
        label="retained signed IPA",
        maximum_bytes=MAX_IPA_BYTES,
    )

    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        raise InstallManifestError(f"schemaVersion must be exactly {SCHEMA_VERSION}")
    if manifest.get("authority") != AUTHORITY:
        raise InstallManifestError("install manifest authority boundary changed")
    if manifest.get("procedureID") != PROCEDURE_ID:
        raise InstallManifestError("install manifest procedureID is not the current stationary procedure")
    if manifest.get("signedInstallableKind") != SIGNED_INSTALLABLE_KIND:
        raise InstallManifestError("install manifest must describe exactly one IPA installable")

    source_sha = _canonical_sha40(manifest.get("sourceCommitSHA"), label="sourceCommitSHA")
    if source_sha != expected_source_sha:
        raise InstallManifestError(
            f"manifest sourceCommitSHA {source_sha} does not match expected source {expected_source_sha}"
        )

    expected_identifier = f"Capture Build V14-{source_sha[:12]}"
    if manifest.get("buildIdentifier") != expected_identifier:
        raise InstallManifestError(
            f"buildIdentifier must be exactly {expected_identifier!r} for this source"
        )
    build_instance_id = _canonical_uuid(manifest.get("buildInstanceID"), label="buildInstanceID")

    digest_keys = (
        "signedInstallableSHA256",
        "externalBuildRecordSHA256",
        "fieldBuildEvidenceRecordSHA256",
        "signedArtifactInspectionSHA256",
        "acceptedBuildSubjectSHA256",
        "acceptedEvidenceSubjectSHA256",
        "acceptedFinalGOSubjectSHA256",
        "acceptedTuyaLockSubjectSHA256",
    )
    for key in digest_keys:
        _canonical_sha256(manifest.get(key), label=key)

    ipa_sha256 = _sha256_file(retained_ipa_path)
    ipa_after = retained_ipa_path.lstat()
    identity = lambda value: (
        value.st_dev,
        value.st_ino,
        value.st_mode,
        value.st_uid,
        value.st_nlink,
        value.st_size,
        value.st_mtime_ns,
        value.st_ctime_ns,
    )
    if identity(ipa_before) != identity(ipa_after):
        raise InstallManifestError("retained signed IPA identity changed while it was hashed")
    if manifest["signedInstallableSHA256"] != ipa_sha256:
        raise InstallManifestError("retained signed IPA bytes do not match the install manifest")

    return {
        "status": "VALID_RETAINED_IPA_MANIFEST",
        "authority": AUTHORITY,
        "physicalExperimentAuthorization": "not-granted",
        "procedureID": PROCEDURE_ID,
        "sourceCommitSHA": source_sha,
        "buildIdentifier": expected_identifier,
        "buildInstanceID": build_instance_id,
        "signedInstallableSHA256": ipa_sha256,
        "manifestSHA256": hashlib.sha256(manifest_bytes).hexdigest(),
    }


def _fixture_manifest(*, source_sha: str, ipa_sha256: str) -> dict[str, object]:
    digest = "b" * 64
    return {
        "schemaVersion": SCHEMA_VERSION,
        "authority": AUTHORITY,
        "procedureID": PROCEDURE_ID,
        "sourceCommitSHA": source_sha,
        "buildIdentifier": f"Capture Build V14-{source_sha[:12]}",
        "buildInstanceID": "12345678-1234-4abc-8def-1234567890ab",
        "signedInstallableKind": SIGNED_INSTALLABLE_KIND,
        "signedInstallableSHA256": ipa_sha256,
        "externalBuildRecordSHA256": digest,
        "fieldBuildEvidenceRecordSHA256": "c" * 64,
        "signedArtifactInspectionSHA256": "d" * 64,
        "acceptedBuildSubjectSHA256": "e" * 64,
        "acceptedEvidenceSubjectSHA256": "f" * 64,
        "acceptedFinalGOSubjectSHA256": "1" * 64,
        "acceptedTuyaLockSubjectSHA256": "2" * 64,
    }


def self_test() -> None:
    source_sha = "a" * 40
    with tempfile.TemporaryDirectory(prefix="nembra-install-manifest-self-test-") as temporary:
        root = Path(temporary)
        ipa = root / "NembraField.ipa"
        ipa.write_bytes(b"nembra-retained-ipa-self-test\n")
        ipa_sha256 = _sha256_file(ipa)
        manifest = root / "manifest.json"
        fixture = _fixture_manifest(source_sha=source_sha, ipa_sha256=ipa_sha256)
        manifest.write_bytes(_canonical_json_bytes(fixture))

        result = validate_manifest(manifest, ipa, expected_source_sha=source_sha)
        if result["status"] != "VALID_RETAINED_IPA_MANIFEST":
            raise AssertionError("valid fixture was not accepted")
        if result["physicalExperimentAuthorization"] != "not-granted":
            raise AssertionError("manifest validation must never grant physical authority")

        ipa.write_bytes(b"tampered-retained-ipa\n")
        try:
            validate_manifest(manifest, ipa, expected_source_sha=source_sha)
        except InstallManifestError:
            pass
        else:
            raise AssertionError("tampered retained IPA was accepted")

        ipa.write_bytes(b"nembra-retained-ipa-self-test\n")
        noncanonical = root / "noncanonical.json"
        noncanonical.write_text(json.dumps(fixture, indent=2), encoding="utf-8")
        try:
            validate_manifest(noncanonical, ipa, expected_source_sha=source_sha)
        except InstallManifestError:
            pass
        else:
            raise AssertionError("noncanonical manifest bytes were accepted")

        duplicate = root / "duplicate.json"
        duplicate.write_text(
            '{"schemaVersion":1,"schemaVersion":1}\n',
            encoding="utf-8",
        )
        try:
            load_manifest(duplicate)
        except InstallManifestError:
            pass
        else:
            raise AssertionError("duplicate manifest keys were accepted")

        try:
            validate_manifest(manifest, ipa, expected_source_sha="3" * 40)
        except InstallManifestError:
            pass
        else:
            raise AssertionError("source mismatch was accepted")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--retained-ipa", type=Path)
    parser.add_argument("--expected-source-sha")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        if args.manifest is not None or args.retained_ipa is not None or args.expected_source_sha is not None:
            parser.error("--self-test accepts no manifest arguments")
        self_test()
        print("retained IPA install-manifest self-test passed")
        return 0

    if args.manifest is None or args.retained_ipa is None or args.expected_source_sha is None:
        parser.error("--manifest, --retained-ipa, and --expected-source-sha are required")

    try:
        result = validate_manifest(
            args.manifest,
            args.retained_ipa,
            expected_source_sha=args.expected_source_sha,
        )
    except InstallManifestError as exc:
        print(f"NOT_READY: {exc}", file=sys.stderr)
        return 2

    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
