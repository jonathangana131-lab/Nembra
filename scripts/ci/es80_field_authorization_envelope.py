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
import stat
import subprocess
import sys
import tempfile

ENVELOPE_SCHEMA_VERSION = 2
AUTHORIZATION_PAYLOAD_SCHEMA_VERSION = 2
DECISION = "GO"
MAX_SUBJECT_BYTES = 1024 * 1024
MAX_PRIVATE_KEY_BYTES = 64 * 1024
DEFAULT_OPENSSL_PATH = "/usr/bin/openssl"

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


def require_openssl() -> str:
    """Resolve one explicitly controlled OpenSSL executable without consulting ambient PATH."""
    configured = os.environ.get("NEMBRA_OPENSSL", DEFAULT_OPENSSL_PATH)
    requested = Path(configured).expanduser()
    if not requested.is_absolute():
        raise AuthorizationEnvelopeError(
            "NEMBRA_OPENSSL must name one absolute OpenSSL executable path"
        )
    if requested.is_symlink():
        raise AuthorizationEnvelopeError(
            "OpenSSL executable must be an explicit non-symlink path"
        )
    try:
        resolved = requested.resolve(strict=True)
        executable_stat = resolved.stat()
    except OSError as exc:
        raise AuthorizationEnvelopeError(
            f"configured OpenSSL executable is unavailable: {requested}"
        ) from exc

    if path_is_within(resolved, REPOSITORY_ROOT):
        raise AuthorizationEnvelopeError(
            "OpenSSL executable must not be controlled by the Nembra repository"
        )
    if not stat.S_ISREG(executable_stat.st_mode):
        raise AuthorizationEnvelopeError("OpenSSL executable must be one regular file")
    if executable_stat.st_mode & 0o022:
        raise AuthorizationEnvelopeError(
            "OpenSSL executable must not be writable by group or other users"
        )
    if executable_stat.st_mode & 0o111 == 0:
        raise AuthorizationEnvelopeError("configured OpenSSL file is not executable")

    if hasattr(os, "geteuid"):
        signing_uid = os.geteuid()
        if executable_stat.st_uid not in {0, signing_uid}:
            raise AuthorizationEnvelopeError(
                "OpenSSL executable must be owned by root or the signing user"
            )

    directory = resolved.parent
    while True:
        try:
            directory_stat = directory.stat()
        except OSError as exc:
            raise AuthorizationEnvelopeError(
                "could not inspect OpenSSL executable custody path"
            ) from exc
        if directory_stat.st_mode & 0o022:
            raise AuthorizationEnvelopeError(
                f"OpenSSL custody path is group/world-writable: {directory}"
            )
        if directory == directory.parent:
            break
        directory = directory.parent

    return str(resolved)


def run_openssl(
    openssl: str,
    arguments: list[str],
    *,
    capture_stdout: bool = False,
    pass_fds: tuple[int, ...] = (),
) -> bytes:
    try:
        completed = subprocess.run(
            [openssl, *arguments],
            check=False,
            stdout=subprocess.PIPE if capture_stdout else None,
            pass_fds=pass_fds,
        )
    except OSError as exc:
        raise AuthorizationEnvelopeError("could not execute OpenSSL") from exc
    if completed.returncode != 0:
        raise AuthorizationEnvelopeError(
            f"OpenSSL command failed with status {completed.returncode}"
        )
    return completed.stdout or b""


