#!/usr/bin/env python3
"""Fingerprint and privately review the ignored inputs used by Capture field builds.

The provenance record contains cryptographic fingerprints and public dependency
versions. It never serializes AppKey/AppSecret, SDK bytes, device identifiers,
or tokens.

A review may additionally create a random local mode-0600 HMAC key and print an
opaque 64-hex commitment over the canonical provenance record. The key remains
private. Publishing only that HMAC commitment therefore does not create a public
credential-guessing oracle, while a later field admission can prove that its
current private generation is the one that produced an externally accepted
commitment.

CLI `verify` is intentionally stronger than the low-level `verify_record`: it
reads the accepted opaque commitment from the exact current Git object and binds
the current private generation to that source authority. This lets the already
pinned field installer re-check authority immediately before and after xcodebuild
without trusting a mutable checkout copy of the commitment.

This is build-input authority plumbing, not physical scooter proof.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import os
import stat
import subprocess
import tempfile
from pathlib import Path


SCHEMA = "nembra-capture-tuya-dependencies-v2"
HOME_KIT_VERSION = "7.8.0"
BUSINESS_EXTENSION_VERSION = "7.8.0"
PRIVATE_REVIEW_DOMAIN = b"nembra-capture-private-input-review-v1\x00"
PRIVATE_REVIEW_KEY_BYTES = 32
PRIVATE_REVIEW_KEY_NAME = "PrivateInputReviewKey.bin"
PRIVATE_REVIEW_AUTHORITY_PATH = "CAPTURE_TUYA_PRIVATE_INPUT_REVIEW_COMMITMENT.txt"
_HEX = frozenset("0123456789abcdef")


class ProvenanceError(RuntimeError):
    pass


def _identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _read_stable_regular_file(path: Path, *, maximum_bytes: int = 512 * 1024 * 1024) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise ProvenanceError(f"could not open required no-follow input: {path}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise ProvenanceError(f"required input is not a single-link regular file: {path}")
        if before.st_size < 0 or before.st_size > maximum_bytes:
            raise ProvenanceError(f"required input has an invalid size: {path}")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > maximum_bytes:
                raise ProvenanceError(f"required input grew beyond its accepted size: {path}")
            chunks.append(chunk)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)

    if _identity(before) != _identity(after):
        raise ProvenanceError(f"required input changed while being fingerprinted: {path}")
    try:
        final_path = path.lstat()
    except OSError as error:
        raise ProvenanceError(f"required input disappeared after fingerprinting: {path}") from error
    if _identity(after) != _identity(final_path):
        raise ProvenanceError(f"required input path changed while being fingerprinted: {path}")
    return b"".join(chunks)


def _read_stable_regular_file_sha256(path: Path) -> tuple[bytes, str]:
    payload = _read_stable_regular_file(path)
    return payload, hashlib.sha256(payload).hexdigest()


def _file_fingerprint(path: Path, **_: object) -> str:
    return _read_stable_regular_file_sha256(path)[1]


def _enumerate_tree(root: Path) -> list[tuple[str, Path, str]]:
    try:
        before = root.lstat()
    except OSError as error:
        raise ProvenanceError(f"required input tree is missing: {root}") from error
    if not stat.S_ISDIR(before.st_mode) or stat.S_ISLNK(before.st_mode):
        raise ProvenanceError(f"required input tree is not a real directory: {root}")

    entries: list[tuple[str, Path, str]] = []
    for current, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        directory_names.sort()
        file_names.sort()
        for directory_name in list(directory_names):
            child = current_path / directory_name
            metadata = child.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                raise ProvenanceError(f"private input tree contains a non-directory or symlink: {child}")
            relative = child.relative_to(root).as_posix()
            entries.append((relative, child, "directory"))
        for file_name in file_names:
            child = current_path / file_name
            metadata = child.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                raise ProvenanceError(f"private input tree contains a non-regular file or symlink: {child}")
            relative = child.relative_to(root).as_posix()
            entries.append((relative, child, "file"))

    after = root.lstat()
    if _identity(before) != _identity(after):
        raise ProvenanceError(f"private input tree changed while being enumerated: {root}")
    return sorted(entries, key=lambda item: (item[0].encode("utf-8"), item[2]))


def _tree_fingerprint(root: Path) -> str:
    digest = hashlib.sha256()
    first = _enumerate_tree(root)
    for relative, path, kind in first:
        relative_bytes = relative.encode("utf-8")
        digest.update(kind.encode("ascii") + b"\0")
        digest.update(len(relative_bytes).to_bytes(8, "big") + relative_bytes)
        if kind == "file":
            file_digest = bytes.fromhex(_file_fingerprint(path))
            digest.update(file_digest)
    second = _enumerate_tree(root)
    if [(item[0], item[2]) for item in first] != [(item[0], item[2]) for item in second]:
        raise ProvenanceError(f"private input tree changed while being fingerprinted: {root}")
    return digest.hexdigest()


def _require_public_versions(lock_bytes: bytes) -> None:
    try:
        lock = lock_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ProvenanceError("Podfile.lock is not UTF-8") from error
    for marker in (
        "ThingSmartHomeKit (7.8.0)",
        "ThingSmartBusinessExtensionKit (7.8.0)",
    ):
        if marker not in lock:
            raise ProvenanceError(f"Podfile.lock is missing exact reviewed dependency {marker}")


def build_record(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> dict[str, str]:
    lock_bytes, lock_digest = _read_stable_regular_file_sha256(lockfile)
    _require_public_versions(lock_bytes)
    record = {
        "schema": SCHEMA,
        "thing_smart_home_kit": HOME_KIT_VERSION,
        "thing_smart_business_extension_kit": BUSINESS_EXTENSION_VERSION,
        "podfile_lock_sha256": _read_stable_regular_file_sha256(lockfile)[1],
        "thing_smart_cryption_podspec_sha256": _file_fingerprint(security_podspec),
        "thing_smart_cryption_build_tree_sha256": _tree_fingerprint(security_build),
        "private_identity_podspec_sha256": _file_fingerprint(identity_podspec),
        "private_identity_sources_tree_sha256": _tree_fingerprint(identity_sources),
    }
    if not hmac.compare_digest(record["podfile_lock_sha256"], lock_digest):
        raise ProvenanceError("Podfile.lock changed while the private-input record was assembled")
    return record


_RECORD_KEYS = (
    "schema",
    "thing_smart_home_kit",
    "thing_smart_business_extension_kit",
    "podfile_lock_sha256",
    "thing_smart_cryption_podspec_sha256",
    "thing_smart_cryption_build_tree_sha256",
    "private_identity_podspec_sha256",
    "private_identity_sources_tree_sha256",
)


def _record_bytes(record: dict[str, str]) -> bytes:
    if set(record) != set(_RECORD_KEYS):
        raise ProvenanceError("private-input record has an unexpected field set")
    for key in _RECORD_KEYS[3:]:
        value = record[key]
        if len(value) != 64 or any(character not in _HEX for character in value):
            raise ProvenanceError(f"private-input record contains malformed SHA-256: {key}")
    return ("".join(f"{key}={record[key]}\n" for key in _RECORD_KEYS)).encode("utf-8")


def write_record(path: Path, record: dict[str, str]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.parent.is_symlink() or not path.parent.is_dir():
        raise ProvenanceError("private-input record parent is not a real directory")
    payload = _record_bytes(record)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        os.fchmod(descriptor, 0o600)
        offset = 0
        while offset < len(payload):
            offset += os.write(descriptor, payload[offset:])
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(temporary_path, path)
        os.chmod(path, 0o600)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass


def _parse_record(payload: bytes) -> dict[str, str]:
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ProvenanceError("private-input record is not UTF-8") from error
    result: dict[str, str] = {}
    for line in text.splitlines():
        if "=" not in line:
            raise ProvenanceError("private-input record contains a malformed line")
        key, value = line.split("=", 1)
        if key in result:
            raise ProvenanceError(f"private-input record repeats field: {key}")
        result[key] = value
    _record_bytes(result)
    return result


def verify_record(path: Path, current: dict[str, str]) -> None:
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
        raise ProvenanceError("private Tuya dependency provenance record is not mode 0600")
    if metadata.st_uid != os.geteuid() or metadata.st_nlink != 1:
        raise ProvenanceError("private Tuya dependency provenance record has invalid ownership")
    expected = _parse_record(_read_stable_regular_file(path, maximum_bytes=16 * 1024))
    if set(expected) != set(current):
        raise ProvenanceError("private Tuya build inputs changed after bootstrap")
    for key in _RECORD_KEYS:
        if not hmac.compare_digest(expected[key], current[key]):
            raise ProvenanceError("private Tuya build inputs changed after bootstrap")


def _require_private_review_parent(path: Path) -> None:
    try:
        metadata = path.parent.lstat()
    except OSError as error:
        raise ProvenanceError("private review directory is unavailable") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise ProvenanceError("private review directory must be one real directory")
    if metadata.st_uid != os.geteuid():
        raise ProvenanceError("private review directory is not owned by the current user")
    if stat.S_IMODE(metadata.st_mode) & 0o022:
        raise ProvenanceError("private review directory is group/world writable")


def _read_private_review_key(path: Path) -> bytes:
    _require_private_review_parent(path)
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise ProvenanceError("private review key is unavailable or unsafe") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise ProvenanceError("private review key is not a single-link regular file")
        if before.st_uid != os.geteuid() or stat.S_IMODE(before.st_mode) != 0o600:
            raise ProvenanceError("private review key custody is not mode 0600/current-user")
        if before.st_size != PRIVATE_REVIEW_KEY_BYTES:
            raise ProvenanceError("private review key has an invalid length")
        key = b""
        while len(key) < PRIVATE_REVIEW_KEY_BYTES:
            chunk = os.read(descriptor, PRIVATE_REVIEW_KEY_BYTES - len(key))
            if not chunk:
                break
            key += chunk
        if os.read(descriptor, 1):
            raise ProvenanceError("private review key has trailing bytes")
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if len(key) != PRIVATE_REVIEW_KEY_BYTES or _identity(before) != _identity(after):
        raise ProvenanceError("private review key changed while it was read")
    try:
        final_path = path.lstat()
    except OSError as error:
        raise ProvenanceError("private review key disappeared during custody") from error
    if _identity(after) != _identity(final_path):
        raise ProvenanceError("private review key pathname changed during custody")
    return key


def _write_new_private_review_key(path: Path) -> bytes:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    _require_private_review_parent(path)
    key = os.urandom(PRIVATE_REVIEW_KEY_BYTES)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        os.fchmod(descriptor, 0o600)
        offset = 0
        while offset < len(key):
            offset += os.write(descriptor, key[offset:])
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(temporary_path, path)
        os.chmod(path, 0o600)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass
    return _read_private_review_key(path)


def private_review_commitment(record: dict[str, str], key: bytes) -> str:
    if len(key) != PRIVATE_REVIEW_KEY_BYTES:
        raise ProvenanceError("private review key has an invalid length")
    return hmac.new(key, PRIVATE_REVIEW_DOMAIN + _record_bytes(record), hashlib.sha256).hexdigest()


def create_private_review(*, record_path: Path, key_path: Path, current: dict[str, str]) -> str:
    if record_path.parent != key_path.parent:
        raise ProvenanceError("private review record and key must share one protected directory")
    write_record(record_path, current)
    key = _write_new_private_review_key(key_path)
    verify_record(record_path, current)
    return private_review_commitment(current, key)


def verify_private_review(
    *,
    record_path: Path,
    key_path: Path,
    current: dict[str, str],
    accepted_commitment: str,
) -> None:
    if len(accepted_commitment) != 64 or any(character not in _HEX for character in accepted_commitment):
        raise ProvenanceError("accepted private-input commitment must be canonical lowercase SHA-256")
    verify_record(record_path, current)
    key = _read_private_review_key(key_path)
    observed = private_review_commitment(current, key)
    if not hmac.compare_digest(observed, accepted_commitment):
        raise ProvenanceError("private Tuya build inputs do not match the externally accepted review commitment")


def _git_output(repo_root: Path, *arguments: str) -> bytes:
    environment = {
        "PATH": "/usr/bin:/bin",
        "LC_ALL": "C",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }
    try:
        completed = subprocess.run(
            ["/usr/bin/git", "-C", str(repo_root), *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            check=False,
        )
    except OSError as error:
        raise ProvenanceError("system Git is unavailable for exact-source review authority") from error
    if completed.returncode != 0:
        raise ProvenanceError("exact-source private review authority could not be resolved")
    return completed.stdout


def exact_source_private_review_commitment(lockfile: Path) -> str:
    try:
        repo_root = lockfile.parent.resolve(strict=True)
    except OSError as error:
        raise ProvenanceError("accepted repository root is unavailable") from error
    head = _git_output(repo_root, "rev-parse", "HEAD").decode("ascii", errors="strict").strip().lower()
    if len(head) != 40 or any(character not in _HEX for character in head):
        raise ProvenanceError("accepted repository HEAD is malformed")
    object_id = _git_output(
        repo_root,
        "rev-parse",
        f"{head}:{PRIVATE_REVIEW_AUTHORITY_PATH}",
    ).decode("ascii", errors="strict").strip().lower()
    if len(object_id) != 40 or any(character not in _HEX for character in object_id):
        raise ProvenanceError("private review authority Git object is malformed")
    payload = _git_output(repo_root, "cat-file", "blob", object_id)
    try:
        text = payload.decode("ascii")
    except UnicodeDecodeError as error:
        raise ProvenanceError("private review authority is not canonical ASCII") from error
    if text.endswith("\n"):
        text = text[:-1]
    if "\n" in text or "\r" in text or len(text) != 64 or any(character not in _HEX for character in text):
        raise ProvenanceError("exact accepted source has no canonical 64-hex private-input review commitment")
    return text


def verify_against_exact_source(*, record_path: Path, lockfile: Path, current: dict[str, str]) -> None:
    accepted = exact_source_private_review_commitment(lockfile)
    verify_private_review(
        record_path=record_path,
        key_path=record_path.parent / PRIVATE_REVIEW_KEY_NAME,
        current=current,
        accepted_commitment=accepted,
    )


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("snapshot", "verify", "review", "verify-review"))
    parser.add_argument("--lockfile", required=True, type=Path)
    parser.add_argument("--security-podspec", required=True, type=Path)
    parser.add_argument("--security-build", required=True, type=Path)
    parser.add_argument("--identity-podspec", required=True, type=Path)
    parser.add_argument("--identity-sources", required=True, type=Path)
    parser.add_argument("--record", required=True, type=Path)
    parser.add_argument("--review-key", type=Path)
    parser.add_argument("--accepted-commitment")
    return parser.parse_args()


def main() -> int:
    arguments = _arguments()
    try:
        current = build_record(
            lockfile=arguments.lockfile,
            security_podspec=arguments.security_podspec,
            security_build=arguments.security_build,
            identity_podspec=arguments.identity_podspec,
            identity_sources=arguments.identity_sources,
        )
        if arguments.operation == "snapshot":
            if arguments.review_key is not None or arguments.accepted_commitment is not None:
                raise ProvenanceError("snapshot mode does not accept review authority")
            write_record(arguments.record, current)
        elif arguments.operation == "verify":
            if arguments.review_key is not None or arguments.accepted_commitment is not None:
                raise ProvenanceError("verify mode resolves review authority from exact Git source and accepts no override")
            verify_against_exact_source(
                record_path=arguments.record,
                lockfile=arguments.lockfile,
                current=current,
            )
        elif arguments.operation == "review":
            if arguments.review_key is None or arguments.accepted_commitment is not None:
                raise ProvenanceError("review mode requires --review-key and no preexisting commitment")
            print(create_private_review(
                record_path=arguments.record,
                key_path=arguments.review_key,
                current=current,
            ))
        else:
            if arguments.review_key is None or arguments.accepted_commitment is None:
                raise ProvenanceError("verify-review mode requires --review-key and --accepted-commitment")
            verify_private_review(
                record_path=arguments.record,
                key_path=arguments.review_key,
                current=current,
                accepted_commitment=arguments.accepted_commitment,
            )
    except (OSError, UnicodeError, ProvenanceError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
