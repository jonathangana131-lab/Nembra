#!/usr/bin/env python3
"""Exploit-negative regressions for Final-GO whole-tree snapshot custody.

Consumes the exact behavioral attacks demonstrated by expected-red #3024 and
#3030. The production per-file read primitive remains real and monkeypatchable;
this suite requires the new whole-tree authority boundary to reject replacement
after a successful per-file read and replacement around every finite endpoint
read. It also proves custody spans the full candidate context and detects
in-place mutation of an already-held inode.

No credentials, Xcode, device, Bluetooth, Tuya traffic, install, launch, or
physical action occurs.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import types
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_whole_tree_snapshot_subject", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current Final-GO subject")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

ACCEPTED_BYTES = b"// exact accepted Final-GO bytes\n"
ATTACKER_BYTES = b"// attacker bytes after whole-tree admission\n"


class FinalGoWholeTreeSnapshotCustodyTests(unittest.TestCase):
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

    def test_control_rejects_persistent_attacker_bytes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-control-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            tracked.write_bytes(ATTACKER_BYTES)
            tracked.chmod(0o644)
            with self.assertRaisesRegex(RuntimeError, "physical tracked bytes differ"):
                MODULE._audit_candidate_tree(root, source)

    def test_post_subject_atomic_replacement_is_rejected_after_real_read(self) -> None:
        """Replay #3024: mutate after the real per-file descriptor proof returns."""
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-post-read-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            original = MODULE._physical_blob_oid
            mutation_count = 0

            def mutate_after_real_read(
                current_root: Path,
                relative: str,
                mode: bytes,
                expected_oid: str,
            ) -> str:
                nonlocal mutation_count
                result = original(current_root, relative, mode, expected_oid)
                if relative == "A.swift" and mutation_count == 0:
                    self.assertEqual(result, expected_oid)
                    self._atomic_replace(tracked, ATTACKER_BYTES, sandbox, 1)
                    mutation_count += 1
                return result

            MODULE._physical_blob_oid = mutate_after_real_read
            try:
                with self.assertRaisesRegex(RuntimeError, "whole-tree snapshot|namespace diverged"):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original

            self.assertEqual(mutation_count, 1, "exact #3024 scheduling seam did not fire")
            self.assertEqual(tracked.read_bytes(), ATTACKER_BYTES)

    def test_restore_before_every_read_and_rediverge_after_every_read_is_rejected(self) -> None:
        """Replay #3030: accepted endpoint bytes cannot defeat held-snapshot identity."""
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-rehash-loop-") as temporary:
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
                self.assertEqual(result, expected_oid)
                self._atomic_replace(tracked, ATTACKER_BYTES, sandbox, read_count * 2 + 1)
                read_count += 1
                return result

            MODULE._physical_blob_oid = race_every_physical_read
            try:
                with self.assertRaisesRegex(RuntimeError, "whole-tree snapshot|namespace diverged"):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original

            self.assertGreaterEqual(read_count, 1, "whole-tree audit bypassed the real physical read primitive")
            self.assertEqual(tracked.read_bytes(), ATTACKER_BYTES)

    def test_candidate_custody_rejects_replacement_at_context_exit(self) -> None:
        """The same held subjects must survive the complete parent-build custody window."""
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-context-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            base = types.SimpleNamespace(
                git=lambda _repo, *_args: "outside",
                git_bytes=lambda _repo, *_args: b"outside",
            )
            with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "whole-tree snapshot|namespace diverged"):
                with MODULE._candidate_git_custody(base, root, source):
                    self._atomic_replace(tracked, ATTACKER_BYTES, sandbox, 10)
            self.assertEqual(tracked.read_bytes(), ATTACKER_BYTES)

    def test_in_place_mutation_of_held_inode_is_rejected(self) -> None:
        """A writer keeping the pathname/inode cannot mutate held bytes unnoticed."""
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-in-place-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            original_audit = MODULE._ORIGINAL_AUDIT
            mutation_count = 0

            def mutate_after_parent_audit(current_root: Path, current_source: str):
                nonlocal mutation_count
                result = original_audit(current_root, current_source)
                with tracked.open("r+b", buffering=0) as handle:
                    handle.seek(0)
                    handle.write(ATTACKER_BYTES)
                    handle.truncate()
                    os.fsync(handle.fileno())
                mutation_count += 1
                return result

            MODULE._ORIGINAL_AUDIT = mutate_after_parent_audit
            try:
                with self.assertRaisesRegex(RuntimeError, "held tracked inode changed"):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._ORIGINAL_AUDIT = original_audit
            self.assertEqual(mutation_count, 1)
            self.assertEqual(tracked.read_bytes(), ATTACKER_BYTES)


if __name__ == "__main__":
    unittest.main(verbosity=2)
