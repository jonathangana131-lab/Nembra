#!/usr/bin/env python3
"""Expected-red: the helper bytes accepted from Git must be the helper bytes executed."""

from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"


class SignedAppHelperExecutionSubjectTests(unittest.TestCase):
    def test_helper_cannot_change_after_blob_check_before_python_exec(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        accepted_blob = 'HELPER_ACCEPTED_BLOB="$(git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE"'
        actual_blob = 'HELPER_ACTUAL_BLOB="$(git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"'
        fingerprint_exec = '/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" fingerprint --app "$APP"'
        verify_exec = '/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" verify-stage'
        for marker in (accepted_blob, actual_blob, fingerprint_exec, verify_exec):
            self.assertIn(marker, source)
        self.assertLess(source.index(actual_blob), source.index(fingerprint_exec))
        self.assertLess(source.index(fingerprint_exec), source.index(verify_exec))

        with tempfile.TemporaryDirectory(prefix="nembra-helper-execution-subject-") as temporary:
            helper = Path(temporary) / "capture_signed_app_install_custody.py"
            accepted = b"#!/usr/bin/env python3\nprint('ACCEPTED_HELPER')\n"
            attacker = b"#!/usr/bin/env python3\nprint('ATTACKER_HELPER_EXECUTED')\n"
            helper.write_bytes(accepted)

            # Stand in for the installer's successful accepted/current blob equality.
            checked_digest = hashlib.sha256(helper.read_bytes()).hexdigest()
            self.assertEqual(checked_digest, hashlib.sha256(accepted).hexdigest())

            # Same-UID replacement occurs after the accepted blob comparison but before
            # the installer's later pathname-based /usr/bin/python3 invocation.
            helper.write_bytes(attacker)
            result = subprocess.run(
                ["/usr/bin/python3", "-I", str(helper)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotIn(
                "ATTACKER_HELPER_EXECUTED",
                result.stdout,
                "the helper pathname was re-opened after its authority check; execute exact accepted bytes under custody instead",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
