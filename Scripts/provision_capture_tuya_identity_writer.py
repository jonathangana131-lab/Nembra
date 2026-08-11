#!/usr/bin/env python3
"""Descriptor-bound writer for Nembra's local-only Tuya app identity.

The shell wrapper owns privileged startup, hidden credential input, and the fixed
checkout root. This helper owns filesystem publication: every private directory
is opened relative to an already-open directory descriptor with O_NOFOLLOW,
and every output is staged with O_EXCL then atomically replaced relative to the
same pinned parent descriptor. Credential material is read only from stdin.
"""

from __future__ import annotations

import base64
import os
import secrets
import stat
import sys
import tempfile
from pathlib import Path


class ProvisionError(RuntimeError):
    pass


def _directory_flags() -> int:
    required = ("O_CLOEXEC", "O_DIRECTORY", "O_NOFOLLOW")
    if any(not hasattr(os, name) for name in required):
        raise ProvisionError("platform cannot enforce descriptor-bound no-follow directory custody")
    return os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW


def _file_flags() -> int:
    required = ("O_CLOEXEC", "O_NOFOLLOW")
    if any(not hasattr(os, name) for name in required):
        raise ProvisionError("platform cannot enforce descriptor-bound no-follow file custody")
    return os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW


def _open_absolute_directory(path: Path, expected_identity: tuple[int, int]) -> int:
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

        metadata = os.fstat(descriptor)
        if (metadata.st_dev, metadata.st_ino) != expected_identity:
            raise ProvisionError("checkout root identity changed after pre-credential admission")
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.geteuid():
            raise ProvisionError("checkout root is not one directory owned by the current user")
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


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


def _write_staged(parent_fd: int, final_name: str, payload: bytes) -> None:
    _validate_existing_output(parent_fd, final_name)
    temporary_name = f".{final_name}.nembra-{os.getpid()}-{secrets.token_hex(12)}"
    descriptor = -1
    try:
        descriptor = os.open(temporary_name, _file_flags(), 0o600, dir_fd=parent_fd)
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1
        ):
            raise ProvisionError("new private identity staging file failed ownership custody")

        view = memoryview(payload)
        offset = 0
        while offset < len(view):
            written = os.write(descriptor, view[offset:])
            if written <= 0:
                raise ProvisionError("could not write complete private identity output")
            offset += written
        os.fchmod(descriptor, 0o600)
        os.fsync(descriptor)
        sealed = os.fstat(descriptor)
        if sealed.st_size != len(payload) or sealed.st_nlink != 1:
            raise ProvisionError("private identity staging file changed before publication")
        os.close(descriptor)
        descriptor = -1

        # Both names are resolved relative to the already-open parent directory.
        # A pathname swap outside this descriptor cannot redirect publication.
        os.replace(
            temporary_name,
            final_name,
            src_dir_fd=parent_fd,
            dst_dir_fd=parent_fd,
        )

        final_descriptor = os.open(
            final_name,
            os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
            dir_fd=parent_fd,
        )
        try:
            final = os.fstat(final_descriptor)
            if (
                not stat.S_ISREG(final.st_mode)
                or final.st_uid != os.geteuid()
                or final.st_nlink != 1
                or final.st_size != len(payload)
            ):
                raise ProvisionError("published private identity output failed final custody")
            os.fchmod(final_descriptor, 0o600)
            os.fsync(final_descriptor)
        finally:
            os.close(final_descriptor)
        os.fsync(parent_fd)
    except Exception:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary_name, dir_fd=parent_fd)
        except FileNotFoundError:
            pass
        except OSError:
            pass
        raise


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


