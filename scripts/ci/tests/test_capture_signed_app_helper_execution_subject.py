#!/usr/bin/env python3
"""The exact helper bytes accepted from Git must be the helper bytes executed."""

from __future__ import annotations

import base64
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"

LOADER = (
    "import sys; "
    "source=sys.stdin.buffer.read(); "
    "scope={'__name__':'__main__','__file__':'<accepted-capture-signed-app-install-custody>'}; "
    "exec(compile(source, scope['__file__'], 'exec'), scope, scope)"
)


class SignedAppHelperExecutionSubjectTests(unittest.TestCase):
    def test_installer_executes_only_captured_helper_bytes(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        accepted_blob = 'HELPER_ACCEPTED_BLOB="$(git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE"'
        actual_blob = 'HELPER_ACTUAL_BLOB="$(git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"'
        capture = 'SIGNED_APP_CUSTODY_HELPER_CAPTURE_B64="$(/usr/bin/base64 < "$SIGNED_APP_CUSTODY_HELPER")"'
        captured_blob = 'HELPER_CAPTURED_BLOB="$(printf \'%s\' "$SIGNED_APP_CUSTODY_HELPER_CAPTURE_B64" | /usr/bin/base64 -D | git hash-object --stdin)"'
        runner = 'run_signed_app_custody_helper() {'
        fingerprint = 'SOURCE_APP_TREE_SHA256="$(run_signed_app_custody_helper fingerprint --app "$APP")"'
        verify = 'STAGED_APP_TREE_SHA256="$(run_signed_app_custody_helper verify-stage \\\'
        pathname_exec = '/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py"'

        for marker in (accepted_blob, actual_blob, capture, captured_blob, runner, fingerprint, verify):
            self.assertIn(marker, source)
        self.assertNotIn(pathname_exec, source)
        self.assertLess(source.index(actual_blob), source.index(capture))
        self.assertLess(source.index(capture), source.index(captured_blob))
        self.assertLess(source.index(captured_blob), source.index(runner))
        self.assertLess(source.index(runner), source.index(fingerprint))
        self.assertLess(source.index(fingerprint), source.index(verify))

    def test_post_capture_path_replacement_cannot_change_executed_bytes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-helper-execution-subject-") as temporary:
            helper = Path(temporary) / "capture_signed_app_install_custody.py"
            accepted = b"#!/usr/bin/env python3\nprint('ACCEPTED_HELPER')\n"
            attacker = b"#!/usr/bin/env python3\nprint('ATTACKER_HELPER_EXECUTED')\n"
            helper.write_bytes(accepted)

            captured_b64 = base64.b64encode(helper.read_bytes())
            captured = base64.b64decode(captured_b64, validate=True)
            accepted_digest = hashlib.sha256(accepted).hexdigest()
            self.assertEqual(hashlib.sha256(captured).hexdigest(), accepted_digest)

            helper.write_bytes(attacker)
            result = subprocess.run(
                ["/usr/bin/python3", "-I", "-c", LOADER],
                input=captured,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            output = result.stdout.decode("utf-8", errors="replace")
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("ACCEPTED_HELPER", output)
            self.assertNotIn("ATTACKER_HELPER_EXECUTED", output)

    def test_pre_capture_replacement_fails_captured_subject_hash(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-helper-execution-subject-") as temporary:
            helper = Path(temporary) / "capture_signed_app_install_custody.py"
            accepted = b"#!/usr/bin/env python3\nprint('ACCEPTED_HELPER')\n"
            attacker = b"#!/usr/bin/env python3\nprint('ATTACKER_HELPER_EXECUTED')\n"
            accepted_digest = hashlib.sha256(accepted).hexdigest()
            helper.write_bytes(accepted)
            helper.write_bytes(attacker)
            captured = base64.b64decode(base64.b64encode(helper.read_bytes()), validate=True)
            self.assertNotEqual(hashlib.sha256(captured).hexdigest(), accepted_digest)


if __name__ == "__main__":
    unittest.main(verbosity=2)
