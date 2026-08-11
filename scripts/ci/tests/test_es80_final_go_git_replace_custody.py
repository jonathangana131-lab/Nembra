#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

TEST_MODULE = Path(__file__).with_name("test_es80_authenticated_stationary_final_go.py")
SPEC = importlib.util.spec_from_file_location("final_go_fixture", TEST_MODULE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Final-GO fixture")
fixture_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixture_module)
go = fixture_module.go
F = fixture_module.F


class FinalGoGitReplaceCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.fixture = F(Path(self.temporary.name))

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def git(self, *args: str, no_replace: bool = False) -> str:
        environment = os.environ.copy()
        if no_replace:
            environment["GIT_NO_REPLACE_OBJECTS"] = "1"
        return subprocess.check_output(
            ["/usr/bin/git", "-C", str(self.fixture.repo), *args],
            text=True,
            env=environment,
        ).strip()

    def run_git(self, *args: str, no_replace: bool = False) -> None:
        environment = os.environ.copy()
        if no_replace:
            environment["GIT_NO_REPLACE_OBJECTS"] = "1"
        subprocess.run(
            ["/usr/bin/git", "-C", str(self.fixture.repo), *args],
            check=True,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def test_candidate_rejects_replace_ref_that_redefines_accepted_tree(self) -> None:
        accepted_source = self.fixture.s
        installer = self.fixture.repo / go.INSTALLER
        accepted_bytes = installer.read_bytes()

        installer.write_text(
            installer.read_text()
            + "# attacker replacement that still preserves required source markers\n"
        )
        self.run_git("add", go.INSTALLER)
        self.run_git("commit", "-qm", "attacker replacement")
        attacker_source = self.git("rev-parse", "HEAD")
        attacker_blob = self.git("rev-parse", f"{attacker_source}:{go.INSTALLER}", no_replace=True)

        # Keep the public/declared source at the accepted commit while locally
        # replacing that commit's object traversal with the attacker commit.
        self.run_git("reset", "--hard", "-q", accepted_source, no_replace=True)
        self.run_git("replace", accepted_source, attacker_source, no_replace=True)

        # Align index/worktree to the replacement tree without moving HEAD.
        # Ordinary replacement-aware status is now clean even though the real
        # accepted commit A has different bytes.
        self.run_git("read-tree", attacker_source, no_replace=True)
        self.run_git("checkout-index", "-a", "-f", no_replace=True)

        self.assertEqual(self.git("rev-parse", "HEAD"), accepted_source)
        self.assertEqual(self.git("status", "--porcelain=v1", "--untracked-files=all"), "")
        self.assertNotEqual(
            self.git("status", "--porcelain=v1", "--untracked-files=all", no_replace=True),
            "",
        )
        self.assertNotEqual(installer.read_bytes(), accepted_bytes)
        self.assertEqual(
            self.git("rev-parse", f"{accepted_source}:{go.INSTALLER}"),
            attacker_blob,
        )
        self.assertNotEqual(
            self.git("rev-parse", f"{accepted_source}:{go.INSTALLER}", no_replace=True),
            attacker_blob,
        )
        self.assertEqual(
            self.git("hash-object", "--no-filters", "--", go.INSTALLER),
            attacker_blob,
        )

        # Production must bind authority to the true accepted object graph,
        # not to locally substituted replacement objects.
        with self.assertRaises(go.GoError):
            go.candidate(self.fixture.repo, accepted_source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
