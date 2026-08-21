#!/usr/bin/env python3
"""Delegate one ES80 field-authorization signing request from an app rendezvous document.

This remains an orchestration wrapper, not a second signer. The caller must supply the independently
accepted exact source commit that is allowed to select every Python source able to observe the
private-key path. The wrapper resolves only immutable Git objects from that commit, re-hashes them,
materializes those bytes into a private execution bundle, and cross-checks that same source commit
against the independently accepted signed-evidence subject before launching the signer.

Cryptographic payload construction, signed-evidence parsing, signing, self-verification, and
no-replace publication remain owned by `es80_field_authorization_envelope.py`.

This source change does not promote the wrapper into the physical/private runbook. A production
invocation still has to execute this wrapper itself from an independently pinned/accepted source
boundary; mutable checkout execution is not private-key authority.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Iterator

HERE = Path(__file__).resolve().parent
REPOSITORY_ROOT = HERE.parents[1]
GIT = Path("/usr/bin/git")
PYTHON = Path("/usr/bin/python3")
MAX_SOURCE_BYTES = 1_048_576
SHA40 = re.compile(r"^[0-9a-f]{40}$")
RFC3339_SECONDS = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

EXECUTION_SOURCES = (
    "scripts/ci/es80_sign_field_authorization_from_rendezvous.py",
    "scripts/ci/es80_field_authorization_rendezvous.py",
    "scripts/ci/es80_field_authorization_envelope.py",
    "scripts/ci/es80_signed_field_artifact_evidence.py",
)
RENDEZVOUS_BASENAME = "es80_field_authorization_rendezvous.py"
SIGNER_BASENAME = "es80_field_authorization_envelope.py"
EVIDENCE_BASENAME = "es80_signed_field_artifact_evidence.py"


class SignerExecutionCustodyError(RuntimeError):
    pass


def _git_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }


def _git_bytes(*arguments: str) -> bytes:
    if not GIT.is_file():
        raise SignerExecutionCustodyError("trusted /usr/bin/git is unavailable")
    try:
        completed = subprocess.run(
            [str(GIT), *arguments],
            cwd=REPOSITORY_ROOT,
            env=_git_environment(),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise SignerExecutionCustodyError("immutable Git-object lookup failed") from error
    return completed.stdout


def _git_text(*arguments: str) -> str:
    try:
        return _git_bytes(*arguments).decode("ascii").strip()
    except UnicodeDecodeError as error:
        raise SignerExecutionCustodyError("Git identity output is not canonical ASCII") from error


def _git_blob_sha(data: bytes) -> str:
    prefix = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(prefix + data).hexdigest()


def _canonical_source_commit(raw: str) -> str:
    if not isinstance(raw, str) or SHA40.fullmatch(raw) is None or raw == "0" * 40:
        raise SignerExecutionCustodyError(
            "accepted signer source commit is not one canonical nonzero full SHA"
        )
    resolved = _git_text("rev-parse", "--verify", f"{raw}^{{commit}}")
    if resolved != raw:
        raise SignerExecutionCustodyError(
            "accepted signer source resolved to a different Git commit"
        )
    return raw


def _accepted_blob(source_commit: str, relative_path: str) -> bytes:
    """Capture one execution source only from the independently accepted exact commit."""
    source_commit = _canonical_source_commit(source_commit)
    blob_id = _git_text("rev-parse", "--verify", f"{source_commit}:{relative_path}")
    if not SHA40.fullmatch(blob_id):
        raise SignerExecutionCustodyError("execution source Git blob identity is invalid")
    blob = _git_bytes("cat-file", "blob", blob_id)
    if not blob or len(blob) > MAX_SOURCE_BYTES or _git_blob_sha(blob) != blob_id:
        raise SignerExecutionCustodyError("execution source Git blob bytes failed identity validation")
    return blob


@contextmanager
def accepted_execution_bundle(source_commit: str) -> Iterator[Path]:
    """Freeze all key-visible code from one independently accepted exact commit."""
    source_commit = _canonical_source_commit(source_commit)
    blobs = {
        relative: _accepted_blob(source_commit, relative)
        for relative in EXECUTION_SOURCES
    }
    with tempfile.TemporaryDirectory(prefix="nembra-es80-field-signer-") as directory:
        root = Path(directory)
        os.chmod(root, 0o700)
        for relative, data in blobs.items():
            destination = root / Path(relative).name
            descriptor = os.open(
                os.fspath(destination),
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o400,
            )
            try:
                written = os.write(descriptor, data)
                if written != len(data):
                    raise SignerExecutionCustodyError("execution source snapshot write was incomplete")
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
            measured = destination.read_bytes()
            if measured != data:
                raise SignerExecutionCustodyError("execution source snapshot verification failed")
        yield root


def _load_frozen_module(path: Path, module_name: str):
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise SignerExecutionCustodyError("accepted signer helper is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def timestamp_unix_milliseconds(raw: str, label: str) -> int:
    """Parse exactly the canonical UTC-seconds syntax accepted by the existing signer."""
    if not isinstance(raw, str) or RFC3339_SECONDS.fullmatch(raw) is None:
        raise ValueError(f"{label} is not canonical UTC seconds")
    try:
        value = datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as error:
        raise ValueError(f"{label} is not canonical UTC seconds") from error
    milliseconds = int(value.timestamp()) * 1_000
    if milliseconds <= 0:
        raise ValueError(f"{label} must be after the Unix epoch")
    return milliseconds


def validate_signing_chronology(
    *,
    attempt_started_at: int,
    must_expire_by: int,
    issued_at: int,
    not_before: int,
    expires_at: int,
) -> None:
    if issued_at < attempt_started_at:
        raise ValueError("issued-at precedes the running app attempt")
    if not_before < attempt_started_at:
        raise ValueError("not-before precedes the running app attempt")
    if not_before < issued_at:
        raise ValueError("not-before precedes issued-at")
    if expires_at <= not_before:
        raise ValueError("expires-at must be later than not-before")
    if expires_at > must_expire_by:
        raise ValueError("expires-at exceeds the running app attempt deadline")


def verify_accepted_evidence_source(
    *,
    evidence_helper,
    signed_evidence: Path,
    accepted_source_commit: str,
) -> None:
    evidence_bytes = evidence_helper.read_exact_file(
        signed_evidence,
        "signed artifact evidence",
        evidence_helper.MAX_JSON_BYTES,
    )
    evidence = evidence_helper.verify_evidence_bytes(evidence_bytes)
    if evidence.get("sourceCommitSHA") != accepted_source_commit:
        raise SignerExecutionCustodyError(
            "signed evidence does not bind the independently accepted signer source commit"
        )


def build_signer_command(
    args: argparse.Namespace,
    rendezvous: dict,
    signer_path: Path,
) -> list[str]:
    """Invoke only the frozen existing signer; stable evidence subjects remain signer-owned."""
    return [
        str(PYTHON),
        str(signer_path),
        "--signed-evidence", str(args.signed_evidence),
        "--private-key", str(args.private_key),
        "--openssl", str(args.openssl),
        "--output", str(args.output),
        "--authorization-id", args.authorization_id,
        "--attempt-challenge-sha256", rendezvous["attemptChallengeSHA256"],
        "--issued-at", args.issued_at,
        "--not-before", args.not_before,
        "--expires-at", args.expires_at,
    ]


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--accepted-source-commit", required=True)
    value.add_argument("--rendezvous", type=Path, required=True)
    value.add_argument("--signed-evidence", type=Path, required=True)
    value.add_argument("--private-key", type=Path, required=True)
    value.add_argument("--openssl", type=Path, required=True)
    value.add_argument("--authorization-id", required=True)
    value.add_argument("--issued-at", required=True)
    value.add_argument("--not-before", required=True)
    value.add_argument("--expires-at", required=True)
    value.add_argument("--output", type=Path, required=True)
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        accepted_source_commit = _canonical_source_commit(args.accepted_source_commit)
        with accepted_execution_bundle(accepted_source_commit) as bundle:
            rendezvous_helper = _load_frozen_module(
                bundle / RENDEZVOUS_BASENAME,
                "es80_field_authorization_rendezvous",
            )
            evidence_helper = _load_frozen_module(
                bundle / EVIDENCE_BASENAME,
                "es80_signed_field_artifact_evidence",
            )
            verify_accepted_evidence_source(
                evidence_helper=evidence_helper,
                signed_evidence=args.signed_evidence,
                accepted_source_commit=accepted_source_commit,
            )
            rendezvous = rendezvous_helper.verify_rendezvous_bytes(
                rendezvous_helper._read_exact(args.rendezvous)
            )
            validate_signing_chronology(
                attempt_started_at=rendezvous["attemptStartedAtUnixMilliseconds"],
                must_expire_by=rendezvous["authorizationMustExpireByUnixMilliseconds"],
                issued_at=timestamp_unix_milliseconds(args.issued_at, "issued-at"),
                not_before=timestamp_unix_milliseconds(args.not_before, "not-before"),
                expires_at=timestamp_unix_milliseconds(args.expires_at, "expires-at"),
            )

            signer = bundle / SIGNER_BASENAME
            environment = {
                "PATH": "/usr/bin:/bin",
                "HOME": "/tmp",
                "LC_ALL": "C",
                "PYTHONNOUSERSITE": "1",
                "PYTHONPATH": "",
            }
            completed = subprocess.run(
                build_signer_command(args, rendezvous, signer),
                cwd=bundle,
                env=environment,
                check=False,
            )
    except (SignerExecutionCustodyError, RuntimeError, ValueError) as error:
        print(f"REFUSED_NOT_AUTHORITY: {error}", file=sys.stderr)
        return 2
    except Exception as error:
        # Frozen helpers own their concrete validation error types. Keep the wrapper fail-closed
        # without importing mutable checkout code merely to name those exceptions.
        print(f"REFUSED_NOT_AUTHORITY: {error}", file=sys.stderr)
        return 2

    if completed.returncode != 0:
        return completed.returncode
    print("SIGNED_ENVELOPE_CREATED_NOT_PHYSICAL_GO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
