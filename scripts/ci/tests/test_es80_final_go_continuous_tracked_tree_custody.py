#!/usr/bin/env python3
"""Adversarial acceptance for inherited continuous Final-GO tree custody.

The current sealed-record Final-GO successor executes exact continuous-custody
parent cb36f926... rather than copying its implementation. These tests therefore
bind that immediate parent identity first and attack the exact parent object that
production build() invokes. This preserves the original #3024/#3030 mechanical
oracles across exact-parent composition without inventing a forwarding seam only
for tests.
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
SPEC = importlib.util.spec_from_file_location("nembra_final_go_continuous_tree_subject", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load sealed-record Final-GO subject")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

EXPECTED_PARENT_SOURCE = "cb36f9265f08708c8e47564f62f4857aeae7af0f"
EXPECTED_PARENT_BLOB = "baef9de23a680bedf16f9f7b367f45f7710ac0c6"
if MODULE.DIRECT_PARENT_SOURCE != EXPECTED_PARENT_SOURCE:
    raise RuntimeError("continuous-custody regression is not bound to the selected exact parent")
if MODULE.DIRECT_PARENT_MODULE_GIT_BLOB != EXPECTED_PARENT_BLOB:
    raise RuntimeError("continuous-custody regression parent blob moved")
SUBJECT = MODULE._parent

ACCEPTED_BYTES = b"// exact accepted Final-GO bytes\n"
ATTACKER_BYTES = b"// attacker bytes outside continuous custody\n"


class FinalGoContinuousTrackedTreeCustodyTests(unittest.TestCase):
    def test_selected_exact_parent_is_the_continuous_custody_subject(self) -> None:
        self.assertEqual(MODULE.DIRECT_PARENT_SOURCE, EXPECTED_PARENT_SOURCE)
        self.assertEqual(MODULE.DIRECT_PARENT_MODULE_GIT_BLOB, EXPECTED_PARENT_BLOB)
        self.assertTrue(callable(SUBJECT._audit_candidate_tree))
        self.assertTrue(callable(SUBJECT._candidate_git_custody))
        self.assertTrue(callable(SUBJECT._physical_blob_oid))

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

        for relative in SUBJECT.FIELD_INPUT_DIRECTORIES:
            path = root / relative
            path.mkdir(parents=True, exist_ok=True)
            self.assertTrue(stat.S_ISDIR(path.lstat().st_mode))
        for relative in SUBJECT.FIELD_INPUT_FILES:
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

    def test_stable_candidate_passes_continuous_audit(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-continuous-stable-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, _tracked = self._candidate(root)
            entries = SUBJECT._audit_candidate_tree(root, source)
            self.assertEqual(set(entries), {"A.swift"})

    def test_post_subject_replacement_is_rejected_before_whole_audit_returns(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-continuous-post-read-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            accepted_mode, accepted_oid = SUBJECT._tree_entries(root, source)["A.swift"]
            original = SUBJECT._physical_blob_oid
            fired = False

            def mutate_after_admitted_read(
                current_root: Path,
                relative: str,
                mode: bytes,
                expected_oid: str,
            ) -> str:
                nonlocal fired
                result = original(current_root, relative, mode, expected_oid)
                if relative == "A.swift" and not fired:
                    attacker = sandbox / "post-read-attacker.swift"
                    attacker.write_bytes(ATTACKER_BYTES)
                    attacker.chmod(0o644)
                    os.replace(attacker, tracked)
                    tracked.chmod(0o644)
                    fired = True
                return result

            SUBJECT._physical_blob_oid = mutate_after_admitted_read
            try:
                with self.assertRaisesRegex(RuntimeError, "tracked-tree mutation observed"):
                    SUBJECT._audit_candidate_tree(root, source)
            finally:
                SUBJECT._physical_blob_oid = original

            self.assertTrue(fired, "post-admission attack seam did not fire")
            self.assertNotEqual(
                original(root, "A.swift", accepted_mode, accepted_oid),
                accepted_oid,
                "attack did not leave divergent bytes for the witness",
            )

    def test_restore_before_every_read_then_mutate_after_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-continuous-rehash-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            original = SUBJECT._physical_blob_oid
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
                # A repaired implementation is expected to reject inside the
                # call above because replacement itself is authority-relevant,
                # even though the presented bytes hash to the accepted OID.
                self._atomic_replace(tracked, ATTACKER_BYTES, sandbox, read_count * 2 + 1)
                read_count += 1
                return result

            SUBJECT._physical_blob_oid = race_every_physical_read
            try:
                with self.assertRaisesRegex(RuntimeError, "tracked-tree mutation observed"):
                    SUBJECT._audit_candidate_tree(root, source)
            finally:
                SUBJECT._physical_blob_oid = original

            # Rejection may happen on the first restore-before-read replacement,
            # which is exactly the desired difference from a finite rehash loop.
            self.assertEqual(read_count, 0)

    def test_mutation_after_initial_audit_is_rejected_at_context_handoff(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-continuous-context-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            base = SUBJECT.generated._load_base_module()
            original_git = base.git
            original_git_bytes = base.git_bytes

            attacker = sandbox / "context-attacker.swift"
            attacker.write_bytes(ATTACKER_BYTES)
            attacker.chmod(0o644)
            with self.assertRaisesRegex(SUBJECT.PrivateReviewGoError, "tracked-tree mutation observed"):
                with SUBJECT._candidate_git_custody(base, root, source):
                    os.replace(attacker, tracked)
                    tracked.chmod(0o644)
            self.assertIs(base.git, original_git)
            self.assertIs(base.git_bytes, original_git_bytes)


if __name__ == "__main__":
    unittest.main(verbosity=2)
