#!/usr/bin/env python3
"""Check the byte/provenance self-consistency of one V14 signed Capture candidate.

This verifier is intentionally portable and does not establish artifact authenticity, Apple
code-signature validity, product acceptance, or physical field authorization. The producer's macOS
codesign evidence plus a later independent trust/acceptance decision remain separate gates.
"""

from __future__ import annotations

import hashlib
import json
import plistlib
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

EXPECTED_BUNDLE_ID = "com.jonathangana131.nembra"
EXPECTED_RECIPE_ID = "ES80-FINGERPRINT-v1"
EXPECTED_PROCEDURE_VERSION = "V14"
EXPECTED_EVIDENCE_CLASS = "signed-field-candidate-not-field-authorization"

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

FIELD_KEYS = {
    "schemaVersion",
    "evidenceClass",
    "buildIdentifier",
    "buildInstanceID",
    "sourceCommitSHA",
    "executableSHA256",
    "infoPlistSHA256",
    "signedAppArchiveSHA256",
    "bundleIdentifier",
    "developmentTeam",
    "experimentRecipeID",
    "procedureVersion",
}

LOWER_SHA40 = re.compile(r"^[0-9a-f]{40}$")
LOWER_SHA256 = re.compile(r"^[0-9a-f]{64}$")
LOWER_UUID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
TEAM_ID = re.compile(r"^[A-Za-z0-9]{10}$")


class VerificationError(Exception):
    pass


def fail(message: str) -> None:
    raise VerificationError(message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_bytes(path: Path) -> bytes:
    try:
        return path.read_bytes()
    except OSError as exc:
        fail(f"Could not read required evidence file {path}: {exc}")


def read_json(path: Path) -> dict[str, Any]:
    raw = read_bytes(path)
    try:
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"Required JSON evidence is malformed at {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"Required JSON evidence must be one object at {path}.")
    return value


def require_exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unknown = sorted(actual - expected)
        fail(f"{label} key set mismatch; missing={missing}, unknown={unknown}")


def require_int(value: Any, expected: int, label: str) -> None:
    if isinstance(value, bool) or not isinstance(value, int) or value != expected:
        fail(f"{label} must equal integer {expected}.")


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str):
        fail(f"{label} must be a string.")
    return value


def require_exact_string(value: Any, expected: str, label: str) -> str:
    text = require_string(value, label)
    if text != expected:
        fail(f"{label} must equal {expected!r}.")
    return text


def require_build_identifier(value: Any, label: str) -> str:
    text = require_string(value, label)
    try:
        encoded = text.encode("utf-8")
    except UnicodeEncodeError as exc:
        fail(f"{label} must be valid UTF-8 text: {exc}")
    if not encoded or len(encoded) > 128:
        fail(f"{label} must contain 1...128 UTF-8 bytes.")
    if text != text.strip():
        fail(f"{label} must not contain surrounding whitespace.")
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in text):
        fail(f"{label} must not contain control characters.")
    return text


def require_regex(value: Any, pattern: re.Pattern[str], label: str) -> str:
    text = require_string(value, label)
    if pattern.fullmatch(text) is None:
        fail(f"{label} has a noncanonical value: {text!r}")
    return text


