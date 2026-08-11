#!/usr/bin/env python3
"""Production regression for CocoaPods generated-subject metadata custody.

The accepted generated subject hashes mode bits. The field build guard therefore
must subscribe to vnode attribute changes while xcodebuild is consuming that
subject; final re-hashing alone cannot detect a chmod mutate/restore window.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD_PATH = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"


def load_guard():
    spec = importlib.util.spec_from_file_location("capture_vnode_attribute_guard_under_test", GUARD_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Capture build guard")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


guard = load_guard()


class FakeQueue:
    def __init__(self) -> None:
        self.registrations: list[object] = []
        self.closed = False

    def control(self, changes, max_events: int, timeout: float):
        if changes:
            self.registrations.extend(changes)
        return []

    def close(self) -> None:
        self.closed = True


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
        return SimpleNamespace(
            ident=descriptor,
            filter=filter,
            flags=flags,
            fflags=fflags,
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

            before = guard.generated_subject.subject_digest(
                lockfile=lockfile,
                pods=pods,
                workspace=workspace,
            )
            script.chmod(0o700)
            after = guard.generated_subject.subject_digest(
                lockfile=lockfile,
                pods=pods,
                workspace=workspace,
            )

            self.assertNotEqual(
                before,
                after,
                "mode changes must materially change generated-subject authority",
            )

    def test_kqueue_subscription_includes_attribute_mutations(self) -> None:
        fake_select = FakeSelect()
        with mock.patch.object(guard, "select", fake_select):
            backend = guard.KqueueVnodeBackend()
            try:
                backend.register(123)
                self.assertEqual(len(fake_select.queue.registrations), 1)
                event = fake_select.queue.registrations[0]
                self.assertNotEqual(
                    event.fflags & fake_select.KQ_NOTE_ATTRIB,
                    0,
                    "field-build vnode custody must subscribe to KQ_NOTE_ATTRIB because mode bits belong to the accepted subject",
                )
            finally:
                backend.close()

    @unittest.skipUnless(sys.platform == "darwin", "real vnode attribute evidence requires macOS kqueue")
    def test_real_kqueue_observes_chmod_of_admitted_generated_file(self) -> None:
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
                    ),
                    "real kqueue custody did not surface generated-file chmod as KQ_NOTE_ATTRIB",
                )
            finally:
                backend.close()
                os.close(descriptor)


if __name__ == "__main__":
    unittest.main(verbosity=2)
