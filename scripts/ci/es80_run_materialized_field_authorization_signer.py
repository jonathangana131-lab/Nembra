#!/usr/bin/env python3
"""Run only a previously materialized exact-source ES80 field-authorization signer bundle.

This is the post-materialization boundary for private signing. The operator first runs the separate
pre-key materializer, records its exact source commit and manifest SHA-256, and then launches this
copy from inside that external private bundle. Before delegating any private-key path to signing
code, this runner verifies its canonical bundle location, owner-only directory/file custody, the
canonical manifest, every materialized source digest, and the caller-supplied exact commit/hash.

This runner does not establish physical ES80 identity, telemetry semantics, command safety, or a
physical GO. Cryptographic payload construction and key opening remain owned by the frozen existing
`es80_field_authorization_envelope.py` signer.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from types import ModuleType
from typing import Any

SCHEMA = "nembra.es80-field-authorization-signer-prekey-bundle"
SCHEMA_VERSION = 1
AUTHORITY = "accepted-git-object-materialization-not-private-key-authority"
MANIFEST_NAME = "NembraFieldAuthorizationSignerPreKeyBundle.json"
RUNNER_RELATIVE_PATH = Path("scripts/ci/es80_run_materialized_field_authorization_signer.py")
WRAPPER_RELATIVE_PATH = Path("scripts/ci/es80_sign_field_authorization_from_rendezvous.py")
RENDEZVOUS_RELATIVE_PATH = Path("scripts/ci/es80_field_authorization_rendezvous.py")
SIGNER_RELATIVE_PATH = Path("scripts/ci/es80_field_authorization_envelope.py")
EVIDENCE_RELATIVE_PATH = Path("scripts/ci/es80_signed_field_artifact_evidence.py")
REQUIRED_EXECUTION_SOURCES = (
    os.fspath(RUNNER_RELATIVE_PATH),
    os.fspath(WRAPPER_RELATIVE_PATH),
    os.fspath(RENDEZVOUS_RELATIVE_PATH),
    os.fspath(SIGNER_RELATIVE_PATH),
    os.fspath(EVIDENCE_RELATIVE_PATH),
)
MAX_MANIFEST_BYTES = 64 * 1024
MAX_SOURCE_BYTES = 1_048_576
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SHA1 = re.compile(r"^[0-9a-f]{40}$")
MANIFEST_KEYS = {
    "schema", "version", "authority", "sourceCommitSHA", "executionSources",
    "privateKeyMaterialized", "physicalExperimentAuthority",
}
ENTRY_KEYS = {"path", "gitBlobSHA1", "sha256", "byteCount"}


class MaterializedSignerRunnerError(RuntimeError):
    pass


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise MaterializedSignerRunnerError("manifest contains a duplicate JSON member")
        value[key] = item
    return value


def _split_absolute(path: Path, label: str) -> tuple[str, ...]:
    raw = os.fspath(path.expanduser())
    candidate = Path(raw)
    if not candidate.is_absolute() or "\x00" in raw:
        raise MaterializedSignerRunnerError(f"{label} must be absolute and NUL-free")
    parts = candidate.parts
    if len(parts) < 2 or parts[0] != os.sep \
            or any(part in {"", ".", ".."} for part in parts[1:]):
        raise MaterializedSignerRunnerError(f"{label} is not canonical")
    return tuple(parts[1:])


def _open_bundle_root(path: Path) -> int:
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY") \
            or os.open not in os.supports_dir_fd:
        raise MaterializedSignerRunnerError(
            "platform cannot guarantee descriptor-relative no-follow bundle custody"
        )
    parts = _split_absolute(path, "--bundle-directory")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(os.sep, flags)
    except OSError as error:
        raise MaterializedSignerRunnerError("cannot open filesystem root") from error
    try:
        for component in parts:
            try:
                next_descriptor = os.open(component, flags, dir_fd=descriptor)
            except OSError as error:
                raise MaterializedSignerRunnerError(
                    "bundle ancestor failed no-follow custody"
                ) from error
            os.close(descriptor)
            descriptor = next_descriptor
        metadata = os.fstat(descriptor)
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o700 \
                or metadata.st_uid != os.geteuid():
            raise MaterializedSignerRunnerError(
                "materialized bundle root must be current-user mode 0700"
            )
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _open_internal_directory(parent_descriptor: int, component: str) -> int:
    if not component or component in {".", ".."} or os.sep in component:
        raise MaterializedSignerRunnerError("bundle directory component is invalid")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(component, flags, dir_fd=parent_descriptor)
    except OSError as error:
        raise MaterializedSignerRunnerError("materialized bundle directory is unavailable") from error
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o700 \
            or metadata.st_uid != os.geteuid():
        os.close(descriptor)
        raise MaterializedSignerRunnerError(
            "materialized bundle directory must be current-user mode 0700"
        )
    return descriptor


def _read_relative_file(
    root_descriptor: int,
    relative_path: Path,
    maximum: int,
) -> bytes:
    parts = relative_path.parts
    if relative_path.is_absolute() or not parts \
            or any(part in {"", ".", ".."} for part in parts):
        raise MaterializedSignerRunnerError("bundle file path is invalid")
    descriptors: list[int] = []
    current = root_descriptor
    try:
        for component in parts[:-1]:
            current = _open_internal_directory(current, component)
            descriptors.append(current)
        flags = os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
        try:
            descriptor = os.open(parts[-1], flags, dir_fd=current)
        except OSError as error:
            raise MaterializedSignerRunnerError("materialized bundle file is unavailable") from error
        try:
            before = os.fstat(descriptor)
            if not stat.S_ISREG(before.st_mode) or stat.S_IMODE(before.st_mode) != 0o400 \
                    or before.st_uid != os.geteuid() or before.st_nlink != 1 \
                    or before.st_size <= 0 or before.st_size > maximum:
                raise MaterializedSignerRunnerError("materialized bundle file custody is invalid")
            chunks: list[bytes] = []
            count = 0
            while True:
                chunk = os.read(descriptor, min(65_536, maximum + 1 - count))
                if not chunk:
                    break
                chunks.append(chunk)
                count += len(chunk)
                if count > maximum:
                    raise MaterializedSignerRunnerError("materialized bundle file is too large")
            after = os.fstat(descriptor)
        finally:
            os.close(descriptor)
    finally:
        for opened in reversed(descriptors):
            os.close(opened)
    identity = lambda item: (
        item.st_dev, item.st_ino, item.st_mode, item.st_uid, item.st_gid,
        item.st_nlink, item.st_size, item.st_mtime_ns, item.st_ctime_ns,
    )
    data = b"".join(chunks)
    if identity(before) != identity(after) or len(data) != before.st_size:
        raise MaterializedSignerRunnerError("materialized bundle file changed while reading")
    return data


def _parse_manifest(data: bytes) -> dict[str, Any]:
    if not data or len(data) > MAX_MANIFEST_BYTES:
        raise MaterializedSignerRunnerError("pre-key bundle manifest size is invalid")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_reject_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise MaterializedSignerRunnerError("pre-key bundle manifest is malformed") from error
    if not isinstance(value, dict) or set(value) != MANIFEST_KEYS:
        raise MaterializedSignerRunnerError("pre-key bundle manifest schema is not closed")
    if canonical_json_bytes(value) != data:
        raise MaterializedSignerRunnerError("pre-key bundle manifest is not canonical JSON")
    if value.get("schema") != SCHEMA or type(value.get("version")) is not int \
            or value["version"] != SCHEMA_VERSION:
        raise MaterializedSignerRunnerError("pre-key bundle manifest schema/version is unsupported")
    if value.get("authority") != AUTHORITY:
        raise MaterializedSignerRunnerError("pre-key bundle manifest authority is unsupported")
    if value.get("privateKeyMaterialized") is not False \
            or value.get("physicalExperimentAuthority") is not False:
        raise MaterializedSignerRunnerError("pre-key bundle manifest claims forbidden authority")
    source_commit = value.get("sourceCommitSHA")
    if not isinstance(source_commit, str) or SHA40.fullmatch(source_commit) is None:
        raise MaterializedSignerRunnerError("pre-key bundle source commit is invalid")
    entries = value.get("executionSources")
    if not isinstance(entries, list) or len(entries) != len(REQUIRED_EXECUTION_SOURCES):
        raise MaterializedSignerRunnerError("pre-key bundle execution source list is invalid")
    paths: list[str] = []
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != ENTRY_KEYS:
            raise MaterializedSignerRunnerError("pre-key bundle execution source schema is invalid")
        path = entry.get("path")
        blob = entry.get("gitBlobSHA1")
        digest = entry.get("sha256")
        byte_count = entry.get("byteCount")
        if not isinstance(path, str) or Path(path).is_absolute() \
                or not Path(path).parts \
                or any(part in {"", ".", ".."} for part in Path(path).parts):
            raise MaterializedSignerRunnerError("pre-key bundle source path is invalid")
        if not isinstance(blob, str) or SHA1.fullmatch(blob) is None:
            raise MaterializedSignerRunnerError("pre-key bundle Git blob identity is invalid")
        if not isinstance(digest, str) or SHA256.fullmatch(digest) is None:
            raise MaterializedSignerRunnerError("pre-key bundle source SHA-256 is invalid")
        if type(byte_count) is not int or byte_count <= 0 or byte_count > MAX_SOURCE_BYTES:
            raise MaterializedSignerRunnerError("pre-key bundle source byte count is invalid")
        paths.append(path)
    if tuple(paths) != REQUIRED_EXECUTION_SOURCES:
        raise MaterializedSignerRunnerError("pre-key bundle execution source order/content drifted")
    return value


def _require_expected_subject(raw_commit: str, raw_manifest_sha256: str) -> tuple[str, str]:
    if SHA40.fullmatch(raw_commit or "") is None:
        raise MaterializedSignerRunnerError(
            "--expected-source-commit must be one full lowercase 40-hex SHA"
        )
    if SHA256.fullmatch(raw_manifest_sha256 or "") is None:
        raise MaterializedSignerRunnerError(
            "--expected-manifest-sha256 must be one lowercase SHA-256"
        )
    return raw_commit, raw_manifest_sha256


def verify_materialized_bundle(
    bundle_directory: Path,
    expected_source_commit: str,
    expected_manifest_sha256: str,
) -> tuple[Path, dict[str, Any]]:
    expected_commit, expected_manifest = _require_expected_subject(
        expected_source_commit, expected_manifest_sha256
    )
    bundle_parts = _split_absolute(bundle_directory, "--bundle-directory")
    bundle = Path(os.sep).joinpath(*bundle_parts)

    script_raw = os.fspath(Path(__file__))
    if not os.path.isabs(script_raw):
        raise MaterializedSignerRunnerError("materialized runner must be launched by absolute path")
    script_parts = Path(script_raw).parts
    if any(part in {"", ".", ".."} for part in script_parts[1:]):
        raise MaterializedSignerRunnerError("materialized runner launch path is not canonical")
    expected_runner = bundle / RUNNER_RELATIVE_PATH
    if Path(script_raw) != expected_runner:
        raise MaterializedSignerRunnerError(
            "runner is not executing from the requested materialized bundle"
        )

    root_descriptor = _open_bundle_root(bundle)
    try:
        manifest_bytes = _read_relative_file(
            root_descriptor, Path(MANIFEST_NAME), MAX_MANIFEST_BYTES
        )
        if hashlib.sha256(manifest_bytes).hexdigest() != expected_manifest:
            raise MaterializedSignerRunnerError("pre-key bundle manifest SHA-256 mismatch")
        manifest = _parse_manifest(manifest_bytes)
        if manifest["sourceCommitSHA"] != expected_commit:
            raise MaterializedSignerRunnerError("pre-key bundle exact source commit mismatch")

        entries = manifest["executionSources"]
        for entry in entries:
            relative = Path(entry["path"])
            data = _read_relative_file(root_descriptor, relative, MAX_SOURCE_BYTES)
            if len(data) != entry["byteCount"]:
                raise MaterializedSignerRunnerError(
                    f"materialized source byte count mismatch: {entry['path']}"
                )
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise MaterializedSignerRunnerError(
                    f"materialized source SHA-256 mismatch: {entry['path']}"
                )
            prefix = f"blob {len(data)}\0".encode("ascii")
            if hashlib.sha1(prefix + data).hexdigest() != entry["gitBlobSHA1"]:
                raise MaterializedSignerRunnerError(
                    f"materialized source Git blob mismatch: {entry['path']}"
                )
    finally:
        os.close(root_descriptor)
    return bundle, manifest


def _load_module(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise MaterializedSignerRunnerError("verified materialized Python module is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--bundle-directory", type=Path, required=True)
    value.add_argument("--expected-source-commit", required=True)
    value.add_argument("--expected-manifest-sha256", required=True)
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
        bundle, _ = verify_materialized_bundle(
            args.bundle_directory,
            args.expected_source_commit,
            args.expected_manifest_sha256,
        )
        wrapper = _load_module(
            bundle / WRAPPER_RELATIVE_PATH,
            "nembra_verified_materialized_field_authorization_wrapper",
        )
        helper = wrapper._load_rendezvous_helper(bundle / RENDEZVOUS_RELATIVE_PATH)
        rendezvous = helper.verify_rendezvous_bytes(helper._read_exact(args.rendezvous))
        wrapper.validate_signing_chronology(
            attempt_started_at=rendezvous["attemptStartedAtUnixMilliseconds"],
            must_expire_by=rendezvous["authorizationMustExpireByUnixMilliseconds"],
            issued_at=wrapper.timestamp_unix_milliseconds(args.issued_at, "issued-at"),
            not_before=wrapper.timestamp_unix_milliseconds(args.not_before, "not-before"),
            expires_at=wrapper.timestamp_unix_milliseconds(args.expires_at, "expires-at"),
        )
        signer = bundle / SIGNER_RELATIVE_PATH
        command = wrapper.build_signer_command(args, rendezvous, signer)
        environment = {
            "PATH": "/usr/bin:/bin",
            "HOME": "/tmp",
            "LC_ALL": "C",
            "PYTHONNOUSERSITE": "1",
            "PYTHONPATH": "",
        }
        completed = subprocess.run(
            command,
            cwd=bundle,
            env=environment,
            stdin=subprocess.DEVNULL,
            check=False,
        )
    except (MaterializedSignerRunnerError, RuntimeError, ValueError, OSError) as error:
        print(f"REFUSED_NOT_AUTHORITY: {error}", file=sys.stderr)
        return 2
    except Exception as error:
        # The verified frozen helper owns its concrete validation type; stay fail-closed without
        # importing mutable checkout code merely to name that exception class.
        print(f"REFUSED_NOT_AUTHORITY: {error}", file=sys.stderr)
        return 2

    if completed.returncode != 0:
        return completed.returncode
    print("SIGNED_BY_VERIFIED_MATERIALIZED_BUNDLE_NOT_PHYSICAL_GO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
