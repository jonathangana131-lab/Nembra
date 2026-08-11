#!/usr/bin/env python3
"""Expected-red contract for residual caller Xcode build-environment authority.

DEVELOPER_DIR has its own current diagnostic. This test owns the broader child
process boundary: xcodebuild must not inherit arbitrary caller build/toolchain
settings after that narrower fence is repaired.
"""
from __future__ import annotations

import ast
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
GUARD_PATH = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"


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
        self.assertEqual(len(popen_calls), 1, "expected one guarded compiler process admission")
        environment_keywords = [
            keyword for keyword in popen_calls[0].keywords if keyword.arg == "env"
        ]
        self.assertEqual(
            len(environment_keywords),
            1,
            "guarded xcodebuild inherits caller build/toolchain environment instead of receiving a closed child environment",
        )
        rendered_environment = ast.unparse(environment_keywords[0].value)
        self.assertNotIn("os.environ", rendered_environment)
        self.assertNotIn("environ.copy", rendered_environment)

    def test_narrow_developer_dir_fence_would_not_close_the_residual_boundary(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        guard = GUARD_PATH.read_text(encoding="utf-8")
        self.assertIn("/usr/bin/xcodebuild", installer)
        self.assertIn("popen_factory(list(command))", guard)
        self.assertNotIn("XCODE_XCCONFIG_FILE", guard)
        self.assertNotIn("TOOLCHAINS", guard)
        self.assertNotIn("SDKROOT", guard)


if __name__ == "__main__":
    unittest.main(verbosity=2)
