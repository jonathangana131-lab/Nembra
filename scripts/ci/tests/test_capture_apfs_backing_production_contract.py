#!/usr/bin/env python3
"""Expected-red contract for compiler-output sparse-image backing-file custody.

#3317 retained exploit-positive real-macOS evidence that ambient umask 000 can
materialize the root-created APFS backing file as root:<build_gid> 0666, allowing
the dedicated build identity to append to the backing image directly. Production
must prevent a transient permissive creation window and explicitly establish a
root-only backing-file subject before the first attach.
"""

from __future__ import annotations

import ast
from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
PRODUCTION = REPOSITORY / "scripts/ci/capture_signed_app_build_origin_custody.py"


def _function_source(module_source: str, name: str) -> str:
    tree = ast.parse(module_source)
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name:
            segment = ast.get_source_segment(module_source, node)
            if segment is None:
                break
            return segment
    raise AssertionError(f"production helper does not define {name}")


class CaptureAPFSBackingProductionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = PRODUCTION.read_text(encoding="utf-8")

    def test_creation_closes_ambient_umask_write_window(self) -> None:
        create_source = _function_source(self.source, "_create_apfs_image")
        self.assertIn(
            "os.umask(0o077)",
            create_source,
            "APFS backing creation still inherits ambient root umask instead of forcing a private creation mask",
        )
        self.assertGreaterEqual(
            create_source.count("os.umask("),
            2,
            "APFS backing creation does not visibly restore the caller's prior umask after hdiutil returns",
        )
        self.assertIn(
            "finally:",
            create_source,
            "APFS backing creation must restore the previous umask on success and failure",
        )

    def test_root_only_backing_seal_precedes_first_attach(self) -> None:
        seal_source = _function_source(self.source, "_seal_apfs_backing_file")
        required = (
            ".lstat()",
            "stat.S_ISREG",
            "stat.S_ISLNK",
            '"/bin/chmod"',
            '"-N"',
            "os.chown(",
            "0, 0",
            "os.chmod(",
            "0o600",
            "st_uid",
            "st_gid",
            "stat.S_IMODE",
        )
        for marker in required:
            self.assertIn(marker, seal_source, f"backing-file seal is missing invariant: {marker}")

        run_source = _function_source(self.source, "run_custodied_build")
        create_index = run_source.index("_create_apfs_image(image)")
        seal_index = run_source.index("_seal_apfs_backing_file(image)")
        attach_index = run_source.index("_attach_apfs(image, mountpoint, readonly=False)")
        self.assertLess(create_index, seal_index)
        self.assertLess(
            seal_index,
            attach_index,
            "root-only backing-file seal must complete before the writable APFS image is attached",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
