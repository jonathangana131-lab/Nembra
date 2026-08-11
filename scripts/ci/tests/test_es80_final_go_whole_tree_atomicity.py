#!/usr/bin/env python3
"""Production-closure replay for #3024 Final-GO whole-tree TOCTOU."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "es80_authenticated_stationary_private_review_final_go_whole_tree.py"
)
SPEC = importlib.util.spec_from_file_location("nembra_final_go_whole_tree_atomic", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load whole-tree Final-GO successor")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoWholeTreeAtomicityTests(unittest.TestCase):
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
        subprocess.run(
            ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted candidate"],
            check=True,
        )
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

    def test_exact_parent_identity_is_pinned(self) -> None:
        self.assertEqual(
            MODULE.PARENT_COMMIT,
            "471cc025b332f4df8b43a98d709710aeb4e0698f",
        )
        self.assertEqual(
            MODULE.PARENT_BLOB,
            "48ce4bd8f933ae062eaaadd0d017d13c781a8c02",
        )
        self.assertEqual(
            MODULE._parent.__nembra_atomic_parent_commit__,
            MODULE.PARENT_COMMIT,
        )
        self.assertEqual(
            MODULE._parent.__nembra_atomic_parent_blob__,
            MODULE.PARENT_BLOB,
        )

    def test_clean_candidate_remains_accepted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-atomic-control-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, _tracked = self._candidate(root)
            entries = MODULE._audit_candidate_tree(root, source)
            self.assertEqual(set(entries), {"A.swift"})

    def test_post_subject_replacement_is_rejected_before_audit_returns(self) -> None:
        """Consume #3024 without removing its deterministic scheduling seam."""
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-atomic-race-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)

            accepted_entries = MODULE._tree_entries(root, source)
            accepted_mode, accepted_oid = accepted_entries["A.swift"]
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
                    os.replace(attacker, tracked)
                    tracked.chmod(0o644)
                    mutation_count += 1
                return result

            MODULE._physical_blob_oid = mutate_after_admitted_read
            try:
                with self.assertRaisesRegex(
                    RuntimeError,
                    r"whole-tree mutation|whole-tree subject identity drifted",
                ):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original

            self.assertEqual(
                mutation_count,
                1,
                "the exact #3024 post-admission mutation seam did not fire",
            )
            self.assertTrue(tracked.is_file())
            self.assertFalse(tracked.is_symlink())
            self.assertEqual(stat.S_IMODE(tracked.stat().st_mode), 0o644)
            self.assertNotEqual(
                original(root, "A.swift", accepted_mode, accepted_oid),
                accepted_oid,
                "attack did not leave divergent physical bytes",
            )

    def test_in_place_write_is_rejected(self) -> None:
        """Directory/file watchers must also catch same-inode byte mutation."""
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-atomic-write-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)

            mutation_count = 0
            original = MODULE._physical_blob_oid

            def write_after_admitted_read(
                current_root: Path,
                relative: str,
                mode: bytes,
                expected_oid: str,
            ) -> str:
                nonlocal mutation_count
                result = original(current_root, relative, mode, expected_oid)
                if relative == "A.swift" and mutation_count == 0:
                    with tracked.open("r+b") as stream:
                        stream.seek(0)
                        stream.write(b"// same-inode attacker mutation\n")
                        stream.truncate()
                        stream.flush()
                        os.fsync(stream.fileno())
                    mutation_count += 1
                return result

            MODULE._physical_blob_oid = write_after_admitted_read
            try:
                with self.assertRaisesRegex(
                    RuntimeError,
                    r"whole-tree mutation|whole-tree subject identity drifted",
                ):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original
            self.assertEqual(mutation_count, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
