#!/usr/bin/env python3
"""Delegate one ES80 field-authorization signing request from an app rendezvous document.

This remains an orchestration wrapper, not a second signer. Before any private-key path is handed
to signing code, it proves that this wrapper and every Python source that will parse or sign the
request exactly match immutable Git blob objects at the checked-out HEAD. It then materializes those
accepted object bytes into a private temporary execution bundle and invokes only that bundle.

Cryptographic payload construction, signed-evidence parsing, signing, self-verification, and
no-replace publication remain owned by `es80_field_authorization_envelope.py`.
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
import stat
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

EXECUTION_SOURCES = (
    "scripts/ci/es80_sign_field_authorization_from_rendezvous.py",
    "scripts/ci/es80_field_authorization_rendezvous.py",
    "scripts/ci/es80_field_authorization_envelope.py",
    "scripts/ci/es80_signed_field_artifact_evidence.py",
)
RENDEZVOUS_BASENAME = "es80_field_authorization_rendezvous.py"
SIGNER_BASENAME = "es80_field_authorization_envelope.py"


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


def _read_exact_worktree(path: Path) -> bytes:
    """Read one source file through a no-follow descriptor and reject mutable aliases."""
    requested = path
    if not requested.is_absolute():
        raise SignerExecutionCustodyError("execution source path is not absolute")
    no_follow = getattr(os, "O_NOFOLLOW", None)
    if no_follow is None:
        raise SignerExecutionCustodyError("platform cannot guarantee no-follow source custody")
    try:
        descriptor = os.open(os.fspath(requested), os.O_RDONLY | no_follow)
    except OSError as error:
        raise SignerExecutionCustodyError("execution source cannot be opened safely") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise SignerExecutionCustodyError("execution source is not one regular single-link file")
        if before.st_size <= 0 or before.st_size > MAX_SOURCE_BYTES:
            raise SignerExecutionCustodyError("execution source size is invalid")
        blocks: list[bytes] = []
        count = 0
        while True:
            block = os.read(descriptor, min(65_536, MAX_SOURCE_BYTES + 1 - count))
            if not block:
                break
            blocks.append(block)
            count += len(block)
            if count > MAX_SOURCE_BYTES:
                raise SignerExecutionCustodyError("execution source exceeds the byte limit")
        after = os.fstat(descriptor)
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
        if identity(after) != identity(before) or count != before.st_size:
            raise SignerExecutionCustodyError("execution source changed during descriptor read")
        return b"".join(blocks)
    finally:
        os.close(descriptor)


def _accepted_blob(relative_path: str) -> bytes:
    blob_id = _git_text("rev-parse", "--verify", f"HEAD:{relative_path}")
    if not SHA40.fullmatch(blob_id):
        raise SignerExecutionCustodyError("execution source Git blob identity is invalid")
    blob = _git_bytes("cat-file", "blob", blob_id)
    if not blob or len(blob) > MAX_SOURCE_BYTES or _git_blob_sha(blob) != blob_id:
        raise SignerExecutionCustodyError("execution source Git blob bytes failed identity validation")

    worktree = _read_exact_worktree(REPOSITORY_ROOT / relative_path)
    if worktree != blob:
        raise SignerExecutionCustodyError(
            f"mutable checkout differs from accepted Git object: {relative_path}"
        )
    return blob


@contextmanager
def accepted_execution_bundle() -> Iterator[Path]:
    """Freeze all code that can see the private-key path before signing begins."""
    head = _git_text("rev-parse", "--verify", "HEAD^{commit}")
    if not SHA40.fullmatch(head):
        raise SignerExecutionCustodyError("repository HEAD is not one canonical full Git commit")

    blobs = {relative: _accepted_blob(relative) for relative in EXECUTION_SOURCES}
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
            if _read_exact_worktree(destination) != data:
                raise SignerExecutionCustodyError("execution source snapshot verification failed")
        yield root


def _load_rendezvous_helper(path: Path):
    spec = importlib.util.spec_from_file_location(
        "es80_field_authorization_rendezvous", path
    )
    if spec is None or spec.loader is None:
        raise SignerExecutionCustodyError("accepted signer rendezvous validator is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def timestamp_unix_milliseconds(raw: str, label: str) -> int:
    """Parse exactly the canonical UTC-seconds syntax accepted by the existing signer."""
    try:
        value = datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError) as error:
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


def build_signer_command(
    args: argparse.Namespace,
    rendezvous: dict,
    signer_path: Path,
) -> list[str]:
    """Invoke only the frozen existing signer; evidence remains signer-owned."""
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
        with accepted_execution_bundle() as bundle:
            helper = _load_rendezvous_helper(bundle / RENDEZVOUS_BASENAME)
            rendezvous = helper.verify_rendezvous_bytes(helper._read_exact(args.rendezvous))
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
        # The frozen rendezvous module owns its concrete validation error type; keep the wrapper
        # fail-closed without importing mutable checkout code merely to name that exception.
        print(f"REFUSED_NOT_AUTHORITY: {error}", file=sys.stderr)
        return 2

    if completed.returncode != 0:
        return completed.returncode
    print("SIGNED_ENVELOPE_CREATED_NOT_PHYSICAL_GO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
