#!/usr/bin/env python3
"""Portable regression tests for the local-only Tuya identity provisioner."""

from __future__ import annotations

import base64
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SOURCE = REPOSITORY_ROOT / "Scripts" / "provision_capture_tuya_identity.sh"
APP_KEY = "nembra-dummy-app-key"
APP_SECRET = "nembra-dummy-app-secret"


def copy_fixture(raw: str) -> tuple[Path, Path]:
    root = Path(raw) / "repo"
    scripts = root / "Scripts"
    scripts.mkdir(parents=True)
    target = scripts / SOURCE.name
    shutil.copy2(SOURCE, target)
    return root, target


def invoke(script: Path, *, extra_env: dict[str, str] | None = None, xtrace: bool = False) -> subprocess.CompletedProcess[bytes]:
    command = ["bash"]
    if xtrace:
        command.append("-x")
    command.append(str(script))
    environment = os.environ.copy()
    if extra_env:
        environment.update(extra_env)
    return subprocess.run(
        command,
        input=f"{APP_KEY}\n{APP_SECRET}\n".encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=environment,
        check=False,
    )


def assert_mode(path: Path, expected: int) -> None:
    actual = stat.S_IMODE(path.stat().st_mode)
    assert actual == expected, f"{path}: expected {oct(expected)}, got {oct(actual)}"


def test_fixed_checkout_owned_destination_and_trace_redaction() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root, script = copy_fixture(raw)
        redirected = Path(raw) / "caller-controlled-runtime"
        result = invoke(
            script,
            extra_env={"NEMBRA_TUYA_RUNTIME_DIR": str(redirected)},
            xtrace=True,
        )
        output = result.stdout.decode(errors="replace")
        assert result.returncode == 0, output
        assert APP_KEY not in output
        assert APP_SECRET not in output
        assert not redirected.exists(), "caller environment must not redirect credential output"

        runtime = root / "LocalSecrets" / "TuyaRuntime"
        podspec = runtime / "NembraTuyaPrivateConfig.podspec"
        identity = runtime / "Sources" / "NembraTuyaPrivateConfig" / "NembraTuyaPrivateIdentity.swift"
        assert podspec.is_file()
        assert identity.is_file()
        assert_mode(podspec, 0o600)
        assert_mode(identity, 0o600)
        generated = podspec.read_text() + identity.read_text()
        assert APP_KEY not in generated
        assert APP_SECRET not in generated
        assert base64.b64encode(APP_KEY.encode()).decode() in generated
        assert base64.b64encode(APP_SECRET.encode()).decode() in generated


def test_symlinked_local_secrets_fails_closed() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root, script = copy_fixture(raw)
        escape = Path(raw) / "escape"
        escape.mkdir()
        (root / "LocalSecrets").symlink_to(escape, target_is_directory=True)
        result = invoke(script)
        assert result.returncode != 0
        assert not (escape / "TuyaRuntime").exists(), "symlinked LocalSecrets must not receive private output"


def test_symlinked_output_fails_without_touching_target() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root, script = copy_fixture(raw)
        source_dir = root / "LocalSecrets" / "TuyaRuntime" / "Sources" / "NembraTuyaPrivateConfig"
        source_dir.mkdir(parents=True)
        sentinel = Path(raw) / "sentinel.txt"
        sentinel.write_text("unchanged")
        (source_dir / "NembraTuyaPrivateIdentity.swift").symlink_to(sentinel)
        result = invoke(script)
        assert result.returncode != 0
        assert sentinel.read_text() == "unchanged"


def test_regular_outputs_can_be_reprovisioned_safely() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root, script = copy_fixture(raw)
        first = invoke(script)
        assert first.returncode == 0, first.stdout.decode(errors="replace")
        second = invoke(script)
        assert second.returncode == 0, second.stdout.decode(errors="replace")
        runtime = root / "LocalSecrets" / "TuyaRuntime"
        assert_mode(runtime / "NembraTuyaPrivateConfig.podspec", 0o600)
        assert_mode(runtime / "Sources" / "NembraTuyaPrivateConfig" / "NembraTuyaPrivateIdentity.swift", 0o600)


def main() -> None:
    test_fixed_checkout_owned_destination_and_trace_redaction()
    test_symlinked_local_secrets_fails_closed()
    test_symlinked_output_fails_without_touching_target()
    test_regular_outputs_can_be_reprovisioned_safely()
    print("Tuya private identity provisioner custody: PASS")


if __name__ == "__main__":
    main()
