#!/usr/bin/env python3
"""Behavioral closure for Final-GO whole-tree mutation custody."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / "scripts" / "ci" / "es80_authenticated_stationary_private_review_whole_tree_final_go.py"


def load_module():
    spec = importlib.util.spec_from_file_location("nembra_whole_tree_final_go_test", MODULE)
    if spec is None or spec.loader is None:
        raise RuntimeError("whole-tree Final-GO module import unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(spec.name, None)
        raise
    return module


class WholeTreeFinalGoCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-final-go-whole-tree-")
        self.repo = Path(self.temporary.name)
        subprocess.run(["/usr/bin/git", "init", "-q", str(self.repo)], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(self.repo), "config", "user.email", "nembra@example.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(self.repo), "config", "user.name", "Nembra Test"], check=True)
        self.a = self.repo / "A.swift"
        self.b = self.repo / "B.swift"
        self.a.write_text("let a = 1\n", encoding="utf-8")
        self.b.write_text("let b = 2\n", encoding="utf-8")
        subprocess.run(["/usr/bin/git", "-C", str(self.repo), "add", "A.swift", "B.swift"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(self.repo), "commit", "-qm", "fixture"], check=True)
        self.source = subprocess.run(
            ["/usr/bin/git", "-C", str(self.repo), "rev-parse", "HEAD"],
            text=True, check=True, capture_output=True,
        ).stdout.strip()
        for relative in self.module.FIELD_INPUT_DIRECTORIES:
            (self.repo / relative).mkdir(parents=True, exist_ok=True)
        for relative in self.module.FIELD_INPUT_FILES:
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _replace_a(self, text: str) -> None:
        replacement = self.repo / ".A.swift.replacement"
        replacement.write_text(text, encoding="utf-8")
        replacement.chmod(0o644)
        os.replace(replacement, self.a)

    def test_clean_candidate_still_passes_exact_parent_audit(self) -> None:
        entries = self.module._audit_candidate_tree(self.repo, self.source)
        self.assertEqual(set(entries), {"A.swift", "B.swift"})

    def test_post_subject_replacement_is_rejected(self) -> None:
        original = self.module._physical_blob_oid
        fired = False

        def attacked(root: Path, relative: str, mode: bytes, accepted_oid: str) -> str:
            nonlocal fired
            result = original(root, relative, mode, accepted_oid)
            if relative == "A.swift" and not fired:
                fired = True
                self._replace_a("let a = 999\n")
            return result

        self.module._physical_blob_oid = attacked
        try:
            with self.assertRaisesRegex(RuntimeError, "changed during Final-GO"):
                self.module._audit_candidate_tree(self.repo, self.source)
        finally:
            self.module._physical_blob_oid = original
        self.assertTrue(fired)
        self.assertEqual(self.a.read_text(encoding="utf-8"), "let a = 999\n")

    def test_restore_read_replace_loop_is_rejected(self) -> None:
        accepted = "let a = 1\n"
        attacker = "let a = 777\n"
        self._replace_a(attacker)
        original = self.module._physical_blob_oid
        calls = 0

        def raced(root: Path, relative: str, mode: bytes, accepted_oid: str) -> str:
            nonlocal calls
            if relative == "A.swift":
                calls += 1
                self._replace_a(accepted)
                result = original(root, relative, mode, accepted_oid)
                self._replace_a(attacker)
                return result
            return original(root, relative, mode, accepted_oid)

        self.module._physical_blob_oid = raced
        try:
            with self.assertRaisesRegex(RuntimeError, "changed during Final-GO"):
                self.module._audit_candidate_tree(self.repo, self.source)
        finally:
            self.module._physical_blob_oid = original
        self.assertGreaterEqual(calls, 1)
        self.assertEqual(self.a.read_text(encoding="utf-8"), attacker)

    def test_candidate_custody_remains_armed_after_initial_audit(self) -> None:
        def ambient_git(repo: Path, *args: str) -> str:
            return subprocess.run(
                ["/usr/bin/git", "-C", str(repo), *args],
                text=True, check=True, capture_output=True,
            ).stdout.strip()

        def ambient_git_bytes(repo: Path, *args: str) -> bytes:
            return subprocess.run(
                ["/usr/bin/git", "-C", str(repo), *args],
                check=True, capture_output=True,
            ).stdout

        base = types.SimpleNamespace(git=ambient_git, git_bytes=ambient_git_bytes)
        with self.assertRaisesRegex(RuntimeError, "changed during Final-GO"):
            with self.module._candidate_git_custody(base, self.repo, self.source):
                self._replace_a("let a = 555\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
