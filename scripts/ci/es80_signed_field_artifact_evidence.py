#!/usr/bin/env python3
"""Create/verify exact-subject evidence for the authenticated-stationary field build.

This helper records digests only. It does not sign an IPA, establish Apple installability, expose an
intended-device pseudonym, or authorize a physical run. Private subjects stay outside Git.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from typing import Any

SCHEMA_VERSION = 1
PROCEDURE_ID = "ES80-AUTHENTICATED-STATIONARY-v1"
BUNDLE_ID = "com.jonathangana131.nembra.capturelearn"
SIGNED_KIND = "ipa"
MAX_SUBJECT_BYTES = 512 * 1024 * 1024
MAX_JSON_BYTES = 1024 * 1024
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
BUILD_INSTANCE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)

EXTERNAL_KEYS = {
    "schemaVersion", "procedureID", "bundleIdentifier", "sourceCommitSHA",
    "buildIdentifier", "buildInstanceID", "executableSHA256", "infoPlistSHA256",
    "tuyaDependencyLockSHA256",
}
FINAL_GO_KEYS = {
    "schemaVersion", "decision", "procedureID", "bundleIdentifier", "sourceCommitSHA",
    "buildIdentifier", "buildInstanceID", "signedInstallableSHA256", "executableSHA256",
    "infoPlistSHA256", "tuyaDependencyLockSHA256", "intendedDevicePseudonymSHA256",
}
EVIDENCE_KEYS = {
    "schemaVersion", "evidenceKind", "procedureID", "bundleIdentifier", "sourceCommitSHA",
    "buildIdentifier", "buildInstanceID", "signedInstallableKind", "signedInstallableSHA256",
    "executableSHA256", "infoPlistSHA256", "tuyaDependencyLockSHA256",
    "externalBuildRecordSHA256", "finalGORecordSHA256", "intendedDevicePseudonymSHA256",
}


class EvidenceError(RuntimeError):
    pass


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8") + b"\n"


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise EvidenceError("JSON contains a duplicate object member")
        result[key] = value
    return result


def parse_closed_json(data: bytes, keys: set[str], label: str) -> dict[str, Any]:
    if not data or len(data) > MAX_JSON_BYTES:
        raise EvidenceError(f"{label} size is invalid")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_reject_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"{label} is not valid JSON") from error
    if not isinstance(value, dict) or set(value) != keys:
        raise EvidenceError(f"{label} schema is not closed")
    if canonical_json_bytes(value) != data:
        raise EvidenceError(f"{label} is not canonical JSON")
    return value


def read_exact_file(path: Path, label: str, maximum: int = MAX_SUBJECT_BYTES) -> bytes:
    candidate = path.expanduser().absolute()
    if candidate.is_symlink() or not hasattr(os, "O_NOFOLLOW"):
        raise EvidenceError(f"{label} must be a non-symlink file")
    try:
        descriptor = os.open(candidate, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0))
    except OSError as error:
        raise EvidenceError(f"cannot open {label}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size <= 0 or before.st_size > maximum:
            raise EvidenceError(f"{label} size or type is invalid")
        chunks: list[bytes] = []
        remaining = maximum + 1
        while remaining:
            chunk = os.read(descriptor, min(1024 * 1024, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    identity = lambda item: (item.st_dev, item.st_ino, item.st_size, item.st_mtime_ns, item.st_ctime_ns)
    data = b"".join(chunks)
    if identity(before) != identity(after) or len(data) != before.st_size:
        raise EvidenceError(f"{label} changed while reading")
    return data


def _sha(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value) or value == "0" * 64:
        raise EvidenceError(f"{label} is not a canonical nonzero SHA-256")
    return value


def _text(value: object, label: str, maximum: int = 128) -> str:
    if not isinstance(value, str) or not value or len(value.encode()) > maximum or value != value.strip():
        raise EvidenceError(f"{label} is invalid")
    return value


def _validate_common(value: dict[str, Any]) -> None:
    if type(value.get("schemaVersion")) is not int or value["schemaVersion"] != SCHEMA_VERSION:
        raise EvidenceError("unsupported subject schema")
    if value.get("procedureID") != PROCEDURE_ID or value.get("bundleIdentifier") != BUNDLE_ID:
        raise EvidenceError("evidence subject names the wrong procedure or bundle")
    source = value.get("sourceCommitSHA")
    instance = value.get("buildInstanceID")
    if not isinstance(source, str) or not SHA40.fullmatch(source):
        raise EvidenceError("source commit is not canonical")
    if not isinstance(instance, str) or not BUILD_INSTANCE.fullmatch(instance):
        raise EvidenceError("build instance is not the canonical lowercase build-instance identity")
    _text(value.get("buildIdentifier"), "build identifier")
    _sha(value.get("executableSHA256"), "executable digest")
    _sha(value.get("infoPlistSHA256"), "Info.plist digest")
    _sha(value.get("tuyaDependencyLockSHA256"), "Tuya lock digest")


def verify_evidence_bytes(data: bytes) -> dict[str, Any]:
    value = parse_closed_json(data, EVIDENCE_KEYS, "signed artifact evidence")
    if value.get("schemaVersion") != SCHEMA_VERSION:
        raise EvidenceError("unsupported signed artifact evidence schema")
    if value.get("evidenceKind") != "signed-field-artifact-digests-not-authorization":
        raise EvidenceError("signed artifact evidence kind is not non-authorizing")
    if value.get("signedInstallableKind") != SIGNED_KIND:
        raise EvidenceError("signed installable kind is not IPA")
    _validate_common(value)
    for key in (
        "signedInstallableSHA256", "externalBuildRecordSHA256", "finalGORecordSHA256",
        "intendedDevicePseudonymSHA256",
    ):
        _sha(value.get(key), key)
    return value


def build_evidence(
    *, ipa: bytes, tuya_lock: bytes, external_record: bytes, final_go_record: bytes,
    intended_device_pseudonym: bytes, source_commit_sha: str, build_identifier: str,
    build_instance_id: str, executable_sha256: str, info_plist_sha256: str,
) -> bytes:
    if not ipa or not tuya_lock or not intended_device_pseudonym:
        raise EvidenceError("exact byte subjects must be non-empty")
    external = parse_closed_json(external_record, EXTERNAL_KEYS, "external build record")
    final_go = parse_closed_json(final_go_record, FINAL_GO_KEYS, "Final GO record")
    _validate_common(external)
    _validate_common(final_go)
    if final_go.get("decision") != "GO":
        raise EvidenceError("Final GO record decision is not GO")
    tuple_values = {
        "sourceCommitSHA": source_commit_sha, "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance_id, "executableSHA256": executable_sha256,
        "infoPlistSHA256": info_plist_sha256,
    }
    for key, expected in tuple_values.items():
        if external.get(key) != expected or final_go.get(key) != expected:
            raise EvidenceError(f"exact build tuple mismatch at {key}")
    tuya_sha = sha256_hex(tuya_lock)
    pseudonym_sha = sha256_hex(intended_device_pseudonym)
    ipa_sha = sha256_hex(ipa)
    if external.get("tuyaDependencyLockSHA256") != tuya_sha:
        raise EvidenceError("external record does not bind the exact Tuya lock")
    for key, expected in (
        ("tuyaDependencyLockSHA256", tuya_sha),
        ("intendedDevicePseudonymSHA256", pseudonym_sha),
        ("signedInstallableSHA256", ipa_sha),
    ):
        if final_go.get(key) != expected:
            raise EvidenceError(f"Final GO record exact subject mismatch at {key}")
    evidence = {
        "schemaVersion": SCHEMA_VERSION,
        "evidenceKind": "signed-field-artifact-digests-not-authorization",
        "procedureID": PROCEDURE_ID,
        "bundleIdentifier": BUNDLE_ID,
        **tuple_values,
        "signedInstallableKind": SIGNED_KIND,
        "signedInstallableSHA256": ipa_sha,
        "tuyaDependencyLockSHA256": tuya_sha,
        "externalBuildRecordSHA256": sha256_hex(external_record),
        "finalGORecordSHA256": sha256_hex(final_go_record),
        "intendedDevicePseudonymSHA256": pseudonym_sha,
    }
    raw = canonical_json_bytes(evidence)
    verify_evidence_bytes(raw)
    return raw


def publish_no_replace(path: Path, data: bytes) -> Path:
    output = path.expanduser().absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists() or output.is_symlink():
        raise EvidenceError("refusing to replace signed artifact evidence")
    fd, staging_name = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
    staging = Path(staging_name)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb", closefd=True) as handle:
            handle.write(data); handle.flush(); os.fsync(handle.fileno())
        os.link(staging, output, follow_symlinks=False)
        staging.unlink()
        if output.read_bytes() != data:
            raise EvidenceError("published evidence bytes changed")
        return output
    except Exception:
        staging.unlink(missing_ok=True)
        raise


def create_from_paths(args: argparse.Namespace) -> bytes:
    raw = build_evidence(
        ipa=read_exact_file(args.ipa, "signed IPA"),
        tuya_lock=read_exact_file(args.tuya_lock, "Tuya dependency lock", MAX_JSON_BYTES),
        external_record=read_exact_file(args.external_record, "external build record", MAX_JSON_BYTES),
        final_go_record=read_exact_file(args.final_go_record, "Final GO record", MAX_JSON_BYTES),
        intended_device_pseudonym=read_exact_file(args.intended_device_pseudonym, "intended-device pseudonym", 4096),
        source_commit_sha=args.source_commit_sha, build_identifier=args.build_identifier,
        build_instance_id=args.build_instance_id, executable_sha256=args.executable_sha256,
        info_plist_sha256=args.info_plist_sha256,
    )
    publish_no_replace(args.output, raw)
    return raw


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", type=Path)
    parser.add_argument("--self-test", action="store_true")
    for name in ("ipa", "tuya-lock", "external-record", "final-go-record", "intended-device-pseudonym", "output"):
        parser.add_argument(f"--{name}", type=Path)
    for name in ("source-commit-sha", "build-identifier", "build-instance-id", "executable-sha256", "info-plist-sha256"):
        parser.add_argument(f"--{name}")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        if len(argv) != 1:
            raise EvidenceError("--self-test accepts no other arguments")
        self_test()
        print("signed artifact evidence self-test: PASS (NOT AUTHORIZATION)")
        return 0
    if args.verify:
        verify_evidence_bytes(read_exact_file(args.verify, "signed artifact evidence", MAX_JSON_BYTES))
        print("signed artifact evidence: VERIFIED (NOT AUTHORIZATION)")
        return 0
    required = [
        key for key, value in vars(args).items()
        if key not in {"verify", "self_test"} and value is None
    ]
    if required:
        raise EvidenceError("missing required arguments")
    raw = create_from_paths(args)
    print(json.dumps({"status": "EVIDENCE_ONLY_NOT_AUTHORIZATION", "evidenceSHA256": sha256_hex(raw)}, sort_keys=True))
    return 0


def self_test() -> None:
    source = "1" * 40
    # Build-instance identity is UUID-shaped but intentionally opaque; this fixture is non-v4 so
    # the self-test rejects accidental reintroduction of UUID-version semantics.
    instance = "12345678-1234-abcd-8def-123456789abc"
    executable = "2" * 64
    plist = "3" * 64
    tuya = b"synthetic Tuya dependency lock\n"
    ipa = b"synthetic signed IPA subject\n"
    pseudonym = b"synthetic intended-device pseudonym\n"
    common = {
        "schemaVersion": SCHEMA_VERSION,
        "procedureID": PROCEDURE_ID,
        "bundleIdentifier": BUNDLE_ID,
        "sourceCommitSHA": source,
        "buildIdentifier": "capture-authorized-stationary-test",
        "buildInstanceID": instance,
        "executableSHA256": executable,
        "infoPlistSHA256": plist,
        "tuyaDependencyLockSHA256": sha256_hex(tuya),
    }
    external = canonical_json_bytes(common)
    final_go = canonical_json_bytes({
        **common,
        "decision": "GO",
        "signedInstallableSHA256": sha256_hex(ipa),
        "intendedDevicePseudonymSHA256": sha256_hex(pseudonym),
    })
    raw = build_evidence(
        ipa=ipa,
        tuya_lock=tuya,
        external_record=external,
        final_go_record=final_go,
        intended_device_pseudonym=pseudonym,
        source_commit_sha=source,
        build_identifier=common["buildIdentifier"],
        build_instance_id=instance,
        executable_sha256=executable,
        info_plist_sha256=plist,
    )
    if verify_evidence_bytes(raw)["signedInstallableSHA256"] != sha256_hex(ipa):
        raise EvidenceError("self-test exact IPA binding failed")


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (EvidenceError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