def provision(
    checkout_root: Path,
    expected_root_identity: tuple[int, int],
    app_key_b64: str,
    app_secret_b64: str,
) -> None:
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

    checkout_fd = local_secrets_fd = runtime_fd = sources_fd = module_fd = -1
    try:
        checkout_fd = _open_absolute_directory(checkout_root, expected_root_identity)
        local_secrets_fd = _ensure_private_directory(checkout_fd, "LocalSecrets")
        runtime_fd = _ensure_private_directory(local_secrets_fd, "TuyaRuntime")
        sources_fd = _ensure_private_directory(runtime_fd, "Sources")
        module_fd = _ensure_private_directory(sources_fd, "NembraTuyaPrivateConfig")

        _write_staged(runtime_fd, "NembraTuyaPrivateConfig.podspec", podspec)
        _write_staged(module_fd, "NembraTuyaPrivateIdentity.swift", swift)
        for descriptor in (module_fd, sources_fd, runtime_fd, local_secrets_fd, checkout_fd):
            os.fsync(descriptor)
    finally:
        for descriptor in (module_fd, sources_fd, runtime_fd, local_secrets_fd, checkout_fd):
            if descriptor >= 0:
                os.close(descriptor)


def _self_test() -> None:
    encoded_key = base64.b64encode(b"dummy-key").decode("ascii")
    encoded_secret = base64.b64encode(b"dummy-secret").decode("ascii")
    with tempfile.TemporaryDirectory(prefix="nembra-tuya-writer-") as temporary:
        checkout = Path(temporary) / "repo"
        checkout.mkdir()
        checkout_metadata = checkout.stat()
        identity = (checkout_metadata.st_dev, checkout_metadata.st_ino)
        provision(checkout, identity, encoded_key, encoded_secret)
        provision(checkout, identity, encoded_key, encoded_secret)

        runtime = checkout / "LocalSecrets/TuyaRuntime"
        podspec = runtime / "NembraTuyaPrivateConfig.podspec"
        identity_file = runtime / "Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift"
        if not podspec.is_file() or not identity_file.is_file():
            raise ProvisionError("self-test did not create both private identity outputs")
        if stat.S_IMODE(podspec.stat().st_mode) != 0o600 or stat.S_IMODE(identity_file.stat().st_mode) != 0o600:
            raise ProvisionError("self-test private outputs are not mode 0600")

        outside = Path(temporary) / "outside"
        outside.mkdir()
        escape_checkout = Path(temporary) / "escape-repo"
        escape_checkout.mkdir()
        escape_metadata = escape_checkout.stat()
        (escape_checkout / "LocalSecrets").symlink_to(outside, target_is_directory=True)
        try:
            provision(
                escape_checkout,
                (escape_metadata.st_dev, escape_metadata.st_ino),
                encoded_key,
                encoded_secret,
            )
        except (ProvisionError, OSError):
            pass
        else:
            raise ProvisionError("self-test followed a symlinked LocalSecrets directory")
        if any(outside.iterdir()):
            raise ProvisionError("self-test wrote private material through a symlink")

        admitted_checkout = Path(temporary) / "admitted-repo"
        admitted_checkout.mkdir()
        admitted_metadata = admitted_checkout.stat()
        admitted_identity = (admitted_metadata.st_dev, admitted_metadata.st_ino)
        admitted_original = Path(temporary) / "admitted-original"
        admitted_checkout.rename(admitted_original)
        admitted_checkout.mkdir()
        try:
            provision(admitted_checkout, admitted_identity, encoded_key, encoded_secret)
        except ProvisionError:
            pass
        else:
            raise ProvisionError("self-test accepted a replacement checkout root")
        if (admitted_checkout / "LocalSecrets").exists():
            raise ProvisionError("self-test published private material into a replacement checkout root")


def _parse_identity(raw_device: str, raw_inode: str) -> tuple[int, int]:
    try:
        device = int(raw_device, 10)
        inode = int(raw_inode, 10)
    except ValueError as exc:
        raise ProvisionError("pre-credential checkout root identity is malformed") from exc
    if device < 0 or inode <= 0:
        raise ProvisionError("pre-credential checkout root identity is invalid")
    return device, inode


def main() -> int:
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
            _self_test()
            return 0
        if len(sys.argv) != 4:
            raise ProvisionError(
                "usage: provision_capture_tuya_identity_writer.py <absolute-checkout-root> <root-device> <root-inode>"
            )
        app_key_b64, app_secret_b64 = _decode_input()
        provision(
            Path(sys.argv[1]),
            _parse_identity(sys.argv[2], sys.argv[3]),
            app_key_b64,
            app_secret_b64,
        )
        return 0
    except (ProvisionError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
