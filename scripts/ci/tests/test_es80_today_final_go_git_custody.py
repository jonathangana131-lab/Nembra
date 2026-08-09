#!/usr/bin/env python3
"""Regression coverage for Final GO trusted-workflow Git custody.

The hardened Final GO entrypoint must not let caller PATH/Git semantics manufacture the Git blob
identity used to trust the default-branch Capture Xcode workflow. The lookup must stay behind the
foundation's producer-owned absolute Git executable, closed Git environment, replacement-object
ban, and real repository custody checks.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_hardened.py"
spec = importlib.util.spec_from_file_location("hardened_git_custody", MODULE_PATH)
hardened = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(hardened)


class FinalGoGitCustodyTests(unittest.TestCase):
    def test_caller_path_cannot_forge_trusted_workflow_blob(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            tooling = root / "not-a-git-repository"
            tooling.mkdir()

            fake_git = fake_bin / "git"
            fake_git.write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' '{hardened.trusted_xcode.TRUSTED_WORKFLOW_BLOB_SHA}'\n",
                encoding="utf-8",
            )
            fake_git.chmod(fake_git.stat().st_mode | stat.S_IXUSR)

            with mock.patch.dict(os.environ, {"PATH": str(fake_bin)}, clear=False):
                with self.assertRaises(hardened.FinalGoError):
                    hardened._workflow_blob_sha_at_commit(
                        tooling,
                        "b" * 40,
                        hardened.trusted_xcode.TRUSTED_WORKFLOW_PATH,
                    )

    def test_lookup_reuses_foundation_closed_git_boundary(self) -> None:
        tooling = Path("/tmp/nembra-tooling-subject")
        commit = "b" * 40
        path = hardened.trusted_xcode.TRUSTED_WORKFLOW_PATH
        expected = hardened.trusted_xcode.TRUSTED_WORKFLOW_BLOB_SHA

        with mock.patch.object(hardened.foundation, "_git", return_value=expected) as git_lookup:
            self.assertEqual(
                hardened._workflow_blob_sha_at_commit(tooling, commit, path),
                expected,
            )

        git_lookup.assert_called_once_with(
            tooling,
            "rev-parse",
            f"{commit}:{path}",
        )

    def test_real_git_replace_ref_cannot_forge_trusted_workflow_blob(self) -> None:
        """Prove the production lookup ignores replacement objects, not only that it delegates."""
        with tempfile.TemporaryDirectory() as temporary:
            tooling = Path(temporary) / "tooling"
            tooling.mkdir()

            def git(*arguments: str) -> str:
                return subprocess.check_output(
                    ["/usr/bin/git", "-C", str(tooling), *arguments],
                    text=True,
                    stderr=subprocess.DEVNULL,
                ).strip()

            subprocess.run(
                ["/usr/bin/git", "-C", str(tooling), "init", "-q"],
                check=True,
            )
            git("config", "user.email", "capture-v14@example.invalid")
            git("config", "user.name", "Capture V14 adversarial test")

            workflow_path = "trusted-workflow.yml"
            workflow = tooling / workflow_path
            workflow.write_text("trusted-default-workflow\n", encoding="utf-8")
            git("add", workflow_path)
            git("commit", "-q", "-m", "trusted workflow")
            trusted_commit = git("rev-parse", "HEAD")
            trusted_blob = git("rev-parse", f"{trusted_commit}:{workflow_path}")

            workflow.write_text("candidate-controlled-workflow\n", encoding="utf-8")
            git("add", workflow_path)
            git("commit", "-q", "-m", "untrusted workflow")
            untrusted_commit = git("rev-parse", "HEAD")
            untrusted_blob = git("rev-parse", f"{untrusted_commit}:{workflow_path}")
            self.assertNotEqual(trusted_blob, untrusted_blob)

            git("replace", untrusted_commit, trusted_commit)
            self.assertEqual(
                git("rev-parse", f"{untrusted_commit}:{workflow_path}"),
                trusted_blob,
                "attack setup must prove ordinary git rev-parse follows refs/replace",
            )

            resolved = hardened._workflow_blob_sha_at_commit(
                tooling,
                untrusted_commit,
                workflow_path,
            )
            self.assertEqual(resolved, untrusted_blob)
            self.assertNotEqual(resolved, trusted_blob)


if __name__ == "__main__":
    unittest.main()
