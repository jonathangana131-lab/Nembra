#!/usr/bin/env python3
"""Create a candidate Nembra Capture field-authorization envelope offline.

This tool deliberately does not parse or promote the schema-v3 external build record or the
canonical field-build evidence record. The package owns those semantic parsers. This tool treats
both files as exact byte subjects, hashes them, creates the exact authorization payload schema
accepted by `PassiveBluetoothCaptureFieldAuthorizationVerifier`, and signs that payload with a
P-256 private key held outside this repository.

A successful envelope is NOT physical GO. It becomes usable software field authority only after an
independently controlled public key is reviewed/pinned in package source, the exact final signed
build/evidence subjects are independently accepted, the running app matches those subjects, the
package field gate deliberately consumes verified authority, and the definitive runbook becomes GO.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

ENVELOPE_SCHEMA_VERSION = 2
AUTHORIZATION_PAYLOAD_SCHEMA_VERSION = 2
DECISION = "GO"
MAX_SUBJECT_BYTES = 1024 * 1024

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
P256_SPKI_PREFIX = bytes.fromhex(
    "3059301306072a8648ce3d020106082a8648ce3d030107034200"
)
P256_X963_LENGTH = 65


class AuthorizationEnvelopeError(RuntimeError):
    pass


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False).encode("utf-8") + b"\n"


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def path_is_within(path: Path, directory: Path) -> bool:
    path_text = os.path.normcase(str(path.resolve()))
    directory_text = os.path.normcase(str(directory.resolve()))
    try:
        return os.path.commonpath([path_text, directory_text]) == directory_text
    except ValueError:
        return False


def require_external_path(path: Path, label: str) -> Path:
    requested = path.expanduser().absolute()
    if requested.is_symlink():
        raise AuthorizationEnvelopeError(f"{label} must not be a symlink")
    resolved = requested.resolve()
    if path_is_within(resolved, REPOSITORY_ROOT):
        raise AuthorizationEnvelopeError(
            f"{label} must remain outside the Nembra repository: {resolved}"
        )
    return resolved


def read_exact_subject(path: Path, label: str) -> bytes:
    requested = path.expanduser().absolute()
    if requested.is_symlink():
        raise AuthorizationEnvelopeError(f"{label} must be one regular non-symlink file")
    resolved = requested.resolve()
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(resolved, flags)
    except OSError as exc:
        raise AuthorizationEnvelopeError(f"cannot open {label}") from exc

    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise AuthorizationEnvelopeError(f"{label} must be one regular file")
        if before.st_size <= 0 or before.st_size > MAX_SUBJECT_BYTES:
            raise AuthorizationEnvelopeError(
                f"{label} size must be 1..{MAX_SUBJECT_BYTES} bytes; got {before.st_size}"
            )
        with os.fdopen(descriptor, "rb", closefd=True) as handle:
            descriptor = -1
            data = handle.read(MAX_SUBJECT_BYTES + 1)
            after = os.fstat(handle.fileno())
    finally:
        if descriptor >= 0:
            os.close(descriptor)

    stable_identity = (
        before.st_dev,
        before.st_ino,
        before.st_size,
        before.st_mtime_ns,
        before.st_ctime_ns,
    ) == (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
        after.st_ctime_ns,
    )
    if not stable_identity or len(data) != before.st_size:
        raise AuthorizationEnvelopeError(f"{label} changed while being read")
    return data


def require_private_key(path: Path) -> Path:
    requested = path.expanduser().absolute()
    if requested.is_symlink():
        raise AuthorizationEnvelopeError(
            "P-256 private key must be one regular non-symlink file outside the repository"
        )
    resolved = require_external_path(requested, "P-256 private key")
    try:
        key_stat = resolved.stat()
    except OSError as exc:
        raise AuthorizationEnvelopeError("cannot stat P-256 private key") from exc
    if not stat.S_ISREG(key_stat.st_mode):
        raise AuthorizationEnvelopeError(
            "P-256 private key must be one regular non-symlink file outside the repository"
        )
    if key_stat.st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise AuthorizationEnvelopeError(
            "P-256 private key permissions must deny all group/other access (for example chmod 600)"
        )
    return resolved


def require_openssl() -> str:
    executable = shutil.which("openssl")
    if executable is None:
        raise AuthorizationEnvelopeError("OpenSSL is required for offline P-256 signing")
    return executable


def run_openssl(
    openssl: str,
    arguments: list[str],
    *,
    capture_stdout: bool = False,
) -> bytes:
    try:
        completed = subprocess.run(
            [openssl, *arguments],
            check=False,
            stdout=subprocess.PIPE if capture_stdout else None,
        )
    except OSError as exc:
        raise AuthorizationEnvelopeError("could not execute OpenSSL") from exc
    if completed.returncode != 0:
        raise AuthorizationEnvelopeError(
            f"OpenSSL command failed with status {completed.returncode}"
        )
    return completed.stdout or b""


def public_key_x963_from_private_key(openssl: str, private_key: Path) -> bytes:
    spki = run_openssl(
        openssl,
        ["pkey", "-in", str(private_key), "-pubout", "-outform", "DER"],
        capture_stdout=True,
    )
    if not spki.startswith(P256_SPKI_PREFIX):
        raise AuthorizationEnvelopeError(
            "authorization private key must be P-256 / prime256v1"
        )
    x963 = spki[len(P256_SPKI_PREFIX) :]
    if len(x963) != P256_X963_LENGTH or x963[0] != 0x04:
        raise AuthorizationEnvelopeError(
            "authorization public key is not one uncompressed P-256 X9.63 point"
        )
    if len(spki) != len(P256_SPKI_PREFIX) + P256_X963_LENGTH:
        raise AuthorizationEnvelopeError("authorization public-key encoding is not canonical P-256")
    return x963


def sign_payload(
    openssl: str,
    private_key: Path,
    payload: bytes,
) -> tuple[bytes, bytes]:
    x963 = public_key_x963_from_private_key(openssl, private_key)
    with tempfile.TemporaryDirectory(prefix="nembra-field-auth-sign-") as temporary:
        directory = Path(temporary)
        payload_path = directory / "authorization-payload.json"
        signature_path = directory / "authorization-signature.der"
        public_key_path = directory / "authorization-public-key.pem"
        payload_path.write_bytes(payload)

        run_openssl(
            openssl,
            [
                "dgst",
                "-sha256",
                "-sign",
                str(private_key),
                "-out",
                str(signature_path),
                str(payload_path),
            ],
        )
        run_openssl(
            openssl,
            ["pkey", "-in", str(private_key), "-pubout", "-out", str(public_key_path)],
        )
        signature = signature_path.read_bytes()
        if not signature:
            raise AuthorizationEnvelopeError("OpenSSL produced an empty authorization signature")
        run_openssl(
            openssl,
            [
                "dgst",
                "-sha256",
                "-verify",
                str(public_key_path),
                "-signature",
                str(signature_path),
                str(payload_path),
            ],
        )
        if payload_path.read_bytes() != payload:
            raise AuthorizationEnvelopeError("authorization payload bytes changed during signing")
    return signature, x963


def build_payload(external_record: bytes, field_evidence: bytes) -> bytes:
    return canonical_json_bytes(
        {
            "schemaVersion": AUTHORIZATION_PAYLOAD_SCHEMA_VERSION,
            "decision": DECISION,
            "externalBuildRecordSHA256": sha256_hex(external_record),
            "fieldBuildEvidenceRecordSHA256": sha256_hex(field_evidence),
        }
    )


def build_envelope(
    external_record: bytes,
    field_evidence: bytes,
    payload: bytes,
    signature_der: bytes,
) -> bytes:
    return canonical_json_bytes(
        {
            "schemaVersion": ENVELOPE_SCHEMA_VERSION,
            "externalBuildRecordBase64": base64.b64encode(external_record).decode("ascii"),
            "fieldBuildEvidenceRecordBase64": base64.b64encode(field_evidence).decode("ascii"),
            "authorizationPayloadBase64": base64.b64encode(payload).decode("ascii"),
            "signatureDERBase64": base64.b64encode(signature_der).decode("ascii"),
        }
    )


def write_envelope_no_replace(output: Path, envelope: bytes) -> Path:
    resolved = require_external_path(output, "signed authorization envelope output")
    resolved.parent.mkdir(parents=True, exist_ok=True)
    try:
        with resolved.open("xb") as handle:
            handle.write(envelope)
            handle.flush()
            os.fsync(handle.fileno())
    except FileExistsError as exc:
        raise AuthorizationEnvelopeError(
            f"refusing to overwrite existing signed authorization envelope: {resolved}"
        ) from exc
    except OSError as exc:
        raise AuthorizationEnvelopeError("could not publish signed authorization envelope") from exc
    if resolved.read_bytes() != envelope:
        raise AuthorizationEnvelopeError("published authorization envelope bytes diverged")
    return resolved


def create_envelope(
    external_record_path: Path,
    field_evidence_path: Path,
    private_key_path: Path,
    output_path: Path,
) -> dict[str, str]:
    external_record = read_exact_subject(external_record_path, "external build record")
    field_evidence = read_exact_subject(field_evidence_path, "field-build evidence record")
    private_key = require_private_key(private_key_path)
    output = require_external_path(output_path, "signed authorization envelope output")
    if output == private_key:
        raise AuthorizationEnvelopeError("authorization output cannot replace the private key")

    payload = build_payload(external_record, field_evidence)
    openssl = require_openssl()
    signature, public_key_x963 = sign_payload(openssl, private_key, payload)
    envelope = build_envelope(external_record, field_evidence, payload, signature)
    published = write_envelope_no_replace(output, envelope)

    return {
        "status": "SIGNED_AUTHORIZATION_ENVELOPE_NOT_PHYSICAL_GO",
        "envelope": str(published),
        "envelopeSHA256": sha256_hex(envelope),
        "authorizationPayloadSHA256": sha256_hex(payload),
        "externalBuildRecordSHA256": sha256_hex(external_record),
        "fieldBuildEvidenceRecordSHA256": sha256_hex(field_evidence),
        "authorityPublicKeyX963Base64": base64.b64encode(public_key_x963).decode("ascii"),
        "authorityPublicKeyX963SHA256": sha256_hex(public_key_x963),
    }


def self_test() -> None:
    openssl = require_openssl()
    with tempfile.TemporaryDirectory(prefix="nembra-field-auth-self-test-") as temporary:
        directory = Path(temporary)
        private_key = directory / "candidate-authority-private-key.pem"
        external_record = directory / "NembraCaptureExternalBuildRecord.json"
        field_evidence = directory / "NembraCaptureFieldBuildEvidenceRecord.json"
        envelope_path = directory / "NembraCaptureFieldAuthorizationEnvelope.json"

        run_openssl(
            openssl,
            ["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(private_key)],
        )
        external_bytes = b'{"schemaVersion":3,"fixture":"opaque-external-subject"}\n'
        evidence_bytes = b'{"schemaVersion":1,"fixture":"opaque-field-evidence-subject"}\n'
        external_record.write_bytes(external_bytes)
        field_evidence.write_bytes(evidence_bytes)

        result = create_envelope(
            external_record,
            field_evidence,
            private_key,
            envelope_path,
        )
        envelope = json.loads(envelope_path.read_bytes())
        if set(envelope) != {
            "schemaVersion",
            "externalBuildRecordBase64",
            "fieldBuildEvidenceRecordBase64",
            "authorizationPayloadBase64",
            "signatureDERBase64",
        }:
            raise AssertionError("generated envelope key set drifted")
        if envelope["schemaVersion"] != ENVELOPE_SCHEMA_VERSION:
            raise AssertionError("generated envelope schema drifted")
        if base64.b64decode(envelope["externalBuildRecordBase64"], validate=True) != external_bytes:
            raise AssertionError("external build record exact bytes were not preserved")
        if base64.b64decode(envelope["fieldBuildEvidenceRecordBase64"], validate=True) != evidence_bytes:
            raise AssertionError("field evidence exact bytes were not preserved")

        payload = base64.b64decode(envelope["authorizationPayloadBase64"], validate=True)
        payload_object = json.loads(payload)
        expected_payload = {
            "schemaVersion": AUTHORIZATION_PAYLOAD_SCHEMA_VERSION,
            "decision": DECISION,
            "externalBuildRecordSHA256": sha256_hex(external_bytes),
            "fieldBuildEvidenceRecordSHA256": sha256_hex(evidence_bytes),
        }
        if payload_object != expected_payload:
            raise AssertionError("authorization payload drifted from exact subject digests")
        if sha256_hex(payload) != result["authorizationPayloadSHA256"]:
            raise AssertionError("reported authorization payload digest is wrong")

        signature = base64.b64decode(envelope["signatureDERBase64"], validate=True)
        if not signature or signature[0] != 0x30:
            raise AssertionError("signature is not a non-empty DER ECDSA sequence")
        if len(base64.b64decode(result["authorityPublicKeyX963Base64"], validate=True)) != 65:
            raise AssertionError("reported P-256 X9.63 public key length is wrong")

        try:
            create_envelope(
                external_record,
                field_evidence,
                private_key,
                envelope_path,
            )
        except AuthorizationEnvelopeError as error:
            if "refusing to overwrite" not in str(error):
                raise
        else:
            raise AssertionError("existing authorization envelope was overwritten")

        private_key.chmod(0o644)
        try:
            require_private_key(private_key)
        except AuthorizationEnvelopeError as error:
            if "permissions must deny all group/other access" not in str(error):
                raise
        else:
            raise AssertionError("group/world-readable authorization private key was accepted")

    repository_private_key = REPOSITORY_ROOT / "never-create-this-private-key.pem"
    try:
        require_external_path(repository_private_key, "P-256 private key")
    except AuthorizationEnvelopeError:
        pass
    else:
        raise AssertionError("repository-contained private-key path was accepted")

    repository_envelope = REPOSITORY_ROOT / "never-create-this-authorization-envelope.json"
    try:
        require_external_path(repository_envelope, "signed authorization envelope output")
    except AuthorizationEnvelopeError:
        pass
    else:
        raise AssertionError("repository-contained authorization output path was accepted")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--external-record", type=Path)
    parser.add_argument("--field-evidence", type=Path)
    parser.add_argument("--private-key-pem", type=Path)
    parser.add_argument("--output-envelope", type=Path)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    arguments = parse_args(argv)
    if arguments.self_test:
        self_test()
        print("field authorization envelope self-test: PASS")
        return 0

    missing = [
        name
        for name, value in (
            ("--external-record", arguments.external_record),
            ("--field-evidence", arguments.field_evidence),
            ("--private-key-pem", arguments.private_key_pem),
            ("--output-envelope", arguments.output_envelope),
        )
        if value is None
    ]
    if missing:
        raise AuthorizationEnvelopeError(
            f"required arguments missing: {', '.join(missing)}"
        )

    result = create_envelope(
        arguments.external_record,
        arguments.field_evidence,
        arguments.private_key_pem,
        arguments.output_envelope,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except AuthorizationEnvelopeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
