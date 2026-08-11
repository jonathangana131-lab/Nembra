#!/usr/bin/env python3
"""Expected-red witness for Final-GO descriptor-snapshot release atomicity.

#3038 keeps exact tracked regular-file descriptors live through the candidate
window and performs a final namespace identity rebind before releasing them.
That is stronger than finite endpoint re-hashing, but the final rebind is still
sequential: `_current_namespace_identity` returns one point-in-time stat tuple,
then `_rebind_snapshot` compares that captured value, returns, and the snapshot
context finally closes the held descriptors.

This witness atomically replaces the tracked pathname *after* the real final
identity read has returned accepted metadata but before that metadata is
compared to the held snapshot. The comparison therefore sees the accepted
pre-replacement tuple, the held descriptor still describes the original inode,
and current production can return accepted tree authority before descriptor
custody is released while the physical pathname already contains attacker
bytes.

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
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_snapshot_release_redteam", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current Final-GO snapshot subject")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

ACCEPTED_BYTES = b"// exact accepted Final-GO bytes\n"
ATTACKER_BYTES = b"// attacker replacement during final identity release\n"


class FinalGoSnapshotReleaseRaceRedTeamTests(unittest.TestCase):
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
    def _atomic_replace(path: Path, payload: bytes, scratch: Path) -> None:
        replacement = scratch / "release-race-replacement.swift"
        replacement.write_bytes(payload)
        replacement.chmod(0o644)
        os.replace(replacement, path)
        path.chmod(0o644)

    def test_control_replacement_before_final_rebind_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-release-control-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            original_audit = MODULE._ORIGINAL_AUDIT

            def mutate_before_final_rebind(current_root: Path, current_source: str):
                result = original_audit(current_root, current_source)
                self._atomic_replace(tracked, ATTACKER_BYTES, sandbox)
                return result

            MODULE._ORIGINAL_AUDIT = mutate_before_final_rebind
            try:
                with self.assertRaisesRegex(RuntimeError, "namespace diverged"):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._ORIGINAL_AUDIT = original_audit

            self.assertEqual(tracked.read_bytes(), ATTACKER_BYTES)

    def test_replacement_after_final_identity_read_is_accepted_before_snapshot_release(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-release-race-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)

            accepted_entries = MODULE._parent._tree_entries(root, source)
            self.assertEqual(set(accepted_entries), {"A.swift"})
            accepted_mode, accepted_oid = accepted_entries["A.swift"]
            self.assertEqual(accepted_mode, b"100644")

            original_identity = MODULE._current_namespace_identity
            identity_reads = 0
            mutation_count = 0

            def mutate_after_final_identity_read(current_root: Path, relative: str) -> tuple[int, ...]:
                nonlocal identity_reads, mutation_count
                identity = original_identity(current_root, relative)
                if relative == "A.swift":
                    identity_reads += 1
                    # The first identity read occurs immediately after snapshot
                    # capture. The second is the final acceptance rebind after
                    # the exact parent raw audit has completed.
                    if identity_reads == 2:
                        self._atomic_replace(tracked, ATTACKER_BYTES, sandbox)
                        mutation_count += 1
                return identity

            MODULE._current_namespace_identity = mutate_after_final_identity_read
            try:
                result = MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._current_namespace_identity = original_identity

            self.assertEqual(identity_reads, 2, "final snapshot identity rebind was not exercised exactly once")
            self.assertEqual(mutation_count, 1, "deterministic release-race mutation seam did not fire")
            self.assertEqual(result["A.swift"], (accepted_mode, accepted_oid))
            self.assertTrue(tracked.is_file())
            self.assertFalse(tracked.is_symlink())
            self.assertEqual(stat.S_IMODE(tracked.stat().st_mode), 0o644)
            self.assertEqual(tracked.read_bytes(), ATTACKER_BYTES)

            current_oid = MODULE._ORIGINAL_PHYSICAL_BLOB_OID(root, "A.swift", accepted_mode, accepted_oid)
            self.assertNotEqual(
                current_oid,
                accepted_oid,
                "release-race witness did not leave divergent physical tracked bytes",
            )
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
                ).strip().lower(),
                source,
                "release-race attack changed accepted Git identity instead of only physical candidate bytes",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
