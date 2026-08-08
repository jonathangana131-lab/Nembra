#!/usr/bin/env python3
"""Bind signed-field evidence to one private immutable IPA snapshot.

The implementation core performs the existing signing/provisioning/evidence checks. This entrypoint
first copies the caller-provided IPA through one no-follow file descriptor into a private temporary
snapshot, proves the source stayed stable across two complete reads, then uses only that snapshot for
digesting, extraction/signing inspection, and retained evidence publication.

This tool still cannot authorize physical Experiment One.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import stat
import sys
import tempfile
from pathlib import Path

_CORE_PATH = Path(__file__).resolve().with_name("_es80_signed_field_artifact_evidence_core.py")
_CORE_SPEC = importlib.util.spec_from_file_location("nembra_signed_field_artifact_evidence_core", _CORE_PATH)
if _CORE_SPEC is None or _CORE_SPEC.loader is None:
    raise RuntimeError("canonical signed-field evidence core could not be loaded")
_core = importlib.util.module_from_spec(_CORE_SPEC)
_CORE_SPEC.loader.exec_module(_core)

# Preserve the incumbent module's public read/validation surface for existing tests and callers while
# keeping this file responsible for the exact-input boundary and CLI. The core file is an internal
# non-executable copy of the previously canonical implementation, not a second evidence vocabulary.
for _name in dir(_core):
    if not _name.startswith("_") and _name != "main":
        globals()[_name] = getattr(_core, _name)

EvidenceError = _core.EvidenceError
_SNAPSHOT_CHUNK_BYTES = 1024 * 1024


def _descriptor_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _hash_descriptor(descriptor: int) -> tuple[str, int]:
    os.lseek(descriptor, 0, os.SEEK_SET)
    digest = hashlib.sha256()
    byte_count = 0
    while True:
        chunk = os.read(descriptor, _SNAPSHOT_CHUNK_BYTES)
        if not chunk:
            break
        digest.update(chunk)
        byte_count += len(chunk)
    return digest.hexdigest(), byte_count


def _write_all(descriptor: int, payload: bytes) -> None:
    view = memoryview(payload)
    while view:
        written = os.write(descriptor, view)
        if written <= 0:
            raise EvidenceError("could not write exact signed-field IPA snapshot")
        view = view[written:]


def snapshot_exact_ipa(source_path: Path, snapshot_path: Path) -> tuple[str, int]:
    """Copy one stable regular IPA subject through one no-follow descriptor.

    The first pass is simultaneously hashed and copied. A second complete hash pass through the same
    descriptor must match, and source identity/size/mtime/ctime must remain unchanged across both
    passes. The private snapshot is then made read-only before any inspector consumes it.
    """
    if not hasattr(os, "O_NOFOLLOW"):
        raise EvidenceError("this platform cannot enforce no-follow exact IPA snapshot input")

    source_flags = os.O_RDONLY | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        source_flags |= os.O_CLOEXEC
    try:
        source_descriptor = os.open(os.fspath(source_path), source_flags)
    except OSError as exc:
        raise EvidenceError("signed field IPA input must be one readable non-symlink file") from exc

    snapshot_descriptor: int | None = None
    snapshot_created = False
    succeeded = False
    try:
        before = os.fstat(source_descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size <= 0:
            raise EvidenceError("signed field IPA input must be one non-empty regular file")

        destination_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_CLOEXEC"):
            destination_flags |= os.O_CLOEXEC
        try:
            snapshot_descriptor = os.open(
                os.fspath(snapshot_path),
                destination_flags,
                0o600,
            )
            snapshot_created = True
        except OSError as exc:
            raise EvidenceError("private signed-field IPA snapshot destination must be absent") from exc

        os.lseek(source_descriptor, 0, os.SEEK_SET)
        first_digest = hashlib.sha256()
        first_count = 0
        while True:
            chunk = os.read(source_descriptor, _SNAPSHOT_CHUNK_BYTES)
            if not chunk:
                break
            first_digest.update(chunk)
            first_count += len(chunk)
            _write_all(snapshot_descriptor, chunk)

        middle = os.fstat(source_descriptor)
        second_sha256, second_count = _hash_descriptor(source_descriptor)
        after = os.fstat(source_descriptor)
        first_sha256 = first_digest.hexdigest()

        stable_identity = (
            _descriptor_identity(before)
            == _descriptor_identity(middle)
            == _descriptor_identity(after)
        )
        if (
            not stable_identity
            or first_count != before.st_size
            or second_count != before.st_size
            or first_sha256 != second_sha256
        ):
            raise EvidenceError(
                "signed field IPA changed while the exact evidence subject was being snapshotted"
            )

        os.fsync(snapshot_descriptor)
        os.fchmod(snapshot_descriptor, 0o400)
        succeeded = True
        return first_sha256, first_count
    finally:
        if snapshot_descriptor is not None:
            os.close(snapshot_descriptor)
        os.close(source_descriptor)
        if snapshot_created and not succeeded:
            try:
                snapshot_path.unlink()
            except FileNotFoundError:
                pass


def _snapshot_self_test() -> None:
    payload = b"exact signed field ipa fixture"
    with tempfile.TemporaryDirectory(prefix="nembra-field-snapshot-self-test-") as temporary:
        root = Path(temporary)
        source = root / "candidate.ipa"
        source.write_bytes(payload)
        snapshot = root / "private-snapshot.ipa"

        digest, byte_count = snapshot_exact_ipa(source, snapshot)
        assert digest == hashlib.sha256(payload).hexdigest()
        assert byte_count == len(payload)
        assert snapshot.read_bytes() == payload
        assert stat.S_IMODE(snapshot.stat().st_mode) == 0o400

        existing = root / "existing.ipa"
        existing.write_bytes(b"do not replace")
        try:
            snapshot_exact_ipa(source, existing)
        except EvidenceError:
            pass
        else:
            raise AssertionError("existing exact-subject snapshot destination must fail closed")
        assert existing.read_bytes() == b"do not replace"

        symlink = root / "candidate-link.ipa"
        try:
            symlink.symlink_to(source)
        except (OSError, NotImplementedError):
            symlink = None
        if symlink is not None:
            try:
                snapshot_exact_ipa(symlink, root / "symlink-snapshot.ipa")
            except EvidenceError:
                pass
            else:
                raise AssertionError("symlink signed-field IPA input must fail closed")


def main(argv: list[str]) -> int:
    args = _core.parse_args(argv)
    if args.self_test:
        _core.self_test()
        _snapshot_self_test()
        print("signed-field artifact evidence self-test: PASS")
        return 0

    missing = [
        name
        for name, value in (
            ("--ipa", args.ipa),
            ("--output-dir", args.output_dir),
            ("--expected-source-sha", args.expected_source_sha),
            ("--intended-device-udid", args.intended_device_udid),
        )
        if value is None
    ]
    if missing:
        raise EvidenceError(f"required arguments missing: {', '.join(missing)}")

    with tempfile.TemporaryDirectory(prefix="nembra-field-input-snapshot-") as temporary:
        snapshot_path = Path(temporary) / "NembraField.ipa"
        snapshot_sha256, snapshot_byte_count = snapshot_exact_ipa(args.ipa, snapshot_path)

        inspection = _core.inspect_ipa(
            snapshot_path,
            args.expected_source_sha,
            intended_device_udid=args.intended_device_udid,
        )
        if (
            inspection["field_build_record"]["signedInstallableSHA256"] != snapshot_sha256
            or inspection["signing_inspection"]["signedInstallableSHA256"] != snapshot_sha256
            or inspection["signing_inspection"]["ipaByteCount"] != snapshot_byte_count
            or _core.sha256_file(snapshot_path) != snapshot_sha256
        ):
            raise EvidenceError(
                "signed-field inspection diverged from the single exact snapshotted IPA subject"
            )

        paths = _core.write_outputs(snapshot_path, args.output_dir.resolve(), inspection)

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