def verify_record_shapes(
    external: dict[str, Any], field: dict[str, Any]
) -> dict[str, str]:
    require_exact_keys(external, EXTERNAL_KEYS, "external build record")
    require_exact_keys(field, FIELD_KEYS, "signed field candidate evidence")
    require_int(external["schemaVersion"], 3, "external schemaVersion")
    require_int(field["schemaVersion"], 1, "field schemaVersion")
    require_exact_string(field["evidenceClass"], EXPECTED_EVIDENCE_CLASS, "evidenceClass")

    external_values = {
        "buildIdentifier": require_build_identifier(
            external["buildIdentifier"], "external buildIdentifier"
        ),
        "buildInstanceID": require_regex(
            external["buildInstanceID"], LOWER_UUID, "external buildInstanceID"
        ),
        "sourceCommitSHA": require_regex(
            external["sourceCommitSHA"], LOWER_SHA40, "external sourceCommitSHA"
        ),
        "executableSHA256": require_regex(
            external["executableSHA256"], LOWER_SHA256, "external executableSHA256"
        ),
        "infoPlistSHA256": require_regex(
            external["infoPlistSHA256"], LOWER_SHA256, "external infoPlistSHA256"
        ),
        "experimentRecipeID": require_exact_string(
            external["experimentRecipeID"], EXPECTED_RECIPE_ID, "external experimentRecipeID"
        ),
        "procedureVersion": require_exact_string(
            external["procedureVersion"], EXPECTED_PROCEDURE_VERSION, "external procedureVersion"
        ),
    }

    field_values = {
        "buildIdentifier": require_build_identifier(
            field["buildIdentifier"], "field buildIdentifier"
        ),
        "buildInstanceID": require_regex(
            field["buildInstanceID"], LOWER_UUID, "field buildInstanceID"
        ),
        "sourceCommitSHA": require_regex(
            field["sourceCommitSHA"], LOWER_SHA40, "field sourceCommitSHA"
        ),
        "executableSHA256": require_regex(
            field["executableSHA256"], LOWER_SHA256, "field executableSHA256"
        ),
        "infoPlistSHA256": require_regex(
            field["infoPlistSHA256"], LOWER_SHA256, "field infoPlistSHA256"
        ),
        "signedAppArchiveSHA256": require_regex(
            field["signedAppArchiveSHA256"], LOWER_SHA256, "field signedAppArchiveSHA256"
        ),
        "bundleIdentifier": require_exact_string(
            field["bundleIdentifier"], EXPECTED_BUNDLE_ID, "field bundleIdentifier"
        ),
        "developmentTeam": require_regex(
            field["developmentTeam"], TEAM_ID, "field developmentTeam"
        ),
        "experimentRecipeID": require_exact_string(
            field["experimentRecipeID"], EXPECTED_RECIPE_ID, "field experimentRecipeID"
        ),
        "procedureVersion": require_exact_string(
            field["procedureVersion"], EXPECTED_PROCEDURE_VERSION, "field procedureVersion"
        ),
    }

    for key in (
        "buildIdentifier",
        "buildInstanceID",
        "sourceCommitSHA",
        "executableSHA256",
        "infoPlistSHA256",
        "experimentRecipeID",
        "procedureVersion",
    ):
        if external_values[key] != field_values[key]:
            fail(f"External build record and field evidence disagree on {key}.")

    return field_values


def require_plist_string(plist: dict[str, Any], key: str) -> str:
    value = plist.get(key)
    if not isinstance(value, str) or not value:
        fail(f"Info.plist requires nonempty string {key}.")
    return value


def verify_plist(plist_bytes: bytes, field: dict[str, str]) -> str:
    try:
        value = plistlib.loads(plist_bytes)
    except Exception as exc:  # plistlib exposes several parse failure types.
        fail(f"Retained Info.plist is malformed: {exc}")
    if not isinstance(value, dict):
        fail("Retained Info.plist must decode as a dictionary.")

    if require_plist_string(value, "CFBundleIdentifier") != EXPECTED_BUNDLE_ID:
        fail("Retained Info.plist bundle identifier does not match Nembra.")
    if require_plist_string(value, "NembraCaptureBuildIdentifier") != field["buildIdentifier"]:
        fail("Retained Info.plist build identifier does not match candidate evidence.")
    if require_plist_string(value, "NembraCaptureBuildInstanceID") != field["buildInstanceID"]:
        fail("Retained Info.plist build-instance ID does not match candidate evidence.")
    if require_plist_string(value, "NembraCaptureBuildCommitSHA") != field["sourceCommitSHA"]:
        fail("Retained Info.plist source SHA does not match candidate evidence.")

    executable_name = require_plist_string(value, "CFBundleExecutable")
    if PurePosixPath(executable_name).name != executable_name:
        fail("CFBundleExecutable must be one basename, not a path.")
    return executable_name


