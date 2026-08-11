#!/usr/bin/env python3
"""Regression for exact accepted signed-app custody-helper execution bytes."""

from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
BEGIN = "# BEGIN ACCEPTED SIGNED-APP CUSTODY HELPER EXECUTOR"
END = "# END ACCEPTED SIGNED-APP CUSTODY HELPER EXECUTOR"
DIRECT_FINGERPRINT = '/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" fingerprint'
DIRECT_VERIFY = '/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" verify-stage'


def git_blob_oid(payload: bytes, algorithm: str = "sha1") -> str:
    framed = b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    return hashlib.new(algorithm, framed).hexdigest()


class SignedAppHelperExecutionAuthorityTests(unittest.TestCase):
    def installer_source(self) -> str:
        return INSTALLER.read_text(encoding="utf-8")

    def executor_source(self) -> str:
        source = self.installer_source()
        begin = source.index(BEGIN)
        end = source.index(END, begin) + len(END)
        return source[begin:end] + "\n"

    def run_executor(
        self,
        helper: Path,
        accepted_oid: str,
        *arguments: str,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/usr/bin/python3", "-I", "-B", "-", str(helper), accepted_oid, *arguments],
            input=self.executor_source(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )

    def test_installer_routes_both_authority_calls_through_pinned_executor(self) -> None:
        source = self.installer_source()
        self.assertNotIn(DIRECT_FINGERPRINT, source)
        self.assertNotIn(DIRECT_VERIFY, source)
        self.assertIn(
            'SOURCE_APP_TREE_SHA256="$(run_accepted_signed_app_custody_helper fingerprint --app "$APP")"',
            source,
        )
        self.assertIn(
            'STAGED_APP_TREE_SHA256="$(run_accepted_signed_app_custody_helper verify-stage',
            source,
        )
        self.assertEqual(source.count("PY_ACCEPTED_CUSTODY_HELPER"), 2)
        self.assertEqual(source.count(BEGIN), 1)
        self.assertEqual(source.count(END), 1)

    def test_exact_accepted_bytes_execute_with_original_helper_argv(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-helper-exec-green-") as temporary:
            helper = Path(temporary) / "capture_signed_app_install_custody.py"
            accepted = (
                b"#!/usr/bin/env python3\n"
                b"import sys\n"
                b"print('ACCEPTED_HELPER:' + ':'.join(sys.argv[1:]))\n"
            )
            helper.write_bytes(accepted)
            result = self.run_executor(helper, git_blob_oid(accepted), "fingerprint", "--app", "/tmp/app")
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("ACCEPTED_HELPER:fingerprint:--app:/tmp/app", result.stdout)

    def test_replacement_after_reviewed_oid_is_rejected_before_attacker_executes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-helper-exec-substitute-") as temporary:
            helper = Path(temporary) / "capture_signed_app_install_custody.py"
            accepted = b"#!/usr/bin/env python3\nprint('ACCEPTED_HELPER')\n"
            attacker = b"#!/usr/bin/env python3\nprint('ATTACKER_HELPER_EXECUTED')\n"
            helper.write_bytes(accepted)
            accepted_oid = git_blob_oid(accepted)
            helper.write_bytes(attacker)

            result = self.run_executor(helper, accepted_oid, "fingerprint")
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("ATTACKER_HELPER_EXECUTED", result.stdout)
            self.assertIn("execution bytes differ from the exact accepted Git blob", result.stdout)

    def test_sha256_repository_object_format_is_supported(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-helper-exec-sha256-") as temporary:
            helper = Path(temporary) / "capture_signed_app_install_custody.py"
            accepted = b"#!/usr/bin/env python3\nprint('SHA256_HELPER')\n"
            helper.write_bytes(accepted)
            result = self.run_executor(helper, git_blob_oid(accepted, "sha256"), "verify-stage")
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("SHA256_HELPER", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
