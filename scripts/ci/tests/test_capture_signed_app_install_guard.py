#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import types
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/capture_signed_app_install_guard.py"

spec = importlib.util.spec_from_file_location("capture_signed_app_install_guard", HELPER)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FakeEvent:
    def __init__(self, ident: int = -1, fflags: int = 1) -> None:
        self.ident = ident
        self.fflags = fflags


class FakeBackend:
    def __init__(self, event_batches: list[list[FakeEvent]] | None = None) -> None:
        self.registered: list[int] = []
        self.event_batches = list(event_batches or [])
        self.closed = False

    def register(self, descriptor: int) -> None:
        self.registered.append(descriptor)

    def events(self, timeout: float):
        if self.event_batches:
            return self.event_batches.pop(0)
        return []

    def close(self) -> None:
        self.closed = True


class FakeProcess:
    def __init__(self, polls_before_exit: int = 1, returncode: int = 0) -> None:
        self.remaining = polls_before_exit
        self.final_returncode = returncode
        self.returncode = None
        self.terminated = False
        self.killed = False

    def poll(self):
        if self.returncode is not None:
            return self.returncode
        if self.remaining > 0:
            self.remaining -= 1
            return None
        self.returncode = self.final_returncode
        return self.returncode

    def terminate(self) -> None:
        self.terminated = True
        self.returncode = -15

    def kill(self) -> None:
        self.killed = True
        self.returncode = -9

    def wait(self, timeout=None):
        if self.returncode is None:
            self.returncode = self.final_returncode
        return self.returncode


class CaptureSignedAppInstallGuardTests(unittest.TestCase):
    def make_app(self) -> tuple[tempfile.TemporaryDirectory[str], Path]:
        temporary = tempfile.TemporaryDirectory(prefix="nembra-install-guard-")
        app = Path(temporary.name) / "Derived/Build/Products/Debug-iphoneos/Nembra Capture.app"
        (app / "Frameworks/Thing.framework").mkdir(parents=True)
        (app / "Info.plist").write_bytes(b"plist-subject")
        (app / "Nembra Capture").write_bytes(b"signed-executable")
        (app / "Frameworks/Thing.framework/Thing").write_bytes(b"framework-bytes")
        return temporary, app

    def test_subject_is_deterministic_and_changes_with_bytes(self) -> None:
        temporary, app = self.make_app()
        with temporary:
            first = module.bundle_subject(app)
            second = module.bundle_subject(app)
            self.assertEqual(first, second)
            self.assertRegex(first, r"^[0-9a-f]{64}$")
            (app / "Nembra Capture").write_bytes(b"different-executable")
            self.assertNotEqual(module.bundle_subject(app), first)

    def test_watch_set_includes_parent_root_nested_directories_and_files(self) -> None:
        temporary, app = self.make_app()
        with temporary:
            watched = set(module.watch_paths(app))
            self.assertIn(app.parent, watched, "parent vnode must catch app-root swap/restore")
            self.assertIn(app, watched)
            self.assertIn(app / "Info.plist", watched)
            self.assertIn(app / "Frameworks", watched)
            self.assertIn(app / "Frameworks/Thing.framework/Thing", watched)

    def test_unchanged_subject_allows_child_result(self) -> None:
        temporary, app = self.make_app()
        with temporary:
            backend = FakeBackend()
            process = FakeProcess(polls_before_exit=1, returncode=0)
            result = module.run_guarded_command(
                app,
                ["fake-verify-install"],
                backend_factory=lambda: backend,
                popen_factory=lambda command: process,
                poll_interval=0,
            )
            self.assertEqual(result, 0)
            self.assertTrue(backend.closed)
            self.assertGreater(len(backend.registered), 4)

    def test_nonrestored_mutation_fails_even_when_event_backend_is_silent(self) -> None:
        temporary, app = self.make_app()
        with temporary:
            backend = FakeBackend()
            process = FakeProcess(polls_before_exit=0, returncode=0)

            def launch(command):
                (app / "Info.plist").write_bytes(b"mutated-after-arming")
                return process

            with self.assertRaisesRegex(module.InstallGuardError, "changed across"):
                module.run_guarded_command(
                    app,
                    ["fake-verify-install"],
                    backend_factory=lambda: backend,
                    popen_factory=launch,
                    poll_interval=0,
                )

    def test_swap_restore_event_fails_and_stops_running_child(self) -> None:
        temporary, app = self.make_app()
        with temporary:
            original = (app / "Info.plist").read_bytes()
            # First events(0) is the pre-admission drain. The second call is the
            # running-window poll and represents a kqueue vnode mutation event.
            backend = FakeBackend(event_batches=[[], [FakeEvent()]])
            process = FakeProcess(polls_before_exit=5, returncode=0)

            def launch(command):
                target = app / "Info.plist"
                target.write_bytes(b"substituted")
                target.write_bytes(original)
                return process

            with self.assertRaisesRegex(module.InstallGuardError, "during verification/install"):
                module.run_guarded_command(
                    app,
                    ["fake-verify-install"],
                    backend_factory=lambda: backend,
                    popen_factory=launch,
                    poll_interval=0,
                )
            self.assertTrue(process.terminated)
            self.assertEqual((app / "Info.plist").read_bytes(), original)

    def test_queued_mutation_before_child_start_fails_closed(self) -> None:
        temporary, app = self.make_app()
        with temporary:
            backend = FakeBackend(event_batches=[[FakeEvent()]])
            launched = False

            def launch(command):
                nonlocal launched
                launched = True
                return FakeProcess()

            with self.assertRaisesRegex(module.InstallGuardError, "before verification/install admission"):
                module.run_guarded_command(
                    app,
                    ["fake-verify-install"],
                    backend_factory=lambda: backend,
                    popen_factory=launch,
                    poll_interval=0,
                )
            self.assertFalse(launched)


if __name__ == "__main__":
    unittest.main(verbosity=2)
