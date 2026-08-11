#!/usr/bin/env python3
"""Expected-red: private dependency custody code must itself have accepted execution authority.

The dependency-resolution adapter can only protect private inputs after its own accepted code and the
canonical build guard have been acquired. The reviewed parent still executes the adapter by mutable
checkout pathname, and the adapter imports its canonical guard from a mutable neighboring pathname.
A same-UID writer can therefore substitute the very code responsible for arming custody, execute it,
and restore accepted bytes before later endpoint cleanliness checks.

This diagnostic is intentionally exploit-positive: green means the current parent still admits the
execution-subject substitution class. It never reads credentials, invokes CocoaPods, builds, signs,
installs, launches, scans Bluetooth, touches Tuya hardware, or creates physical authority.
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[3]
BOOTSTRAP = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"
ADAPTER = ROOT / "Scripts/capture_tuya_private_dependency_resolution_guard.py"
CANONICAL_GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not import diagnostic subject: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateDependencyHelperExecutionSubjectRedTeamTests(unittest.TestCase):
    def test_parent_source_still_acquires_adapter_and_canonical_guard_by_mutable_path(self) -> None:
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
        adapter = ADAPTER.read_text(encoding="utf-8")

        self.assertIn(
            'PRIVATE_INPUT_RESOLUTION_GUARD="$SCRIPT_DIR/capture_tuya_private_dependency_resolution_guard.py"',
            bootstrap,
        )
        self.assertIn('[[ ! -f "$PRIVATE_INPUT_RESOLUTION_GUARD" || -L "$PRIVATE_INPUT_RESOLUTION_GUARD" ]]', bootstrap)
        self.assertGreaterEqual(
            bootstrap.count('/usr/bin/python3 -I "$PRIVATE_INPUT_RESOLUTION_GUARD"'),
            2,
            "both dependency resolution and provenance snapshot should expose the reviewed path acquisition",
        )
        self.assertNotIn("PRIVATE_INPUT_RESOLUTION_GUARD_SHA256", bootstrap)

        self.assertIn(
            'guard_path = Path(__file__).with_name("capture_tuya_private_input_build_guard.py")',
            adapter,
        )
        self.assertIn("importlib.util.spec_from_file_location(", adapter)
        self.assertIn("spec.loader.exec_module(module)", adapter)
        self.assertNotIn("CAPTURE_TUYA_PRIVATE_INPUT_BUILD_GUARD_SHA256", adapter)

    def test_transient_adapter_replacement_executes_and_restores_clean_final_bytes(self) -> None:
        """Model the bootstrap's shape-check -> pathname-exec -> later-clean-endpoint topology."""
        with tempfile.TemporaryDirectory(prefix="nembra-private-adapter-substitution-") as temporary:
            sandbox = Path(temporary)
            subject = sandbox / "capture_tuya_private_dependency_resolution_guard.py"
            marker = sandbox / "attacker-ran.txt"

            accepted = b"raise SystemExit(93)\n"
            subject.write_bytes(accepted)
            accepted_digest = sha256(accepted)

            before = subject.lstat()
            self.assertTrue(stat.S_ISREG(before.st_mode))
            self.assertFalse(subject.is_symlink())

            malicious = textwrap.dedent(
                f"""
                from pathlib import Path
                Path({str(marker)!r}).write_text("executed\\n", encoding="utf-8")
                raise SystemExit(0)
                """
            ).lstrip().encode("utf-8")
            replacement = sandbox / "replacement.py"
            replacement.write_bytes(malicious)
            os.replace(replacement, subject)

            completed = subprocess.run(
                [sys.executable, "-I", str(subject)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(marker.read_text(encoding="utf-8"), "executed\n")

            restored = sandbox / "restored.py"
            restored.write_bytes(accepted)
            os.replace(restored, subject)
            self.assertEqual(sha256(subject.read_bytes()), accepted_digest)
            self.assertTrue(stat.S_ISREG(subject.lstat().st_mode))
            self.assertFalse(subject.is_symlink())

    def test_adapter_executes_substituted_neighbor_guard_before_any_custody_can_exist(self) -> None:
        """Use the exact reviewed adapter bytes with an attacker-controlled same-name neighbor module."""
        with tempfile.TemporaryDirectory(prefix="nembra-private-guard-neighbor-") as temporary:
            sandbox = Path(temporary)
            checkout = sandbox / "repo"
            scripts = checkout / "Scripts"
            scripts.mkdir(parents=True)

            copied_adapter = scripts / ADAPTER.name
            shutil.copyfile(ADAPTER, copied_adapter)
            marker = sandbox / "malicious-guard-ran.txt"

            malicious_guard = scripts / CANONICAL_GUARD.name
            malicious_guard.write_text(
                textwrap.dedent(
                    """
                    from dataclasses import dataclass
                    from pathlib import Path
                    import os

                    @dataclass(frozen=True)
                    class PrivateInputs:
                        lockfile: Path
                        security_podspec: Path
                        security_build: Path
                        identity_podspec: Path
                        identity_sources: Path

                    def run_guarded_build(inputs, command, *, backend_factory=None):
                        Path(os.environ["NEMBRA_REDTEAM_MARKER"]).write_text(
                            "malicious canonical guard executed\\n",
                            encoding="utf-8",
                        )
                        return 0
                    """
                ).lstrip(),
                encoding="utf-8",
            )

            podfile = checkout / "Podfile"
            podfile.write_text("# fixture\n", encoding="utf-8")
            sdk = checkout / "LocalSecrets/TuyaSDK"
            security_build = sdk / "Build"
            security_build.mkdir(parents=True)
            security_podspec = sdk / "ThingSmartCryption.podspec"
            security_podspec.write_text("fixture\n", encoding="utf-8")
            runtime = checkout / "LocalSecrets/TuyaRuntime"
            identity_sources = runtime / "Sources/NembraTuyaPrivateConfig"
            identity_sources.mkdir(parents=True)
            identity_podspec = runtime / "NembraTuyaPrivateConfig.podspec"
            identity_podspec.write_text("fixture\n", encoding="utf-8")

            adapter = load_module(copied_adapter, "nembra_private_dependency_adapter_red_team_current")
            old_cwd = Path.cwd()
            previous_marker = os.environ.get("NEMBRA_REDTEAM_MARKER")
            os.environ["NEMBRA_REDTEAM_MARKER"] = str(marker)
            try:
                os.chdir(checkout)
                result = adapter.main(
                    [
                        "--lockfile",
                        str(podfile),
                        "--security-podspec",
                        str(security_podspec),
                        "--security-build",
                        str(security_build),
                        "--identity-podspec",
                        str(identity_podspec),
                        "--identity-sources",
                        str(identity_sources),
                        "--",
                        "/usr/bin/false",
                    ]
                )
            finally:
                os.chdir(old_cwd)
                if previous_marker is None:
                    os.environ.pop("NEMBRA_REDTEAM_MARKER", None)
                else:
                    os.environ["NEMBRA_REDTEAM_MARKER"] = previous_marker

            self.assertEqual(result, 0)
            self.assertEqual(
                marker.read_text(encoding="utf-8"),
                "malicious canonical guard executed\n",
                "reviewed adapter did not execute the substituted same-name canonical guard",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
