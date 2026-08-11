#!/usr/bin/env python3
"""Expected-red contract for residual caller Xcode build-environment authority.

DEVELOPER_DIR has its own current diagnostic. This test owns the broader child
process boundary: xcodebuild must not inherit arbitrary caller build/toolchain
settings after that narrower fence is repaired.
"""
from __future__ import annotations

import ast
import importlib.util
import os
from pathlib import Path
import sys
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


class ImmediateProcess:
    returncode = 0

    def poll(self):
        return 0

    def wait(self, timeout=None):
        del timeout
        return self.returncode

    def terminate(self) -> None:
        self.returncode = -15

    def kill(self) -> None:
        self.returncode = -9


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

    def test_actual_guarded_child_excludes_poisoned_caller_build_authority(self) -> None:
        guard = load_guard()
        caller_poison = {
            "XCODE_XCCONFIG_FILE": "/tmp/nembra-attacker.xcconfig",
            "TOOLCHAINS": "nembra.attacker.toolchain",
            "SDKROOT": "/tmp/nembra-attacker-sdk",
            "SWIFT_EXEC": "/tmp/nembra-attacker-swiftc",
            "CC": "/tmp/nembra-attacker-cc",
            "CXX": "/tmp/nembra-attacker-cxx",
            "DYLD_INSERT_LIBRARIES": "/tmp/nembra-attacker.dylib",
            "DYLD_LIBRARY_PATH": "/tmp/nembra-attacker-libs",
            "DYLD_FRAMEWORK_PATH": "/tmp/nembra-attacker-frameworks",
        }
        previous = {name: os.environ.get(name) for name in caller_poison}
        os.environ.update(caller_poison)
        captured: dict[str, object] = {}

        def capture_popen(command, **kwargs):
            captured["command"] = list(command)
            captured["env"] = kwargs.get("env")
            return ImmediateProcess()

        original_watch_paths = guard._watch_paths
        guard._watch_paths = lambda _inputs: ()
        try:
            result = guard.run_guarded_build(
                StableInputs(),
                ["/usr/bin/xcodebuild", "-version"],
                backend_factory=NoopBackend,
                popen_factory=capture_popen,
                poll_interval=0.0,
            )
        finally:
            guard._watch_paths = original_watch_paths
            for name, value in previous.items():
                if value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = value

        self.assertEqual(result, 0)
        self.assertEqual(captured.get("command"), ["/usr/bin/xcodebuild", "-version"])
        child_environment = captured.get("env")
        self.assertIsInstance(
            child_environment,
            dict,
            "guarded compiler admission must pass one explicit closed environment to the child",
        )
        assert isinstance(child_environment, dict)
        for name, attacker_value in caller_poison.items():
            self.assertNotEqual(
                child_environment.get(name),
                attacker_value,
                f"caller-controlled {name} reached the guarded compiler child",
            )

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
