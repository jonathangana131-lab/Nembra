#!/usr/bin/env python3
"""Production regression for Final-GO whole-tree mutation custody.

Consumes the authority classes demonstrated by expected-red #3024 and #3030.
The accepted successor must reject both one-shot post-admission replacement and
restore-before-every-read finite-rehash races without weakening the exact #2921
per-subject descriptor proof.
"""
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
    / "es80_authenticated_stationary_private_review_final_go_atomic.py"
)
SPEC = importlib.util.spec_from_file_location("nembra_final_go_whole_tree_custody", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load whole-tree Final-GO successor")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

ACCEPTED_BYTES = b"// exact accepted Final-GO bytes\n"
ATTACKER_BYTES = b"// attacker bytes after admitted read\n"


class FinalGoWholeTreeCustodyTests(unittest.TestCase):
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
    def _atomic_replace(path: Path, payload: bytes, scratch: Path, ordinal: int) -> None:
        replacement = scratch / f"replacement-{ordinal}.swift"
        replacement.write_bytes(payload)
        replacement.chmod(0o644)
        os.replace(replacement, path)
        path.chmod(0o644)

    def test_exact_parent_blob_and_successor_patch_are_selected(self) -> None:
        self.assertEqual(MODULE.PARENT_SOURCE, "471cc025b332f4df8b43a98d709710aeb4e0698f")
        self.assertEqual(MODULE.PARENT_MODULE_GIT_BLOB, "48ce4bd8f933ae062eaaadd0d017d13c781a8c02")
        self.assertIs(MODULE._parent._audit_candidate_tree, MODULE._audit_candidate_tree)

    def test_clean_candidate_remains_accepted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-custody-clean-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, _ = self._candidate(root)
            entries = MODULE._audit_candidate_tree(root, source)
            self.assertEqual(set(entries), {"A.swift"})

    def test_persistent_pre_audit_mutation_still_fails_parent_blob_proof(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-custody-control-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            tracked.write_bytes(ATTACKER_BYTES)
            tracked.chmod(0o644)
            with self.assertRaisesRegex(RuntimeError, "physical tracked bytes differ"):
                MODULE._audit_candidate_tree(root, source)

    def test_post_subject_atomic_replacement_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-custody-race-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            accepted_mode, accepted_oid = MODULE._tree_entries(root, source)["A.swift"]
            attacker = sandbox / "attacker.swift"
            attacker.write_bytes(ATTACKER_BYTES)
            attacker.chmod(0o644)

            original = MODULE._physical_blob_oid
            mutation_count = 0

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
                    MODULE.WholeTreeCustodyError,
                    "whole-tree candidate mutation observed",
                ):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original

            self.assertEqual(mutation_count, 1)
            self.assertEqual(stat.S_IMODE(tracked.stat().st_mode), 0o644)
            self.assertNotEqual(
                original(root, "A.swift", accepted_mode, accepted_oid),
                accepted_oid,
            )

    def test_restore_before_every_read_then_replace_after_every_read_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-custody-loop-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            accepted_mode, accepted_oid = MODULE._tree_entries(root, source)["A.swift"]
            original = MODULE._physical_blob_oid
            read_count = 0

            def race_every_physical_read(
                current_root: Path,
                relative: str,
                mode: bytes,
                expected_oid: str,
            ) -> str:
                nonlocal read_count
                if relative != "A.swift":
                    return original(current_root, relative, mode, expected_oid)
                self._atomic_replace(tracked, ACCEPTED_BYTES, sandbox, read_count * 2)
                result = original(current_root, relative, mode, expected_oid)
                self.assertEqual(result, accepted_oid)
                self._atomic_replace(tracked, ATTACKER_BYTES, sandbox, read_count * 2 + 1)
                read_count += 1
                return result

            MODULE._physical_blob_oid = race_every_physical_read
            try:
                with self.assertRaisesRegex(
                    MODULE.WholeTreeCustodyError,
                    "whole-tree candidate mutation observed",
                ):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original

            self.assertGreaterEqual(read_count, 1)
            self.assertEqual(tracked.read_bytes(), ATTACKER_BYTES)
            self.assertNotEqual(
                original(root, "A.swift", accepted_mode, accepted_oid),
                accepted_oid,
            )

    def test_in_place_write_after_admitted_read_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-custody-inplace-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            original = MODULE._physical_blob_oid
            mutation_count = 0

            def mutate_in_place_after_read(
                current_root: Path,
                relative: str,
                mode: bytes,
                expected_oid: str,
            ) -> str:
                nonlocal mutation_count
                result = original(current_root, relative, mode, expected_oid)
                if relative == "A.swift" and mutation_count == 0:
                    tracked.write_bytes(ATTACKER_BYTES)
                    tracked.chmod(0o644)
                    mutation_count += 1
                return result

            MODULE._physical_blob_oid = mutate_in_place_after_read
            try:
                with self.assertRaisesRegex(
                    MODULE.WholeTreeCustodyError,
                    "whole-tree candidate mutation observed",
                ):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original
            self.assertEqual(mutation_count, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
