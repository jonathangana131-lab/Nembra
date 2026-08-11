#!/usr/bin/env python3
"""Current-head QA for parent-directory replacement during Final-GO payload reads."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_parent_directory_custody", PRIVATE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current Final-GO candidate authority")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoParentDirectoryReadCustodyTests(unittest.TestCase):
    def test_parent_namespace_swap_after_descriptor_walk_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-parent-directory-") as temporary:
            root = Path(temporary).resolve(strict=True)
            relative = "NembraApp/App/Capture.swift"
            accepted_root = root / "NembraApp"
            accepted_path = accepted_root / "App/Capture.swift"
            escaped_root = root / "NembraApp.accepted"
            replacement_root = root / "Replacement"
            replacement_path = replacement_root / "App/Capture.swift"
            accepted_path.parent.mkdir(parents=True)
            replacement_path.parent.mkdir(parents=True)
            accepted_path.write_bytes(b"accepted-final-go-source\n")
            replacement_path.write_bytes(b"replacement-parent-source\n")
            accepted_path.chmod(0o644)
            replacement_path.chmod(0o644)

            original_stat = MODULE.os.stat
            replacement_fired = False

            def interpose_stat(subject, *args, **kwargs):
                nonlocal replacement_fired
                if (
                    subject == "Capture.swift"
                    and kwargs.get("dir_fd") is not None
                    and kwargs.get("follow_symlinks") is False
                    and not replacement_fired
                ):
                    replacement_fired = True
                    os.rename(accepted_root, escaped_root)
                    os.symlink("Replacement", accepted_root)
                return original_stat(subject, *args, **kwargs)

            MODULE.os.stat = interpose_stat
            try:
                with self.assertRaises(RuntimeError):
                    MODULE._read_physical_payload(root, relative, b"100644")
            finally:
                MODULE.os.stat = original_stat

            self.assertTrue(replacement_fired, "fixture did not reach post-ancestry final admission")
            self.assertEqual(
                (escaped_root / "App/Capture.swift").read_bytes(),
                b"accepted-final-go-source\n",
            )
            self.assertEqual((root / relative).read_bytes(), b"replacement-parent-source\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
