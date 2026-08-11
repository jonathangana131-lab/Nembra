#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD_PATH = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"
SPEC = importlib.util.spec_from_file_location("capture_vnode_attrib_guard", GUARD_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Capture build guard")
GUARD = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = GUARD
SPEC.loader.exec_module(GUARD)


class FakeQueue:
    def __init__(self) -> None:
        self.registrations: list[object] = []

    def control(self, changes, max_events: int, timeout: float):
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


class VnodeAttributeCustodyTests(unittest.TestCase):
    def test_kqueue_subscription_includes_attribute_mutations(self) -> None:
        fake_select = FakeSelect()
        with mock.patch.object(GUARD, "select", fake_select):
            backend = GUARD.KqueueVnodeBackend()
            try:
                backend.register(123)
                self.assertEqual(len(fake_select.queue.registrations), 1)
                event = fake_select.queue.registrations[0]
                self.assertNotEqual(
                    event.fflags & fake_select.KQ_NOTE_ATTRIB,
                    0,
                    "accepted generated mode bits require KQ_NOTE_ATTRIB custody during xcodebuild",
                )
            finally:
                backend.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
