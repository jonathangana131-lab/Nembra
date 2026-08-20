#!/usr/bin/env python3
"""Materialize an exact accepted-source ES80 signer bundle before any private key is supplied.

This utility is deliberately a pre-key boundary. It accepts one explicit full source commit and one
new external output directory, reads the complete signer stack from immutable Git blob objects, and
writes those exact bytes using the repository-relative layout expected by the signer. It never
accepts, opens, names, or forwards a private key and it does not create field or physical authority.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from typing import Any

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
GIT = Path("/usr/bin/git")
SCHEMA = "nembra.es80-field-authorization-signer-prekey-bundle"
SCHEMA_VERSION = 1
AUTHORITY = "accepted-git-object-materialization-not-private-key-authority"
MANIFEST_NAME = "NembraFieldAuthorizationSignerPreKeyBundle.json"
MAX_SOURCE_BYTES = 1_048_576
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")

EXECUTION_SOURCES = (
    "scripts/ci/es80_sign_field_authorization_from_rendezvous.py",
    "scripts/ci/es80_field_authorization_rendezvous.py",
    "scripts/ci/es80_field_authorization_envelope.py",
    "scripts/ci/es80_signed_field_artifact_evidence.py",
)


class PreKeyBundleError(RuntimeError):
    pass


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


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
    if not GIT.is_absolute() or not GIT.is_file():
        raise PreKeyBundleError("trusted /usr/bin/git is unavailable")
    try:
        completed = subprocess.run(
            [str(GIT), *arguments],
            cwd=REPOSITORY_ROOT,
            env=_git_environment(),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise PreKeyBundleError("immutable Git-object lookup failed") from error
    return completed.stdout


def _git_text(*arguments: str) -> str:
    try:
        return _git_bytes(*arguments).decode("ascii").strip()
    except UnicodeDecodeError as error:
        raise PreKeyBundleError("Git identity output is not canonical ASCII") from error


def _git_blob_sha1(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest()


def _require_exact_source_commit(raw: str) -> str:
    if not isinstance(raw, str) or SHA40.fullmatch(raw) is None:
        raise PreKeyBundleError("--source-commit must be one full lowercase 40-hex commit SHA")
    resolved = _git_text("rev-parse", "--verify", f"{raw}^{{commit}}")
    if resolved != raw:
        raise PreKeyBundleError("source commit did not resolve to the exact requested commit")
    return raw


def _accepted_blob(source_commit: str, relative_path: str) -> tuple[str, bytes]:
    if Path(relative_path).is_absolute() or ".." in Path(relative_path).parts:
        raise PreKeyBundleError("execution source path is not repository-relative")
    blob_id = _git_text("rev-parse", "--verify", f"{source_commit}:{relative_path}")
    if SHA40.fullmatch(blob_id) is None:
        raise PreKeyBundleError(f"execution source blob identity is invalid: {relative_path}")
    blob = _git_bytes("cat-file", "blob", blob_id)
    if not blob or len(blob) > MAX_SOURCE_BYTES or _git_blob_sha1(blob) != blob_id:
        raise PreKeyBundleError(f"execution source Git blob failed identity validation: {relative_path}")
    return blob_id, blob


def _directory_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_nlink,
    )


def _split_absolute(path: Path, label: str) -> tuple[str, ...]:
    raw = os.fspath(path.expanduser())
    candidate = Path(raw)
    if not candidate.is_absolute():
        raise PreKeyBundleError(f"{label} must be absolute")
    parts = candidate.parts
    if len(parts) < 2 or parts[0] != os.sep \
            or any(part in {"", ".", ".."} for part in parts[1:]):
        raise PreKeyBundleError(f"{label} is not canonical")
    return tuple(parts[1:])


def _open_external_directory(path: Path, repository_identity: tuple[int, int]) -> int:
    """Open an existing canonical directory while rejecting every symlink ancestor and the repo."""
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY") \
            or os.open not in os.supports_dir_fd:
        raise PreKeyBundleError("platform cannot guarantee descriptor-relative no-follow custody")
    parts = _split_absolute(path, "output parent")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(os.sep, flags)
    except OSError as error:
        raise PreKeyBundleError("cannot open filesystem root for output custody") from error
    try:
        metadata = os.fstat(descriptor)
        if (metadata.st_dev, metadata.st_ino) == repository_identity:
            raise PreKeyBundleError("output path resolves inside the Nembra repository")
        for component in parts:
            try:
                next_descriptor = os.open(component, flags, dir_fd=descriptor)
            except OSError as error:
                raise PreKeyBundleError("output ancestor failed no-follow custody") from error
            os.close(descriptor)
            descriptor = next_descriptor
            metadata = os.fstat(descriptor)
            if not stat.S_ISDIR(metadata.st_mode):
                raise PreKeyBundleError("output ancestor is not a directory")
            if (metadata.st_dev, metadata.st_ino) == repository_identity:
                raise PreKeyBundleError("output path resolves inside the Nembra repository")
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _create_output_root(output: Path) -> tuple[Path, int]:
    parts = _split_absolute(output, "--output-directory")
    name = parts[-1]
    parent = Path(os.sep).joinpath(*parts[:-1]) if len(parts) > 1 else Path(os.sep)
    repository = REPOSITORY_ROOT.resolve(strict=True)
    repository_metadata = repository.stat()
    repository_identity = (repository_metadata.st_dev, repository_metadata.st_ino)
    parent_descriptor = _open_external_directory(parent, repository_identity)
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        try:
            os.mkdir(name, 0o700, dir_fd=parent_descriptor)
        except FileExistsError as error:
            raise PreKeyBundleError("output directory already exists; refusing replacement") from error
        except OSError as error:
            raise PreKeyBundleError("cannot create private output directory") from error
        try:
            root_descriptor = os.open(name, flags, dir_fd=parent_descriptor)
        except OSError as error:
            raise PreKeyBundleError("cannot bind newly created output directory") from error
    finally:
        os.close(parent_descriptor)
    metadata = os.fstat(root_descriptor)
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o700 \
            or metadata.st_uid != os.geteuid():
        os.close(root_descriptor)
        raise PreKeyBundleError("private output directory custody is invalid")
    canonical = parent / name
    return canonical, root_descriptor


def _open_or_create_directory(parent_descriptor: int, component: str) -> int:
    if not component or component in {".", ".."} or os.sep in component:
        raise PreKeyBundleError("bundle directory component is invalid")
    try:
        os.mkdir(component, 0o700, dir_fd=parent_descriptor)
    except FileExistsError:
        pass
    except OSError as error:
        raise PreKeyBundleError("cannot create private bundle directory") from error
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(component, flags, dir_fd=parent_descriptor)
    except OSError as error:
        raise PreKeyBundleError("cannot bind private bundle directory") from error
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o700 \
            or metadata.st_uid != os.geteuid():
        os.close(descriptor)
        raise PreKeyBundleError("private bundle directory custody is invalid")
    return descriptor


def _write_all(descriptor: int, data: bytes) -> None:
    offset = 0
    while offset < len(data):
        written = os.write(descriptor, data[offset:])
        if written <= 0:
            raise PreKeyBundleError("bundle source write made no progress")
        offset += written
    os.fsync(descriptor)


def _write_private_file(parent_descriptor: int, name: str, data: bytes) -> None:
    if not name or name in {".", ".."} or os.sep in name:
        raise PreKeyBundleError("bundle filename is invalid")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(name, flags, 0o400, dir_fd=parent_descriptor)
    except OSError as error:
        raise PreKeyBundleError("cannot create private bundle file") from error
    try:
        os.fchmod(descriptor, 0o400)
        _write_all(descriptor, data)
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o400 \
                or metadata.st_uid != os.geteuid() or metadata.st_nlink != 1 \
                or metadata.st_size != len(data):
            raise PreKeyBundleError("private bundle file custody is invalid")
    finally:
        os.close(descriptor)


def _read_private_file(parent_descriptor: int, name: str, maximum: int) -> bytes:
    flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(name, flags, dir_fd=parent_descriptor)
    except OSError as error:
        raise PreKeyBundleError("cannot reopen private bundle file") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or stat.S_IMODE(before.st_mode) != 0o400 \
                or before.st_uid != os.geteuid() or before.st_nlink != 1 \
                or before.st_size <= 0 or before.st_size > maximum:
            raise PreKeyBundleError("private bundle file verification metadata is invalid")
        chunks: list[bytes] = []
        remaining = maximum + 1
        while remaining > 0:
            chunk = os.read(descriptor, min(65_536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    identity = lambda item: (
        item.st_dev, item.st_ino, item.st_mode, item.st_uid, item.st_gid,
        item.st_nlink, item.st_size, item.st_mtime_ns, item.st_ctime_ns,
    )
    data = b"".join(chunks)
    if identity(before) != identity(after) or len(data) != before.st_size:
        raise PreKeyBundleError("private bundle file changed while verifying")
    return data


def _write_relative_source(root_descriptor: int, relative_path: str, data: bytes) -> None:
    parts = Path(relative_path).parts
    if not parts or Path(relative_path).is_absolute() \
            or any(part in {"", ".", ".."} for part in parts):
        raise PreKeyBundleError("execution source path is invalid")
    descriptors: list[int] = []
    current = root_descriptor
    try:
        for component in parts[:-1]:
            current = _open_or_create_directory(current, component)
            descriptors.append(current)
        _write_private_file(current, parts[-1], data)
        if _read_private_file(current, parts[-1], MAX_SOURCE_BYTES) != data:
            raise PreKeyBundleError("materialized execution source differs from accepted Git blob")
    finally:
        for descriptor in reversed(descriptors):
            os.close(descriptor)


def materialize(source_commit: str, output_directory: Path) -> dict[str, Any]:
    exact_commit = _require_exact_source_commit(source_commit)
    accepted: list[tuple[str, str, bytes]] = []
    for relative in EXECUTION_SOURCES:
        blob_id, blob = _accepted_blob(exact_commit, relative)
        accepted.append((relative, blob_id, blob))

    output, root_descriptor = _create_output_root(output_directory.expanduser())
    try:
        entries: list[dict[str, Any]] = []
        for relative, blob_id, blob in accepted:
            _write_relative_source(root_descriptor, relative, blob)
            entries.append({
                "path": relative,
                "gitBlobSHA1": blob_id,
                "sha256": hashlib.sha256(blob).hexdigest(),
                "byteCount": len(blob),
            })
        manifest = {
            "schema": SCHEMA,
            "version": SCHEMA_VERSION,
            "authority": AUTHORITY,
            "sourceCommitSHA": exact_commit,
            "executionSources": entries,
            "privateKeyMaterialized": False,
            "physicalExperimentAuthority": False,
        }
        manifest_bytes = canonical_json_bytes(manifest)
        _write_private_file(root_descriptor, MANIFEST_NAME, manifest_bytes)
        if _read_private_file(root_descriptor, MANIFEST_NAME, 64 * 1024) != manifest_bytes:
            raise PreKeyBundleError("pre-key bundle manifest changed after publication")
    finally:
        os.close(root_descriptor)
    return {
        "status": "MATERIALIZED_PREKEY_BUNDLE_NOT_AUTHORITY",
        "sourceCommitSHA": exact_commit,
        "outputDirectory": os.fspath(output),
        "manifestSHA256": hashlib.sha256(manifest_bytes).hexdigest(),
    }


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--source-commit", required=True)
    value.add_argument("--output-directory", type=Path, required=True)
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        result = materialize(args.source_commit, args.output_directory)
    except (PreKeyBundleError, OSError) as error:
        print(f"REFUSED_NOT_AUTHORITY: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
