#!/usr/bin/env python3
"""Descriptor-bound writer for Nembra's local-only Tuya app identity.

The privileged shell wrapper owns hidden credential input, pins these source
bytes before input, and opens the admitted checkout directory before input.
This helper inherits that exact directory descriptor and never reopens the
checkout pathname for publication. The pathname is re-opened only as a drift
check: its descriptor identity must still equal the inherited admitted root
before any private descendant is created.

Credential-bearing staging files are created directly under the admitted root,
not under long-lived descendant directory descriptors. On Darwin, publication
uses renameatx_np with no-follow-any + resolve-beneath semantics so every path
component is resolved beneath that admitted root in the publication syscall.
The sealed staging descriptor remains open through publication and the final
named inode must match it exactly before success.
"""

from __future__ import annotations

import base64
import ctypes
import hashlib
import hmac
import os
import secrets
import stat
import sys
import tempfile
from pathlib import Path


class ProvisionError(RuntimeError):
    pass


_DARWIN_RENAME_NOFOLLOW_ANY = 0x00000010
_DARWIN_RENAME_RESOLVE_BENEATH = 0x00000020
_PRIVATE_STAGE_PREFIX = ".nembra-private-stage-"
_PRIVATE_STAGE_NONCE_HEX_LENGTH = 24
_PRIVATE_STAGE_MAX_BYTES = 1_048_576


def _directory_flags() -> int:
    required = ("O_CLOEXEC", "O_DIRECTORY", "O_NOFOLLOW")
    if any(not hasattr(os, name) for name in required):
        raise ProvisionError("platform cannot enforce descriptor-bound no-follow directory custody")
    return os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW


def _file_flags() -> int:
    required = ("O_CLOEXEC", "O_NOFOLLOW")
    if any(not hasattr(os, name) for name in required):
        raise ProvisionError("platform cannot enforce descriptor-bound no-follow file custody")
    return os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW


def _open_absolute_directory(path: Path) -> int:
    raw = os.fspath(path)
    if not path.is_absolute() or os.path.normpath(raw) != raw:
        raise ProvisionError("checkout root must be one canonical absolute path")

    descriptor = os.open(os.sep, _directory_flags())
    try:
        for component in path.parts[1:]:
            if not component or component in (".", "..") or "/" in component:
                raise ProvisionError("checkout root contains an invalid path component")
            next_descriptor = os.open(component, _directory_flags(), dir_fd=descriptor)
            os.close(descriptor)
            descriptor = next_descriptor
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _duplicate_inherited_checkout(raw_fd: str) -> int:
    try:
        descriptor_number = int(raw_fd, 10)
    except ValueError as exc:
        raise ProvisionError("inherited checkout descriptor is not a decimal file descriptor") from exc
    if descriptor_number < 0 or str(descriptor_number) != raw_fd:
        raise ProvisionError("inherited checkout descriptor is not canonical")
    try:
        descriptor = os.dup(descriptor_number)
    except OSError as exc:
        raise ProvisionError("inherited checkout descriptor is unavailable") from exc
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.geteuid():
            raise ProvisionError("inherited checkout descriptor is not one current-user directory")
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _require_checkout_path_identity(checkout_fd: int, checkout_root: Path) -> None:
    current_fd = _open_absolute_directory(checkout_root)
    try:
        admitted = os.fstat(checkout_fd)
        current = os.fstat(current_fd)
        if (
            admitted.st_dev != current.st_dev
            or admitted.st_ino != current.st_ino
            or not stat.S_ISDIR(current.st_mode)
            or current.st_uid != os.geteuid()
        ):
            raise ProvisionError("checkout root identity changed after private-input admission")
    finally:
        os.close(current_fd)



