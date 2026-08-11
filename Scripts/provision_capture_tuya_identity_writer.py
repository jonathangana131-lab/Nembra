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


def provision(checkout_root: Path, app_key_b64: str, app_secret_b64: str) -> None:
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
        checkout_fd = _open_absolute_directory(checkout_root)
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
        provision(checkout, encoded_key, encoded_secret)
        provision(checkout, encoded_key, encoded_secret)

        runtime = checkout / "LocalSecrets/TuyaRuntime"
        podspec = runtime / "NembraTuyaPrivateConfig.podspec"
        identity = runtime / "Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift"
        if not podspec.is_file() or not identity.is_file():
            raise ProvisionError("self-test did not create both private identity outputs")
        if stat.S_IMODE(podspec.stat().st_mode) != 0o600 or stat.S_IMODE(identity.stat().st_mode) != 0o600:
            raise ProvisionError("self-test private outputs are not mode 0600")

        outside = Path(temporary) / "outside"
        outside.mkdir()
        escape_checkout = Path(temporary) / "escape-repo"
        escape_checkout.mkdir()
        (escape_checkout / "LocalSecrets").symlink_to(outside, target_is_directory=True)
        try:
            provision(escape_checkout, encoded_key, encoded_secret)
        except (ProvisionError, OSError):
            pass
        else:
            raise ProvisionError("self-test followed a symlinked LocalSecrets directory")
        if any(outside.iterdir()):
            raise ProvisionError("self-test wrote private material through a symlink")


def main() -> int:
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
            _self_test()
            return 0
        if len(sys.argv) != 2:
            raise ProvisionError("usage: provision_capture_tuya_identity_writer.py <absolute-checkout-root>")
        app_key_b64, app_secret_b64 = _decode_input()
        provision(Path(sys.argv[1]), app_key_b64, app_secret_b64)
        return 0
    except (ProvisionError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
