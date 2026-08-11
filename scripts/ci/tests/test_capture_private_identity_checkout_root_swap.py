#!/usr/bin/env python3
"""Expected-red: private Tuya credential publication must stay bound to the checkout opened before input.

The provisioner resolves its checkout path and captures/pins the writer before asking for credentials,
but the writer currently reopens that checkout by pathname only after the operator has entered those
credentials. A same-UID process can rename the admitted checkout and place a different directory at
the same pathname during that input window. Descendant O_NOFOLLOW/dir_fd custody then protects the
replacement tree rather than the originally admitted checkout.

This diagnostic uses a PTY so the real hidden-input prompts become deterministic race boundaries. It
swaps the checkout after the AppKey prompt, then requires publication to fail closed and forbids any
private identity output under the replacement path.
"""

from __future__ import annotations

import errno
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import time
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
PROVISIONER = REPOSITORY / "Scripts" / "provision_capture_tuya_identity.sh"
WRITER = REPOSITORY / "Scripts" / "provision_capture_tuya_identity_writer.py"
DEPENDENCY_ADAPTER = REPOSITORY / "Scripts" / "capture_tuya_private_dependency_resolution_guard.py"


class PrivateIdentityCheckoutRootSwapTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-root-swap-")
        self.sandbox = Path(self.temporary.name)
        self.checkout = self.sandbox / "repo"
        scripts = self.checkout / "Scripts"
        scripts.mkdir(parents=True)
        shutil.copy2(PROVISIONER, scripts / PROVISIONER.name)
        shutil.copy2(WRITER, scripts / WRITER.name)
        (scripts / PROVISIONER.name).chmod(0o700)
        (scripts / WRITER.name).chmod(0o600)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def _read_until(master_fd: int, marker: bytes, process: subprocess.Popen[bytes], timeout: float = 5.0) -> bytes:
        deadline = time.monotonic() + timeout
        captured = bytearray()
        while marker not in captured:
            if time.monotonic() >= deadline:
                raise AssertionError(f"timed out waiting for {marker!r}; output={bytes(captured)!r}")
            ready, _, _ = select.select([master_fd], [], [], 0.1)
            if not ready:
                if process.poll() is not None:
                    raise AssertionError(
                        f"provisioner exited before prompt {marker!r}: status={process.returncode}, output={bytes(captured)!r}"
                    )
                continue
            try:
                chunk = os.read(master_fd, 4096)
            except OSError as exc:
                if exc.errno == errno.EIO and process.poll() is not None:
                    break
                raise
            if not chunk:
                break
            captured.extend(chunk)
        return bytes(captured)

    @staticmethod
    def _drain(master_fd: int, process: subprocess.Popen[bytes], timeout: float = 5.0) -> bytes:
        deadline = time.monotonic() + timeout
        captured = bytearray()
        while process.poll() is None and time.monotonic() < deadline:
            ready, _, _ = select.select([master_fd], [], [], 0.1)
            if ready:
                try:
                    captured.extend(os.read(master_fd, 4096))
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
        if process.poll() is None:
            process.kill()
            process.wait(timeout=2)
            raise AssertionError("provisioner did not terminate after credential input")
        while True:
            ready, _, _ = select.select([master_fd], [], [], 0)
            if not ready:
                break
            try:
                chunk = os.read(master_fd, 4096)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            captured.extend(chunk)
        return bytes(captured)

    def test_dependency_resolution_adapter_uses_canonical_private_api(self) -> None:
        source = DEPENDENCY_ADAPTER.read_text(encoding="utf-8")
        self.assertIn("return guard.run_guarded_build(inputs, command)", source)
        self.assertIn("def _lexical_absolute(path: Path) -> Path:", source)
        self.assertIn("def _require_real_checkout_ancestry(path: Path, root: Path, *, label: str) -> Path:", source)
        self.assertNotIn("guard._lexical_absolute", source)
        self.assertNotIn("guard._require_real_checkout_ancestry", source)
        self.assertNotIn("require_accepted_generated_subject", source)
        self.assertNotIn("require_accepted_private_review_commitment", source)
        self.assertNotIn("require_accepted_authority_helpers", source)
        self.assertNotIn("require_accepted_tracked_source", source)

    def test_checkout_root_swap_after_admission_cannot_redirect_credentials(self) -> None:
        script = self.checkout / "Scripts" / PROVISIONER.name
        master_fd, slave_fd = pty.openpty()
        try:
            environment = {
                "HOME": str(self.sandbox),
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "LANG": "C.UTF-8",
                "LC_ALL": "C.UTF-8",
            }
            process = subprocess.Popen(
                [str(script)],
                cwd=self.sandbox,
                env=environment,
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                close_fds=True,
            )
            os.close(slave_fd)
            slave_fd = -1

            prefix = self._read_until(master_fd, b"AppKey (input hidden):", process)
            self.assertNotIn(b"ERROR:", prefix, prefix.decode("utf-8", errors="replace"))

            original_checkout = self.sandbox / "repo-original"
            os.rename(self.checkout, original_checkout)
            self.checkout.mkdir()

            os.write(master_fd, b"nembra-dummy-app-key\n")
            self._read_until(master_fd, b"AppSecret (input hidden):", process)
            os.write(master_fd, b"nembra-dummy-app-secret\n")
            output = self._drain(master_fd, process)

            replacement_identity = self.checkout / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift"
            replacement_podspec = self.checkout / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"

            self.assertNotEqual(
                process.returncode,
                0,
                "credential publication succeeded after the admitted checkout pathname was replaced; bind the checkout root identity before credential input",
            )
            self.assertFalse(
                replacement_identity.exists() or replacement_podspec.exists(),
                "private credential material was redirected into a replacement checkout tree",
            )
            self.assertNotIn(b"Private Tuya app identity provisioned locally", output)
        finally:
            if slave_fd >= 0:
                os.close(slave_fd)
            os.close(master_fd)


if __name__ == "__main__":
    unittest.main(verbosity=2)
