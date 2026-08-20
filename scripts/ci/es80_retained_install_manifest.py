#!/usr/bin/env python3
"""Build or validate the canonical retained-install manifest consumed by Capture.

This module is deliberately non-authorizing. It does not verify a signature, install an app,
contact a device, grant OFF1, or establish Bluetooth/physical truth. It owns the Python side of the
same byte-level manifest contract decoded by `AuthenticatedStationaryCaptureInstallManifestVerifier`
in Swift so the installer and running app cannot disagree about one supposedly canonical record.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
import uuid
from typing import Any

SCHEMA = "nembra.es80-authenticated-stationary-install-manifest"
SCHEMA_VERSION = 1
PROCEDURE_ID = "ES80-AUTHENTICATED-STATIONARY-v1"
BUNDLE_IDENTIFIER = "com.jonathangana131.nembra.capturelearn"
MAX_MANIFEST_BYTES = 16_384

SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
UUID4 = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
)

BINDING_KEYS = (
    "procedureID",
    "sourceCommitSHA",
    "bundleIdentifier",
    "buildIdentifier",
    "buildInstanceID",
    "retainedIPASHA256",
    "executableSHA256",
    "infoPlistSHA256",
    "tuyaDependencyLockSHA256",
    "externalBuildRecordSHA256",
    "signedBuildEvidenceSHA256",
    "finalGORecordSHA256",
    "intendedDevicePseudonymSHA256",
    "authorizationEnvelopeSHA256",
)
MANIFEST_KEYS = {"schema", "version", *BINDING_KEYS}
DIGEST_KEYS = (
    "retainedIPASHA256",
    "executableSHA256",
    "infoPlistSHA256",
    "tuyaDependencyLockSHA256",
    "externalBuildRecordSHA256",
    "signedBuildEvidenceSHA256",
    "finalGORecordSHA256",
    "intendedDevicePseudonymSHA256",
    "authorizationEnvelopeSHA256",
)


class RetainedInstallManifestError(RuntimeError):
    pass


def canonical_json_bytes(value: object) -> bytes:
    # Match JSONEncoder(outputFormatting: [.sortedKeys, .withoutEscapingSlashes]) exactly for this
    # ASCII-only closed schema: compact object, sorted keys, and no trailing newline.
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise RetainedInstallManifestError("manifest contains a duplicate JSON member")
        value[key] = item
    return value


def _canonical_nonzero_sha256(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value) or value == "0" * 64:
        raise RetainedInstallManifestError(f"{label} is not a canonical nonzero SHA-256")
    return value


def _canonical_uuid4(value: object) -> str:
    if not isinstance(value, str) or not UUID4.fullmatch(value):
        raise RetainedInstallManifestError("buildInstanceID is not a canonical lowercase UUIDv4")
    if uuid.UUID(value).version != 4:
        raise RetainedInstallManifestError("buildInstanceID is not UUIDv4")
    return value


def _build_identifier(value: object) -> str:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > 128:
        raise RetainedInstallManifestError("buildIdentifier is invalid")
    if value != value.strip() or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise RetainedInstallManifestError("buildIdentifier is invalid")
    return value


def _validate_bindings(value: dict[str, Any]) -> dict[str, Any]:
    if value.get("procedureID") != PROCEDURE_ID:
        raise RetainedInstallManifestError("manifest names the wrong procedure")
    if value.get("bundleIdentifier") != BUNDLE_IDENTIFIER:
        raise RetainedInstallManifestError("manifest names the wrong bundle")
    source = value.get("sourceCommitSHA")
    if not isinstance(source, str) or not SHA40.fullmatch(source) or source == "0" * 40:
        raise RetainedInstallManifestError("sourceCommitSHA is not one canonical nonzero full Git SHA")
    _build_identifier(value.get("buildIdentifier"))
    _canonical_uuid4(value.get("buildInstanceID"))
    for key in DIGEST_KEYS:
        _canonical_nonzero_sha256(value.get(key), key)
    return value


def build_manifest(bindings: dict[str, Any]) -> bytes:
    if set(bindings) != set(BINDING_KEYS):
        raise RetainedInstallManifestError("manifest bindings are not a closed schema")
    _validate_bindings(bindings)
    manifest = {
        "schema": SCHEMA,
        "version": SCHEMA_VERSION,
        **bindings,
    }
    encoded = canonical_json_bytes(manifest)
    if len(encoded) > MAX_MANIFEST_BYTES:
        raise RetainedInstallManifestError("manifest exceeds the byte limit")
    return encoded


def verify_manifest_bytes(data: bytes) -> dict[str, Any]:
    if not data or len(data) > MAX_MANIFEST_BYTES:
        raise RetainedInstallManifestError("manifest size is invalid")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_reject_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RetainedInstallManifestError("manifest is malformed JSON") from error
    if not isinstance(value, dict) or set(value) != MANIFEST_KEYS:
        raise RetainedInstallManifestError("manifest schema is not closed")
    if canonical_json_bytes(value) != data:
        raise RetainedInstallManifestError("manifest is not canonical JSON")
    if value.get("schema") != SCHEMA or type(value.get("version")) is not int or value["version"] != SCHEMA_VERSION:
        raise RetainedInstallManifestError("manifest schema/version is unsupported")
    return _validate_bindings(value)


def verify_manifest_against_expected(
    data: bytes, expected_bindings: dict[str, Any]
) -> dict[str, Any]:
    if set(expected_bindings) != set(BINDING_KEYS):
        raise RetainedInstallManifestError("expected bindings are not a closed schema")
    _validate_bindings(expected_bindings)
    value = verify_manifest_bytes(data)
    for key in BINDING_KEYS:
        if value[key] != expected_bindings[key]:
            raise RetainedInstallManifestError(f"manifest exact-subject mismatch at {key}")
    return value


def _read_manifest(path: Path) -> bytes:
    candidate = path.expanduser()
    if not candidate.is_file() or candidate.is_symlink():
        raise RetainedInstallManifestError("manifest path must be one regular non-symlink file")
    data = candidate.read_bytes()
    if not data or len(data) > MAX_MANIFEST_BYTES:
        raise RetainedInstallManifestError("manifest file size is invalid")
    return data


def _self_test() -> None:
    example = {
        "procedureID": PROCEDURE_ID,
        "sourceCommitSHA": "1" * 40,
        "bundleIdentifier": BUNDLE_IDENTIFIER,
        "buildIdentifier": "Capture Build manifest-self-test",
        "buildInstanceID": "12345678-1234-4abc-8def-123456789abc",
        "retainedIPASHA256": "2" * 64,
        "executableSHA256": "3" * 64,
        "infoPlistSHA256": "4" * 64,
        "tuyaDependencyLockSHA256": "5" * 64,
        "externalBuildRecordSHA256": "6" * 64,
        "signedBuildEvidenceSHA256": "7" * 64,
        "finalGORecordSHA256": "8" * 64,
        "intendedDevicePseudonymSHA256": "9" * 64,
        "authorizationEnvelopeSHA256": "a" * 64,
    }
    data = build_manifest(example)
    verify_manifest_against_expected(data, example)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--validate", type=Path, metavar="MANIFEST")
    args = parser.parse_args(argv)
    if args.self_test == bool(args.validate):
        parser.error("choose exactly one of --self-test or --validate")
    try:
        if args.self_test:
            _self_test()
            print("PASS_NOT_INSTALL_AUTHORITY: retained-install manifest self-test")
        else:
            verify_manifest_bytes(_read_manifest(args.validate))
            print("VALID_NOT_INSTALL_AUTHORITY: retained-install manifest structure")
    except RetainedInstallManifestError as error:
        print(f"INVALID_NOT_INSTALL_AUTHORITY: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
