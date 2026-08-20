#!/usr/bin/env python3
"""Create or verify one offline ES80 authenticated-stationary authorization envelope.

The envelope grants at most one OFF1 start for one app-generated challenge. It is software
authorization only: it does not identify/authenticate a scooter or establish BLE/telemetry truth.
Production private keys are supplied externally; this program has no production-key generator.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
from typing import Any
import uuid

import es80_signed_field_artifact_evidence as artifact_evidence

ENVELOPE_SCHEMA_VERSION = 1
PAYLOAD_SCHEMA_VERSION = 1
ENVELOPE_SCHEMA = "nembra.es80-authenticated-stationary-field-authorization-envelope"
PAYLOAD_SCHEMA = "nembra.es80-authenticated-stationary-field-authorization"
PROCEDURE_ID = artifact_evidence.PROCEDURE_ID
BUNDLE_ID = artifact_evidence.BUNDLE_ID
DECISION = "GO"
MAXIMUM_OFF1_STARTS = 1
MAX_VALIDITY_SECONDS = 15 * 60
MAX_JSON_BYTES = 1024 * 1024
MAX_ENVELOPE_BYTES = 32_768
MAX_PAYLOAD_BYTES = 16_384
MAX_PRIVATE_KEY_BYTES = 64 * 1024
OPENSSL_TIMEOUT_SECONDS = 30
DEFAULT_SELF_TEST_OPENSSL = Path("/usr/bin/openssl")
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
UUID4 = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
RFC3339_SECONDS = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
P256_SPKI_PREFIX = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200")

PAYLOAD_KEYS = {
    "schema", "version", "decision", "procedureID", "authorizationID",
    "attemptChallengeSHA256", "issuedAtUnixMilliseconds", "notBeforeUnixMilliseconds",
    "expiresAtUnixMilliseconds", "maximumOFF1Starts",
    "bundleIdentifier", "sourceCommitSHA", "buildIdentifier", "buildInstanceID",
    "executableSHA256", "infoPlistSHA256", "tuyaDependencyLockSHA256",
    "externalBuildRecordSHA256", "signedBuildEvidenceSHA256", "finalGORecordSHA256",
    "intendedDevicePseudonymSHA256",
}
ENVELOPE_KEYS = {
    "schema", "version", "payloadBase64", "signatureDERBase64",
}


class AuthorizationEnvelopeError(RuntimeError):
    pass


def canonical_json_bytes(value: object) -> bytes:
    # This exact compact/sorted representation is also enforced by Swift JSONEncoder.
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise AuthorizationEnvelopeError("JSON contains a duplicate object member")
        result[key] = value
    return result


def parse_closed_json(
    data: bytes, keys: set[str], label: str, maximum_bytes: int = MAX_JSON_BYTES
) -> dict[str, Any]:
    if not data or len(data) > maximum_bytes:
        raise AuthorizationEnvelopeError(f"{label} size is invalid")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AuthorizationEnvelopeError(f"{label} is malformed") from error
    if not isinstance(value, dict) or set(value) != keys:
        raise AuthorizationEnvelopeError(f"{label} schema is not closed")
    if canonical_json_bytes(value) != data:
        raise AuthorizationEnvelopeError(f"{label} is not canonical JSON")
    return value


def _sha(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value) or value == "0" * 64:
        raise AuthorizationEnvelopeError(f"{label} is not a canonical nonzero SHA-256")
    return value


def _timestamp(value: object, label: str) -> datetime:
    if not isinstance(value, str) or not RFC3339_SECONDS.fullmatch(value):
        raise AuthorizationEnvelopeError(f"{label} is not canonical UTC seconds")
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as error:
        raise AuthorizationEnvelopeError(f"{label} is invalid") from error


def _authorization_id(value: object) -> str:
    if not isinstance(value, str) or not UUID4.fullmatch(value):
        raise AuthorizationEnvelopeError("authorization ID is not a canonical UUIDv4")
    if uuid.UUID(value).version != 4:
        raise AuthorizationEnvelopeError("authorization ID is not UUIDv4")
    return value


def _unix_milliseconds(value: object, label: str) -> int:
    instant = _timestamp(value, label)
    milliseconds = int(instant.timestamp()) * 1000
    if milliseconds <= 0:
        raise AuthorizationEnvelopeError(f"{label} is outside the supported epoch")
    return milliseconds


def _validate_payload(value: dict[str, Any], evidence: dict[str, Any], evidence_bytes: bytes) -> None:
    if value.get("schema") != PAYLOAD_SCHEMA \
            or type(value.get("version")) is not int \
            or value["version"] != PAYLOAD_SCHEMA_VERSION:
        raise AuthorizationEnvelopeError("unsupported authorization payload schema")
    if value.get("decision") != DECISION:
        raise AuthorizationEnvelopeError("authorization decision is unsupported")
    if value.get("procedureID") != PROCEDURE_ID or value.get("bundleIdentifier") != BUNDLE_ID:
        raise AuthorizationEnvelopeError("authorization names the wrong procedure or bundle")
    _authorization_id(value.get("authorizationID"))
    _sha(value.get("attemptChallengeSHA256"), "attempt challenge digest")
    if type(value.get("maximumOFF1Starts")) is not int or value["maximumOFF1Starts"] != 1:
        raise AuthorizationEnvelopeError("authorization is not single-start OFF1 authority")
    for key in (
        "issuedAtUnixMilliseconds", "notBeforeUnixMilliseconds", "expiresAtUnixMilliseconds",
    ):
        if type(value.get(key)) is not int or value[key] <= 0:
            raise AuthorizationEnvelopeError(f"{key} is invalid")
    issued = value["issuedAtUnixMilliseconds"]
    not_before = value["notBeforeUnixMilliseconds"]
    expires = value["expiresAtUnixMilliseconds"]
    if not (issued <= not_before < expires):
        raise AuthorizationEnvelopeError("authorization chronology is invalid")
    if expires - issued > MAX_VALIDITY_SECONDS * 1000:
        raise AuthorizationEnvelopeError("authorization validity exceeds the maximum")
    expected = {
        "sourceCommitSHA": evidence["sourceCommitSHA"],
        "buildIdentifier": evidence["buildIdentifier"],
        "buildInstanceID": evidence["buildInstanceID"],
        "executableSHA256": evidence["executableSHA256"],
        "infoPlistSHA256": evidence["infoPlistSHA256"],
        "tuyaDependencyLockSHA256": evidence["tuyaDependencyLockSHA256"],
        "externalBuildRecordSHA256": evidence["externalBuildRecordSHA256"],
        "signedBuildEvidenceSHA256": sha256_hex(evidence_bytes),
        "finalGORecordSHA256": evidence["finalGORecordSHA256"],
        "intendedDevicePseudonymSHA256": evidence["intendedDevicePseudonymSHA256"],
    }
    for key, expected_value in expected.items():
        if value.get(key) != expected_value:
            raise AuthorizationEnvelopeError(f"authorization exact subject mismatch at {key}")
    if not isinstance(value.get("sourceCommitSHA"), str) or not SHA40.fullmatch(value["sourceCommitSHA"]):
        raise AuthorizationEnvelopeError("source commit is not canonical")
    if not isinstance(value.get("buildIdentifier"), str) or not value["buildIdentifier"] \
            or len(value["buildIdentifier"].encode()) > 128 \
            or value["buildIdentifier"] != value["buildIdentifier"].strip():
        raise AuthorizationEnvelopeError("build identifier is invalid")
    if not isinstance(value.get("buildInstanceID"), str) \
            or not artifact_evidence.BUILD_INSTANCE.fullmatch(value["buildInstanceID"]):
        raise AuthorizationEnvelopeError("build instance ID is invalid")
    for key in (
        "executableSHA256", "infoPlistSHA256", "tuyaDependencyLockSHA256",
        "externalBuildRecordSHA256", "signedBuildEvidenceSHA256", "finalGORecordSHA256",
        "intendedDevicePseudonymSHA256",
    ):
        _sha(value.get(key), key)


def _decode_base64(value: object, label: str) -> bytes:
    if not isinstance(value, str):
        raise AuthorizationEnvelopeError(f"{label} is invalid")
    try:
        raw = base64.b64decode(value, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise AuthorizationEnvelopeError(f"{label} is invalid") from error
    if not raw or base64.b64encode(raw).decode("ascii") != value:
        raise AuthorizationEnvelopeError(f"{label} is not canonical base64")
    return raw


def path_is_within(path: Path, directory: Path) -> bool:
    try:
        path.resolve().relative_to(directory.resolve())
        return True
    except ValueError:
        return False


def require_openssl(path: Path) -> str:
    requested = path.expanduser()
    if not requested.is_absolute() or requested.is_symlink():
        raise AuthorizationEnvelopeError("--openssl must be an absolute non-symlink executable")
    try:
        resolved = requested.resolve(strict=True)
        metadata = resolved.stat()
    except OSError as error:
        raise AuthorizationEnvelopeError("configured OpenSSL is unavailable") from error
    if path_is_within(resolved, REPOSITORY_ROOT) or not stat.S_ISREG(metadata.st_mode):
        raise AuthorizationEnvelopeError("OpenSSL custody is invalid")
    if metadata.st_uid != 0 or metadata.st_mode & 0o022 or metadata.st_mode & 0o111 == 0:
        raise AuthorizationEnvelopeError("OpenSSL executable custody is invalid")
    ancestor = resolved.parent
    while True:
        item = ancestor.stat()
        if item.st_uid != 0 or item.st_mode & 0o022:
            raise AuthorizationEnvelopeError("OpenSSL ancestor custody is invalid")
        if ancestor == ancestor.parent:
            break
        ancestor = ancestor.parent
    return str(resolved)


def _run_openssl(openssl: str, args: list[str], *, stdout: bool = False) -> bytes:
    try:
        result = subprocess.run(
            [openssl, *args], check=False, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd="/",
            env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C", "OPENSSL_CONF": "/dev/null"},
            timeout=OPENSSL_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise AuthorizationEnvelopeError("OpenSSL execution failed") from error
    if result.returncode != 0:
        raise AuthorizationEnvelopeError(f"OpenSSL operation failed with status {result.returncode}")
    return result.stdout if stdout else b""


def _read_private_key(path: Path) -> bytes:
    requested = path.expanduser().absolute()
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise AuthorizationEnvelopeError("P-256 private key custody is unavailable")
    components = requested.parts
    if len(components) < 2 or any(component in ("", ".", "..") for component in components[1:]):
        raise AuthorizationEnvelopeError("P-256 private key custody is invalid")
    try:
        requested.relative_to(REPOSITORY_ROOT)
    except ValueError:
        pass
    else:
        raise AuthorizationEnvelopeError("P-256 private key custody is invalid")

    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    file_flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    descriptors: list[int] = []
    try:
        current = os.open("/", directory_flags)
        descriptors.append(current)
        for component in components[1:-1]:
            current = os.open(component, directory_flags, dir_fd=current)
            descriptors.append(current)
            if not stat.S_ISDIR(os.fstat(current).st_mode):
                raise AuthorizationEnvelopeError("P-256 private key ancestor custody is invalid")
        descriptor = os.open(components[-1], file_flags, dir_fd=current)
        descriptors.append(descriptor)
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise AuthorizationEnvelopeError("P-256 private key must be one regular file")
        key_mode = stat.S_IMODE(before.st_mode)
        if key_mode & 0o077 or key_mode != 0o600 or before.st_uid != os.geteuid():
            raise AuthorizationEnvelopeError("P-256 private key must be owner-only mode 0600")
        if before.st_size <= 0 or before.st_size > MAX_PRIVATE_KEY_BYTES:
            raise AuthorizationEnvelopeError("P-256 private key size is invalid")
        data = os.read(descriptor, MAX_PRIVATE_KEY_BYTES + 1)
        after = os.fstat(descriptor)
    except OSError as error:
        raise AuthorizationEnvelopeError("cannot open P-256 private key") from error
    finally:
        for descriptor in reversed(descriptors):
            try:
                os.close(descriptor)
            except OSError:
                pass
    identity = lambda item: (
        item.st_dev, item.st_ino, item.st_size, item.st_mtime_ns, item.st_ctime_ns,
        item.st_mode, item.st_uid, item.st_gid, item.st_nlink,
    )
    if identity(before) != identity(after) or len(data) != before.st_size:
        raise AuthorizationEnvelopeError("P-256 private key changed while reading")
    return data


def _write_private(path: Path, data: bytes) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(descriptor, data)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _x963_from_spki(spki: bytes) -> bytes:
    if len(spki) != len(P256_SPKI_PREFIX) + 65 or not spki.startswith(P256_SPKI_PREFIX):
        raise AuthorizationEnvelopeError("signing key is not P-256")
    x963 = spki[len(P256_SPKI_PREFIX):]
    if x963[0] != 4:
        raise AuthorizationEnvelopeError("P-256 public key is not uncompressed X9.63")
    return x963


def _sign_payload(payload: bytes, private_key_path: Path, openssl_path: Path) -> tuple[bytes, bytes]:
    openssl = require_openssl(openssl_path)
    key_bytes = _read_private_key(private_key_path)
    with tempfile.TemporaryDirectory(prefix="nembra-auth-sign-") as name:
        directory = Path(name); os.chmod(directory, 0o700)
        key = directory / "authority.pem"; body = directory / "payload.json"; signature = directory / "signature.der"
        _write_private(key, key_bytes); _write_private(body, payload)
        spki = _run_openssl(openssl, ["pkey", "-in", str(key), "-pubout", "-outform", "DER"], stdout=True)
        x963 = _x963_from_spki(spki)
        _run_openssl(openssl, ["dgst", "-sha256", "-sign", str(key), "-out", str(signature), str(body)])
        signature_bytes = signature.read_bytes()
        public = directory / "public.pem"
        _run_openssl(openssl, ["pkey", "-in", str(key), "-pubout", "-out", str(public)])
        _run_openssl(openssl, ["dgst", "-sha256", "-verify", str(public), "-signature", str(signature), str(body)])
    if not signature_bytes:
        raise AuthorizationEnvelopeError("OpenSSL produced an empty signature")
    return signature_bytes, x963


def _verify_signature(payload: bytes, signature: bytes, public_key_path: Path, openssl_path: Path) -> bytes:
    openssl = require_openssl(openssl_path)
    public_bytes = artifact_evidence.read_exact_file(public_key_path, "authorization public key", MAX_PRIVATE_KEY_BYTES)
    with tempfile.TemporaryDirectory(prefix="nembra-auth-verify-") as name:
        directory = Path(name); os.chmod(directory, 0o700)
        public = directory / "public.pem"; body = directory / "payload.json"; sig = directory / "signature.der"
        _write_private(public, public_bytes); _write_private(body, payload); _write_private(sig, signature)
        spki = _run_openssl(openssl, ["pkey", "-pubin", "-in", str(public), "-pubout", "-outform", "DER"], stdout=True)
        x963 = _x963_from_spki(spki)
        _run_openssl(openssl, ["dgst", "-sha256", "-verify", str(public), "-signature", str(sig), str(body)])
    return x963


def create_envelope_bytes(
    *, signed_evidence: bytes, authorization_id: str, attempt_challenge_sha256: str,
    issued_at: str, not_before: str, expires_at: str, private_key_path: Path,
    openssl_path: Path,
) -> bytes:
    try:
        evidence = artifact_evidence.verify_evidence_bytes(signed_evidence)
    except artifact_evidence.EvidenceError as error:
        raise AuthorizationEnvelopeError("signed artifact evidence is invalid") from error
    payload = {
        "schema": PAYLOAD_SCHEMA,
        "version": PAYLOAD_SCHEMA_VERSION,
        "decision": DECISION,
        "procedureID": PROCEDURE_ID,
        "authorizationID": authorization_id,
        "attemptChallengeSHA256": attempt_challenge_sha256,
        "issuedAtUnixMilliseconds": _unix_milliseconds(issued_at, "issuedAt"),
        "notBeforeUnixMilliseconds": _unix_milliseconds(not_before, "notBefore"),
        "expiresAtUnixMilliseconds": _unix_milliseconds(expires_at, "expiresAt"),
        "maximumOFF1Starts": MAXIMUM_OFF1_STARTS,
        "bundleIdentifier": evidence["bundleIdentifier"],
        "sourceCommitSHA": evidence["sourceCommitSHA"],
        "buildIdentifier": evidence["buildIdentifier"],
        "buildInstanceID": evidence["buildInstanceID"],
        "executableSHA256": evidence["executableSHA256"],
        "infoPlistSHA256": evidence["infoPlistSHA256"],
        "tuyaDependencyLockSHA256": evidence["tuyaDependencyLockSHA256"],
        "externalBuildRecordSHA256": evidence["externalBuildRecordSHA256"],
        "signedBuildEvidenceSHA256": sha256_hex(signed_evidence),
        "finalGORecordSHA256": evidence["finalGORecordSHA256"],
        "intendedDevicePseudonymSHA256": evidence["intendedDevicePseudonymSHA256"],
    }
    _validate_payload(payload, evidence, signed_evidence)
    payload_bytes = canonical_json_bytes(payload)
    signature, _ = _sign_payload(payload_bytes, private_key_path, openssl_path)
    envelope = canonical_json_bytes({
        "schema": ENVELOPE_SCHEMA,
        "version": ENVELOPE_SCHEMA_VERSION,
        "payloadBase64": base64.b64encode(payload_bytes).decode("ascii"),
        "signatureDERBase64": base64.b64encode(signature).decode("ascii"),
    })
    parse_closed_json(
        envelope, ENVELOPE_KEYS, "authorization envelope", MAX_ENVELOPE_BYTES
    )
    return envelope


def verify_envelope_bytes(
    envelope_bytes: bytes, *, signed_evidence: bytes, public_key_path: Path, openssl_path: Path,
    now: datetime | None = None, expected_authorization_id: str | None = None,
    expected_attempt_challenge_sha256: str | None = None,
) -> dict[str, Any]:
    envelope = parse_closed_json(
        envelope_bytes, ENVELOPE_KEYS, "authorization envelope", MAX_ENVELOPE_BYTES
    )
    if envelope.get("schema") != ENVELOPE_SCHEMA \
            or type(envelope.get("version")) is not int \
            or envelope["version"] != ENVELOPE_SCHEMA_VERSION:
        raise AuthorizationEnvelopeError("unsupported authorization envelope schema")
    payload_bytes = _decode_base64(envelope.get("payloadBase64"), "authorization payload")
    signature = _decode_base64(envelope.get("signatureDERBase64"), "authorization signature")
    payload = parse_closed_json(
        payload_bytes, PAYLOAD_KEYS, "authorization payload", MAX_PAYLOAD_BYTES
    )
    try:
        evidence = artifact_evidence.verify_evidence_bytes(signed_evidence)
    except artifact_evidence.EvidenceError as error:
        raise AuthorizationEnvelopeError("signed artifact evidence is invalid") from error
    _validate_payload(payload, evidence, signed_evidence)
    _verify_signature(payload_bytes, signature, public_key_path, openssl_path)
    if expected_authorization_id is not None and payload["authorizationID"] != expected_authorization_id:
        raise AuthorizationEnvelopeError("authorization ID does not match the expected attempt")
    if expected_attempt_challenge_sha256 is not None \
            and payload["attemptChallengeSHA256"] != expected_attempt_challenge_sha256:
        raise AuthorizationEnvelopeError("attempt challenge does not match the expected attempt")
    instant = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    instant_milliseconds = int(instant.timestamp() * 1000)
    if not (
        payload["notBeforeUnixMilliseconds"]
        <= instant_milliseconds
        < payload["expiresAtUnixMilliseconds"]
    ):
        raise AuthorizationEnvelopeError("authorization is not active")
    return payload


def publish_no_replace(path: Path, data: bytes) -> None:
    output = path.expanduser().absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists() or output.is_symlink():
        raise AuthorizationEnvelopeError("refusing to replace authorization envelope")
    descriptor, staging_name = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
    staging = Path(staging_name)
    linked = False
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data); handle.flush(); os.fsync(handle.fileno())
        os.link(staging, output, follow_symlinks=False); linked = True
        staging.unlink()
        if output.read_bytes() != data:
            raise AuthorizationEnvelopeError("published authorization envelope changed")
    except Exception:
        staging.unlink(missing_ok=True)
        if linked:
            output.unlink(missing_ok=True)
        raise


def self_test() -> None:
    openssl = require_openssl(DEFAULT_SELF_TEST_OPENSSL)
    digest = lambda character: character * 64
    evidence = artifact_evidence.canonical_json_bytes({
        "schemaVersion": artifact_evidence.SCHEMA_VERSION,
        "evidenceKind": "signed-field-artifact-digests-not-authorization",
        "procedureID": PROCEDURE_ID,
        "bundleIdentifier": BUNDLE_ID,
        "sourceCommitSHA": "1" * 40,
        "buildIdentifier": "capture-auth-self-test",
        # Keep this deliberately non-v4: authorization IDs remain UUIDv4, while the build-instance
        # rendezvous is only UUID-shaped and opaque under the runtime/install-manifest contract.
        "buildInstanceID": "12345678-1234-abcd-8def-123456789abc",
        "signedInstallableKind": "ipa",
        "signedInstallableSHA256": digest("2"),
        "executableSHA256": digest("3"),
        "infoPlistSHA256": digest("4"),
        "tuyaDependencyLockSHA256": digest("5"),
        "externalBuildRecordSHA256": digest("6"),
        "finalGORecordSHA256": digest("7"),
        "intendedDevicePseudonymSHA256": digest("8"),
    })
    with tempfile.TemporaryDirectory(prefix="nembra-auth-self-test-", dir=Path.home()) as name:
        directory = Path(name); os.chmod(directory, 0o700)
        key = directory / "ephemeral-test-key.pem"; public = directory / "ephemeral-test-public.pem"
        _run_openssl(openssl, ["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key)])
        os.chmod(key, 0o600)
        _run_openssl(openssl, ["pkey", "-in", str(key), "-pubout", "-out", str(public)])
        issued = "2026-08-19T20:00:00Z"; expires = "2026-08-19T20:10:00Z"
        authorization_id = "87654321-4321-4321-8321-cba987654321"
        challenge = digest("9")
        envelope = create_envelope_bytes(
            signed_evidence=evidence, authorization_id=authorization_id,
            attempt_challenge_sha256=challenge, issued_at=issued, not_before=issued,
            expires_at=expires, private_key_path=key, openssl_path=DEFAULT_SELF_TEST_OPENSSL,
        )
        verified = verify_envelope_bytes(
            envelope, signed_evidence=evidence, public_key_path=public,
            openssl_path=DEFAULT_SELF_TEST_OPENSSL,
            now=datetime(2026, 8, 19, 20, 1, tzinfo=timezone.utc),
            expected_authorization_id=authorization_id,
            expected_attempt_challenge_sha256=challenge,
        )
        if verified["maximumOFF1Starts"] != 1:
            raise AuthorizationEnvelopeError("self-test accepted replay-unsafe authority")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--verify", type=Path)
    parser.add_argument("--signed-evidence", type=Path)
    parser.add_argument("--private-key", type=Path)
    parser.add_argument("--public-key", type=Path)
    parser.add_argument("--openssl", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--authorization-id")
    parser.add_argument("--attempt-challenge-sha256")
    parser.add_argument("--issued-at")
    parser.add_argument("--not-before")
    parser.add_argument("--expires-at")
    parser.add_argument("--now")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        if len(argv) != 1:
            raise AuthorizationEnvelopeError("--self-test accepts no other arguments")
        self_test(); print("offline authorization signer self-test: PASS")
        return 0
    if args.verify:
        required = (args.signed_evidence, args.public_key, args.openssl)
        if any(value is None for value in required):
            raise AuthorizationEnvelopeError("verification requires signed evidence, public key, and OpenSSL")
        evidence = artifact_evidence.read_exact_file(args.signed_evidence, "signed artifact evidence", MAX_JSON_BYTES)
        envelope = artifact_evidence.read_exact_file(args.verify, "authorization envelope", MAX_JSON_BYTES)
        now = _timestamp(args.now, "now") if args.now else None
        payload = verify_envelope_bytes(
            envelope, signed_evidence=evidence, public_key_path=args.public_key,
            openssl_path=args.openssl, now=now,
            expected_authorization_id=args.authorization_id,
            expected_attempt_challenge_sha256=args.attempt_challenge_sha256,
        )
        print(json.dumps({"status": "VERIFIED_SINGLE_ATTEMPT", "payloadSHA256": sha256_hex(canonical_json_bytes(payload))}, sort_keys=True))
        return 0
    required = (
        args.signed_evidence, args.private_key, args.openssl, args.output, args.authorization_id,
        args.attempt_challenge_sha256, args.issued_at, args.not_before, args.expires_at,
    )
    if any(value is None for value in required):
        raise AuthorizationEnvelopeError("missing required creation arguments")
    evidence = artifact_evidence.read_exact_file(args.signed_evidence, "signed artifact evidence", MAX_JSON_BYTES)
    envelope = create_envelope_bytes(
        signed_evidence=evidence, authorization_id=args.authorization_id,
        attempt_challenge_sha256=args.attempt_challenge_sha256, issued_at=args.issued_at,
        not_before=args.not_before, expires_at=args.expires_at,
        private_key_path=args.private_key, openssl_path=args.openssl,
    )
    publish_no_replace(args.output, envelope)
    print(json.dumps({"status": "SIGNED_SINGLE_ATTEMPT_AUTHORIZATION", "envelopeSHA256": sha256_hex(envelope)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (AuthorizationEnvelopeError, artifact_evidence.EvidenceError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
