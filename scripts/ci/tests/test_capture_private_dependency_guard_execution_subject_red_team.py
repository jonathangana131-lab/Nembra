#!/usr/bin/env python3
"""Expected-red: dependency-resolution adapter must not execute mutable sibling guard bytes.

Validation only. The witness copies the exact production adapter into an isolated
fixture, replaces only its dynamically loaded sibling guard with attacker bytes,
and requires the adapter to fail closed before any child command can execute.
No credentials, CocoaPods, Xcode, Bluetooth, device, or physical action occurs.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
ADAPTER = ROOT / "Scripts" / "capture_tuya_private_dependency_resolution_guard.py"
CANONICAL_GUARD = ROOT / "Scripts" / "capture_tuya_private_input_build_guard.py"


ATTACKER_GUARD = r'''from pathlib import Path
import subprocess

class BuildGuardError(RuntimeError):
    pass

class PrivateInputs:
    def __init__(self, *, lockfile: Path, security_podspec: Path, security_build: Path,
                 identity_podspec: Path, identity_sources: Path) -> None:
        self.lockfile = lockfile
        self.security_podspec = security_podspec
        self.security_build = security_build
        self.identity_podspec = identity_podspec
        self.identity_sources = identity_sources

def run_guarded_build(inputs, command, *, backend_factory=None, popen_factory=None,
                      poll_interval: float = 0.10) -> int:
    # Deliberately ignore every custody input/backend and execute the child.
    return subprocess.run(list(command), check=False).returncode
'''


def load_fixture_adapter(path: Path):
    spec = importlib.util.spec_from_file_location(
        "nembra_private_dependency_guard_execution_subject_fixture",
        path,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("fixture adapter import unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(spec.name, None)
        raise
    return module


class PrivateDependencyGuardExecutionSubjectRedTeamTests(unittest.TestCase):
    def test_mutable_regular_sibling_guard_cannot_authorize_child_execution(self) -> None:
        source = ADAPTER.read_text(encoding="utf-8")
        self.assertIn(
            'Path(__file__).with_name("capture_tuya_private_input_build_guard.py")',
            source,
            "witness requires the current dynamic sibling-loader topology",
        )
        self.assertIn("spec.loader.exec_module(module)", source)

        with tempfile.TemporaryDirectory(prefix="nembra-private-guard-exec-") as temporary:
            fixture_root = Path(temporary)
            scripts = fixture_root / "Scripts"
            scripts.mkdir()
            adapter_path = scripts / ADAPTER.name
            guard_path = scripts / CANONICAL_GUARD.name
            shutil.copy2(ADAPTER, adapter_path)
            shutil.copy2(CANONICAL_GUARD, guard_path)
            accepted_guard_bytes = guard_path.read_bytes()

            # Same-UID worktree attacker replaces the tracked regular-file subject
            # before the adapter's first load. Preserve a normal regular-file shape;
            # the production loader checks only file + non-symlink before execution.
            guard_path.write_text(ATTACKER_GUARD, encoding="utf-8")
            guard_path.chmod(0o644)
            metadata = guard_path.lstat()
            self.assertTrue(stat.S_ISREG(metadata.st_mode))
            self.assertFalse(guard_path.is_symlink())
            self.assertNotEqual(guard_path.read_bytes(), accepted_guard_bytes)

            checkout = fixture_root / "repo"
            podfile = checkout / "Podfile"
            sdk = checkout / "LocalSecrets" / "TuyaSDK"
            security_podspec = sdk / "ThingSmartCryption.podspec"
            security_build = sdk / "Build"
            runtime = checkout / "LocalSecrets" / "TuyaRuntime"
            identity_podspec = runtime / "NembraTuyaPrivateConfig.podspec"
            identity_sources = runtime / "Sources" / "NembraTuyaPrivateConfig"
            sentinel = checkout / "ATTACKER_CHILD_EXECUTED"

            security_build.mkdir(parents=True)
            identity_sources.mkdir(parents=True)
            podfile.write_text("# fixture\n", encoding="utf-8")
            security_podspec.write_text("# fixture\n", encoding="utf-8")
            identity_podspec.write_text("# fixture\n", encoding="utf-8")

            adapter = load_fixture_adapter(adapter_path)
            arguments = [
                "--lockfile", str(podfile),
                "--security-podspec", str(security_podspec),
                "--security-build", str(security_build),
                "--identity-podspec", str(identity_podspec),
                "--identity-sources", str(identity_sources),
                "--",
                "/usr/bin/python3",
                "-c",
                f"from pathlib import Path; Path({str(sentinel)!r}).write_text('executed')",
            ]
            result = adapter.main(arguments)

            print(f"NEMBRA_PRIVATE_GUARD_EXEC_ATTACK_RESULT={result}")
            print(f"NEMBRA_PRIVATE_GUARD_EXEC_SENTINEL={int(sentinel.exists())}")

            self.assertFalse(
                sentinel.exists(),
                "EXPECTED RED: exact production adapter executed attacker-supplied sibling guard bytes, which bypassed vnode custody and authorized the child command. Bind/capture the canonical guard execution subject to accepted bytes before exec_module().",
            )
            self.assertNotEqual(
                result,
                0,
                "dependency-resolution authority must fail closed when canonical guard bytes are not accepted",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
