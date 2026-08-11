#!/usr/bin/env python3
"""Expected-red regression for caller-selected Xcode environment authority."""
from __future__ import annotations

import ast
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
GUARD_PATH = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"


def load_guard():
    spec = importlib.util.spec_from_file_location(
        "nembra_field_xcode_environment_guard", GUARD_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("build guard import unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class StableInputs:
    def generation_snapshot(self):
        return ("stable",)


class NoopBackend:
    def register(self, descriptor: int) -> None:
        del descriptor

    def events(self, timeout: float):
        del timeout
        return ()

    def close(self) -> None:
        return None


class CaptureFieldXcodeEnvironmentAuthorityTests(unittest.TestCase):
    def test_guarded_build_process_must_own_a_closed_child_environment(self) -> None:
        source = GUARD_PATH.read_text(encoding="utf-8")
        tree = ast.parse(source)
        run_guarded_build = next(
            node
            for node in tree.body
            if isinstance(node, ast.FunctionDef) and node.name == "run_guarded_build"
        )
        popen_calls = [
            node
            for node in ast.walk(run_guarded_build)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "popen_factory"
        ]
        self.assertEqual(len(popen_calls), 1)
        environment_keywords = [
            keyword for keyword in popen_calls[0].keywords if keyword.arg == "env"
        ]
        self.assertEqual(
            len(environment_keywords),
            1,
            "guarded xcodebuild inherits caller environment instead of receiving a closed child environment",
        )
        rendered_environment = ast.unparse(environment_keywords[0].value)
        self.assertNotIn("os.environ", rendered_environment)
        self.assertNotIn("environ.copy", rendered_environment)

    def test_field_installer_uses_absolute_xcodebuild_but_environment_is_a_separate_boundary(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        self.assertIn("/usr/bin/xcodebuild", installer)
        self.assertIn("DEVELOPER_DIR", "DEVELOPER_DIR")

    @unittest.skipUnless(sys.platform == "darwin", "requires real macOS xcodebuild selection")
    def test_real_macos_caller_developer_dir_cannot_redirect_guarded_xcodebuild(self) -> None:
        guard = load_guard()
        baseline_environment = os.environ.copy()
        baseline_environment.pop("DEVELOPER_DIR", None)
        baseline = subprocess.run(
            ["/usr/bin/xcodebuild", "-version"],
            env=baseline_environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(baseline.returncode, 0, baseline.stderr)

        original_watch_paths = guard._watch_paths
        guard._watch_paths = lambda _inputs: ()
        try:
            with tempfile.TemporaryDirectory(prefix="nembra-xcode-env-authority-") as directory:
                alternate_developer_dir = Path(directory) / "AlternateDeveloper"
                alternate_developer_dir.mkdir()
                previous = os.environ.get("DEVELOPER_DIR")
                os.environ["DEVELOPER_DIR"] = str(alternate_developer_dir)
                try:
                    result = guard.run_guarded_build(
                        StableInputs(),
                        ["/usr/bin/xcodebuild", "-version"],
                        backend_factory=NoopBackend,
                        poll_interval=0.01,
                    )
                finally:
                    if previous is None:
                        os.environ.pop("DEVELOPER_DIR", None)
                    else:
                        os.environ["DEVELOPER_DIR"] = previous
        finally:
            guard._watch_paths = original_watch_paths

        self.assertEqual(
            result,
            0,
            "caller DEVELOPER_DIR reached the guarded xcodebuild process",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
