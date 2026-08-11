#!/usr/bin/env python3
"""Regression coverage for the private-only dependency-resolution guard adapter."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[3]
ADAPTER_PATH = ROOT / "Scripts/capture_tuya_private_dependency_resolution_guard.py"


def load_adapter():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_dependency_resolution_guard_adapter_test",
        ADAPTER_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("dependency-resolution guard adapter import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class _PrivateInputs:
    def __init__(
        self,
        *,
        lockfile: Path,
        security_podspec: Path,
        security_build: Path,
        identity_podspec: Path,
        identity_sources: Path,
    ) -> None:
        self.lockfile = lockfile
        self.security_podspec = security_podspec
        self.security_build = security_build
        self.identity_podspec = identity_podspec
        self.identity_sources = identity_sources


class _CompatibleGuard:
    PrivateInputs = _PrivateInputs
    BuildGuardError = RuntimeError
    last_call = None

    @staticmethod
    def _lexical_absolute(path: Path) -> Path:
        return path.absolute()

    @staticmethod
    def _require_real_checkout_ancestry(path: Path, root: Path, *, label: str) -> Path:
        if path != root and root not in path.parents:
            raise RuntimeError(f"{label} escaped fixture root")
        return path

    @staticmethod
    def run_guarded_build(
        inputs,
        command,
        *,
        backend_factory=None,
        popen_factory=None,
        poll_interval: float = 0.10,
    ) -> int:
        _CompatibleGuard.last_call = (inputs, list(command))
        return 23


class _DriftedGuard(_CompatibleGuard):
    @staticmethod
    def run_guarded_build(
        inputs,
        command,
        *,
        backend_factory=None,
        popen_factory=None,
        poll_interval: float = 0.10,
        require_accepted_tracked_source: bool = False,
    ) -> int:
        raise AssertionError("drifted guard must be rejected before invocation")


class DependencyResolutionGuardAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        _CompatibleGuard.last_call = None

    def _fixture_arguments(self, root: Path) -> list[str]:
        lockfile = root / "Podfile"
        security_podspec = root / "LocalSecrets/TuyaSDK/TuyaSmartLifeSDK.podspec"
        security_build = root / "LocalSecrets/TuyaSDK/Build"
        identity_podspec = root / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"
        identity_sources = root / "LocalSecrets/TuyaRuntime/Sources"

        lockfile.write_text("# fixture\n", encoding="utf-8")
        security_podspec.parent.mkdir(parents=True)
        security_podspec.write_text("# fixture\n", encoding="utf-8")
        security_build.mkdir(parents=True)
        identity_podspec.parent.mkdir(parents=True, exist_ok=True)
        identity_podspec.write_text("# fixture\n", encoding="utf-8")
        identity_sources.mkdir(parents=True)

        return [
            "--lockfile",
            str(lockfile),
            "--security-podspec",
            str(security_podspec),
            "--security-build",
            str(security_build),
            "--identity-podspec",
            str(identity_podspec),
            "--identity-sources",
            str(identity_sources),
            "--",
            "/usr/bin/true",
        ]

    def test_adapter_invokes_current_canonical_private_only_signature(self) -> None:
        adapter = load_adapter()
        with tempfile.TemporaryDirectory(prefix="nembra-private-resolution-adapter-") as temporary:
            root = Path(temporary)
            arguments = self._fixture_arguments(root)
            with mock.patch.object(adapter, "_load_guard", return_value=_CompatibleGuard):
                result = adapter.main(arguments)

        self.assertEqual(result, 23)
        self.assertIsNotNone(_CompatibleGuard.last_call)
        inputs, command = _CompatibleGuard.last_call
        self.assertEqual(command, ["/usr/bin/true"])
        self.assertEqual(inputs.lockfile.name, "Podfile")

    def test_adapter_fails_closed_when_canonical_guard_signature_drifts(self) -> None:
        adapter = load_adapter()
        with tempfile.TemporaryDirectory(prefix="nembra-private-resolution-adapter-drift-") as temporary:
            root = Path(temporary)
            arguments = self._fixture_arguments(root)
            with mock.patch.object(adapter, "_load_guard", return_value=_DriftedGuard):
                result = adapter.main(arguments)

        self.assertEqual(result, 74)
        self.assertIsNone(_CompatibleGuard.last_call)


if __name__ == "__main__":
    unittest.main(verbosity=2)
