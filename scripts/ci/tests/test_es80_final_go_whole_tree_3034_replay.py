#!/usr/bin/env python3
"""Exact-child adversarial replay for #3034 whole-tree Final-GO custody."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import types
import unittest

ROOT = Path(__file__).resolve().parents[3]
SUBJECT = ROOT / "scripts" / "ci" / "es80_authenticated_stationary_private_review_final_go_whole_tree.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_3034_replay_subject", SUBJECT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load #3034 Final-GO successor")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

ACCEPTED_A = b"// exact accepted A\n"
ACCEPTED_B = b"// exact accepted B\n"
ATTACKER = b"// attacker bytes between reads\n"


class FinalGo3034ReplayTests(unittest.TestCase):
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

    def test_3030_restore_before_every_read_replace_after_every_read_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-3034-loop-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked, _ = self._candidate(root)
            self._atomic_replace(tracked, ATTACKER, sandbox, 0)
            entries = MODULE._tree_entries(root, source)
            accepted_mode, accepted_oid = entries["A.swift"]
            original = MODULE._physical_blob_oid
            reads = 0

            def race_every_read(current_root: Path, relative: str, mode: bytes, expected_oid: str) -> str:
                nonlocal reads
                if relative != "A.swift":
                    return original(current_root, relative, mode, expected_oid)
                self._atomic_replace(tracked, ACCEPTED_A, sandbox, reads * 2 + 1)
                result = original(current_root, relative, mode, expected_oid)
                self.assertEqual(result, accepted_oid)
                self._atomic_replace(tracked, ATTACKER, sandbox, reads * 2 + 2)
                reads += 1
                return result

            MODULE._physical_blob_oid = race_every_read
            try:
                with self.assertRaisesRegex(RuntimeError, r"whole-tree mutation|identity drifted"):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original
            self.assertGreaterEqual(reads, 1)
            self.assertEqual(tracked.read_bytes(), ATTACKER)
            self.assertEqual(entries["A.swift"], (accepted_mode, accepted_oid))

    def test_field_input_file_mutation_is_rejected_during_candidate_custody(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-3034-field-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, _, _ = self._candidate(root)

            def ambient_git(repo: Path, *args: str) -> str:
                return subprocess.run(
                    ["/usr/bin/git", "-C", str(repo), *args],
                    text=True,
                    check=True,
                    capture_output=True,
                ).stdout.strip()

            def ambient_git_bytes(repo: Path, *args: str) -> bytes:
                return subprocess.run(
                    ["/usr/bin/git", "-C", str(repo), *args],
                    check=True,
                    capture_output=True,
                ).stdout

            base = types.SimpleNamespace(git=ambient_git, git_bytes=ambient_git_bytes)
            podfile_lock = root / MODULE.FIELD_INPUT_FILES[0]
            with self.assertRaisesRegex(RuntimeError, r"whole-tree mutation|identity drifted"):
                with MODULE._candidate_git_custody(base, root, source):
                    with podfile_lock.open("ab") as stream:
                        stream.write(b"ATTACK\n")
                        stream.flush()
                        os.fsync(stream.fileno())

    def test_platform_backend_is_real_kernel_backend(self) -> None:
        backend = MODULE._backend()
        try:
            if sys.platform == "darwin":
                self.assertEqual(type(backend).__name__, "_KqueueMutationBackend")
            elif sys.platform.startswith("linux"):
                self.assertEqual(type(backend).__name__, "_InotifyMutationBackend")
            else:
                self.fail("validation runner is outside supported custody platforms")
        finally:
            backend.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