def _is_canonical_private_stage_name(name: str) -> bool:
    if not name.startswith(_PRIVATE_STAGE_PREFIX):
        return False
    suffix = name[len(_PRIVATE_STAGE_PREFIX):]
    pid_text, separator, nonce = suffix.partition("-")
    if not separator or not (0 < len(pid_text) <= 20):
        return False
    if not pid_text.isascii() or not pid_text.isdecimal() or pid_text == "0":
        return False
    if str(int(pid_text, 10)) != pid_text:
        return False
    return (
        len(nonce) == _PRIVATE_STAGE_NONCE_HEX_LENGTH
        and all(character in "0123456789abcdef" for character in nonce)
    )


class _RecoveredPrivateStage:
    """Descriptor custody for one exact writer-shaped hard-exit residue."""

    def __init__(self, name: str, descriptor: int, metadata: os.stat_result) -> None:
        self.name = name
        self.descriptor = descriptor
        self.metadata = metadata

    def take_descriptor(self) -> int:
        if self.descriptor < 0:
            raise ProvisionError("recovered private identity staging descriptor was already consumed")
        descriptor = self.descriptor
        self.descriptor = -1
        return descriptor

    def close(self) -> None:
        if self.descriptor >= 0:
            os.close(self.descriptor)
            self.descriptor = -1


def _recover_private_stage_residue(checkout_fd: int) -> _RecoveredPrivateStage | None:
    """Admit at most one exact crash residue by descriptor; never delete by pathname."""
    try:
        entries = os.listdir(checkout_fd)
    except OSError as exc:
        raise ProvisionError("could not inspect private identity staging namespace") from exc

    reserved = sorted(name for name in entries if name.startswith(_PRIVATE_STAGE_PREFIX))
    for name in reserved:
        if not _is_canonical_private_stage_name(name):
            raise ProvisionError("reserved private identity staging namespace contains a non-writer entry")
    if not reserved:
        return None
    if len(reserved) != 1:
        raise ProvisionError("private identity staging namespace contains multiple ambiguous crash residues")

    name = reserved[0]
    try:
        named = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)
    except OSError as exc:
        raise ProvisionError("could not inspect reserved private identity staging entry") from exc
    if (
        not stat.S_ISREG(named.st_mode)
        or named.st_uid != os.geteuid()
        or named.st_nlink != 1
        or stat.S_IMODE(named.st_mode) != 0o600
        or named.st_size > _PRIVATE_STAGE_MAX_BYTES
    ):
        raise ProvisionError("reserved private identity staging entry is not safe writer-owned crash residue")

    descriptor = -1
    try:
        descriptor = os.open(
            name,
            os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW,
            dir_fd=checkout_fd,
        )
        held = os.fstat(descriptor)
        current = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)
        if (
            not stat.S_ISREG(held.st_mode)
            or held.st_uid != os.geteuid()
            or held.st_nlink != 1
            or stat.S_IMODE(held.st_mode) != 0o600
            or held.st_size > _PRIVATE_STAGE_MAX_BYTES
            or named.st_dev != held.st_dev
            or named.st_ino != held.st_ino
            or named.st_uid != held.st_uid
            or named.st_nlink != held.st_nlink
            or named.st_mode != held.st_mode
            or named.st_size != held.st_size
            or current.st_dev != held.st_dev
            or current.st_ino != held.st_ino
            or current.st_uid != held.st_uid
            or current.st_nlink != held.st_nlink
            or current.st_mode != held.st_mode
            or current.st_size != held.st_size
        ):
            raise ProvisionError("reserved private identity staging entry changed during recovery admission")
        recovered = _RecoveredPrivateStage(name, descriptor, held)
        descriptor = -1
        return recovered
    except ProvisionError:
        raise
    except OSError as exc:
        raise ProvisionError("could not safely admit writer-owned private identity crash residue") from exc
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def _require_recovered_stage_binding(
    checkout_fd: int,
    recovered: _RecoveredPrivateStage,
    descriptor: int,
) -> None:
    """Re-bind the reserved name to the held inode before any recovered-byte mutation."""
    try:
        current = os.stat(recovered.name, dir_fd=checkout_fd, follow_symlinks=False)
    except OSError as exc:
        raise ProvisionError("recovered private identity staging name changed before reuse") from exc
    held = os.fstat(descriptor)
    admitted = recovered.metadata
    if (
        not stat.S_ISREG(held.st_mode)
        or held.st_uid != os.geteuid()
        or held.st_nlink != 1
        or stat.S_IMODE(held.st_mode) != 0o600
        or held.st_size > _PRIVATE_STAGE_MAX_BYTES
        or held.st_dev != admitted.st_dev
        or held.st_ino != admitted.st_ino
        or held.st_uid != admitted.st_uid
        or held.st_nlink != admitted.st_nlink
        or held.st_mode != admitted.st_mode
        or held.st_size != admitted.st_size
        or current.st_dev != held.st_dev
        or current.st_ino != held.st_ino
        or current.st_uid != held.st_uid
        or current.st_nlink != held.st_nlink
        or current.st_mode != held.st_mode
        or current.st_size != held.st_size
    ):
        raise ProvisionError("recovered private identity staging name no longer binds the admitted inode")


