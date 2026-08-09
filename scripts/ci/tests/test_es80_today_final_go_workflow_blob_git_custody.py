#!/usr/bin/env python3
"""Expected-red guard for the trusted default-branch workflow Git-blob authority lookup."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_hardened.py"
spec = importlib.util.spec_from_file_location("hardened", MODULE_PATH)
hardened = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(hardened)


class TrustedWorkflowBlobGitCustodyTests(unittest.TestCase):
    def test_workflow_blob_lookup_uses_absolute_git_and_closed_environment(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            completed = mock.Mock(stdout=("e" * 40) + "\n")
            with mock.patch.object(
                hardened.subprocess,
                "run",
                return_value=completed,
            ) as run:
                value = hardened._workflow_blob_sha_at_commit(
                    repository,
                    "a" * 40,
                    ".github/workflows/capture-xcode27-trusted-command.yml",
                )

            self.assertEqual(value, "e" * 40)
            run.assert_called_once()
            args, kwargs = run.call_args
            command = args[0]
            self.assertEqual(
                command[0],
                "/usr/bin/git",
                "trusted workflow Git authority must not resolve an executable through caller PATH",
            )
            environment = kwargs.get("env")
            self.assertIsInstance(
                environment,
                dict,
                "trusted workflow Git authority must not inherit caller Git/process environment",
            )
            self.assertEqual(environment.get("PATH"), "/usr/bin:/bin:/usr/sbin:/sbin")
            self.assertEqual(environment.get("GIT_CONFIG_NOSYSTEM"), "1")
            self.assertEqual(environment.get("GIT_CONFIG_GLOBAL"), "/dev/null")
            self.assertEqual(environment.get("GIT_NO_REPLACE_OBJECTS"), "1")
            self.assertNotIn("GIT_OBJECT_DIRECTORY", environment)
            self.assertNotIn("GIT_ALTERNATE_OBJECT_DIRECTORIES", environment)


if __name__ == "__main__":
    unittest.main()
