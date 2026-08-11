#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "Scripts/capture_signed_app_install_guard.py"
spec = importlib.util.spec_from_file_location("capture_signed_app_install_guard", HELPER)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


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
    def __init__(self):
        self.calls = 0

    def events(self, timeout: float):
        self.calls += 1
        if self.calls == 2:
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
        (app / "Info.plist").write_text("plist-a\n", encoding="utf-8")
        (app / "Frameworks/Test.framework/Test").write_bytes(b"framework-a")
        return app

    def test_fingerprint_changes_when_signed_bundle_bytes_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = self.make_app(Path(temporary))
            before = module.fingerprint_bundle(app)
            (app / "Info.plist").write_text("plist-b\n", encoding="utf-8")
            after = module.fingerprint_bundle(app)
            self.assertNotEqual(before, after)

    def test_guard_rejects_preinstall_swap_before_child_runs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            app = self.make_app(Path(temporary))
            accepted = module.fingerprint_bundle(app)
            (app / "Info.plist").write_text("substituted\n", encoding="utf-8")
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
                    backend_factory=EventBackend,
                    popen_factory=lambda command: RunningOnceProcess(),
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
