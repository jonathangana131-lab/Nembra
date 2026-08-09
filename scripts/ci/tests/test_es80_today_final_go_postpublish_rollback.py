#!/usr/bin/env python3
"""Expected-red regression for Final GO publication after the rename boundary.

A failed invocation must not leave an authoritative-looking FinalGO.json whose bytes still say
`decision: GO`. This test deliberately fails the parent-directory fsync after the atomic rename.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"
spec = importlib.util.spec_from_file_location("final_go", MODULE_PATH)
final_go = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(final_go)


class FinalGoPostPublishRollbackTests(unittest.TestCase):
    def test_directory_fsync_failure_retracts_published_go_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            raw = b'{"decision":"GO"}\n'
            real_fsync = final_go.os.fsync
            fsync_calls = 0

            def fail_parent_directory_fsync(fd: int) -> None:
                nonlocal fsync_calls
                fsync_calls += 1
                if fsync_calls == 2:
                    raise OSError("simulated parent-directory fsync failure after rename")
                real_fsync(fd)

            with mock.patch.object(final_go.os, "fsync", side_effect=fail_parent_directory_fsync):
                with self.assertRaisesRegex(
                    OSError,
                    "simulated parent-directory fsync failure after rename",
                ):
                    final_go.publish_record_no_replace(output, raw)

            self.assertFalse(
                output.exists() or output.is_symlink(),
                "failed Final GO publication left an authoritative destination path behind",
            )
            self.assertEqual(list(root.glob(".FinalGO.json.*.staging")), [])


if __name__ == "__main__":
    unittest.main()
