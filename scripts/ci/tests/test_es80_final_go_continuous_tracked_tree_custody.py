#!/usr/bin/env python3
"""Adversarial acceptance for continuous Final-GO tracked-tree custody.

These tests consume the two current expected-red findings without weakening
them: a mutation after one admitted tracked read (#3024), and restore-before /
mutate-after every finite endpoint read (#3030). The repaired subject must fail
closed because kernel mutation custody spans the whole authority interval.
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
    raise RuntimeError("could not load continuous-custody Final-GO subject")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

ACCEPTED_BYTES = b"// exact accepted Final-GO bytes\n"
ATTACKER_BYTES = b"// attacker bytes outside continuous custody\n"


class FinalGoContinuousTrackedTreeCustodyTests(unittest.TestCase):
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

    def test_stable_candidate_passes_continuous_audit(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-continuous-stable-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, _tracked = self._candidate(root)
            entries = MODULE._audit_candidate_tree(root, source)
            self.assertEqual(set(entries), {"A.swift"})

    def test_post_subject_replacement_is_rejected_before_whole_audit_returns(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-continuous-post-read-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            accepted_mode, accepted_oid = MODULE._tree_entries(root, source)["A.swift"]
            original = MODULE._physical_blob_oid
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

            MODULE._physical_blob_oid = mutate_after_admitted_read
            try:
                with self.assertRaisesRegex(RuntimeError, "tracked-tree mutation observed"):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original

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
                # A repaired implementation is expected to reject inside the
                # call above because replacement itself is authority-relevant,
                # even though the presented bytes hash to the accepted OID.
                self._atomic_replace(tracked, ATTACKER_BYTES, sandbox, read_count * 2 + 1)
                read_count += 1
                return result

            MODULE._physical_blob_oid = race_every_physical_read
            try:
                with self.assertRaisesRegex(RuntimeError, "tracked-tree mutation observed"):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original

            # Rejection may happen on the first restore-before-read replacement,
            # which is exactly the desired difference from a finite rehash loop.
            self.assertEqual(read_count, 0)

    def test_mutation_after_initial_audit_is_rejected_at_context_handoff(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-continuous-context-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            base = MODULE.generated._load_base_module()
            original_git = base.git
            original_git_bytes = base.git_bytes

            attacker = sandbox / "context-attacker.swift"
            attacker.write_bytes(ATTACKER_BYTES)
            attacker.chmod(0o644)
            with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "tracked-tree mutation observed"):
                with MODULE._candidate_git_custody(base, root, source):
                    os.replace(attacker, tracked)
                    tracked.chmod(0o644)
            self.assertIs(base.git, original_git)
            self.assertIs(base.git_bytes, original_git_bytes)


if __name__ == "__main__":
    unittest.main(verbosity=2)
