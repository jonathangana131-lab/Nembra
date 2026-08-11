#!/usr/bin/env python3
"""Expected-red regression for field-installer private-device runner custody.

The accepted installer itself may be sealed by Final GO, but authority helpers it
executes must also be bound to accepted bytes. A mutable checkout module must
not be able to run after the installer's initial clean-tree admission and alter
the intended-device digest decision.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
RUNNER_RELATIVE = "scripts/ci/es80_signed_field_artifact_private_runner.py"

VULNERABLE_RUNNER_ASSIGNMENT = (
    'PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"'
)
VULNERABLE_PATH_IMPORT = 'spec = importlib.util.spec_from_file_location("nembra_private_device_reader", runner_path)'

# This is the exact authority shape embedded in the installer today. The
# regression executes it only in a temporary directory with no device/build
# side effects so a substituted module can demonstrate process-wide mutation.
INLINE_DEVICE_AUTHORITY = r'''
import hashlib
import hmac
import importlib.util
import os
import re
import sys
from pathlib import Path

runner_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("nembra_private_device_reader", runner_path)
if spec is None or spec.loader is None:
    raise RuntimeError("private intended-device reader could not be loaded")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
value = module.read_private_identifier(Path(sys.argv[2]), Path(sys.argv[3]))
expected_digest = os.environ.get("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256", "")
if re.fullmatch(r"[0-9a-f]{64}", expected_digest) is None:
    raise RuntimeError("expected intended-device digest is unavailable or malformed")
actual_digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
if not hmac.compare_digest(actual_digest, expected_digest):
    raise RuntimeError("private intended-device identifier does not match Final GO authority")
sys.stdout.write(value)
'''


class PrivateDeviceRunnerExecutionSubjectTests(unittest.TestCase):
    def installer_source(self) -> str:
        return INSTALLER.read_text(encoding="utf-8")

    def test_installer_must_not_reopen_private_device_authority_runner_by_mutable_checkout_path(self) -> None:
        source = self.installer_source()
        self.assertNotIn(
            VULNERABLE_RUNNER_ASSIGNMENT,
            source,
            "field installer still selects the private-device authority helper by mutable checkout pathname",
        )
        self.assertNotIn(
            VULNERABLE_PATH_IMPORT,
            source,
            "field installer still executes private-device authority Python through a mutable pathname import",
        )

    def test_current_mutable_runner_can_subvert_digest_decision_after_admission(self) -> None:
        source = self.installer_source()
        if VULNERABLE_RUNNER_ASSIGNMENT not in source or VULNERABLE_PATH_IMPORT not in source:
            self.skipTest("production no longer uses the demonstrated mutable private-runner execution boundary")

        legitimate = "LEGITIMATE-DEVICE-IDENTIFIER"
        forged = "FORGED-DEVICE-IDENTIFIER"
        expected_digest = hashlib.sha256(legitimate.encode("utf-8")).hexdigest()

        with tempfile.TemporaryDirectory(prefix="nembra-private-device-runner-redteam-") as temporary:
            root = Path(temporary)
            runner = root / "es80_signed_field_artifact_private_runner.py"
            private_file = root / "device.txt"
            marker = root / "replacement-executed"
            private_file.write_text(legitimate + "\n", encoding="utf-8")
            private_file.chmod(0o600)

            # The substituted helper executes in the same interpreter as the
            # digest decision. It can mutate the already-imported hmac module,
            # then return a forged device identifier that would otherwise fail.
            runner.write_text(
                textwrap.dedent(
                    f'''\
                    from pathlib import Path
                    import hmac

                    def read_private_identifier(path, repository_root):
                        Path({str(marker)!r}).write_text("executed\\n", encoding="utf-8")
                        hmac.compare_digest = lambda actual, expected: True
                        return {forged!r}
                    '''
                ),
                encoding="utf-8",
            )

            env = {
                "PATH": "/usr/bin:/bin",
                "HOME": str(root),
                "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256": expected_digest,
                "PYTHONDONTWRITEBYTECODE": "1",
            }
            completed = subprocess.run(
                ["/usr/bin/python3", "-I", "-B", "-", str(runner), str(private_file), str(root)],
                input=INLINE_DEVICE_AUTHORITY,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                check=False,
            )

            self.assertTrue(marker.exists(), "diagnostic did not execute the substituted private-device runner")
            self.assertNotEqual(
                completed.returncode,
                0,
                "mutable runner executed and forged intended-device authority despite a digest for different bytes",
            )
            self.assertNotEqual(
                completed.stdout,
                forged,
                "forged device identifier escaped the intended-device digest boundary",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
