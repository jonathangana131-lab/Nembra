#!/usr/bin/env python3
"""Behavioral regression for signed-field Apple verification process custody.

Explicit /usr/bin tool paths are necessary but not sufficient: the exact Apple processes that
mint code-signing/provisioning evidence must not inherit caller-controlled startup/config state.
"""

from __future__ import annotations

import importlib.util
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence.py"

POISONED_ENV = {
    "PATH": "/tmp/nembra-attacker-bin",
    "HOME": "/tmp/nembra-attacker-home",
    "CODESIGN_ALLOCATE": "/tmp/nembra-attacker-codesign-allocate",
    "DYLD_INSERT_LIBRARIES": "/tmp/nembra-attacker.dylib",
    "DYLD_LIBRARY_PATH": "/tmp/nembra-attacker-libs",
    "LD_PRELOAD": "/tmp/nembra-attacker.so",
    "PYTHONPATH": "/tmp/nembra-attacker-python",
}


def load_inspector():
    spec = importlib.util.spec_from_file_location("nembra_apple_process_custody", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load signed-field inspector")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def assert_closed_process_boundary(testcase: unittest.TestCase, kwargs: dict) -> None:
    environment = kwargs.get("env")
    testcase.assertIsInstance(
        environment,
        dict,
        "Security-sensitive Apple verification processes must receive an explicit controlled environment.",
    )
    assert isinstance(environment, dict)
    testcase.assertEqual(environment.get("PATH"), "/usr/bin:/bin")
    for key, poisoned_value in POISONED_ENV.items():
        if key == "PATH":
            continue
        testcase.assertNotEqual(
            environment.get(key),
            poisoned_value,
            f"Caller-controlled {key} must not cross the Apple verification process boundary.",
        )
    testcase.assertEqual(kwargs.get("cwd"), "/")
    testcase.assertIs(kwargs.get("stdin"), subprocess.DEVNULL)
    timeout = kwargs.get("timeout")
    testcase.assertIsInstance(timeout, (int, float))
    assert isinstance(timeout, (int, float))
    testcase.assertGreater(timeout, 0)
    testcase.assertLessEqual(timeout, 60)


class SignedFieldArtifactAppleProcessCustodyTests(unittest.TestCase):
    def test_codesign_text_wrapper_ignores_poisoned_caller_process_state(self) -> None:
        inspector = load_inspector()
        completed = subprocess.CompletedProcess(
            args=["/usr/bin/codesign", "--version"],
            returncode=0,
            stdout="codesign fixture",
            stderr="",
        )
        with (
            mock.patch.dict(os.environ, POISONED_ENV, clear=False),
            mock.patch.object(inspector.subprocess, "run", return_value=completed) as run,
        ):
            inspector._run_text(["/usr/bin/codesign", "--version"])

        kwargs = run.call_args.kwargs
        self.assertTrue(kwargs.get("text"))
        self.assertTrue(kwargs.get("capture_output"))
        self.assertFalse(kwargs.get("check"))
        assert_closed_process_boundary(self, kwargs)

    def test_security_profile_decode_ignores_poisoned_caller_process_state(self) -> None:
        inspector = load_inspector()
        completed = subprocess.CompletedProcess(
            args=["/usr/bin/security", "cms", "-D"],
            returncode=0,
            stdout=plistlib.dumps({}),
            stderr=b"",
        )

        with tempfile.TemporaryDirectory(prefix="nembra-apple-process-custody-") as temporary:
            app_path = Path(temporary) / "Nembra.app"
            app_path.mkdir()
            profile_path = app_path / "embedded.mobileprovision"
            profile_path.write_bytes(b"profile fixture")

            with (
                mock.patch.dict(os.environ, POISONED_ENV, clear=False),
                mock.patch.object(inspector.sys, "platform", "darwin"),
                mock.patch.object(
                    inspector,
                    "_trusted_system_apple_tool",
                    return_value="/usr/bin/security",
                ),
                mock.patch.object(
                    inspector,
                    "read_effective_signed_entitlements",
                    return_value={},
                ),
                mock.patch.object(
                    inspector,
                    "read_leaf_signing_certificate_der",
                    return_value=b"certificate fixture",
                ),
                mock.patch.object(
                    inspector,
                    "validate_provisioning_profile",
                    return_value=("PROFILE-UUID", "2099-01-01T00:00:00Z", "TEAM.bundle"),
                ),
                mock.patch.object(inspector.subprocess, "run", return_value=completed) as run,
            ):
                inspector.verify_provisioning_profile(
                    app_path,
                    team_identifier="ABCDE12345",
                    bundle_identifier=inspector.BUNDLE_ID,
                    intended_device_udid="00008101-001234567890001E",
                )

        kwargs = run.call_args.kwargs
        self.assertIs(kwargs.get("stdout"), subprocess.PIPE)
        self.assertIs(kwargs.get("stderr"), subprocess.PIPE)
        self.assertFalse(kwargs.get("check"))
        assert_closed_process_boundary(self, kwargs)


if __name__ == "__main__":
    unittest.main()
