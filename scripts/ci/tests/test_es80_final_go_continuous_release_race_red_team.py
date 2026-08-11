#!/usr/bin/env python3
"""Expected-red witness for Final-GO continuous-custody watcher release.

SUCCESS on the attacked production head means its last kernel event poll can
return clean, then a tracked pathname can be replaced before watcher teardown
without any later observation or immutable authority handoff.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_continuous_release_redteam", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load continuous-custody Final-GO subject")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

ACCEPTED_BYTES = b"// exact accepted bytes\n"
ATTACKER_BYTES = b"// attacker bytes after final event poll\n"


class FinalGoContinuousReleaseRaceRedTeamTests(unittest.TestCase):
    def _candidate(self, root: Path) -> tuple[str, Path]:
        subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
        subprocess.run(
            ["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"],
            check=True,
        )
        subprocess.run(
            ["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Release Red Team"],
            check=True,
        )
        tracked = root / "A.swift"
        tracked.write_bytes(ACCEPTED_BYTES)
        tracked.chmod(0o644)
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "A.swift"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted candidate"], check=True)
        source = subprocess.check_output(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
        ).strip().lower()
        for relative in MODULE.FIELD_INPUT_DIRECTORIES:
            path = root / relative
            path.mkdir(parents=True, exist_ok=True)
            self.assertTrue(stat.S_ISDIR(path.lstat().st_mode))
        for relative in MODULE.FIELD_INPUT_FILES:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("PODS:\n", encoding="utf-8")
            path.chmod(0o600)
        return source, tracked

    @staticmethod
    def _replace(path: Path, payload: bytes, scratch: Path) -> None:
        replacement = scratch / "release-race-replacement.swift"
        replacement.write_bytes(payload)
        replacement.chmod(0o644)
        os.replace(replacement, path)
        path.chmod(0o644)

    def test_mutation_after_final_event_poll_escapes_custody_release(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-release-race-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            fired = False

            with MODULE._continuous_tracked_tree_custody(root, source) as custody:
                real_events = custody.backend.events
                calls = 0

                def raced_events(timeout: float):
                    nonlocal calls, fired
                    calls += 1
                    result = real_events(timeout)
                    if calls == 2 and not result and not fired:
                        # prove_quiet() has already completed its identity reproof;
                        # this is its final kernel-event observation before close().
                        # Queue a real replacement event only after that observation.
                        self._replace(tracked, ATTACKER_BYTES, sandbox)
                        fired = True
                    return result

                custody.backend.events = raced_events  # type: ignore[method-assign]

            self.assertTrue(fired, "final-poll release-race scheduling seam did not fire")
            self.assertEqual(
                tracked.read_bytes(),
                ATTACKER_BYTES,
                "attacker bytes were not physical at successful custody return",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
