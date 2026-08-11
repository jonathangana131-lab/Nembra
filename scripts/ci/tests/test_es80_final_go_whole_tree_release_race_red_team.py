#!/usr/bin/env python3
"""Expected-red witness for the whole-tree guard release race.

SUCCESS on the attacked production head means the guard can drain its kernel
event queue, re-prove one tracked subject, then accept a mutation that lands
after that subject's final lstat but before watcher teardown.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / "scripts" / "ci" / "es80_authenticated_stationary_private_review_whole_tree_final_go.py"


def load_module():
    spec = importlib.util.spec_from_file_location("nembra_whole_tree_release_race_redteam", MODULE)
    if spec is None or spec.loader is None:
        raise RuntimeError("whole-tree Final-GO successor import unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(spec.name, None)
        raise
    return module


class WholeTreeReleaseRaceRedTeamTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-final-go-release-race-")
        self.repo = Path(self.temporary.name)
        subprocess.run(["/usr/bin/git", "init", "-q", str(self.repo)], check=True)
        subprocess.run(
            ["/usr/bin/git", "-C", str(self.repo), "config", "user.email", "nembra@example.invalid"],
            check=True,
        )
        subprocess.run(
            ["/usr/bin/git", "-C", str(self.repo), "config", "user.name", "Nembra Red Team"],
            check=True,
        )
        self.a = self.repo / "A.swift"
        self.b = self.repo / "B.swift"
        self.a.write_text("let a = 1\n", encoding="utf-8")
        self.b.write_text("let b = 2\n", encoding="utf-8")
        subprocess.run(
            ["/usr/bin/git", "-C", str(self.repo), "add", "A.swift", "B.swift"],
            check=True,
        )
        subprocess.run(
            ["/usr/bin/git", "-C", str(self.repo), "commit", "-qm", "fixture"],
            check=True,
        )
        self.source = subprocess.run(
            ["/usr/bin/git", "-C", str(self.repo), "rev-parse", "HEAD"],
            text=True,
            check=True,
            capture_output=True,
        ).stdout.strip()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _replace_a(self, text: str) -> None:
        replacement = self.repo / ".A.swift.release-race"
        replacement.write_text(text, encoding="utf-8")
        replacement.chmod(0o644)
        os.replace(replacement, self.a)

    def test_mutation_after_final_subject_lstat_escapes_watcher_teardown(self) -> None:
        entries = self.module._entries_for_guard(self.repo, self.source)
        guard = self.module._WholeTreeMutationGuard(self.repo, entries)
        attacker = "let a = 909\n"
        real_lstat = self.module.os.lstat
        fired = False

        # Arm cleanly first. Only after the context body is complete do we install
        # the scheduling seam used by __exit__'s final acceptance reproof.
        with guard:
            def raced_lstat(path, *args, **kwargs):
                nonlocal fired
                metadata = real_lstat(path, *args, **kwargs)
                try:
                    attacked = Path(path) == self.a
                except TypeError:
                    attacked = False
                if attacked and not fired:
                    fired = True
                    # assert_clean() has already drained backend.events() for this
                    # pass. Return the accepted A.swift metadata after placing a
                    # real replacement, so the queued CREATE/MOVE/leaf events land
                    # after the only event drain and are discarded on close().
                    self._replace_a(attacker)
                return metadata

            self.module.os.lstat = raced_lstat

        self.module.os.lstat = real_lstat
        self.assertTrue(fired, "release-race scheduling seam never reached A.swift final lstat")
        self.assertEqual(
            self.a.read_text(encoding="utf-8"),
            attacker,
            "attacker replacement was not the physical tracked subject at guard return",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
