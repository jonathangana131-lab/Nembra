#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_hardened.py"
spec = importlib.util.spec_from_file_location("hardened", MODULE_PATH)
hardened = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(hardened)


class HardenedFinalGoGitCustodyTests(unittest.TestCase):
    def test_workflow_blob_lookup_does_not_trust_caller_path_git(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_git = fake_bin / "git"
            fake_git.write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' '{hardened.trusted_xcode.TRUSTED_WORKFLOW_BLOB_SHA}'\n",
                encoding="utf-8",
            )
            fake_git.chmod(fake_git.stat().st_mode | stat.S_IXUSR)
            tooling_repo = root / "tooling-repo"
            tooling_repo.mkdir()
            with mock.patch.dict(os.environ, {"PATH": str(fake_bin)}, clear=False):
                with self.assertRaises(hardened.FinalGoError):
                    hardened._workflow_blob_sha_at_commit(
                        tooling_repo,
                        "c" * 40,
                        hardened.trusted_xcode.TRUSTED_WORKFLOW_PATH,
                    )


if __name__ == "__main__":
    unittest.main()