def _ensure_private_directory(parent_fd: int, name: str) -> int:
    if not name or name in (".", "..") or "/" in name:
        raise ProvisionError("private identity path contains an invalid component")
    try:
        os.mkdir(name, 0o700, dir_fd=parent_fd)
    except FileExistsError:
        pass
    except OSError as exc:
        raise ProvisionError(f"could not create private identity directory {name!r}") from exc

    try:
        descriptor = os.open(name, _directory_flags(), dir_fd=parent_fd)
    except OSError as exc:
        raise ProvisionError(
            f"private identity directory is missing, not a directory, or is a symlink: {name!r}"
        ) from exc

    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.geteuid():
            raise ProvisionError("private identity directory is not owned by the current user")
        os.fchmod(descriptor, 0o700)
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _require_named_child(parent_fd: int, name: str, child_fd: int) -> None:
    try:
        named = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except OSError as exc:
        raise ProvisionError(f"private identity ancestry changed for {name!r}") from exc
    held = os.fstat(child_fd)
    if (
        not stat.S_ISDIR(named.st_mode)
        or not stat.S_ISDIR(held.st_mode)
        or named.st_uid != os.geteuid()
        or held.st_uid != os.geteuid()
        or named.st_dev != held.st_dev
        or named.st_ino != held.st_ino
    ):
        raise ProvisionError(f"private identity directory is no longer the admitted child: {name!r}")


def _require_private_chain(
    checkout_fd: int,
    local_secrets_fd: int,
    runtime_fd: int,
    sources_fd: int,
    module_fd: int,
) -> None:
    _require_named_child(checkout_fd, "LocalSecrets", local_secrets_fd)
    _require_named_child(local_secrets_fd, "TuyaRuntime", runtime_fd)
    _require_named_child(runtime_fd, "Sources", sources_fd)
    _require_named_child(sources_fd, "NembraTuyaPrivateConfig", module_fd)


def _relative_components(relative_path: str) -> tuple[str, ...]:
    if (
        not relative_path
        or os.path.isabs(relative_path)
        or os.path.normpath(relative_path) != relative_path
    ):
        raise ProvisionError("private identity publication path must be canonical and relative")
    components = tuple(relative_path.split("/"))
    if any(not component or component in (".", "..") or "/" in component for component in components):
        raise ProvisionError("private identity publication path contains an invalid component")
    return components


def _open_relative_regular_file(checkout_fd: int, relative_path: str) -> int:
    components = _relative_components(relative_path)
    parent_fd = os.dup(checkout_fd)
    try:
        for component in components[:-1]:
            next_fd = os.open(component, _directory_flags(), dir_fd=parent_fd)
            os.close(parent_fd)
            parent_fd = next_fd
        descriptor = os.open(
            components[-1],
            os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
            dir_fd=parent_fd,
        )
        return descriptor
    finally:
        os.close(parent_fd)


def _validate_existing_output(parent_fd: int, name: str) -> None:
    try:
        metadata = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    except OSError as exc:
        raise ProvisionError(f"could not inspect existing private identity output {name!r}") from exc

    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or metadata.st_nlink != 1
    ):
        raise ProvisionError(
            f"refusing to replace private identity output that is not one owned regular file: {name!r}"
        )


