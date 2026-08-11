#!/usr/bin/env python3
"""Descriptor-bound writer for Nembra's local-only Tuya app identity.

Credential material arrives only on stdin. The destination pathname is non-secret.
The writer creates a fresh runtime directory relative to descriptor-pinned parents,
refuses symlink components/existing destinations, and never overwrites prior identity.
"""

from __future__ import annotations

import base64
import errno
import os
import stat
import sys
import tempfile
from pathlib import Path


class ProvisionError(RuntimeError):
    pass


def _flags(*, directory: bool = False) -> int:
    required = ("O_NOFOLLOW", "O_CLOEXEC")
    if any(not hasattr(os, name) for name in required):
        raise ProvisionError("platform cannot enforce no-follow private identity custody")
    value = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC
    if directory:
        if not hasattr(os, "O_DIRECTORY"):
            raise ProvisionError("platform cannot enforce directory-only private identity custody")
        value |= os.O_DIRECTORY
    return value


def _open_directory_component(parent_fd: int, name: str, *, create: bool) -> int:
    if not name or name in (".", "..") or "/" in name:
        raise ProvisionError("private identity destination contains an invalid path component")
    if create:
        try:
            os.mkdir(name, 0o700, dir_fd=parent_fd)
        except FileExistsError:
            pass
        except OSError as exc:
            raise ProvisionError(f"could not create private identity directory component {name!r}") from exc
    try:
        descriptor = os.open(name, _flags(directory=True), dir_fd=parent_fd)
    except OSError as exc:
        raise ProvisionError(
            f"private identity destination component is missing, not a directory, or is a symlink: {name!r}"
        ) from exc
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode):
        os.close(descriptor)
        raise ProvisionError("private identity destination component is not a directory")
    return descriptor


def _open_parent(destination: Path) -> tuple[int, str]:
    raw = os.fspath(destination)
    if not destination.is_absolute() or os.path.normpath(raw) != raw:
        raise ProvisionError("private identity destination must be one canonical absolute path")
    parts = destination.parts
    if len(parts) < 2 or parts[0] != os.sep:
        raise ProvisionError("private identity destination must have one named final component")

    descriptor = os.open(os.sep, _flags(directory=True))
    try:
        for component in parts[1:-1]:
            next_descriptor = _open_directory_component(descriptor, component, create=True)
            os.close(descriptor)
            descriptor = next_descriptor
        return descriptor, parts[-1]
    except Exception:
        os.close(descriptor)
        raise


def _mkdir_fresh(parent_fd: int, name: str) -> int:
    try:
        os.mkdir(name, 0o700, dir_fd=parent_fd)
    except FileExistsError as exc:
        raise ProvisionError(
            "Refusing to reuse or follow an existing Tuya runtime destination; remove the old local runtime deliberately before reprovisioning."
        ) from exc
    except OSError as exc:
        raise ProvisionError("could not create fresh private Tuya runtime destination") from exc
    descriptor = _open_directory_component(parent_fd, name, create=False)
    os.fchmod(descriptor, 0o700)
    return descriptor


def _mkdir_child(parent_fd: int, name: str) -> int:
    try:
        os.mkdir(name, 0o700, dir_fd=parent_fd)
    except OSError as exc:
        raise ProvisionError(f"could not create private identity child directory {name!r}") from exc
    descriptor = _open_directory_component(parent_fd, name, create=False)
    os.fchmod(descriptor, 0o700)
    return descriptor


def _write_fresh_file(parent_fd: int, name: str, payload: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        descriptor = os.open(name, flags, 0o600, dir_fd=parent_fd)
    except OSError as exc:
        raise ProvisionError(f"refusing to replace private identity file {name!r}") from exc
    try:
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1
        ):
            raise ProvisionError("new private identity output failed regular-file ownership custody")
        view = memoryview(payload)
        offset = 0
        while offset < len(view):
            written = os.write(descriptor, view[offset:])
            if written <= 0:
                raise ProvisionError("could not write complete private identity output")
            offset += written
        os.fchmod(descriptor, 0o600)
        os.fsync(descriptor)
        final = os.fstat(descriptor)
        if final.st_size != len(payload) or final.st_nlink != 1:
            raise ProvisionError("private identity output changed while being sealed")
    finally:
        os.close(descriptor)


