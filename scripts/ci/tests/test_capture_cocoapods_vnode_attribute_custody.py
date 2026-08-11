#!/usr/bin/env python3
"""Acceptance evidence for compiler-window vnode attribute custody."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import resource
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD_PATH = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"


def load_guard():
    name = "nembra_capture_vnode_attribute_current"
    spec = importlib.util.spec_from_file_location(name, GUARD_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Capture build guard")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


guard = load_guard()


class FakeQueue:
    def __init__(self) -> None:
        self.registrations: list[object] = []

    def control(self, changes, max_events: int, timeout: float):
        del max_events, timeout
        if changes:
            self.registrations.extend(changes)
        return []

    def close(self) -> None:
        pass


class FakeSelect:
    KQ_FILTER_VNODE = -4
    KQ_EV_ADD = 0x0001
    KQ_EV_ENABLE = 0x0004
    KQ_EV_CLEAR = 0x0020
    KQ_NOTE_DELETE = 0x0001
    KQ_NOTE_WRITE = 0x0002
    KQ_NOTE_EXTEND = 0x0004
    KQ_NOTE_ATTRIB = 0x0008
    KQ_NOTE_LINK = 0x0010
    KQ_NOTE_RENAME = 0x0020
    KQ_NOTE_REVOKE = 0x0040

    def __init__(self) -> None:
        self.queue = FakeQueue()

    def kqueue(self):
        return self.queue

    def kevent(self, descriptor: int, *, filter: int, flags: int, fflags: int):
        return SimpleNamespace(ident=descriptor, filter=filter, flags=flags, fflags=fflags)


class QuietBackend:
    def register(self, descriptor: int) -> None:
        del descriptor

    def events(self, timeout: float):
        del timeout
        return []

    def close(self) -> None:
        pass


def make_field_inputs(root: Path, *, generated_file_count: int = 0):
    lockfile = root / "Podfile.lock"
    pods = root / "Pods"
    workspace = root / "NembraCapture.xcworkspace"
    lockfile.write_text("LOCK\n", encoding="utf-8")
    pods.mkdir()
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")

    generated = pods / "Generated"
    generated.mkdir()
    for index in range(generated_file_count):
        (generated / f"input-{index:04d}.xcconfig").write_text(
            f"SETTING_{index} = {index}\n", encoding="utf-8"
        )

    security_build = root / "LocalSecrets/TuyaSDK/Build"
    security_build.mkdir(parents=True)
    security_podspec = root / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"
    security_podspec.write_text("security\n", encoding="utf-8")
    (security_build / "libThingSmartCryption.a").write_bytes(b"private-security-sdk")

    identity_sources = root / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"
    identity_sources.mkdir(parents=True)
    identity_podspec = root / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"
    identity_podspec.write_text("identity\n", encoding="utf-8")
    (identity_sources / "Identity.swift").write_text("private identity\n", encoding="utf-8")

    # Current field custody watches the external provenance witness and review key
    # even when this portable budget test does not request accepted-authority
    # verification. They must therefore exist as admitted paths in the fixture.
    (identity_podspec.parent / "ResolvedTuyaDependencyProvenance.txt").write_text(
        "fixture-witness\n", encoding="utf-8"
    )
    (identity_podspec.parent / "PrivateReviewCommitment.key").write_text(
        "fixture-key\n", encoding="utf-8"
    )

    return guard.PrivateInputs(
        lockfile=lockfile,
        security_podspec=security_podspec,
        security_build=security_build,
        identity_podspec=identity_podspec,
        identity_sources=identity_sources,
        generated_pods=pods,
        generated_workspace=workspace,
    )


class CocoaPodsVnodeAttributeCustodyTests(unittest.TestCase):
    def test_generated_subject_digest_treats_mode_as_authority(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-vnode-attrib-subject-") as temporary:
            root = Path(temporary)
            lockfile = root / "Podfile.lock"
            pods = root / "Pods"
            workspace = root / "NembraCapture.xcworkspace"
            lockfile.write_text("LOCK\n", encoding="utf-8")
            pods.mkdir()
            workspace.mkdir()
            script = pods / "build-phase.sh"
            script.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            (workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")
            script.chmod(0o600)
            before = guard.generated_build.build_subject(lockfile=lockfile, pods=pods, workspace=workspace)
            script.chmod(0o700)
            after = guard.generated_build.build_subject(lockfile=lockfile, pods=pods, workspace=workspace)
            self.assertNotEqual(before, after)

    def test_kqueue_subscription_includes_attribute_mutations(self) -> None:
        fake_select = FakeSelect()
        with mock.patch.object(guard, "select", fake_select):
            backend = guard.KqueueVnodeBackend()
            try:
                backend.register(123)
                self.assertEqual(len(fake_select.queue.registrations), 1)
                event = fake_select.queue.registrations[0]
                self.assertNotEqual(event.fflags & fake_select.KQ_NOTE_ATTRIB, 0)
            finally:
                backend.close()

    def test_guard_expands_soft_descriptor_budget_for_realistic_generated_tree(self) -> None:
        original_soft, original_hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        low_soft = 48 if original_soft == resource.RLIM_INFINITY else min(int(original_soft), 48)
        if low_soft < 32:
            self.skipTest("host soft descriptor limit is already too small for safe harness")
        if original_hard != resource.RLIM_INFINITY and int(original_hard) < 192:
            self.skipTest("host hard descriptor limit cannot exercise soft-limit expansion")

        with tempfile.TemporaryDirectory(prefix="nembra-vnode-fd-budget-") as temporary:
            root = Path(temporary)
            inputs = make_field_inputs(root, generated_file_count=96)
            resource.setrlimit(resource.RLIMIT_NOFILE, (low_soft, original_hard))
            try:
                result = guard.run_guarded_build(
                    inputs,
                    [sys.executable, "-c", "raise SystemExit(0)"],
                    backend_factory=QuietBackend,
                    poll_interval=0.001,
                )
                self.assertEqual(result, 0)
                raised_soft, _ = resource.getrlimit(resource.RLIMIT_NOFILE)
                self.assertGreater(raised_soft, low_soft)
            finally:
                resource.setrlimit(resource.RLIMIT_NOFILE, (original_soft, original_hard))

    @unittest.skipUnless(sys.platform == "darwin", "real vnode attribute evidence requires macOS kqueue")
    def test_real_kqueue_observes_chmod_of_admitted_file(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-vnode-attrib-kqueue-") as temporary:
            path = Path(temporary) / "generated-build-phase.sh"
            path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            path.chmod(0o600)
            descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_CLOEXEC", 0))
            backend = guard.KqueueVnodeBackend()
            try:
                backend.register(descriptor)
                path.chmod(0o700)
                events = backend.events(1.0)
                self.assertTrue(
                    any(
                        int(getattr(event, "fflags", 0)) & guard.select.KQ_NOTE_ATTRIB
                        for event in events
                    )
                )
            finally:
                backend.close()
                os.close(descriptor)


if __name__ == "__main__":
    unittest.main(verbosity=2)