def _require_sealed_staging_name(checkout_fd: int, source_name: str, sealed: os.stat_result) -> None:
    try:
        current = os.stat(source_name, dir_fd=checkout_fd, follow_symlinks=False)
    except OSError as exc:
        raise ProvisionError("sealed private identity staging name disappeared before publication") from exc
    if (
        not stat.S_ISREG(current.st_mode)
        or current.st_uid != os.geteuid()
        or current.st_nlink != 1
        or current.st_dev != sealed.st_dev
        or current.st_ino != sealed.st_ino
    ):
        raise ProvisionError("private identity staging name no longer references the sealed inode")


def _require_final_relative_name_binding(
    checkout_fd: int,
    relative_path: str,
    sealed: os.stat_result,
    payload: bytes,
) -> None:
    """Re-bind the canonical credential name to the accepted inode at success."""
    rebound_fd = -1
    try:
        rebound_fd = _open_relative_regular_file(checkout_fd, relative_path)
        rebound = os.fstat(rebound_fd)
        if (
            not stat.S_ISREG(rebound.st_mode)
            or rebound.st_uid != os.geteuid()
            or rebound.st_nlink != 1
            or stat.S_IMODE(rebound.st_mode) != 0o600
            or rebound.st_size != len(payload)
            or rebound.st_dev != sealed.st_dev
            or rebound.st_ino != sealed.st_ino
        ):
            raise ProvisionError(
                "private identity canonical destination no longer names the accepted sealed inode"
            )
        _require_descriptor_payload(
            rebound_fd,
            payload,
            "private identity canonical destination failed final payload binding",
        )
    finally:
        if rebound_fd >= 0:
            os.close(rebound_fd)


class _SealedStaging:
    def __init__(self, metadata: os.stat_result, descriptor: int, payload: bytes) -> None:
        self.metadata = metadata
        self.descriptor = descriptor
        self.payload = payload

    def __getattr__(self, name: str):
        return getattr(self.metadata, name)


def _payload_stat_identity(metadata: os.stat_result) -> tuple[int, ...]:
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


def _require_descriptor_payload(descriptor: int, payload: bytes, label: str) -> None:
    before = os.fstat(descriptor)
    if (
        not stat.S_ISREG(before.st_mode)
        or before.st_uid != os.geteuid()
        or before.st_nlink != 1
        or before.st_size != len(payload)
    ):
        raise ProvisionError(f"{label}: descriptor metadata no longer matches accepted payload custody")

    chunks: list[bytes] = []
    offset = 0
    while offset < before.st_size:
        chunk = os.pread(descriptor, min(65_536, before.st_size - offset), offset)
        if not chunk:
            raise ProvisionError(f"{label}: descriptor bytes changed during accepted payload read")
        chunks.append(chunk)
        offset += len(chunk)
    if os.pread(descriptor, 1, before.st_size):
        raise ProvisionError(f"{label}: descriptor grew during accepted payload read")

    after = os.fstat(descriptor)
    if _payload_stat_identity(before) != _payload_stat_identity(after):
        raise ProvisionError(f"{label}: descriptor metadata changed during accepted payload read")
    actual = hashlib.sha256(b"".join(chunks)).digest()
    expected = hashlib.sha256(payload).digest()
    if not hmac.compare_digest(actual, expected):
        raise ProvisionError(f"{label}: descriptor bytes do not match the accepted payload")