def _decode_stdin() -> tuple[str, str]:
    payload = sys.stdin.buffer.read()
    parts = payload.split(b"\0")
    if len(parts) != 2 or not parts[0] or not parts[1]:
        raise ProvisionError("expected exactly two non-empty base64 credential fields on stdin")
    values: list[str] = []
    for value in parts:
        try:
            text = value.decode("ascii")
            base64.b64decode(text, validate=True)
        except Exception as exc:
            raise ProvisionError("credential input is not canonical base64 text") from exc
        values.append(text)
    return values[0], values[1]


def provision(destination: Path, app_key_b64: str, app_secret_b64: str) -> None:
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

    parent_fd, final_name = _open_parent(destination)
    runtime_fd = sources_fd = module_fd = -1
    try:
        runtime_fd = _mkdir_fresh(parent_fd, final_name)
        sources_fd = _mkdir_child(runtime_fd, "Sources")
        module_fd = _mkdir_child(sources_fd, "NembraTuyaPrivateConfig")
        _write_fresh_file(runtime_fd, "NembraTuyaPrivateConfig.podspec", podspec)
        _write_fresh_file(module_fd, "NembraTuyaPrivateIdentity.swift", swift)
        os.fsync(module_fd)
        os.fsync(sources_fd)
        os.fsync(runtime_fd)
        os.fsync(parent_fd)
    finally:
        for descriptor in (module_fd, sources_fd, runtime_fd, parent_fd):
            if descriptor >= 0:
                os.close(descriptor)


def _self_test() -> None:
    encoded_key = base64.b64encode(b"dummy-key").decode("ascii")
    encoded_secret = base64.b64encode(b"dummy-secret").decode("ascii")
    with tempfile.TemporaryDirectory(prefix="nembra-tuya-provisioner-") as temporary:
        root = Path(temporary)
        destination = root / "fresh" / "runtime"
        provision(destination, encoded_key, encoded_secret)
        identity = destination / "Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift"
        podspec = destination / "NembraTuyaPrivateConfig.podspec"
        if not identity.is_file() or not podspec.is_file():
            raise ProvisionError("self-test did not create both private identity outputs")
        if stat.S_IMODE(identity.stat().st_mode) != 0o600 or stat.S_IMODE(podspec.stat().st_mode) != 0o600:
            raise ProvisionError("self-test private identity outputs are not mode 0600")
        try:
            provision(destination, encoded_key, encoded_secret)
        except ProvisionError:
            pass
        else:
            raise ProvisionError("self-test reused an existing private runtime destination")

        outside = root / "outside"
        outside.mkdir()
        symlink_destination = root / "runtime-link"
        symlink_destination.symlink_to(outside, target_is_directory=True)
        try:
            provision(symlink_destination, encoded_key, encoded_secret)
        except ProvisionError:
            pass
        else:
            raise ProvisionError("self-test followed an existing runtime symlink")
        if any(outside.iterdir()):
            raise ProvisionError("self-test wrote private material through a runtime symlink")

        parent_target = root / "parent-target"
        parent_target.mkdir()
        parent_link = root / "parent-link"
        parent_link.symlink_to(parent_target, target_is_directory=True)
        try:
            provision(parent_link / "runtime", encoded_key, encoded_secret)
        except ProvisionError:
            pass
        else:
            raise ProvisionError("self-test followed a symlinked destination parent")


def main() -> int:
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
            _self_test()
            return 0
        if len(sys.argv) != 2:
            raise ProvisionError("usage: provision_capture_tuya_identity_writer.py <absolute-runtime-directory>")
        app_key_b64, app_secret_b64 = _decode_stdin()
        provision(Path(sys.argv[1]), app_key_b64, app_secret_b64)
        return 0
    except (ProvisionError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
