#!/usr/bin/env python3
"""Expected-red diagnostic for private Tuya identity publication custody.

The production provisioner validates a random temp pathname and later reopens that
pathname to write credential-bearing Swift source. This diagnostic only widens the
existing interval between validation and reopen so an ancestor-directory replacement
is deterministic; it does not replace either production filesystem operation.
"""

from __future__ import annotations

import base64
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[3]
SOURCE = REPO / "Scripts/provision_capture_tuya_identity.sh"
ANCHOR = 'validate_private_temp "$IDENTITY_TMP" "$IDENTITY_TMP_PREFIX" "$SOURCE_DIR"\n'


class TuyaPrivateIdentityAncestorSwapDiagnostic(unittest.TestCase):
    def test_validated_identity_temp_cannot_be_retargeted_before_credential_write(self) -> None:
        source = SOURCE.read_text(encoding="utf-8")
        self.assertEqual(source.count(ANCHOR), 1, "production temp-validation anchor changed; re-review diagnostic")

        with tempfile.TemporaryDirectory(prefix="nembra-tuya-ancestor-swap-") as temporary:
            sandbox = Path(temporary)
            repo = sandbox / "repo"
            scripts = repo / "Scripts"
            scripts.mkdir(parents=True)
            fixture = scripts / "provision_capture_tuya_identity.sh"

            hook = (
                ANCHOR
                + '/usr/bin/touch "$ROOT/.nembra-race-ready"\n'
                + 'while [[ ! -e "$ROOT/.nembra-race-go" ]]; do /bin/sleep 0.01; done\n'
            )
            fixture.write_text(source.replace(ANCHOR, hook, 1), encoding="utf-8")
            fixture.chmod(0o700)

            app_key = "nembra-race-app-key"
            app_secret = "nembra-race-app-secret"
            process = subprocess.Popen(
                [str(fixture)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                env={**os.environ, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
            )
            assert process.stdin is not None
            process.stdin.write(app_key + "\n" + app_secret + "\n")
            process.stdin.flush()
            process.stdin.close()

            ready = repo / ".nembra-race-ready"
            deadline = time.monotonic() + 10
            while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists(), "fixture never reached the exact post-validation/pre-reopen window")

            source_dir = repo / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"
            temps = list(source_dir.glob(".NembraTuyaPrivateIdentity.swift.*"))
            self.assertEqual(len(temps), 1, "expected one validated identity temp")
            temp_name = temps[0].name

            original_dir = sandbox / "original-private-source-dir"
            source_dir.rename(original_dir)
            source_dir.mkdir(parents=True)
            source_dir.chmod(0o700)

            sentinel = sandbox / "credential-redirection-sentinel"
            sentinel.write_text("unchanged", encoding="utf-8")
            os.symlink(sentinel, source_dir / temp_name)
            (repo / ".nembra-race-go").touch()

            returncode = process.wait(timeout=10)
            output = process.stdout.read() if process.stdout is not None else ""
            leaked = sentinel.read_text(encoding="utf-8")
            encoded_key = base64.b64encode(app_key.encode()).decode()
            encoded_secret = base64.b64encode(app_secret.encode()).decode()

            self.assertNotIn(app_key, output)
            self.assertNotIn(app_secret, output)
            self.assertEqual(
                leaked,
                "unchanged",
                "credential-bearing identity bytes followed an ancestor-replaced temp pathname",
            )
            self.assertNotIn(encoded_key, leaked)
            self.assertNotIn(encoded_secret, leaked)
            self.assertNotEqual(
                returncode,
                0,
                "provisioner reported success after its validated identity-temp ancestor was replaced",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