def unique_zip_member(names: list[str], suffix: str, label: str) -> str:
    matches = [name for name in names if name == suffix or name.endswith("/" + suffix)]
    if len(matches) != 1:
        fail(f"Signed app archive must contain exactly one {label}; found {len(matches)}.")
    return matches[0]


def verify_candidate(artifact_dir: Path) -> dict[str, Any]:
    external_path = artifact_dir / "NembraCaptureExternalBuildRecord.json"
    field_path = artifact_dir / "NembraCaptureSignedFieldCandidateEvidence.json"
    executable_path = artifact_dir / "build-evidence" / "Nembra"
    plist_path = artifact_dir / "build-evidence" / "Info.plist"
    app_archive_path = artifact_dir / "build-evidence" / "Nembra.signed-app.zip"

    external = read_json(external_path)
    field_record = read_json(field_path)
    field = verify_record_shapes(external, field_record)

    executable_bytes = read_bytes(executable_path)
    plist_bytes = read_bytes(plist_path)
    app_archive_bytes = read_bytes(app_archive_path)

    if sha256_bytes(executable_bytes) != field["executableSHA256"]:
        fail("Retained signed executable bytes do not match the declared executableSHA256.")
    if sha256_bytes(plist_bytes) != field["infoPlistSHA256"]:
        fail("Retained Info.plist bytes do not match the declared infoPlistSHA256.")
    if sha256_bytes(app_archive_bytes) != field["signedAppArchiveSHA256"]:
        fail("Signed app transfer archive does not match signedAppArchiveSHA256.")

    executable_name = verify_plist(plist_bytes, field)

    try:
        with zipfile.ZipFile(app_archive_path) as archive:
            names = archive.namelist()
            if any(".." in PurePosixPath(name).parts for name in names):
                fail("Signed app archive contains a parent-directory traversal entry.")
            plist_member = unique_zip_member(names, "Nembra.app/Info.plist", "Nembra.app/Info.plist")
            executable_member = unique_zip_member(
                names, f"Nembra.app/{executable_name}", "signed Nembra executable"
            )
            if archive.read(plist_member) != plist_bytes:
                fail("Signed app archive Info.plist differs from retained Info.plist bytes.")
            if archive.read(executable_member) != executable_bytes:
                fail("Signed app archive executable differs from retained signed executable bytes.")
    except zipfile.BadZipFile as exc:
        fail(f"Signed app transfer archive is malformed: {exc}")

    return {
        "verification": "self-consistent-byte-provenance",
        "authenticity": "not-established-by-portable-verifier",
        "fieldAuthorization": "NO-GO",
        "codeSignatureVerification": "not-reperformed-by-portable-verifier",
        "buildIdentifier": field["buildIdentifier"],
        "buildInstanceID": field["buildInstanceID"],
        "sourceCommitSHA": field["sourceCommitSHA"],
        "executableSHA256": field["executableSHA256"],
        "infoPlistSHA256": field["infoPlistSHA256"],
        "signedAppArchiveSHA256": field["signedAppArchiveSHA256"],
        "experimentRecipeID": field["experimentRecipeID"],
        "procedureVersion": field["procedureVersion"],
    }


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(
            "usage: verify_signed_capture_candidate.py <Artifacts/Xcode27FieldCandidate>",
            file=sys.stderr,
        )
        return 2

    artifact_dir = Path(argv[1])
    if not artifact_dir.is_dir():
        print(f"verification failed: artifact directory does not exist: {artifact_dir}", file=sys.stderr)
        return 2

    try:
        result = verify_candidate(artifact_dir)
    except VerificationError as exc:
        print(f"verification failed: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
