#!/usr/bin/env python3
"""Expected-red witness for the continuous tracked-tree custody release edge.

SUCCESS on the attacked production head means the final kernel event drain can
return clean, a real tracked mutation can land immediately afterward, and the
context can then close its watcher without consuming that queued evidence.
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
MODULE = ROOT / "scripts" / "ci" / "es80_authenticated_stationary_private_review_final_go.py"


def load_module():
    spec = importlib.util.spec_from_file_location(
        "nembra_continuous_tree_release_race_redteam", MODULE
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("continuous tracked-tree Final-GO successor import unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(spec.name, None)
        raise
    return module


class ContinuousTreeReleaseRaceRedTeamTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self.temporary = tempfile.TemporaryDirectory(
            prefix="nembra-final-go-continuous-release-race-"
        )
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

    def test_mutation_after_final_event_drain_escapes_context_release(self) -> None:
        attacker = "let a = 909\n"
        fired = False
        observed_calls = 0

        with self.module._continuous_tracked_tree_custody(self.repo, self.source) as custody:
            real_events = custody.backend.events

            def raced_events(timeout: float):
                nonlocal fired, observed_calls
                events = real_events(timeout)
                observed_calls += 1
                # The wrapper is installed only after arm() has already completed,
                # so call 1 is the completion pre-reproof drain and call 2 is the
                # final post-reproof drain. Mutate only after the real final drain
                # returned clean; production has no later event read before close().
                if observed_calls == 2 and not events and not fired:
                    fired = True
                    self._replace_a(attacker)
                return events

            custody.backend.events = raced_events

        self.assertTrue(fired, "release-race scheduling seam never reached the final event drain")
        self.assertEqual(observed_calls, 2, "production performed an unexpected later event drain")
        self.assertEqual(
            self.a.read_text(encoding="utf-8"),
            attacker,
            "attacker replacement was not the physical tracked subject at custody return",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
