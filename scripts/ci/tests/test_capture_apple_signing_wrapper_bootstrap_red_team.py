#!/usr/bin/env python3
"""Exploit-positive bootstrap witness for the private Apple-signing field wrapper.

The accepted wrapper verifies its physical bytes before its own intended sudo calls,
but that verification is code inside the same field-writable wrapper. This witness
creates a modified copy which retains the accepted self-check text but executes a
harmless noninteractive root-UID probe before that check can run.

A passing exploit test is validation RED, not product acceptance.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
TRANSPORT = ROOT / "scripts/field/run_apple_signing_context_preflight.command"


def git_blob_oid(payload: bytes) -> str:
    return hashlib.sha1(
        b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    ).hexdigest()


class AppleSigningWrapperBootstrapRedTeamTests(unittest.TestCase):
    def test_accepted_wrapper_self_check_precedes_its_intended_sudo(self) -> None:
        source = TRANSPORT.read_text(encoding="utf-8")
        self_check = '[[ "$CURRENT_SCRIPT_BLOB" == "$SCRIPT_BLOB" ]] || fail'
        first_sudo = '/usr/bin/sudo -n /usr/bin/mktemp'
        self.assertIn(self_check, source)
        self.assertIn(first_sudo, source)
        self.assertLess(source.index(self_check), source.index(first_sudo))

    def test_field_mutable_wrapper_can_enter_noninteractive_root_before_self_check(self) -> None:
        accepted = TRANSPORT.read_bytes()
        marker = b"export PATH\n"
        self.assertEqual(accepted.count(marker), 1)
        payload = (
            b"export PATH\n"
            b"# Exploit-positive harmless witness: modified field bytes execute first.\n"
            b"/usr/bin/sudo -n /usr/bin/python3 -B -I -c 'import os; print(os.geteuid())'\n"
            b"exit 0\n"
        )
        modified = accepted.replace(marker, payload, 1)
        self.assertNotEqual(git_blob_oid(modified), git_blob_oid(accepted))
        self.assertIn(
            b'[[ "$CURRENT_SCRIPT_BLOB" == "$SCRIPT_BLOB" ]] || fail',
            modified,
            "the accepted self-check remains present but must not be reached",
        )

        with tempfile.TemporaryDirectory(prefix="nembra-apple-wrapper-bootstrap-") as directory:
            attacked = Path(directory) / "run_apple_signing_context_preflight.command"
            attacked.write_bytes(modified)
            attacked.chmod(0o755)
            result = subprocess.run(
                ["/bin/bash", str(attacked)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                env={
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                    "HOME": os.environ.get("HOME", "/tmp"),
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                result.stdout.strip(),
                "0",
                "modified field wrapper did not obtain the harmless root-UID witness before self-verification",
            )

    def test_transport_has_no_external_trusted_launcher_boundary(self) -> None:
        source = TRANSPORT.read_text(encoding="utf-8")
        self.assertIn('CURRENT_SCRIPT_BLOB="$(' , source)
        self.assertIn('hash-object "$EXECUTING_SCRIPT"', source)
        self.assertNotIn("NEMBRA_TRUSTED_BOOTSTRAP_ATTESTATION", source)
        self.assertNotIn("ROOT_VERIFIED_WRAPPER_EXEC", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
