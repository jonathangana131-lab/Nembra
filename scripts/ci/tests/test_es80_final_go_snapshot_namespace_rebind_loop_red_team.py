#!/usr/bin/env python3
"""Expected-red witness for finite Final-GO snapshot namespace rebind loops.

#3038 keeps accepted regular-file inodes open across candidate custody and
correctly rejects persistent replacement plus finite content rehash attacks.
Its final live-namespace proof is nevertheless a sequential identity sampling
loop: for each held subject, `_current_namespace_identity(...)` is called once
and the returned identity is compared with the held inode.

A same-UID writer can therefore present the accepted held inode at the tracked
pathname only while each identity query executes, then immediately restore a
different same-shape inode before the next subject / overall return. The held
file descriptor remains perfectly stable throughout; what is not continuously
bound is the live pathname that Final-GO ultimately authorizes.

This validation changes no production code, credentials, Xcode/device state,
Bluetooth/Tuya traffic, install, launch, or physical procedure.
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
SPEC = importlib.util.spec_from_file_location("nembra_final_go_snapshot_rebind_redteam", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load #3038 Final-GO snapshot subject")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

ACCEPTED_BYTES = b"// exact accepted Final-GO bytes\n"
ATTACKER_BYTES = b"// attacker namespace bytes after identity query\n"


class FinalGoSnapshotNamespaceRebindLoopRedTeamTests(unittest.TestCase):
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

    @staticmethod
    def _install_attacker_and_hold_accepted(
        tracked: Path,
        accepted_holder: Path,
        attacker_source: Path,
    ) -> None:
        os.replace(tracked, accepted_holder)
        os.replace(attacker_source, tracked)
        tracked.chmod(0o644)

    @staticmethod
    def _present_accepted_only_for_identity_query(
        tracked: Path,
        accepted_holder: Path,
        attacker_holder: Path,
        query,
    ):
        # Move the currently-live attacker out, temporarily rebind the exact
        # accepted inode to the authorized pathname, sample that identity, then
        # immediately restore the divergent inode before returning the sampled
        # accepted metadata to production.
        os.replace(tracked, attacker_holder)
        os.replace(accepted_holder, tracked)
        try:
            result = query()
        finally:
            os.replace(tracked, accepted_holder)
            os.replace(attacker_holder, tracked)
            tracked.chmod(0o644)
        return result

    def test_final_audit_rebind_can_sample_accepted_inode_then_return_divergent_path(self) -> None:
        """Exploit the actual final `_audit_candidate_tree` namespace rebind."""
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-rebind-audit-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)

            accepted_entries = MODULE._tree_entries(root, source)
            accepted_mode, accepted_oid = accepted_entries["A.swift"]
            accepted_holder = sandbox / "accepted-held.swift"
            attacker_source = sandbox / "attacker-source.swift"
            attacker_holder = sandbox / "attacker-held.swift"
            attacker_source.write_bytes(ATTACKER_BYTES)
            attacker_source.chmod(0o644)

            original_audit = MODULE._ORIGINAL_AUDIT
            original_identity = MODULE._current_namespace_identity
            attack_active = False
            query_count = 0

            def diverge_after_exact_parent_audit(current_root: Path, current_source: str):
                nonlocal attack_active
                result = original_audit(current_root, current_source)
                self.assertEqual(result, accepted_entries)
                self._install_attacker_and_hold_accepted(tracked, accepted_holder, attacker_source)
                attack_active = True
                return result

            def race_namespace_identity(current_root: Path, relative: str):
                nonlocal query_count
                if not attack_active or relative != "A.swift":
                    return original_identity(current_root, relative)
                query_count += 1
                return self._present_accepted_only_for_identity_query(
                    tracked,
                    accepted_holder,
                    attacker_holder,
                    lambda: original_identity(current_root, relative),
                )

            MODULE._ORIGINAL_AUDIT = diverge_after_exact_parent_audit
            MODULE._current_namespace_identity = race_namespace_identity
            try:
                result_entries = MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._current_namespace_identity = original_identity
                MODULE._ORIGINAL_AUDIT = original_audit

            self.assertTrue(attack_active, "post-parent-audit divergence seam did not fire")
            self.assertGreaterEqual(query_count, 1, "final namespace identity rebind was not exercised")
            self.assertEqual(result_entries, accepted_entries)
            self.assertTrue(tracked.is_file())
            self.assertFalse(tracked.is_symlink())
            self.assertEqual(stat.S_IMODE(tracked.stat().st_mode), 0o644)
            self.assertEqual(tracked.read_bytes(), ATTACKER_BYTES)
            self.assertEqual(accepted_holder.read_bytes(), ACCEPTED_BYTES)
            self.assertNotEqual(
                MODULE._ORIGINAL_PHYSICAL_BLOB_OID(root, "A.swift", accepted_mode, accepted_oid),
                accepted_oid,
                "attack did not leave divergent physical bytes after Final-GO audit returned success",
            )
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
                ).strip().lower(),
                source,
                "attack changed accepted Git commit identity rather than only live namespace custody",
            )

    def test_candidate_custody_exit_rebind_can_return_with_divergent_live_path(self) -> None:
        """The same finite identity loop is raceable at full custody release."""
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-rebind-context-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)

            accepted_entries = MODULE._tree_entries(root, source)
            accepted_mode, accepted_oid = accepted_entries["A.swift"]
            accepted_holder = sandbox / "accepted-context-held.swift"
            attacker_source = sandbox / "attacker-context-source.swift"
            attacker_holder = sandbox / "attacker-context-held.swift"
            attacker_source.write_bytes(ATTACKER_BYTES)
            attacker_source.chmod(0o644)

            base = types.SimpleNamespace(
                git=lambda _repo, *_args: "outside",
                git_bytes=lambda _repo, *_args: b"outside",
            )
            original_identity = MODULE._current_namespace_identity
            attack_active = False
            query_count = 0

            def race_namespace_identity(current_root: Path, relative: str):
                nonlocal query_count
                if not attack_active or relative != "A.swift":
                    return original_identity(current_root, relative)
                query_count += 1
                return self._present_accepted_only_for_identity_query(
                    tracked,
                    accepted_holder,
                    attacker_holder,
                    lambda: original_identity(current_root, relative),
                )

            MODULE._current_namespace_identity = race_namespace_identity
            try:
                with MODULE._candidate_git_custody(base, root, source):
                    self._install_attacker_and_hold_accepted(tracked, accepted_holder, attacker_source)
                    attack_active = True
            finally:
                MODULE._current_namespace_identity = original_identity

            self.assertTrue(attack_active)
            self.assertGreaterEqual(query_count, 1, "custody-release namespace rebind was not exercised")
            self.assertEqual(tracked.read_bytes(), ATTACKER_BYTES)
            self.assertEqual(accepted_holder.read_bytes(), ACCEPTED_BYTES)
            self.assertNotEqual(
                MODULE._ORIGINAL_PHYSICAL_BLOB_OID(root, "A.swift", accepted_mode, accepted_oid),
                accepted_oid,
                "candidate custody returned with accepted physical bytes instead of exercising the race",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