def _secure_replace_beneath(
    checkout_fd: int,
    source_name: str,
    destination_relative: str,
    sealed: os.stat_result,
) -> None:
    _relative_components(source_name)
    _relative_components(destination_relative)
    _require_sealed_staging_name(checkout_fd, source_name, sealed)
    if isinstance(sealed, _SealedStaging):
        _require_descriptor_payload(
            sealed.descriptor,
            sealed.payload,
            "private identity staging payload changed immediately before publication",
        )
    if sys.platform == "darwin":
        libc = ctypes.CDLL(None, use_errno=True)
        try:
            renameatx_np = libc.renameatx_np
        except AttributeError as exc:
            raise ProvisionError("Darwin cannot provide renameatx_np publication custody") from exc
        renameatx_np.argtypes = (
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        )
        renameatx_np.restype = ctypes.c_int
        flags = _DARWIN_RENAME_NOFOLLOW_ANY | _DARWIN_RENAME_RESOLVE_BENEATH
        result = renameatx_np(
            checkout_fd,
            os.fsencode(source_name),
            checkout_fd,
            os.fsencode(destination_relative),
            flags,
        )
        if result != 0:
            error = ctypes.get_errno()
            raise ProvisionError("Darwin rejected private identity publication outside admitted ancestry") from OSError(
                error,
                os.strerror(error),
            )
        return

    # Linux CI fallback exercises the same root-relative custody shape. Physical
    # field publication is macOS-only and is required to take the Darwin path.
    os.replace(
        source_name,
        destination_relative,
        src_dir_fd=checkout_fd,
        dst_dir_fd=checkout_fd,
    )


def _sanitize_held_private_descriptor(descriptor: int) -> None:
    """Sanitize only the exact already-held private inode on a failed write path."""
    try:
        os.ftruncate(descriptor, 0)
        os.fsync(descriptor)
    except OSError as exc:
        raise ProvisionError("could not sanitize held private identity staging inode after failure") from exc


def _write_staged(
    checkout_fd: int,
    destination_parent_fd: int,
    final_name: str,
    destination_relative: str,
    payload: bytes,
    recovered_stage: _RecoveredPrivateStage | None = None,
) -> None:
    components = _relative_components(destination_relative)
    if components[-1] != final_name:
        raise ProvisionError("private identity final name does not match its admitted relative path")
    _validate_existing_output(destination_parent_fd, final_name)

    temporary_name = (
        recovered_stage.name
        if recovered_stage is not None
        else f"{_PRIVATE_STAGE_PREFIX}{os.getpid()}-{secrets.token_hex(12)}"
    )
    staging_fd = final_fd = -1
    sealed: os.stat_result | None = None
    try:
        if recovered_stage is not None:
            staging_fd = recovered_stage.take_descriptor()
            _require_recovered_stage_binding(checkout_fd, recovered_stage, staging_fd)
            os.ftruncate(staging_fd, 0)
            os.lseek(staging_fd, 0, os.SEEK_SET)
        else:
            staging_fd = os.open(temporary_name, _file_flags(), 0o600, dir_fd=checkout_fd)
        metadata = os.fstat(staging_fd)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1
        ):
            raise ProvisionError("new private identity staging file failed ownership custody")

        view = memoryview(payload)
        offset = 0
        while offset < len(view):
            written = os.write(staging_fd, view[offset:])
            if written <= 0:
                raise ProvisionError("could not write complete private identity output")
            offset += written
        os.fchmod(staging_fd, 0o600)
        os.fsync(staging_fd)
        sealed = os.fstat(staging_fd)
        if sealed.st_size != len(payload) or sealed.st_nlink != 1:
            raise ProvisionError("private identity staging file changed before publication")

        _require_descriptor_payload(
            staging_fd,
            payload,
            "private identity staging payload changed before publication",
        )
        sealed_authority = _SealedStaging(sealed, staging_fd, payload)
        _secure_replace_beneath(
            checkout_fd,
            temporary_name,
            destination_relative,
            sealed_authority,
        )

        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)
        final = os.fstat(final_fd)
        if (
            not stat.S_ISREG(final.st_mode)
            or final.st_uid != os.geteuid()
            or final.st_nlink != 1
            or final.st_size != len(payload)
            or final.st_dev != sealed.st_dev
            or final.st_ino != sealed.st_ino
        ):
            raise ProvisionError("published private identity output is not the sealed staging inode")
        try:
            _require_descriptor_payload(
                final_fd,
                payload,
                "published private identity payload failed post-publication authority",
            )
            os.fchmod(final_fd, 0o600)
            os.fsync(final_fd)
            _require_descriptor_payload(
                final_fd,
                payload,
                "published private identity payload changed before durable success",
            )
        except Exception:
            raise
        os.fsync(checkout_fd)
        try:
            _require_final_relative_name_binding(
                checkout_fd,
                destination_relative,
                sealed,
                payload,
            )
        except Exception:
            raise
    except Exception:
        if staging_fd >= 0:
            _sanitize_held_private_descriptor(staging_fd)
        raise
    finally:
        if final_fd >= 0:
            os.close(final_fd)
        if staging_fd >= 0:
            os.close(staging_fd)


