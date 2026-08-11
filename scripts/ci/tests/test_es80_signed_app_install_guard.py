#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/es80_signed_app_install_guard.py"

spec = importlib.util.spec_from_file_location("es80_signed_app_install_guard", HELPER)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load signed app install guard")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class FakeBackend:
    def __init__(self, event_batches: list[list[object]] | None = None) -> None:
        self.event_batches = list(event_batches or [])
        self.registered = 0
        self.closed = False

    def register(self, descriptor: int) -> None:
        self.registered += 1

    def events(self, timeout: float):
        if self.event_batches:
            return self.event_batches.pop(0)
        return []

    def close(self) -> None:
        self.closed = True


class ImmediateProcess:
    def __init__(self, command) -> None:
        self.command = list(command)
        self.returncode = 0

    def poll(self):
        return 0

    def terminate(self):
        self.returncode = -15

    def kill(self):
        self.returncode = -9

    def wait(self, timeout=None):
        return self.returncode


class OneTickProcess(ImmediateProcess):
    def __init__(self, command) -> None:
        super().__init__(command)
        self._polls = 0

    def poll(self):
        self._polls += 1
        if self._polls == 1:
            return None
        return self.returncode


class SignedAppInstallGuardTests(unittest.TestCase):
    def make_app(self, root: Path) -> Path:
        app = root / "Derived/Build/Products/Debug-iphoneos/Nembra Capture.app"
        (app / "Frameworks/Example.framework").mkdir(parents=True)
        (app / "Info.plist").write_bytes(b"plist-subject")
        (app / "Nembra Capture").write_bytes(b"executable-subject")
        (app / "Frameworks/Example.framework/Example").write_bytes(b"framework-subject")
        return app

    def test_digest_is_deterministic_and_changes_with_bytes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-signed-app-guard-") as temporary:
            app = self.make_app(Path(temporary))
            first = guard.digest_app(app)
            second = guard.digest_app(app)
            self.assertEqual(first, second)
            self.assertRegex(first, r"^[0-9a-f]{64}$")
            (app / "Info.plist").write_bytes(b"changed-plist-subject")
            self.assertNotEqual(guard.digest_app(app), first)

    def test_symlinked_bundle_entry_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-signed-app-guard-") as temporary:
            root = Path(temporary)
            app = self.make_app(root)
            target = root / "outside.txt"
            target.write_text("outside", encoding="utf-8")
            (app / "escape").symlink_to(target)
            with self.assertRaises(guard.InstallSubjectError):
                guard.digest_app(app)

    def test_guarded_install_accepts_unchanged_exact_subject(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-signed-app-guard-") as temporary:
            app = self.make_app(Path(temporary))
            expected = guard.digest_app(app)
            backend = FakeBackend()
            status = guard.guarded_install(
                app,
                expected,
                ["/usr/bin/true"],
                backend_factory=lambda: backend,
                popen_factory=lambda command: ImmediateProcess(command),
            )
            self.assertEqual(status, 0)
            self.assertGreater(backend.registered, 0)
            self.assertTrue(backend.closed)

    def test_guarded_install_rejects_subject_changed_before_admission(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-signed-app-guard-") as temporary:
            app = self.make_app(Path(temporary))
            expected = guard.digest_app(app)
            (app / "Info.plist").write_bytes(b"substituted")
            with self.assertRaisesRegex(guard.InstallSubjectError, "changed after field-authority verification"):
                guard.guarded_install(
                    app,
                    expected,
                    ["/usr/bin/true"],
                    backend_factory=FakeBackend,
                    popen_factory=lambda command: ImmediateProcess(command),
                )

    def test_guarded_install_rejects_vnode_event_during_consumer_window(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-signed-app-guard-") as temporary:
            app = self.make_app(Path(temporary))
            expected = guard.digest_app(app)
            # First events(0) call is the pre-child queue drain; second call is
            # while the fake consumer remains live.
            backend = FakeBackend([[], [object()]])
            with self.assertRaisesRegex(guard.InstallSubjectError, "while devicectl was consuming"):
                guard.guarded_install(
                    app,
                    expected,
                    ["/usr/bin/false"],
                    backend_factory=lambda: backend,
                    popen_factory=lambda command: OneTickProcess(command),
                )
            self.assertTrue(backend.closed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
