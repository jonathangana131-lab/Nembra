#!/usr/bin/env python3
"""Expected-red regression for partial no-replace publisher success.

The production publisher creates the authoritative destination hard link before unlinking the staging
name. If that unlink fails, the publisher raises before `publish_record_no_replace` marks the
transaction published. A failed invocation must still retract or quarantine the authoritative GO
pathname.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_publication.py"
spec = importlib.util.spec_from_file_location("publication", MODULE_PATH)
publication = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(publication)


class FinalGoPartialPublisherRollbackTests(unittest.TestCase):
    def test_staging_unlink_failure_after_destination_link_retracts_go_path(self) -> None:
        raw = b'{"decision":"GO"}\n'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            real_unlink = Path.unlink
            injected = False

            def fail_first_staging_unlink(path: Path, *args, **kwargs):
                nonlocal injected
                if not injected and path.name.endswith(".staging"):
                    injected = True
                    raise OSError("simulated staging unlink failure after destination link")
                return real_unlink(path, *args, **kwargs)

            with mock.patch.object(Path, "unlink", autospec=True, side_effect=fail_first_staging_unlink):
                with self.assertRaisesRegex(
                    OSError,
                    "simulated staging unlink failure after destination link",
                ):
                    publication.publish_record_no_replace(output, raw)

            self.assertTrue(injected, "regression did not cross the destination-link boundary")
            self.assertFalse(
                output.exists() or output.is_symlink(),
                "failed Final GO invocation left the authoritative destination path behind",
            )
            self.assertEqual(list(root.glob(".FinalGO.json.*.staging")), [])


if __name__ == "__main__":
    unittest.main()
