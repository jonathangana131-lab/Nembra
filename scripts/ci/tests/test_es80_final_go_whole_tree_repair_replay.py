#!/usr/bin/env python3
"""Exact-child replay of #3024 and #3030 against the whole-tree repair."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SUBJECT = ROOT / "scripts" / "ci" / "es80_authenticated_stationary_private_review_whole_tree_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_whole_tree_replay_subject", SUBJECT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load repaired Final-GO subject")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

ACCEPTED_A = b"// accepted A\n"
ACCEPTED_B = b"// accepted B\n"
ATTACKER = b"// attacker bytes\n"


class FinalGoWholeTreeRepairReplayTests(unittest.TestCase):
    def _candidate(self, root: Path) -> tuple[str, Path, Path]:
        subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)
        a = root / "A.swift"
        b = root / "B.swift"
        a.write_bytes(ACCEPTED_A)
        b.write_bytes(ACCEPTED_B)
        a.chmod(0o644)
        b.chmod(0o644)
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "A.swift", "B.swift"], check=True)
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
        return source, a, b

    @staticmethod
    def _atomic_replace(path: Path, payload: bytes, scratch: Path, ordinal: int) -> None:
        replacement = scratch / f"replacement-{ordinal}.swift"
        replacement.write_bytes(payload)
        replacement.chmod(0o644)
        os.replace(replacement, path)
        path.chmod(0o644)

    def test_3024_post_subject_replacement_is_now_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-3024-replay-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked, _ = self._candidate(root)
            original = MODULE._physical_blob_oid
            fired = False

            def attack_after_real_read(current_root: Path, relative: str, mode: bytes, expected_oid: str) -> str:
                nonlocal fired
                result = original(current_root, relative, mode, expected_oid)
                if relative == "A.swift" and not fired:
                    fired = True
                    self._atomic_replace(tracked, ATTACKER, sandbox, 1)
                return result

            MODULE._physical_blob_oid = attack_after_real_read
            try:
                with self.assertRaisesRegex(RuntimeError, "changed during Final-GO"):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original
            self.assertTrue(fired)
            self.assertEqual(tracked.read_bytes(), ATTACKER)

    def test_3030_restore_before_every_read_replace_after_every_read_is_now_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-3030-replay-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked, _ = self._candidate(root)
            self._atomic_replace(tracked, ATTACKER, sandbox, 0)
            entries = MODULE._tree_entries(root, source)
            accepted_mode, accepted_oid = entries["A.swift"]
            original = MODULE._physical_blob_oid
            read_count = 0

            def race_every_read(current_root: Path, relative: str, mode: bytes, expected_oid: str) -> str:
                nonlocal read_count
                if relative != "A.swift":
                    return original(current_root, relative, mode, expected_oid)
                self._atomic_replace(tracked, ACCEPTED_A, sandbox, read_count * 2 + 1)
                result = original(current_root, relative, mode, expected_oid)
                self.assertEqual(result, accepted_oid)
                self._atomic_replace(tracked, ATTACKER, sandbox, read_count * 2 + 2)
                read_count += 1
                return result

            MODULE._physical_blob_oid = race_every_read
            try:
                with self.assertRaisesRegex(RuntimeError, "changed during Final-GO"):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original
            self.assertGreaterEqual(read_count, 1)
            self.assertEqual(tracked.read_bytes(), ATTACKER)
            self.assertEqual(stat.S_IMODE(tracked.stat().st_mode), 0o644)
            self.assertEqual(entries["A.swift"], (accepted_mode, accepted_oid))


if __name__ == "__main__":
    unittest.main(verbosity=2)
