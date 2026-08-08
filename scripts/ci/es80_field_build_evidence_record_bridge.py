#!/usr/bin/env python3
"""Bridge signed-IPA inspection evidence into Nembra's closed-world package record.

This tool is deliberately evidence-only. It validates the exact retained IPA, the exact schema-v3
external build record, and the richer signed-artifact inspection record emitted by
`es80_signed_field_artifact_evidence.py`, then emits the exact schema-v1 wire record consumed by
`PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON`.

Successful output is not attestation, release approval, installation proof, or physical GO.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

EXTERNAL_SCHEMA_VERSION = 3
FIELD_RECORD_SCHEMA_VERSION = 1
INSPECTION_SCHEMA_VERSION = 1
RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
INSPECTION_AUTHORITY = "signed-field-artifact-evidence-not-field-authorization"
INSTALLABLE_KIND = "ipa"

SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)

EXTERNAL_KEYS = {
    "schemaVersion",
    "buildIdentifier",
    "buildInstanceID",
    "sourceCommitSHA",
    "executableSHA256",
    "infoPlistSHA256",
    "experimentRecipeID",
    "procedureVersion",
}

INSPECTION_KEYS = {
    "schemaVersion",
    "authority",
    "buildIdentifier",
    "buildInstanceID",
    "sourceCommitSHA",
    "bundleIdentifier",
    "platformName",
    "supportedPlatforms",
    "teamIdentifier",
    "signingAuthorities",
    "ipaSHA256",
    "ipaByteCount",
    "executableSHA256",
    "infoPlistSHA256",
    "externalBuildRecordSHA256",
    "experimentRecipeID",
    "procedureVersion",
}

FIELD_RECORD_KEYS = {
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


class BridgeError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_exact_json(path: Path) -> tuple[bytes, dict]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise BridgeError(f"cannot read {path}") from exc
    try:
        value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BridgeError(f"{path} is not valid UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise BridgeError(f"{path} JSON root must be an object")
    return data, value


def require_exact_keys(value: dict, expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        raise BridgeError(
            f"{label} has wrong closed-world keys; missing={missing!r} unexpected={unexpected!r}"
        )


def require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise BridgeError(f"{label} must be a non-empty string")
    return value


def require_sha40(value: object, label: str) -> str:
    text = require_string(value, label)
    if not SHA40_RE.fullmatch(text):
        raise BridgeError(f"{label} must be one canonical lowercase 40-hex SHA")
    return text


def require_sha256(value: object, label: str) -> str:
    text = require_string(value, label)
    if not SHA256_RE.fullmatch(text):
        raise BridgeError(f"{label} must be one canonical lowercase SHA-256")
    return text


def require_uuid(value: object, label: str) -> str:
    text = require_string(value, label)
    if not UUID_RE.fullmatch(text):
        raise BridgeError(f"{label} must be one canonical lowercase UUID-shaped value")
    return text


def require_build_identifier(value: object) -> str:
    text = require_string(value, "buildIdentifier")
    if len(text.encode("utf-8")) > 128 or text != text.strip():
        raise BridgeError("buildIdentifier is not canonical")
    if any(ord(character) < 32 or ord(character) == 127 for character in text):
        raise BridgeError("buildIdentifier contains a control character")
    return text


def validate_external_record(value: dict) -> dict[str, str]:
    require_exact_keys(value, EXTERNAL_KEYS, "external build record")
    if value["schemaVersion"] != EXTERNAL_SCHEMA_VERSION:
        raise BridgeError("external build record schemaVersion must be 3")
    if value["experimentRecipeID"] != RECIPE_ID:
        raise BridgeError("external build record recipe is unsupported")
    if value["procedureVersion"] != PROCEDURE_VERSION:
        raise BridgeError("external build record procedure is unsupported")
    return {
        "buildIdentifier": require_build_identifier(value["buildIdentifier"]),
        "buildInstanceID": require_uuid(value["buildInstanceID"], "buildInstanceID"),
        "sourceCommitSHA": require_sha40(value["sourceCommitSHA"], "sourceCommitSHA"),
        "executableSHA256": require_sha256(value["executableSHA256"], "executableSHA256"),
        "infoPlistSHA256": require_sha256(value["infoPlistSHA256"], "infoPlistSHA256"),
    }


def validate_inspection_record(value: dict) -> dict[str, str]:
    require_exact_keys(value, INSPECTION_KEYS, "signed-artifact inspection record")
    if value["schemaVersion"] != INSPECTION_SCHEMA_VERSION:
        raise BridgeError("signed-artifact inspection schemaVersion must be 1")
    if value["authority"] != INSPECTION_AUTHORITY:
        raise BridgeError("signed-artifact inspection authority label is unsupported")
    if value["experimentRecipeID"] != RECIPE_ID:
        raise BridgeError("signed-artifact inspection recipe is unsupported")
    if value["procedureVersion"] != PROCEDURE_VERSION:
        raise BridgeError("signed-artifact inspection procedure is unsupported")
    if value["bundleIdentifier"] != "com.jonathangana131.nembra":
        raise BridgeError("signed-artifact inspection bundle identifier is not Nembra")
    if value["platformName"] != "iphoneos":
        raise BridgeError("signed-artifact inspection platform is not iphoneos")
    supported = value["supportedPlatforms"]
    if not isinstance(supported, list) or "iPhoneOS" not in supported:
        raise BridgeError("signed-artifact inspection does not declare iPhoneOS")
    if any(not isinstance(item, str) or "Simulator" in item for item in supported):
        raise BridgeError("signed-artifact inspection contains an invalid platform declaration")
    team_identifier = require_string(value["teamIdentifier"], "teamIdentifier")
    if team_identifier.lower() in {"not set", "none", "-"}:
        raise BridgeError("signed-artifact inspection does not carry a concrete TeamIdentifier")
    authorities = value["signingAuthorities"]
    if not isinstance(authorities, list) or not authorities or any(
        not isinstance(item, str) or not item for item in authorities
    ):
        raise BridgeError("signed-artifact inspection does not carry a signing authority chain")
    byte_count = value["ipaByteCount"]
    if not isinstance(byte_count, int) or isinstance(byte_count, bool) or byte_count <= 0:
        raise BridgeError("signed-artifact inspection ipaByteCount must be a positive integer")
    return {
        "buildIdentifier": require_build_identifier(value["buildIdentifier"]),
        "buildInstanceID": require_uuid(value["buildInstanceID"], "buildInstanceID"),
        "sourceCommitSHA": require_sha40(value["sourceCommitSHA"], "sourceCommitSHA"),
        "executableSHA256": require_sha256(value["executableSHA256"], "executableSHA256"),
        "infoPlistSHA256": require_sha256(value["infoPlistSHA256"], "infoPlistSHA256"),
        "ipaSHA256": require_sha256(value["ipaSHA256"], "ipaSHA256"),
        "externalBuildRecordSHA256": require_sha256(
            value["externalBuildRecordSHA256"], "externalBuildRecordSHA256"
        ),
        "ipaByteCount": str(byte_count),
    }


def build_field_record(
    external_bytes: bytes,
    external: dict,
    inspection: dict,
    retained_ipa: Path,
) -> dict:
    external_tuple = validate_external_record(external)
    inspection_tuple = validate_inspection_record(inspection)

    external_digest = sha256_bytes(external_bytes)
    if inspection_tuple["externalBuildRecordSHA256"] != external_digest:
        raise BridgeError("inspection record does not bind the exact external build-record bytes")

    for key in (
        "buildIdentifier",
        "buildInstanceID",
        "sourceCommitSHA",
        "executableSHA256",
        "infoPlistSHA256",
    ):
        if inspection_tuple[key] != external_tuple[key]:
            raise BridgeError(f"inspection/external build tuple mismatch at {key}")

    try:
        ipa_size = retained_ipa.stat().st_size
    except OSError as exc:
        raise BridgeError("retained IPA is not readable") from exc
    if not retained_ipa.is_file():
        raise BridgeError("retained IPA must be a regular file")
    if ipa_size != int(inspection_tuple["ipaByteCount"]):
        raise BridgeError("retained IPA byte count does not match inspection evidence")
    ipa_digest = sha256_file(retained_ipa)
    if ipa_digest != inspection_tuple["ipaSHA256"]:
        raise BridgeError("retained IPA SHA-256 does not match inspection evidence")

    record = {
        "schemaVersion": FIELD_RECORD_SCHEMA_VERSION,
        "externalBuildRecordSHA256": external_digest,
        "signedInstallableSHA256": ipa_digest,
        "signedInstallableKind": INSTALLABLE_KIND,
        "buildIdentifier": external_tuple["buildIdentifier"],
        "buildInstanceID": external_tuple["buildInstanceID"],
        "sourceCommitSHA": external_tuple["sourceCommitSHA"],
        "executableSHA256": external_tuple["executableSHA256"],
        "infoPlistSHA256": external_tuple["infoPlistSHA256"],
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    require_exact_keys(record, FIELD_RECORD_KEYS, "generated field-build evidence record")
    return record


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n"


def write_record(output: Path, record: dict) -> None:
    if output.exists():
        raise BridgeError(f"refusing to overwrite existing field-build evidence record: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    data = canonical_json_bytes(record)
    output.write_bytes(data)
    if output.read_bytes() != data:
        raise BridgeError("written field-build evidence record bytes diverged from generated bytes")


def self_test() -> None:
    build_id = "Capture Build V14-aaaaaaaaaaaa"
    build_instance = "12345678-1234-4abc-8def-1234567890ab"
    source_sha = "a" * 40
    executable_sha = "b" * 64
    plist_sha = "c" * 64
    ipa_bytes = b"signed-ipa-fixture"
    external = {
        "schemaVersion": 3,
        "buildIdentifier": build_id,
        "buildInstanceID": build_instance,
        "sourceCommitSHA": source_sha,
        "executableSHA256": executable_sha,
        "infoPlistSHA256": plist_sha,
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }
    external_bytes = canonical_json_bytes(external)
    inspection = {
        "schemaVersion": 1,
        "authority": INSPECTION_AUTHORITY,
        "buildIdentifier": build_id,
        "buildInstanceID": build_instance,
        "sourceCommitSHA": source_sha,
        "bundleIdentifier": "com.jonathangana131.nembra",
        "platformName": "iphoneos",
        "supportedPlatforms": ["iPhoneOS"],
        "teamIdentifier": "TEAM123456",
        "signingAuthorities": ["Apple Development: Fixture"],
        "ipaSHA256": sha256_bytes(ipa_bytes),
        "ipaByteCount": len(ipa_bytes),
        "executableSHA256": executable_sha,
        "infoPlistSHA256": plist_sha,
        "externalBuildRecordSHA256": sha256_bytes(external_bytes),
        "experimentRecipeID": RECIPE_ID,
        "procedureVersion": PROCEDURE_VERSION,
    }

    import tempfile

    with tempfile.TemporaryDirectory(prefix="nembra-field-record-self-test-") as temporary:
        ipa = Path(temporary) / "NembraField.ipa"
        ipa.write_bytes(ipa_bytes)
        record = build_field_record(external_bytes, external, inspection, ipa)
        assert set(record) == FIELD_RECORD_KEYS
        assert record["signedInstallableSHA256"] == sha256_bytes(ipa_bytes)
        assert record["signedInstallableKind"] == "ipa"
        assert record["infoPlistSHA256"] == plist_sha

        bad = dict(inspection)
        bad["externalBuildRecordSHA256"] = "d" * 64
        try:
            build_field_record(external_bytes, external, bad, ipa)
        except BridgeError:
            pass
        else:
            raise AssertionError("detached external-record digest was accepted")

        bad = dict(inspection)
        bad["physicalGO"] = True
        try:
            build_field_record(external_bytes, external, bad, ipa)
        except BridgeError:
            pass
        else:
            raise AssertionError("authority-looking unexpected field was accepted")

        ipa.write_bytes(b"detached-ipa")
        try:
            build_field_record(external_bytes, external, inspection, ipa)
        except BridgeError:
            pass
        else:
            raise AssertionError("detached retained IPA was accepted")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--external-record", type=Path)
    parser.add_argument("--inspection-record", type=Path)
    parser.add_argument("--retained-ipa", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        self_test()
        print("field-build evidence record bridge self-test: PASS")
        return 0

    missing = [
        name
        for name, value in (
            ("--external-record", args.external_record),
            ("--inspection-record", args.inspection_record),
            ("--retained-ipa", args.retained_ipa),
            ("--output", args.output),
        )
        if value is None
    ]
    if missing:
        raise BridgeError(f"required arguments missing: {', '.join(missing)}")

    external_bytes, external = read_exact_json(args.external_record.resolve())
    _, inspection = read_exact_json(args.inspection_record.resolve())
    record = build_field_record(
        external_bytes,
        external,
        inspection,
        args.retained_ipa.resolve(),
    )
    write_record(args.output.resolve(), record)
    print(
        json.dumps(
            {
                "status": "EVIDENCE_ONLY_NOT_FIELD_AUTHORIZATION",
                "fieldBuildEvidenceRecord": str(args.output.resolve()),
                "signedInstallableSHA256": record["signedInstallableSHA256"],
                "externalBuildRecordSHA256": record["externalBuildRecordSHA256"],
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except BridgeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
