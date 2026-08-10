#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "Scripts" / "capture_tuya_private_input_build_guard.py"
SPEC = importlib.util.spec_from_file_location("capture_tuya_private_input_build_guard", HELPER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load build-window guard")
guard = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = guard
SPEC.loader.exec_module(guard)


class FakeBackend:
    def __init__(self, *, emit_during_build: bool = False) -> None:
        self.emit_during_build = emit_during_build
        self.registered: list[int] = []
        self.emitted = False
        self.closed = False

    def register(self, descriptor: int) -> None:
        self.registered.append(descriptor)

    def events(self, timeout: float):
        if timeout > 0 and self.emit_during_build and not self.emitted:
            self.emitted = True
            return [SimpleNamespace(ident=self.registered[0], fflags=0x2)]
        return []

    def close(self) -> None:
        self.closed = True


class SuccessfulProcess:
    def __init__(self) -> None:
        self.returncode = None
        self.poll_count = 0

    def poll(self):
        self.poll_count += 1
        if self.poll_count >= 2:
            self.returncode = 0
        return self.returncode

    def terminate(self) -> None:
        self.returncode = -15

    def kill(self) -> None:
        self.returncode = -9

    def wait(self, timeout=None):
        if self.returncode is None:
            self.returncode = 0
        return self.returncode


class RunningProcess(SuccessfulProcess):
    def poll(self):
        return self.returncode


class CapturePrivateBuildWindowGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.lockfile = self.root / "Podfile.lock"
        self.security_podspec = self.root / "ThingSmartCryption.podspec"
        self.security_build = self.root / "SecurityBuild"
        self.identity_podspec = self.root / "NembraTuyaPrivateConfig.podspec"
        self.identity_sources = self.root / "IdentitySources"
        self.lockfile.write_text("LOCK\n", encoding="utf-8")
        self.security_podspec.write_text("Pod::Spec.new {}\n", encoding="utf-8")
        self.identity_podspec.write_text("Pod::Spec.new {}\n", encoding="utf-8")
        (self.security_build / "Nested").mkdir(parents=True)
        (self.security_build / "ThingSmartCryption.bin").write_bytes(b"security")
        (self.security_build / "Nested" / "resource.dat").write_bytes(b"resource")
        self.identity_sources.mkdir()
        (self.identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            "enum NembraTuyaPrivateIdentity {}\n", encoding="utf-8"
        )
        self.inputs = guard.PrivateInputs(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_watch_paths_cover_every_regular_file_and_directory(self) -> None:
        symlink = self.security_build / "resource-link"
        symlink.symlink_to(self.security_build / "Nested" / "resource.dat")
        paths = set(guard._watch_paths(self.inputs))
        self.assertIn(self.lockfile, paths)
        self.assertIn(self.security_podspec, paths)
        self.assertIn(self.identity_podspec, paths)
        self.assertIn(self.security_build, paths)
        self.assertIn(self.security_build / "Nested", paths)
        self.assertIn(self.security_build / "ThingSmartCryption.bin", paths)
        self.assertIn(self.security_build / "Nested" / "resource.dat", paths)
        self.assertIn(self.identity_sources, paths)
        self.assertIn(self.identity_sources / "NembraTuyaPrivateIdentity.swift", paths)
        self.assertNotIn(symlink, paths)

    def test_success_keeps_watchers_armed_through_final_generation(self) -> None:
        backend = FakeBackend()
        process = SuccessfulProcess()
        result = guard.run_guarded_build(
            self.inputs,
            ["/usr/bin/true"],
            backend_factory=lambda: backend,
            popen_factory=lambda command: process,
            poll_interval=0.0,
        )
        self.assertEqual(result, 0)
        self.assertTrue(backend.registered)
        self.assertTrue(backend.closed)

    def test_vnode_event_terminates_build_and_fails_closed(self) -> None:
        backend = FakeBackend(emit_during_build=True)
        process = RunningProcess()
        with self.assertRaisesRegex(guard.BuildGuardError, "mutation was observed while xcodebuild was running"):
            guard.run_guarded_build(
                self.inputs,
                ["xcodebuild", "build"],
                backend_factory=lambda: backend,
                popen_factory=lambda command: process,
                poll_interval=0.01,
            )
        self.assertEqual(process.returncode, -15)
        self.assertTrue(backend.closed)

    def test_generation_change_while_watches_arm_fails_before_child_start(self) -> None:
        backend = FakeBackend()
        original_snapshot = self.inputs.generation_snapshot
        calls = 0

        def changing_snapshot():
            nonlocal calls
            calls += 1
            snapshot = original_snapshot()
            if calls == 1:
                return snapshot
            self.security_build.joinpath("ThingSmartCryption.bin").write_bytes(b"changed")
            return original_snapshot()

        object.__setattr__(self.inputs, "generation_snapshot", changing_snapshot)
        started = False

        def should_not_start(command):
            nonlocal started
            started = True
            return SuccessfulProcess()

        with self.assertRaisesRegex(guard.BuildGuardError, "changed while build-window monitoring was armed"):
            guard.run_guarded_build(
                self.inputs,
                ["xcodebuild", "build"],
                backend_factory=lambda: backend,
                popen_factory=should_not_start,
                poll_interval=0.0,
            )
        self.assertFalse(started)

    def test_source_uses_write_membership_and_replacement_vnode_events(self) -> None:
        source = HELPER.read_text(encoding="utf-8")
        for token in (
            "KQ_FILTER_VNODE",
            "KQ_NOTE_WRITE",
            "KQ_NOTE_EXTEND",
            "KQ_NOTE_LINK",
            "KQ_NOTE_RENAME",
            "KQ_NOTE_DELETE",
            "KQ_NOTE_REVOKE",
            "armed_snapshot = inputs.generation_snapshot()",
            "final_snapshot = inputs.generation_snapshot()",
        ):
            self.assertIn(token, source)


if __name__ == "__main__":
    unittest.main()