def snapshot_private_key(openssl: str, private_key_path: Path, directory: Path) -> Path:
    """Create one immutable-for-this-operation private key snapshot from one no-follow descriptor.

    The source key path is never reopened after this function begins. OpenSSL reads the exact opened
    inode through `/dev/fd`, canonicalizes it once into a private temporary snapshot, and all later
    public-key derivation/signing/verification uses only that snapshot.
    """
    resolved = require_external_path(private_key_path, "P-256 private key")
    if not hasattr(os, "O_NOFOLLOW"):
        raise AuthorizationEnvelopeError("platform cannot enforce no-follow authority-key input")

    flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(resolved, flags)
    except OSError as exc:
        raise AuthorizationEnvelopeError("cannot open P-256 private key") from exc

    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise AuthorizationEnvelopeError(
                "P-256 private key must be one regular non-symlink file outside the repository"
            )
        if before.st_size <= 0 or before.st_size > MAX_PRIVATE_KEY_BYTES:
            raise AuthorizationEnvelopeError(
                f"P-256 private key size must be 1..{MAX_PRIVATE_KEY_BYTES} bytes"
            )
        if before.st_mode & 0o077:
            raise AuthorizationEnvelopeError(
                "P-256 private key must not be accessible by group or other users"
            )
        if hasattr(os, "geteuid") and before.st_uid != os.geteuid():
            raise AuthorizationEnvelopeError(
                "P-256 private key must be owned by the signing user"
            )

        fd_path = Path("/dev/fd") / str(descriptor)
        if not fd_path.exists():
            raise AuthorizationEnvelopeError("platform does not expose inherited private-key file descriptors")

        snapshot_path = directory / "authorization-private-key.pem"
        snapshot_path.touch(mode=0o600, exist_ok=False)
        snapshot_path.chmod(0o600)
        os.lseek(descriptor, 0, os.SEEK_SET)
        run_openssl(
            openssl,
            ["pkey", "-in", str(fd_path), "-out", str(snapshot_path)],
            pass_fds=(descriptor,),
        )
        after = os.fstat(descriptor)

        stable_source = (
            before.st_dev,
            before.st_ino,
            before.st_mode,
            before.st_uid,
            before.st_gid,
            before.st_size,
            before.st_mtime_ns,
            before.st_ctime_ns,
        ) == (
            after.st_dev,
            after.st_ino,
            after.st_mode,
            after.st_uid,
            after.st_gid,
            after.st_size,
            after.st_mtime_ns,
            after.st_ctime_ns,
        )
        if not stable_source:
            raise AuthorizationEnvelopeError("P-256 private key changed while the signing snapshot was created")

        snapshot_stat = snapshot_path.stat()
        if not stat.S_ISREG(snapshot_stat.st_mode) or snapshot_stat.st_size <= 0:
            raise AuthorizationEnvelopeError("OpenSSL did not produce one private signing-key snapshot")
        if snapshot_stat.st_mode & 0o077:
            raise AuthorizationEnvelopeError("private signing-key snapshot permissions are not private")
        if hasattr(os, "geteuid") and snapshot_stat.st_uid != os.geteuid():
            raise AuthorizationEnvelopeError("private signing-key snapshot has the wrong owner")
        return snapshot_path
    finally:
        os.close(descriptor)


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
    private_key_source: Path,
    payload: bytes,
) -> tuple[bytes, bytes]:
    with tempfile.TemporaryDirectory(prefix="nembra-field-auth-sign-") as temporary:
        directory = Path(temporary)
        directory.chmod(0o700)
        private_key = snapshot_private_key(openssl, private_key_source, directory)
        x963 = public_key_x963_from_private_key(openssl, private_key)

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
    private_key = require_external_path(private_key_path, "P-256 private key")
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
        private_key.chmod(0o600)
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

        permissive_key = directory / "permissive-private-key.pem"
        run_openssl(
            openssl,
            ["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(permissive_key)],
        )
        permissive_key.chmod(0o644)
        try:
            create_envelope(
                external_record,
                field_evidence,
                permissive_key,
                directory / "permissive-key-envelope.json",
            )
        except AuthorizationEnvelopeError as error:
            if "group or other" not in str(error):
                raise
        else:
            raise AssertionError("group/other-readable authority private key was accepted")

        # Prove signer identity is detached from later source-path replacement: snapshot key A once,
        # replace the source path with key B, and require the snapshot's public point to stay key A.
        snapshot_directory = directory / "snapshot-test"
        snapshot_directory.mkdir(mode=0o700)
        snapshot = snapshot_private_key(openssl, private_key, snapshot_directory)
        snapshot_x963 = public_key_x963_from_private_key(openssl, snapshot)
        replacement_key = directory / "replacement-private-key.pem"
        run_openssl(
            openssl,
            ["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(replacement_key)],
        )
        replacement_key.chmod(0o600)
        replacement_x963 = public_key_x963_from_private_key(openssl, replacement_key)
        if replacement_x963 == snapshot_x963:
            raise AssertionError("replacement fixture unexpectedly reused the original P-256 key")
        os.replace(replacement_key, private_key)
        if public_key_x963_from_private_key(openssl, snapshot) != snapshot_x963:
            raise AssertionError("private signing snapshot changed after source-path replacement")

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