def _decode_input() -> tuple[str, str]:
    payload = sys.stdin.buffer.read()
    parts = payload.split(b"\0")
    if len(parts) != 2 or not parts[0] or not parts[1]:
        raise ProvisionError("expected exactly two non-empty base64 credential fields on stdin")

    values: list[str] = []
    for encoded in parts:
        try:
            text = encoded.decode("ascii")
            raw = base64.b64decode(text, validate=True)
            if not raw or base64.b64encode(raw).decode("ascii") != text:
                raise ValueError("non-canonical base64")
        except Exception as exc:
            raise ProvisionError("credential input is not canonical base64 text") from exc
        values.append(text)
    return values[0], values[1]


def provision(checkout_fd: int, checkout_root: Path, app_key_b64: str, app_secret_b64: str) -> None:
    podspec = b"""Pod::Spec.new do |s|\n  s.name = 'NembraTuyaPrivateConfig'\n  s.version = '1.0.0'\n  s.summary = 'Local-only Nembra Capture Tuya app identity.'\n  s.description = 'Generated private field-build configuration. Never commit this pod.'\n  s.homepage = 'https://localhost.invalid/nembra-private-config'\n  s.license = { :type => 'Private' }\n  s.author = { 'Nembra' => 'local-only' }\n  s.source = { :git => 'https://localhost.invalid/nembra-private-config.git', :tag => s.version.to_s }\n  s.platform = :ios, '17.0'\n  s.swift_version = '6.0'\n  s.source_files = 'Sources/NembraTuyaPrivateConfig/**/*.swift'\nend\n"""
    swift = f"""import Foundation

public enum NembraTuyaPrivateIdentity {{
    private static let encodedAppKey = \"{app_key_b64}\"
    private static let encodedAppSecret = \"{app_secret_b64}\"

    public static var appKey: String {{ decode(encodedAppKey) }}
    public static var appSecret: String {{ decode(encodedAppSecret) }}

    private static func decode(_ value: String) -> String {{
        guard let data = Data(base64Encoded: value),
              let decoded = String(data: data, encoding: .utf8) else {{
            preconditionFailure(\"Invalid local Tuya identity encoding\")
        }}
        return decoded
    }}
}}
""".encode("utf-8")

    local_secrets_fd = runtime_fd = sources_fd = module_fd = -1
    recovered_stage: _RecoveredPrivateStage | None = None
    try:
        _require_checkout_path_identity(checkout_fd, checkout_root)
        recovered_stage = _recover_private_stage_residue(checkout_fd)
        _require_checkout_path_identity(checkout_fd, checkout_root)
        local_secrets_fd = _ensure_private_directory(checkout_fd, "LocalSecrets")
        runtime_fd = _ensure_private_directory(local_secrets_fd, "TuyaRuntime")
        sources_fd = _ensure_private_directory(runtime_fd, "Sources")
        module_fd = _ensure_private_directory(sources_fd, "NembraTuyaPrivateConfig")

        podspec_relative = "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"
        identity_relative = (
            "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/"
            "NembraTuyaPrivateIdentity.swift"
        )

        _require_private_chain(checkout_fd, local_secrets_fd, runtime_fd, sources_fd, module_fd)
        _write_staged(
            checkout_fd,
            runtime_fd,
            "NembraTuyaPrivateConfig.podspec",
            podspec_relative,
            podspec,
            recovered_stage=recovered_stage,
        )
        _require_checkout_path_identity(checkout_fd, checkout_root)
        _require_private_chain(checkout_fd, local_secrets_fd, runtime_fd, sources_fd, module_fd)

        _write_staged(
            checkout_fd,
            module_fd,
            "NembraTuyaPrivateIdentity.swift",
            identity_relative,
            swift,
        )
        _require_checkout_path_identity(checkout_fd, checkout_root)
        _require_private_chain(checkout_fd, local_secrets_fd, runtime_fd, sources_fd, module_fd)

        for descriptor in (module_fd, sources_fd, runtime_fd, local_secrets_fd, checkout_fd):
            os.fsync(descriptor)
    finally:
        if recovered_stage is not None:
            recovered_stage.close()
        for descriptor in (module_fd, sources_fd, runtime_fd, local_secrets_fd):
            if descriptor >= 0:
                os.close(descriptor)


