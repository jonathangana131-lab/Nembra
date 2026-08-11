#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "Scripts/capture_signed_app_install_guard.py"
spec = importlib.util.spec_from_file_location("capture_signed_app_install_guard", HELPER)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

BUILD_ID = "capture-v14-0123456789ab"
SOURCE_SHA = "0123456789abcdef0123456789abcdef01234567"
LOCK_SHA = "89abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567"
PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"
BUNDLE_ID = "com.jonathangana131.nembra.capturelearn"
TEAM_ID = "A1B2C3D4E5"
APPLICATION_ID = TEAM_ID + "." + BUNDLE_ID


class NullBackend:
    def register(self, descriptor: int) -> None:
        pass

    def events(self, timeout: float):
        return ()

    def close(self) -> None:
        pass


class DummyProcess:
    def __init__(self, returncode: int = 0):
        self.returncode = returncode

    def poll(self):
        return self.returncode

    def terminate(self):
        self.returncode = -15

    def wait(self, timeout=None):
        return self.returncode

    def kill(self):
        self.returncode = -9


class EventBackend(NullBackend):
    def __init__(self, event_call: int = 2):
        self.calls = 0
        self.event_call = event_call

    def events(self, timeout: float):
        self.calls += 1
        if self.calls == self.event_call:
            return (object(),)
        return ()


class RunningOnceProcess(DummyProcess):
    def __init__(self):
        super().__init__(0)
        self._polls = 0

    def poll(self):
        self._polls += 1
        if self._polls == 1:
            return None
        return self.returncode


class SignedAppInstallGuardTests(unittest.TestCase):
    def make_app(self, root: Path) -> Path:
        app = root / "Nembra Capture.app"
        (app / "Frameworks/Test.framework").mkdir(parents=True)
        info = {
            "NembraCaptureBuildIdentifier": BUILD_ID,
            "NembraCaptureSourceCommitSHA": SOURCE_SHA,
            "NembraCaptureTuyaDependencyLockSHA256": LOCK_SHA,
            "NembraCaptureProcedureIdentifier": PROCEDURE,
            "CFBundleIdentifier": BUNDLE_ID,
        }
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        (app / "embedded.mobileprovision").write_bytes(b"synthetic-profile")
        (app / "Frameworks/Test.framework/Test").write_bytes(b"framework-a")
        return app

    @staticmethod
    def authority_run(command, stdout=None, stderr=None, check=False):
        if "/usr/bin/codesign" in command and "--verify" in command:
            return subprocess.CompletedProcess(command, 0, b"", b"")
        if "/usr/bin/codesign" in command and "--entitlements" in command:
            payload = plistlib.dumps(
                {
                    "com.apple.developer.applesignin": ["Default"],
                    "application-identifier": APPLICATION_ID,
                    "com.apple.developer.team-identifier": TEAM_ID,
                }
            )
            return subprocess.CompletedProcess(command, 0, b"", payload)
        if "/usr/bin/security" in command and "cms" in command:
            payload = plistlib.dumps(
                {
                    "Entitlements": {
                        "com.apple.developer.applesignin": ["Default"],
                        "application-identifier": APPLICATION_ID,
                        "com.apple.developer.team-identifier": TEAM_ID,
                    },
                    "TeamIdentifier": [TEAM_ID],
                }
            )
            return subprocess.CompletedProcess(command, 0, payload, b"")
        raise AssertionError(f"unexpected authority command: {command}")

    def seal(self, app: Path, backend_factory=NullBackend) -> str:
        return module.verify_authority_and_seal(
            app,
            expected_build_identifier=BUILD_ID,
            expected_source_sha=SOURCE_SHA,
            expected_tuya_lock_sha256=LOCK_SHA,
            expected_procedure_id=PROCEDURE,
            expected_bundle_id=BUNDLE_ID,
            expected_team_id=TEAM_ID,
            backend_factory=backend_factory,
            run_factory=self.authority_run,
        )

    def test_fingerprint_changes_when_signed_bundle_bytes_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = self.make_app(Path(temporary))
            before = module.fingerprint_bundle(app)
            (app / "Frameworks/Test.framework/Test").write_bytes(b"framework-b")
            after = module.fingerprint_bundle(app)
            self.assertNotEqual(before, after)

    def test_authority_verification_seals_the_exact_verified_subject(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = self.make_app(Path(temporary))
            sealed = self.seal(app)
            self.assertEqual(sealed, module.fingerprint_bundle(app))

    def test_authority_verification_rejects_mutation_event(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = self.make_app(Path(temporary))
            with self.assertRaises(module.InstallCustodyError):
                self.seal(app, backend_factory=lambda: EventBackend(event_call=2))

    def test_authority_verification_rejects_provenance_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = self.make_app(Path(temporary))
            info = plistlib.loads((app / "Info.plist").read_bytes())
            info["NembraCaptureSourceCommitSHA"] = "f" * 40
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            with self.assertRaises(module.InstallCustodyError):
                self.seal(app)

    def test_guard_rejects_preinstall_swap_before_child_runs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = self.make_app(Path(temporary))
            accepted = module.fingerprint_bundle(app)
            (app / "Frameworks/Test.framework/Test").write_bytes(b"substituted")
            calls: list[list[str]] = []

            def popen(command):
                calls.append(command)
                return DummyProcess()

            with self.assertRaises(module.InstallCustodyError):
                module.run_guarded_install(
                    app,
                    accepted,
                    ["fake-devicectl"],
                    backend_factory=NullBackend,
                    popen_factory=popen,
                )
            self.assertEqual(calls, [])

    def test_guard_allows_unchanged_subject(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = self.make_app(Path(temporary))
            accepted = module.fingerprint_bundle(app)
            result = module.run_guarded_install(
                app,
                accepted,
                ["fake-devicectl"],
                backend_factory=NullBackend,
                popen_factory=lambda command: DummyProcess(0),
            )
            self.assertEqual(result, 0)

    def test_vnode_event_fails_closed_during_child(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = self.make_app(Path(temporary))
            accepted = module.fingerprint_bundle(app)
            with self.assertRaises(module.InstallCustodyError):
                module.run_guarded_install(
                    app,
                    accepted,
                    ["fake-devicectl"],
                    backend_factory=lambda: EventBackend(event_call=2),
                    popen_factory=lambda command: RunningOnceProcess(),
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
