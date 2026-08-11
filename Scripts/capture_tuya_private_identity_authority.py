#!/usr/bin/env python3
"""Root-sealed, non-secret authority for Nembra's private Tuya identity transaction.

The private identity writer owns credential bytes. This helper owns only a small
root-sealed receipt containing SHA-256 fingerprints of the exact successful
writer outputs. A new provisioning attempt revokes the prior receipt before any
credential input. Failed or partial publication therefore cannot become later
CocoaPods build input merely because attacker-controlled bytes occupy a canonical
LocalSecrets pathname.

No AppKey, AppSecret, SDK bytes, device identifiers, account tokens, or session
material are written to the authority receipt.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
from typing import Final

SCHEMA: Final = "nembra-private-identity-authority-v1"
AUTHORITY_ROOT: Final = Path("/private/tmp/nembra-capture-private-identity-authority-v1")
PODSPEC_RELATIVE: Final = "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"
IDENTITY_RELATIVE: Final = (
    "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/"
    "NembraTuyaPrivateIdentity.swift"
)
WRITER_RELATIVE: Final = "Scripts/provision_capture_tuya_identity_writer.py"
_PRIVATE_STAGE_PREFIX: Final = ".nembra-private-stage-"
_MAX_PRIVATE_FILE_BYTES: Final = 1024 * 1024
_MAX_RECEIPT_BYTES: Final = 4096
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_RECEIPT_KEYS: Final = {
    "schema",
    "checkout_subject",
    "checkout_path_sha256",
    "checkout_dev",
    "checkout_ino",
    "operator_uid",
    "writer_sha256",
    "podspec_sha256",
    "identity_sha256",
}


class AuthorityError(RuntimeError):
    pass


def _directory_flags() -> int:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    directory = getattr(os, "O_DIRECTORY", None)
    if nofollow is None or directory is None:
        raise AuthorityError("private identity authority requires O_NOFOLLOW and O_DIRECTORY support")
    return os.O_RDONLY | os.O_CLOEXEC | nofollow | directory


def _regular_read_flags() -> int:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise AuthorityError("private identity authority requires O_NOFOLLOW support")
    return os.O_RDONLY | os.O_CLOEXEC | nofollow


def _stat_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _canonical_checkout_root(raw: str | Path) -> Path:
    root = Path(raw)
    if not root.is_absolute():
        raise AuthorityError("checkout root must be an absolute physical path")
    try:
        resolved = root.resolve(strict=True)
    except OSError as exc:
        raise AuthorityError("checkout root is unavailable") from exc
    if resolved != root:
        raise AuthorityError("checkout root must already be canonical; symlink aliases are not authority")
    return root


def _open_checkout_root(root: Path) -> tuple[int, os.stat_result]:
    try:
        descriptor = os.open(root, _directory_flags())
    except OSError as exc:
        raise AuthorityError("could not admit the checkout root for private identity authority") from exc
    try:
        held = os.fstat(descriptor)
        named = root.lstat()
        if (
            not stat.S_ISDIR(held.st_mode)
            or stat.S_ISLNK(named.st_mode)
            or not stat.S_ISDIR(named.st_mode)
            or _stat_identity(held) != _stat_identity(named)
        ):
            raise AuthorityError("checkout root pathname does not bind the admitted directory")
        return descriptor, held
    except Exception:
        os.close(descriptor)
        raise


def _checkout_subject(root: Path, metadata: os.stat_result) -> tuple[str, str]:
    path_digest = hashlib.sha256(os.fsencode(str(root))).hexdigest()
    subject = hashlib.sha256(
        b"nembra-private-identity-authority-subject-v1\0"
        + bytes.fromhex(path_digest)
        + b"\0"
        + str(metadata.st_dev).encode("ascii")
        + b":"
        + str(metadata.st_ino).encode("ascii")
    ).hexdigest()
    return subject, path_digest


def _relative_components(relative: str) -> tuple[str, ...]:
    path = Path(relative)
    if path.is_absolute():
        raise AuthorityError("private authority path must remain checkout-relative")
    parts = path.parts
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise AuthorityError("private authority path is not canonical")
    return tuple(parts)


def _open_relative_regular(
    root_fd: int,
    relative: str,
    *,
    expected_uid: int | None,
    expected_file_mode: int | None,
    expected_directory_mode: int | None,
    max_bytes: int,
) -> tuple[int, list[tuple[int, str, tuple[int, ...]]]]:
    parts = _relative_components(relative)
    held_directories: list[int] = []
    bindings: list[tuple[int, str, tuple[int, ...]]] = []
    parent_fd = root_fd
    try:
        for component in parts[:-1]:
            child_fd = os.open(component, _directory_flags(), dir_fd=parent_fd)
            held_directories.append(child_fd)
            child = os.fstat(child_fd)
            named = os.stat(component, dir_fd=parent_fd, follow_symlinks=False)
            if (
                not stat.S_ISDIR(child.st_mode)
                or stat.S_ISLNK(named.st_mode)
                or not stat.S_ISDIR(named.st_mode)
                or _stat_identity(child) != _stat_identity(named)
                or (expected_uid is not None and child.st_uid != expected_uid)
                or (
                    expected_directory_mode is not None
                    and stat.S_IMODE(child.st_mode) != expected_directory_mode
                )
            ):
                raise AuthorityError("private identity directory ancestry is outside admitted authority")
            bindings.append((parent_fd, component, _stat_identity(child)))
            parent_fd = child_fd

        descriptor = os.open(parts[-1], _regular_read_flags(), dir_fd=parent_fd)
        held = os.fstat(descriptor)
        named = os.stat(parts[-1], dir_fd=parent_fd, follow_symlinks=False)
        if (
            not stat.S_ISREG(held.st_mode)
            or stat.S_ISLNK(named.st_mode)
            or not stat.S_ISREG(named.st_mode)
            or _stat_identity(held) != _stat_identity(named)
            or held.st_nlink != 1
            or held.st_size > max_bytes
            or (expected_uid is not None and held.st_uid != expected_uid)
            or (
                expected_file_mode is not None
                and stat.S_IMODE(held.st_mode) != expected_file_mode
            )
        ):
            os.close(descriptor)
            raise AuthorityError("private identity build input is outside admitted file authority")
        bindings.append((parent_fd, parts[-1], _stat_identity(held)))
        return descriptor, bindings
    except Exception:
        for held_fd in reversed(held_directories):
            os.close(held_fd)
        raise


def _close_binding_directories(root_fd: int, bindings: list[tuple[int, str, tuple[int, ...]]]) -> None:
    descriptors = {parent_fd for parent_fd, _, _ in bindings if parent_fd != root_fd}
    for descriptor in sorted(descriptors, reverse=True):
        try:
            os.close(descriptor)
        except OSError:
            pass


def _sha256_relative_regular(
    root_fd: int,
    relative: str,
    *,
    expected_uid: int | None,
    expected_file_mode: int | None,
    expected_directory_mode: int | None,
    max_bytes: int = _MAX_PRIVATE_FILE_BYTES,
) -> str:
    descriptor = -1
    bindings: list[tuple[int, str, tuple[int, ...]]] = []
    try:
        descriptor, bindings = _open_relative_regular(
            root_fd,
            relative,
            expected_uid=expected_uid,
            expected_file_mode=expected_file_mode,
            expected_directory_mode=expected_directory_mode,
            max_bytes=max_bytes,
        )
        before = os.fstat(descriptor)
        digest = hashlib.sha256()
        bytes_read = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            bytes_read += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        if _stat_identity(before) != _stat_identity(after) or bytes_read != after.st_size:
            raise AuthorityError("private identity build input changed while fingerprinted")

        for parent_fd, name, expected in bindings:
            current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
            if _stat_identity(current) != expected:
                raise AuthorityError("private identity pathname changed during authority verification")
        final = os.fstat(descriptor)
        if _stat_identity(final) != _stat_identity(after):
            raise AuthorityError("private identity descriptor changed during authority verification")
        return digest.hexdigest()
    except OSError as exc:
        raise AuthorityError("could not fingerprint a required private identity build input") from exc
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        _close_binding_directories(root_fd, bindings)


def _require_no_private_stage_residue(checkout_fd: int) -> None:
    try:
        names = os.listdir(checkout_fd)
    except OSError as exc:
        raise AuthorityError("could not inspect private identity staging namespace") from exc
    if any(name.startswith(_PRIVATE_STAGE_PREFIX) for name in names):
        raise AuthorityError("private identity staging residue remains; successful transaction authority is unavailable")


def _authority_directory_fd(
    authority_root: Path,
    *,
    create: bool,
    authority_uid: int,
) -> int | None:
    try:
        metadata = authority_root.lstat()
    except FileNotFoundError:
        if not create:
            return None
        try:
            os.mkdir(authority_root, 0o755)
            metadata = authority_root.lstat()
        except OSError as exc:
            raise AuthorityError("could not create the protected private identity authority directory") from exc
    except OSError as exc:
        raise AuthorityError("could not inspect the private identity authority directory") from exc

    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != authority_uid
        or stat.S_IMODE(metadata.st_mode) != 0o755
    ):
        raise AuthorityError("private identity authority directory is not protected by expected ownership")

    try:
        descriptor = os.open(authority_root, _directory_flags())
    except OSError as exc:
        raise AuthorityError("could not open the private identity authority directory") from exc
    held = os.fstat(descriptor)
    current = authority_root.lstat()
    if _stat_identity(held) != _stat_identity(current):
        os.close(descriptor)
        raise AuthorityError("private identity authority directory changed during admission")
    return descriptor


def _receipt_name(subject: str) -> str:
    if _HEX64.fullmatch(subject) is None:
        raise AuthorityError("private identity checkout subject is malformed")
    return f"{subject}.json"


def _read_receipt(authority_fd: int, name: str, authority_uid: int) -> dict[str, object]:
    descriptor = -1
    try:
        descriptor = os.open(name, _regular_read_flags(), dir_fd=authority_fd)
        before = os.fstat(descriptor)
        named = os.stat(name, dir_fd=authority_fd, follow_symlinks=False)
        if (
            not stat.S_ISREG(before.st_mode)
            or stat.S_ISLNK(named.st_mode)
            or not stat.S_ISREG(named.st_mode)
            or _stat_identity(before) != _stat_identity(named)
            or before.st_uid != authority_uid
            or before.st_nlink != 1
            or stat.S_IMODE(before.st_mode) != 0o444
            or before.st_size > _MAX_RECEIPT_BYTES
        ):
            raise AuthorityError("private identity authority receipt metadata is unsafe")
        payload = bytearray()
        while True:
            chunk = os.read(descriptor, 4096)
            if not chunk:
                break
            payload.extend(chunk)
            if len(payload) > _MAX_RECEIPT_BYTES:
                raise AuthorityError("private identity authority receipt is oversized")
        after = os.fstat(descriptor)
        current = os.stat(name, dir_fd=authority_fd, follow_symlinks=False)
        if _stat_identity(before) != _stat_identity(after) or _stat_identity(after) != _stat_identity(current):
            raise AuthorityError("private identity authority receipt changed while read")
        try:
            decoded = json.loads(bytes(payload).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise AuthorityError("private identity authority receipt is malformed") from exc
        if not isinstance(decoded, dict) or set(decoded) != _RECEIPT_KEYS:
            raise AuthorityError("private identity authority receipt has an unexpected schema")
        return decoded
    except FileNotFoundError as exc:
        raise AuthorityError("private identity authority receipt is missing; reprovision first") from exc
    except OSError as exc:
        raise AuthorityError("private identity authority receipt could not be read") from exc
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def _validate_receipt_fields(
    receipt: dict[str, object],
    *,
    subject: str,
    path_sha256: str,
    checkout_metadata: os.stat_result,
    operator_uid: int,
    expected_writer_sha256: str,
) -> tuple[str, str]:
    if receipt.get("schema") != SCHEMA:
        raise AuthorityError("private identity authority receipt schema is not accepted")
    if receipt.get("checkout_subject") != subject or receipt.get("checkout_path_sha256") != path_sha256:
        raise AuthorityError("private identity authority receipt belongs to a different checkout")
    if receipt.get("checkout_dev") != checkout_metadata.st_dev or receipt.get("checkout_ino") != checkout_metadata.st_ino:
        raise AuthorityError("private identity authority receipt checkout inode no longer matches")
    if receipt.get("operator_uid") != operator_uid:
        raise AuthorityError("private identity authority receipt belongs to a different local operator")
    if receipt.get("writer_sha256") != expected_writer_sha256:
        raise AuthorityError("private identity authority receipt was produced by different writer bytes")
    podspec_sha = receipt.get("podspec_sha256")
    identity_sha = receipt.get("identity_sha256")
    if not isinstance(podspec_sha, str) or _HEX64.fullmatch(podspec_sha) is None:
        raise AuthorityError("private identity podspec receipt fingerprint is malformed")
    if not isinstance(identity_sha, str) or _HEX64.fullmatch(identity_sha) is None:
        raise AuthorityError("private identity source receipt fingerprint is malformed")
    return podspec_sha, identity_sha


def _verify_current_subject(
    root: Path,
    *,
    operator_uid: int,
    expected_writer_sha256: str,
    authority_root: Path,
    authority_uid: int,
) -> Path:
    if _HEX64.fullmatch(expected_writer_sha256) is None:
        raise AuthorityError("accepted private identity writer digest is malformed")
    checkout_fd, checkout_metadata = _open_checkout_root(root)
    authority_fd = -1
    try:
        subject, path_sha256 = _checkout_subject(root, checkout_metadata)
        authority_fd_or_none = _authority_directory_fd(
            authority_root,
            create=False,
            authority_uid=authority_uid,
        )
        if authority_fd_or_none is None:
            raise AuthorityError("private identity authority has not been sealed; reprovision first")
        authority_fd = authority_fd_or_none
        receipt = _read_receipt(authority_fd, _receipt_name(subject), authority_uid)
        expected_podspec_sha, expected_identity_sha = _validate_receipt_fields(
            receipt,
            subject=subject,
            path_sha256=path_sha256,
            checkout_metadata=checkout_metadata,
            operator_uid=operator_uid,
            expected_writer_sha256=expected_writer_sha256,
        )
        _require_no_private_stage_residue(checkout_fd)
        writer_sha = _sha256_relative_regular(
            checkout_fd,
            WRITER_RELATIVE,
            expected_uid=None,
            expected_file_mode=None,
            expected_directory_mode=None,
        )
        if writer_sha != expected_writer_sha256:
            raise AuthorityError("current private identity writer bytes do not match the accepted digest")
        podspec_sha = _sha256_relative_regular(
            checkout_fd,
            PODSPEC_RELATIVE,
            expected_uid=operator_uid,
            expected_file_mode=0o600,
            expected_directory_mode=0o700,
        )
        identity_sha = _sha256_relative_regular(
            checkout_fd,
            IDENTITY_RELATIVE,
            expected_uid=operator_uid,
            expected_file_mode=0o600,
            expected_directory_mode=0o700,
        )
        if podspec_sha != expected_podspec_sha or identity_sha != expected_identity_sha:
            raise AuthorityError("current private identity bytes do not match the last successful sealed transaction")
        return authority_root / _receipt_name(subject)
    finally:
        if authority_fd >= 0:
            os.close(authority_fd)
        os.close(checkout_fd)


def _write_root_receipt(
    authority_fd: int,
    name: str,
    receipt: dict[str, object],
    *,
    authority_uid: int,
) -> None:
    try:
        existing = os.stat(name, dir_fd=authority_fd, follow_symlinks=False)
    except FileNotFoundError:
        existing = None
    except OSError as exc:
        raise AuthorityError("could not inspect existing private identity authority receipt") from exc
    if existing is not None and (
        not stat.S_ISREG(existing.st_mode)
        or existing.st_uid != authority_uid
        or existing.st_nlink != 1
        or stat.S_IMODE(existing.st_mode) != 0o444
    ):
        raise AuthorityError("existing private identity authority receipt is not safe to replace")

    encoded = (json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    if len(encoded) > _MAX_RECEIPT_BYTES:
        raise AuthorityError("private identity authority receipt exceeds the size contract")
    temporary = f".{name}.{os.getpid()}.{secrets.token_hex(12)}.tmp"
    descriptor = -1
    try:
        descriptor = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
            0o600,
            dir_fd=authority_fd,
        )
        view = memoryview(encoded)
        offset = 0
        while offset < len(view):
            written = os.write(descriptor, view[offset:])
            if written <= 0:
                raise AuthorityError("could not write complete private identity authority receipt")
            offset += written
        os.fsync(descriptor)
        os.fchmod(descriptor, 0o444)
        sealed = os.fstat(descriptor)
        if (
            not stat.S_ISREG(sealed.st_mode)
            or sealed.st_uid != authority_uid
            or sealed.st_nlink != 1
            or stat.S_IMODE(sealed.st_mode) != 0o444
            or sealed.st_size != len(encoded)
        ):
            raise AuthorityError("new private identity authority receipt failed root custody")
        os.replace(temporary, name, src_dir_fd=authority_fd, dst_dir_fd=authority_fd)
        os.fsync(authority_fd)
    except OSError as exc:
        raise AuthorityError("could not publish the private identity authority receipt") from exc
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary, dir_fd=authority_fd)
        except FileNotFoundError:
            pass
        except OSError:
            pass


def _seal_current_subject(
    root: Path,
    *,
    operator_uid: int,
    expected_writer_sha256: str,
    expected_podspec_sha256: str,
    expected_identity_sha256: str,
    authority_root: Path,
    authority_uid: int,
) -> Path:
    for value, label in (
        (expected_writer_sha256, "writer"),
        (expected_podspec_sha256, "podspec"),
        (expected_identity_sha256, "identity"),
    ):
        if _HEX64.fullmatch(value) is None:
            raise AuthorityError(f"private identity {label} digest is malformed")

    checkout_fd, checkout_metadata = _open_checkout_root(root)
    authority_fd = -1
    try:
        _require_no_private_stage_residue(checkout_fd)
        writer_sha = _sha256_relative_regular(
            checkout_fd,
            WRITER_RELATIVE,
            expected_uid=None,
            expected_file_mode=None,
            expected_directory_mode=None,
        )
        podspec_sha = _sha256_relative_regular(
            checkout_fd,
            PODSPEC_RELATIVE,
            expected_uid=operator_uid,
            expected_file_mode=0o600,
            expected_directory_mode=0o700,
        )
        identity_sha = _sha256_relative_regular(
            checkout_fd,
            IDENTITY_RELATIVE,
            expected_uid=operator_uid,
            expected_file_mode=0o600,
            expected_directory_mode=0o700,
        )
        if writer_sha != expected_writer_sha256:
            raise AuthorityError("writer bytes changed between successful provision and authority seal")
        if podspec_sha != expected_podspec_sha256 or identity_sha != expected_identity_sha256:
            raise AuthorityError("private identity bytes changed between successful provision and authority seal")

        subject, path_sha256 = _checkout_subject(root, checkout_metadata)
        authority_fd_or_none = _authority_directory_fd(
            authority_root,
            create=True,
            authority_uid=authority_uid,
        )
        if authority_fd_or_none is None:
            raise AuthorityError("private identity authority directory could not be created")
        authority_fd = authority_fd_or_none
        receipt = {
            "schema": SCHEMA,
            "checkout_subject": subject,
            "checkout_path_sha256": path_sha256,
            "checkout_dev": checkout_metadata.st_dev,
            "checkout_ino": checkout_metadata.st_ino,
            "operator_uid": operator_uid,
            "writer_sha256": writer_sha,
            "podspec_sha256": podspec_sha,
            "identity_sha256": identity_sha,
        }
        name = _receipt_name(subject)
        _write_root_receipt(authority_fd, name, receipt, authority_uid=authority_uid)
        return authority_root / name
    finally:
        if authority_fd >= 0:
            os.close(authority_fd)
        os.close(checkout_fd)


def _invalidate_current_subject(
    root: Path,
    *,
    authority_root: Path,
    authority_uid: int,
) -> None:
    checkout_fd, checkout_metadata = _open_checkout_root(root)
    authority_fd = -1
    try:
        subject, _ = _checkout_subject(root, checkout_metadata)
        authority_fd_or_none = _authority_directory_fd(
            authority_root,
            create=False,
            authority_uid=authority_uid,
        )
        if authority_fd_or_none is None:
            return
        authority_fd = authority_fd_or_none
        name = _receipt_name(subject)
        try:
            metadata = os.stat(name, dir_fd=authority_fd, follow_symlinks=False)
        except FileNotFoundError:
            return
        except OSError as exc:
            raise AuthorityError("could not inspect private identity authority receipt for revocation") from exc
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != authority_uid
            or metadata.st_nlink != 1
            or stat.S_IMODE(metadata.st_mode) != 0o444
        ):
            raise AuthorityError("private identity authority receipt is unsafe to revoke automatically")
        os.unlink(name, dir_fd=authority_fd)
        os.fsync(authority_fd)
    except OSError as exc:
        raise AuthorityError("could not revoke prior private identity authority") from exc
    finally:
        if authority_fd >= 0:
            os.close(authority_fd)
        os.close(checkout_fd)


def _sudo_operator_uid() -> int:
    raw = os.environ.get("SUDO_UID", "")
    if not raw.isdigit():
        raise AuthorityError("privileged private identity authority requires a real sudo operator UID")
    uid = int(raw)
    if uid <= 0:
        raise AuthorityError("privileged private identity authority cannot bind root as the field operator")
    return uid


def _usage() -> AuthorityError:
    return AuthorityError(
        "usage: capture_tuya_private_identity_authority.py "
        "invalidate <checkout-root> | "
        "seal <checkout-root> <writer-sha256> <podspec-sha256> <identity-sha256> | "
        "verify <checkout-root> <writer-sha256>"
    )


def main() -> int:
    try:
        if len(sys.argv) >= 2 and sys.argv[1] in {"invalidate", "seal"}:
            if os.geteuid() != 0:
                raise AuthorityError("private identity authority seal/revocation requires root")
            operator_uid = _sudo_operator_uid()
            if sys.argv[1] == "invalidate":
                if len(sys.argv) != 3:
                    raise _usage()
                root = _canonical_checkout_root(sys.argv[2])
                _invalidate_current_subject(
                    root,
                    authority_root=AUTHORITY_ROOT,
                    authority_uid=0,
                )
                return 0
            if len(sys.argv) != 6:
                raise _usage()
            root = _canonical_checkout_root(sys.argv[2])
            receipt = _seal_current_subject(
                root,
                operator_uid=operator_uid,
                expected_writer_sha256=sys.argv[3].lower(),
                expected_podspec_sha256=sys.argv[4].lower(),
                expected_identity_sha256=sys.argv[5].lower(),
                authority_root=AUTHORITY_ROOT,
                authority_uid=0,
            )
            print(receipt)
            return 0

        if len(sys.argv) == 4 and sys.argv[1] == "verify":
            if os.geteuid() == 0:
                raise AuthorityError("run private identity bootstrap verification as the non-root field operator")
            root = _canonical_checkout_root(sys.argv[2])
            receipt = _verify_current_subject(
                root,
                operator_uid=os.geteuid(),
                expected_writer_sha256=sys.argv[3].lower(),
                authority_root=AUTHORITY_ROOT,
                authority_uid=0,
            )
            print(receipt)
            return 0

        raise _usage()
    except (AuthorityError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
