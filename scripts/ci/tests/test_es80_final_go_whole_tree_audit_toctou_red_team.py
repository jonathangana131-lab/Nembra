#!/usr/bin/env python3
"""Expected-red witness for Final-GO whole-tree candidate audit atomicity.

The selected Final-GO implementation descriptor-binds each tracked payload while reading it, but
`_audit_candidate_tree` verifies tracked subjects sequentially and later performs only a raw
name/type inventory. Once one tracked file has returned from `_physical_blob_oid`, no whole-tree
custody or final content reproof keeps that already-admitted file bound until the audit returns.

This diagnostic mutates the exact tracked pathname *after* its descriptor read and namespace reproof
have completed but before `_audit_candidate_tree` can finish. The replacement keeps the same name,
regular-file type, and executable shape, so the final raw walk sees no extra path. A successful test
means the attacked Final-GO parent can return an accepted tree while its physical tracked bytes have
already diverged.

No credentials, Xcode, device, Bluetooth, Tuya traffic, install, launch, or physical action occurs.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_whole_tree_toctou_subject", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current Final-GO subject")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoWholeTreeAuditToctouRedTeamTests(unittest.TestCase):
    def _candidate(self, root: Path) -> tuple[str, Path]:
        subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
        subprocess.run(
            ["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"],
            check=True,
        )
        subprocess.run(
            ["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"],
            check=True,
        )
        tracked = root / "A.swift"
        tracked.write_text("// exact accepted Final-GO bytes\n", encoding="utf-8")
        tracked.chmod(0o644)
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "A.swift"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted candidate"], check=True)
        source = subprocess.check_output(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"],
            text=True,
        ).strip().lower()

        # These are explicitly allowed field inputs and must exist for the real production audit.
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

    def test_control_rejects_tracked_mutation_that_exists_before_audit(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-whole-tree-control-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            tracked.write_text("// attacker bytes before audit\n", encoding="utf-8")
            tracked.chmod(0o644)
            with self.assertRaisesRegex(RuntimeError, "physical tracked bytes differ"):
                MODULE._audit_candidate_tree(root, source)

    def test_post_subject_mutation_is_accepted_before_whole_audit_returns(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-whole-tree-race-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)

            accepted_entries = MODULE._tree_entries(root, source)
            self.assertEqual(set(accepted_entries), {"A.swift"})
            accepted_mode, accepted_oid = accepted_entries["A.swift"]
            self.assertEqual(accepted_mode, b"100644")
            self.assertEqual(
                MODULE._physical_blob_oid(root, "A.swift", accepted_mode, accepted_oid),
                accepted_oid,
                "control candidate did not begin on exact accepted physical bytes",
            )

            attacker = sandbox / "attacker-replacement.swift"
            attacker.write_text("// attacker replacement after per-file reproof\n", encoding="utf-8")
            attacker.chmod(0o644)
            mutation_count = 0
            original = MODULE._physical_blob_oid

            def mutate_after_admitted_read(
                current_root: Path,
                relative: str,
                mode: bytes,
                expected_oid: str,
            ) -> str:
                nonlocal mutation_count
                result = original(current_root, relative, mode, expected_oid)
                if relative == "A.swift" and mutation_count == 0:
                    # The production descriptor read, stable-stat checks, and final pathname rebind
                    # have all completed at this point. Replace only after that subject was admitted.
                    os.replace(attacker, tracked)
                    tracked.chmod(0o644)
                    mutation_count += 1
                return result

            MODULE._physical_blob_oid = mutate_after_admitted_read
            try:
                result_entries = MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original

            self.assertEqual(mutation_count, 1, "deterministic post-admission mutation seam did not fire")
            self.assertEqual(result_entries["A.swift"], (accepted_mode, accepted_oid))
            self.assertTrue(tracked.is_file())
            self.assertFalse(tracked.is_symlink())
            self.assertEqual(stat.S_IMODE(tracked.stat().st_mode), 0o644)

            current_oid = original(root, "A.swift", accepted_mode, accepted_oid)
            self.assertNotEqual(
                current_oid,
                accepted_oid,
                "attack did not leave divergent physical tracked bytes after Final-GO returned success",
            )
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
                ).strip().lower(),
                source,
                "attack changed accepted Git commit identity instead of only the physical candidate",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
