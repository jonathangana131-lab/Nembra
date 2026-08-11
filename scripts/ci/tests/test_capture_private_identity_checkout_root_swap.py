#!/usr/bin/env python3
"""Private Tuya checkout-root and dependency ancestry custody regressions.

Credential publication must stay bound to the checkout opened before input, and
pre-generated dependency work must stay bound to the same real checkout/ancestry
for the complete guarded child window. Dependency custody helper source itself is
also copied into the fixture and admitted through the production pinned-byte path.
"""

from __future__ import annotations

import errno
import importlib.util
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
AUTHORITY_HELPER = REPOSITORY / "Scripts" / "capture_tuya_private_identity_authority.py"
DEPENDENCY_ADAPTER = REPOSITORY / "Scripts" / "capture_tuya_private_dependency_resolution_guard.py"
CANONICAL_BUILD_GUARD = REPOSITORY / "Scripts" / "capture_tuya_private_input_build_guard.py"
PROVENANCE_HELPER = REPOSITORY / "Scripts" / "capture_tuya_private_input_provenance.py"


def load_dependency_adapter():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_dependency_adapter_checkout_test",
        DEPENDENCY_ADAPTER,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("private dependency adapter import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentityCheckoutRootSwapTests(unittest.TestCase):
    def setUp(self) -> None:
        # macOS exposes /var as a symlink to /private/var. Production correctly
        # rejects symlinked checkout ancestry, so place the fixture beneath the
        # resolved temporary root instead of weakening the no-symlink contract.
        temporary_root = Path(tempfile.gettempdir()).resolve(strict=True)
        self.temporary = tempfile.TemporaryDirectory(
            prefix="nembra-private-root-swap-",
            dir=temporary_root,
        )
        self.sandbox = Path(self.temporary.name)
        self.checkout = self.sandbox / "repo"
        scripts = self.checkout / "Scripts"
        scripts.mkdir(parents=True)
        for source in (
            PROVISIONER,
            WRITER,
            AUTHORITY_HELPER,
            CANONICAL_BUILD_GUARD,
            PROVENANCE_HELPER,
        ):
            shutil.copy2(source, scripts / source.name)
        (scripts / PROVISIONER.name).chmod(0o700)
        (scripts / WRITER.name).chmod(0o600)
        (scripts / AUTHORITY_HELPER.name).chmod(0o600)
        (scripts / CANONICAL_BUILD_GUARD.name).chmod(0o600)
        (scripts / PROVENANCE_HELPER.name).chmod(0o600)
        self.fixture_build_guard = scripts / CANONICAL_BUILD_GUARD.name
        self.fixture_provenance = scripts / PROVENANCE_HELPER.name

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

    def _dependency_fixture(self) -> tuple[Path, Path, Path, Path, Path]:
        podfile = self.checkout / "Podfile"
        podfile.write_text("# dependency custody fixture\n", encoding="utf-8")

        sdk = self.checkout / "LocalSecrets" / "TuyaSDK"
        build = sdk / "Build"
        build.mkdir(parents=True)
        security_podspec = sdk / "ThingSmartCryption.podspec"
        security_podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (build / "libfixture.a").write_bytes(b"fixture-sdk-bytes")

        runtime = self.checkout / "LocalSecrets" / "TuyaRuntime"
        identity_sources = runtime / "Sources" / "NembraTuyaPrivateConfig"
        identity_sources.mkdir(parents=True)
        identity_podspec = runtime / "NembraTuyaPrivateConfig.podspec"
        identity_podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            "enum NembraTuyaPrivateIdentity {}\n",
            encoding="utf-8",
        )
        return podfile, security_podspec, build, identity_podspec, identity_sources

    def _adapter_argv(
        self,
        podfile: Path,
        security_podspec: Path,
        build: Path,
        identity_podspec: Path,
        identity_sources: Path,
        command: list[str],
    ) -> list[str]:
        return [
            "--canonical-guard-source", str(self.fixture_build_guard),
            "--provenance-helper-source", str(self.fixture_provenance),
            "--lockfile", str(podfile),
            "--security-podspec", str(security_podspec),
            "--security-build", str(build),
            "--identity-podspec", str(identity_podspec),
            "--identity-sources", str(identity_sources),
            "--",
            *command,
        ]

    def test_dependency_resolution_adapter_uses_canonical_private_api(self) -> None:
        source = DEPENDENCY_ADAPTER.read_text(encoding="utf-8")
        self.assertIn("return guard.run_guarded_build(", source)
        self.assertIn("backend_factory=lambda: _AncestryCustodyBackend(checkout, inputs)", source)
        self.assertIn('cwd_fd = os.open(".", flags)', source)
        self.assertIn("select.KQ_NOTE_DELETE | select.KQ_NOTE_RENAME | select.KQ_NOTE_REVOKE", source)
        self.assertIn("def _lexical_absolute(path: Path) -> Path:", source)
        self.assertIn("def _require_real_checkout_ancestry(path: Path, root: Path, *, label: str) -> Path:", source)
        self.assertIn('parser.add_argument("--canonical-guard-source", required=True, type=Path)', source)
        self.assertIn('parser.add_argument("--provenance-helper-source", required=True, type=Path)', source)
        self.assertIn("_CANONICAL_GUARD_GIT_BLOB_OID", source)
        self.assertIn("_PROVENANCE_HELPER_GIT_BLOB_OID", source)
        self.assertIn("_capture_accepted_python_source(", source)
        self.assertNotIn("guard._lexical_absolute", source)
        self.assertNotIn("guard._require_real_checkout_ancestry", source)
        self.assertNotIn("require_accepted_generated_subject", source)
        self.assertNotIn("require_accepted_private_review_commitment", source)
        self.assertNotIn("require_accepted_authority_helpers", source)
        self.assertNotIn("require_accepted_tracked_source", source)

    @unittest.skipUnless(hasattr(select, "kqueue"), "macOS kqueue required")
    def test_dependency_resolution_adapter_clean_child_runs_under_real_ancestry_custody(self) -> None:
        adapter = load_dependency_adapter()
        fixture = self._dependency_fixture()
        previous = Path.cwd()
        try:
            os.chdir(self.checkout)
            result = adapter.main(self._adapter_argv(*fixture, ["/usr/bin/true"]))
        finally:
            os.chdir(previous)
        self.assertEqual(result, 0)

    @unittest.skipUnless(hasattr(select, "kqueue"), "macOS kqueue required")
    def test_dependency_resolution_adapter_rejects_ancestry_swap_restore_during_child(self) -> None:
        adapter = load_dependency_adapter()
        fixture = self._dependency_fixture()
        mutation = (
            "import os; "
            "os.rename('LocalSecrets', 'LocalSecrets-held'); "
            "os.rename('LocalSecrets-held', 'LocalSecrets')"
        )
        previous = Path.cwd()
        try:
            os.chdir(self.checkout)
            result = adapter.main(
                self._adapter_argv(*fixture, ["/usr/bin/python3", "-c", mutation])
            )
        finally:
            os.chdir(previous)
        self.assertNotEqual(
            result,
            0,
            "swap/restore of an admitted ancestry directory escaped vnode custody",
        )

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
