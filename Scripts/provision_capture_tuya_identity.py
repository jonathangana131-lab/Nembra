#!/usr/bin/env python3
"""Provision Nembra Capture's local-only Tuya app identity without exposing secrets.

The real AppKey/AppSecret are accepted only from hidden terminal prompts. They are
never accepted through argv or environment variables and are written only below
ignored LocalSecrets/TuyaRuntime with private permissions and no-overwrite
semantics.
"""

from __future__ import annotations

import getpass
import os
import shutil
import stat
import sys
import tempfile
from pathlib import Path

PODSPEC_NAME = "NembraTuyaPrivateConfig.podspec"
SOURCE_RELATIVE = Path("Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift")


def _swift_string_literal(value: str) -> str:
    if not value or len(value) > 512:
        raise ValueError("private Tuya identity values must contain 1...512 characters")
    if any(ord(ch) == 0 or ch in "\r\n" or (ord(ch) < 0x20 and ch != "\t") for ch in value):
        raise ValueError("private Tuya identity values contain unsupported control characters")
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t")
    return f'"{escaped}"'


def _write_exclusive(path: Path, payload: str) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        remaining = memoryview(payload.encode("utf-8"))
        while remaining:
            written = os.write(descriptor, remaining)
            if written <= 0:
                raise OSError("short private-config write")
            remaining = remaining[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _validate_or_create_local_secrets(repo_root: Path) -> Path:
    local_secrets = repo_root / "LocalSecrets"
    if local_secrets.exists() or local_secrets.is_symlink():
        metadata = local_secrets.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise RuntimeError("LocalSecrets must be a real directory, not a symlink or other object")
        if metadata.st_uid != os.getuid():
            raise RuntimeError("LocalSecrets must be owned by the current user")
        if stat.S_IMODE(metadata.st_mode) & 0o022:
            raise RuntimeError("LocalSecrets must not be group/world writable")
    else:
        local_secrets.mkdir(mode=0o700)
    return local_secrets


def _podspec_text() -> str:
    return """Pod::Spec.new do |s|
  s.name = 'NembraTuyaPrivateConfig'
  s.version = '1.0.0'
  s.summary = 'Local-only Nembra Capture Tuya app identity'
  s.description = 'Generated private field-build identity. Never publish or redistribute.'
  s.homepage = 'https://example.invalid/nembra-private-config'
  s.license = { :type => 'Proprietary', :text => 'Local private configuration; do not redistribute.' }
  s.author = { 'Nembra Local Build' => 'local-only@example.invalid' }
  # The Podfile consumes this pod only through :path. This fail-closed .invalid
  # source is metadata required by the podspec DSL and must never be fetched.
  s.source = { :git => 'https://example.invalid/NembraTuyaPrivateConfig.git', :tag => s.version.to_s }
  s.ios.deployment_target = '17.0'
  s.swift_version = '5.0'
  s.source_files = 'Sources/NembraTuyaPrivateConfig/**/*.swift'
end
"""


def provision(repo_root: Path, app_key: str, app_secret: str) -> Path:
    repo_root = repo_root.resolve(strict=True)
    local_secrets = _validate_or_create_local_secrets(repo_root)
    target = local_secrets / "TuyaRuntime"
    if target.exists() or target.is_symlink():
        raise RuntimeError(
            "LocalSecrets/TuyaRuntime already exists; refusing to overwrite private identity"
        )

    key_literal = _swift_string_literal(app_key)
    secret_literal = _swift_string_literal(app_secret)
    target.mkdir(mode=0o700)
    try:
        sources = target / "Sources"
        module = sources / "NembraTuyaPrivateConfig"
        sources.mkdir(mode=0o700)
        module.mkdir(mode=0o700)

        swift_source = (
            "public enum NembraTuyaPrivateIdentity {\n"
            f"    public static let appKey = {key_literal}\n"
            f"    public static let appSecret = {secret_literal}\n"
            "}\n"
        )
        _write_exclusive(target / PODSPEC_NAME, _podspec_text())
        _write_exclusive(target / SOURCE_RELATIVE, swift_source)

        for directory in (target, sources, module):
            os.chmod(directory, 0o700)
        directory_descriptor = os.open(target, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    except BaseException:
        shutil.rmtree(target, ignore_errors=True)
        raise
    return target


def _self_test() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        repo_root = Path(temporary)
        target = provision(repo_root, 'key"\\fixture', "secret-\tfixture")
        podspec = target / PODSPEC_NAME
        swift_source = target / SOURCE_RELATIVE

        assert stat.S_IMODE(target.stat().st_mode) == 0o700
        assert stat.S_IMODE(podspec.stat().st_mode) == 0o600
        assert stat.S_IMODE(swift_source.stat().st_mode) == 0o600
        generated = swift_source.read_text()
        assert 'key\\"\\\\fixture' in generated
        assert "secret-\\tfixture" in generated
        assert 'key"\\fixture' not in generated

        try:
            provision(repo_root, "replacement", "replacement")
        except RuntimeError:
            pass
        else:
            raise AssertionError("provisioner replaced an existing private identity")

        for invalid in ("", "bad\nvalue", "bad\rvalue", "bad\x00value"):
            try:
                _swift_string_literal(invalid)
            except ValueError:
                pass
            else:
                raise AssertionError(f"invalid private identity value was accepted: {invalid!r}")

    print("private Tuya identity provisioner self-test: PASS")


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        _self_test()
        return 0
    if sys.argv[1:]:
        print("Usage: provision_capture_tuya_identity.py [--self-test]", file=sys.stderr)
        return 2

    repo_root = Path(__file__).resolve().parents[1]
    try:
        app_key = getpass.getpass("Tuya AppKey (input hidden): ")
        app_secret = getpass.getpass("Tuya AppSecret (input hidden): ")
        provision(repo_root, app_key, app_secret)
    except (EOFError, KeyboardInterrupt, ValueError, RuntimeError, OSError) as error:
        print(f"ERROR: private Tuya identity provisioning failed: {error}", file=sys.stderr)
        return 3
    finally:
        if "app_key" in locals():
            app_key = ""
        if "app_secret" in locals():
            app_secret = ""

    print("Private Tuya app identity provisioned under ignored LocalSecrets/TuyaRuntime.")
    print("No AppKey/AppSecret value was written to argv, environment, Git, or stdout.")
    print("Next: run Scripts/bootstrap_capture_tuya_sdk.sh from this exact accepted Capture checkout.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
