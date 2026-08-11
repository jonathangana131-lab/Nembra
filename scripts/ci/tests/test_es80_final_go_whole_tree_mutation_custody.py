#!/usr/bin/env python3
"""Regression for Final-GO continuous whole-tree mutation custody."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
from types import SimpleNamespace
import stat
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_whole_tree_custody", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current Final-GO whole-tree custody subject")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoWholeTreeMutationCustodyTests(unittest.TestCase):
    def _candidate(self, root: Path) -> tuple[str, Path, bytes, str]:
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
        accepted_payload = b"// exact accepted Final-GO bytes\n"
        tracked.write_bytes(accepted_payload)
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
        entries = MODULE._tree_entries(root, source)
        self.assertEqual(entries["A.swift"][0], b"100644")
        return source, tracked, accepted_payload, entries["A.swift"][1]

    def test_post_subject_replacement_is_rejected_before_audit_returns(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-whole-tree-closure-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked, _, accepted_oid = self._candidate(root)
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
                    "continuous whole-tree mutation custody",
                    msg="post-admission tracked replacement escaped whole-tree custody",
                ):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original

            self.assertEqual(mutation_count, 1, "deterministic post-admission mutation seam did not fire")
            self.assertNotEqual(
                original(root, "A.swift", b"100644", accepted_oid),
                accepted_oid,
                "attack fixture did not leave divergent physical bytes",
            )

    def test_mutate_restore_inside_candidate_context_is_still_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-whole-tree-restore-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, tracked, accepted_payload, accepted_oid = self._candidate(root)
            base = SimpleNamespace(
                git=lambda *_args, **_kwargs: "",
                git_bytes=lambda *_args, **_kwargs: b"",
            )

            with self.assertRaisesRegex(
                MODULE.PrivateReviewGoError,
                "continuous whole-tree mutation custody",
                msg="mutate-then-restore escaped continuous candidate custody",
            ):
                with MODULE._candidate_git_custody(base, root, source):
                    tracked.write_bytes(b"// transient attacker bytes\n")
                    tracked.chmod(0o644)
                    tracked.write_bytes(accepted_payload)
                    tracked.chmod(0o644)

            self.assertEqual(tracked.read_bytes(), accepted_payload)
            self.assertEqual(
                MODULE._physical_blob_oid(root, "A.swift", b"100644", accepted_oid),
                accepted_oid,
                "endpoint bytes were not restored; fixture must prove event history, not endpoint hashing",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
