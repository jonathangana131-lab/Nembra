#!/usr/bin/env python3
"""Regress authority-metadata mutation visibility in the current private-input guard."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import select
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD_PATH = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"


def load_guard():
    name = "nembra_capture_private_vnode_attrib_custody"
    spec = importlib.util.spec_from_file_location(name, GUARD_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load current Capture private-input guard")
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


class MissingAttribSelect:
    KQ_FILTER_VNODE = -4
    KQ_EV_ADD = 0x0001
    KQ_EV_ENABLE = 0x0004
    KQ_EV_CLEAR = 0x0020
    KQ_NOTE_DELETE = 0x0001
    KQ_NOTE_WRITE = 0x0002
    KQ_NOTE_EXTEND = 0x0004
    KQ_NOTE_LINK = 0x0010
    KQ_NOTE_RENAME = 0x0020
    KQ_NOTE_REVOKE = 0x0040

    def kqueue(self):
        return FakeQueue()

    def kevent(self, descriptor: int, *, filter: int, flags: int, fflags: int):
        return SimpleNamespace(ident=descriptor, filter=filter, flags=flags, fflags=fflags)


class CapturePrivateVnodeAttribCustodyTests(unittest.TestCase):
    def test_kqueue_capability_admission_requires_attribute_events(self) -> None:
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

    def test_missing_attribute_capability_fails_closed(self) -> None:
        with (
            mock.patch.object(guard, "select", MissingAttribSelect()),
            self.assertRaises(guard.BuildGuardError),
        ):
            guard.KqueueVnodeBackend()

    @unittest.skipUnless(sys.platform == "darwin", "real vnode attribute evidence requires macOS kqueue")
    def test_real_kqueue_observes_chmod_of_admitted_descriptor(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-vnode-attrib-") as temporary:
            path = Path(temporary) / "private-input.fixture"
            path.write_bytes(b"accepted-private-input\n")
            path.chmod(0o600)
            descriptor = os.open(
                path,
                os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0),
            )
            backend = guard.KqueueVnodeBackend()
            try:
                backend.register(descriptor)
                path.chmod(0o400)
                events = backend.events(1.0)
                self.assertTrue(
                    any(
                        int(getattr(event, "fflags", 0)) & select.KQ_NOTE_ATTRIB
                        for event in events
                    ),
                    "chmod changed authority metadata but produced no KQ_NOTE_ATTRIB evidence",
                )
            finally:
                backend.close()
                os.close(descriptor)


if __name__ == "__main__":
    unittest.main(verbosity=2)
