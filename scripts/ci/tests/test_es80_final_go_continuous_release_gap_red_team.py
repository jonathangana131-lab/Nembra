#!/usr/bin/env python3
"""Expected-red: a final watcher drain still has a release gap before close.

The attacked #3042 successor correctly adds a trailing event drain after its
identity reproof. This witness schedules the mutation *after that final real
kernel drain has returned* but before custody closes. If the context can then
return while the physical tracked file is divergent, event observation alone
is not an atomic authority handoff.
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
SUBJECT = ROOT / "scripts" / "ci" / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_3042_release_gap", SUBJECT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current continuous Final-GO subject")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ContinuousFinalGoReleaseGapRedTeamTests(unittest.TestCase):
    def _candidate(self, root: Path) -> tuple[str, Path]:
        subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Red Team"], check=True)
        tracked = root / "A.swift"
        tracked.write_text("let a = 1\n", encoding="utf-8")
        tracked.chmod(0o644)
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "A.swift"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "fixture"], check=True)
        source = subprocess.check_output(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
        ).strip().lower()
        return source, tracked

    @staticmethod
    def _replace(path: Path, payload: str, scratch: Path) -> None:
        replacement = scratch / ".release-gap-replacement"
        replacement.write_text(payload, encoding="utf-8")
        replacement.chmod(0o644)
        os.replace(replacement, path)
        path.chmod(0o644)

    def test_mutation_after_final_real_event_drain_escapes_close(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-3042-release-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            attacker = "let a = 909\n"

            custody = MODULE._TrackedTreeCustody(root, source)
            custody.arm()
            real_events = custody.backend.events
            calls = 0
            fired = False

            def raced_events(timeout: float):
                nonlocal calls, fired
                result = real_events(timeout)
                calls += 1
                # prove_quiet() does exactly two event observations: one before
                # identity reproof and one after it. Mutate only after the
                # *second real drain* has returned its pre-mutation result.
                if calls == 2 and not fired:
                    self._replace(tracked, attacker, sandbox)
                    fired = True
                return result

            custody.backend.events = raced_events  # type: ignore[method-assign]
            try:
                # Current production is expected to return from this final
                # point-in-time quiet proof even though the mutation lands after
                # its last observation. Closing then discards the queued event.
                custody.prove_quiet("Final-GO authority completion")
            finally:
                custody.close()

            self.assertTrue(fired, "release-gap scheduling seam did not fire after final event drain")
            self.assertEqual(calls, 2, "production quiet proof changed its expected observation shape")
            self.assertEqual(
                tracked.read_text(encoding="utf-8"),
                attacker,
                "attack did not leave the physical tracked subject divergent at custody release",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
