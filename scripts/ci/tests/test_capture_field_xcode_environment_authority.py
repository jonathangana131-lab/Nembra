#!/usr/bin/env python3
"""Regression contract for residual caller Xcode build-environment authority.

DEVELOPER_DIR has its own accepted production fence. This test owns the broader
compiler child boundary: xcodebuild must receive an explicit minimal environment
rather than inheriting arbitrary caller build/toolchain settings.
"""
from __future__ import annotations

import ast
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
GUARD_PATH = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"


class CaptureFieldXcodeEnvironmentAuthorityTests(unittest.TestCase):
    def _guard_tree(self) -> ast.Module:
        return ast.parse(GUARD_PATH.read_text(encoding="utf-8"))

    def test_guarded_build_process_owns_one_explicit_child_environment(self) -> None:
        tree = self._guard_tree()
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
        environment_keywords = [keyword for keyword in popen_calls[0].keywords if keyword.arg == "env"]
        self.assertEqual(
            len(environment_keywords),
            1,
            "guarded xcodebuild must receive one explicit child environment",
        )
        rendered_environment = ast.unparse(environment_keywords[0].value)
        self.assertEqual(
            rendered_environment,
            "_closed_xcode_environment()",
            "compiler admission must use the reviewed closed-environment primitive",
        )

    def test_closed_environment_is_constructed_without_ambient_environment_copy(self) -> None:
        tree = self._guard_tree()
        helper = next(
            node
            for node in tree.body
            if isinstance(node, ast.FunctionDef) and node.name == "_closed_xcode_environment"
        )
        rendered = ast.unparse(helper)
        self.assertNotIn("os.environ", rendered)
        self.assertNotIn("os.getenv", rendered)
        self.assertNotIn("environ.copy", rendered)

        literals = {
            value.value
            for value in ast.walk(helper)
            if isinstance(value, ast.Constant) and isinstance(value.value, str)
        }
        for required in (
            "PATH",
            "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME",
            "USER",
            "LOGNAME",
        ):
            self.assertIn(required, literals, f"closed compiler child environment omitted {required}")

        forbidden = (
            "DEVELOPER_DIR",
            "XCODE_XCCONFIG_FILE",
            "TOOLCHAINS",
            "SDKROOT",
            "DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH",
            "CPATH",
            "CFLAGS",
            "CXXFLAGS",
            "LDFLAGS",
        )
        for name in forbidden:
            self.assertNotIn(name, literals, f"closed compiler child environment admitted {name}")

    def test_developer_dir_fence_remains_before_xcode_tools(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        unset_index = installer.index("unset DEVELOPER_DIR")
        first_xcode_tool = min(
            index
            for index in (
                installer.find("/usr/bin/xcrun"),
                installer.find("/usr/bin/xcodebuild"),
            )
            if index >= 0
        )
        self.assertLess(unset_index, first_xcode_tool)


if __name__ == "__main__":
    unittest.main(verbosity=2)