def _self_test() -> None:
    encoded_key = base64.b64encode(b"dummy-key").decode("ascii")
    encoded_secret = base64.b64encode(b"dummy-secret").decode("ascii")
    with tempfile.TemporaryDirectory(prefix="nembra-tuya-writer-") as temporary:
        root = Path(os.path.realpath(temporary))
        checkout = root / "repo"
        checkout.mkdir()
        checkout_fd = os.open(checkout, _directory_flags())
        try:
            provision(checkout_fd, checkout, encoded_key, encoded_secret)
            provision(checkout_fd, checkout, encoded_key, encoded_secret)
        finally:
            os.close(checkout_fd)

        runtime = checkout / "LocalSecrets/TuyaRuntime"
        podspec = runtime / "NembraTuyaPrivateConfig.podspec"
        identity = runtime / "Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift"
        if not podspec.is_file() or not identity.is_file():
            raise ProvisionError("self-test did not create both private identity outputs")
        if stat.S_IMODE(podspec.stat().st_mode) != 0o600 or stat.S_IMODE(identity.stat().st_mode) != 0o600:
            raise ProvisionError("self-test private outputs are not mode 0600")

        outside = root / "outside"
        outside.mkdir()
        escape_checkout = root / "escape-repo"
        escape_checkout.mkdir()
        (escape_checkout / "LocalSecrets").symlink_to(outside, target_is_directory=True)
        escape_fd = os.open(escape_checkout, _directory_flags())
        try:
            try:
                provision(escape_fd, escape_checkout, encoded_key, encoded_secret)
            except (ProvisionError, OSError):
                pass
            else:
                raise ProvisionError("self-test followed a symlinked LocalSecrets directory")
        finally:
            os.close(escape_fd)
        if any(outside.iterdir()):
            raise ProvisionError("self-test wrote private material through a symlink")

        admitted = root / "admitted-repo"
        admitted.mkdir()
        admitted_fd = os.open(admitted, _directory_flags())
        original = root / "admitted-repo-original"
        try:
            admitted.rename(original)
            admitted.mkdir()
            try:
                provision(admitted_fd, admitted, encoded_key, encoded_secret)
            except ProvisionError:
                pass
            else:
                raise ProvisionError("self-test accepted a replaced checkout pathname")
            if (admitted / "LocalSecrets").exists():
                raise ProvisionError("self-test redirected private output into a replacement checkout")
        finally:
            os.close(admitted_fd)


def main() -> int:
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
            _self_test()
            return 0
        if len(sys.argv) != 3:
            raise ProvisionError(
                "usage: provision_capture_tuya_identity_writer.py <inherited-checkout-fd> <canonical-checkout-root>"
            )
        checkout_fd = _duplicate_inherited_checkout(sys.argv[1])
        try:
            app_key_b64, app_secret_b64 = _decode_input()
            provision(checkout_fd, Path(sys.argv[2]), app_key_b64, app_secret_b64)
        finally:
            os.close(checkout_fd)
        return 0
    except (ProvisionError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
