#!/usr/bin/env python3
"""Expected-red witness for finite Final-GO snapshot namespace rebinds.

#3038 holds every accepted regular-file inode open across the candidate window,
then sequentially re-binds each current pathname to the held leaf identity.
Open file descriptors pin leaf inodes, not the namespace path used to reach
those leaves. A same-UID writer can therefore swap an entire tracked ancestor
directory out of the checkout between those finite identity checks.

This witness keeps the real #3038 snapshot, real #2921 raw audit, real held
leaf descriptors, and real `_current_namespace_identity(...)` primitive. On the
final rebind round only, it presents the original accepted ancestor directory
for each individual identity read and immediately swaps an attacker directory
back afterward. Every held leaf fstat remains unchanged because only the
ancestor directory is renamed; every current identity read sees the accepted
leaf; yet the audit returns with attacker bytes occupying the tracked paths.

No credential, Xcode, device, Bluetooth, Tuya, install, launch, or physical
action occurs.
"""

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
SCRIPT = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_snapshot_rebind_redteam", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load snapshot-custody Final-GO subject")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

ACCEPTED_A = b"// accepted A\n"
ACCEPTED_B = b"// accepted B\n"
ATTACKER_A = b"// attacker A after identity rebind\n"
ATTACKER_B = b"// attacker B after identity rebind\n"


class FinalGoSnapshotRebindRaceRedTeamTests(unittest.TestCase):
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

        tracked = root / "Tracked"
        tracked.mkdir()
        (tracked / "A.swift").write_bytes(ACCEPTED_A)
        (tracked / "B.swift").write_bytes(ACCEPTED_B)
        (tracked / "A.swift").chmod(0o644)
        (tracked / "B.swift").chmod(0o644)
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "Tracked"], check=True)
        subprocess.run(
            ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted candidate"],
            check=True,
        )
        source = subprocess.check_output(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"],
            text=True,
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

    def test_control_clean_snapshot_candidate_is_admitted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-rebind-control-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, _ = self._candidate(root)
            result = MODULE._audit_candidate_tree(root, source)
            self.assertEqual(set(result), {"Tracked/A.swift", "Tracked/B.swift"})

    def test_final_leaf_identity_rebind_can_be_raced_by_ancestor_directory_swap(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-snapshot-rebind-race-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, live = self._candidate(root)

            attacker = sandbox / "attacker-tracked"
            attacker.mkdir()
            (attacker / "A.swift").write_bytes(ATTACKER_A)
            (attacker / "B.swift").write_bytes(ATTACKER_B)
            (attacker / "A.swift").chmod(0o644)
            (attacker / "B.swift").chmod(0o644)
            parked_accepted = sandbox / "accepted-tracked"

            original_identity = MODULE._current_namespace_identity
            identity_calls = 0
            attack_round_calls = 0
            attacker_live = False

            def install_accepted() -> None:
                nonlocal attacker_live
                if not attacker_live:
                    return
                os.rename(live, attacker)
                os.rename(parked_accepted, live)
                attacker_live = False

            def install_attacker() -> None:
                nonlocal attacker_live
                if attacker_live:
                    return
                os.rename(live, parked_accepted)
                os.rename(attacker, live)
                attacker_live = True

            def race_final_rebind(current_root: Path, relative: str) -> tuple[int, ...]:
                nonlocal identity_calls, attack_round_calls
                identity_calls += 1

                # _held_tracked_snapshot performs one complete initial rebind
                # before yielding to the exact parent audit. With two tracked
                # leaves, calls 1-2 are that admission round. Calls 3-4 are the
                # finite final rebind performed after the parent raw audit.
                if identity_calls <= 2:
                    return original_identity(current_root, relative)

                self.assertIn(relative, {"Tracked/A.swift", "Tracked/B.swift"})
                install_accepted()
                accepted_identity = original_identity(current_root, relative)
                install_attacker()
                attack_round_calls += 1
                return accepted_identity

            MODULE._current_namespace_identity = race_final_rebind
            try:
                result = MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._current_namespace_identity = original_identity

            self.assertEqual(
                attack_round_calls,
                2,
                "fixture did not race every leaf in the final namespace-rebind round",
            )
            self.assertEqual(set(result), {"Tracked/A.swift", "Tracked/B.swift"})
            self.assertTrue(attacker_live, "fixture did not leave attacker ancestor installed")
            self.assertEqual((live / "A.swift").read_bytes(), ATTACKER_A)
            self.assertEqual((live / "B.swift").read_bytes(), ATTACKER_B)

            accepted_entries = MODULE._parent._tree_entries(root, source)
            for relative in ("Tracked/A.swift", "Tracked/B.swift"):
                mode, accepted_oid = accepted_entries[relative]
                self.assertEqual(mode, b"100644")
                current_oid = MODULE._parent._physical_blob_oid(root, relative, mode, accepted_oid)
                self.assertNotEqual(
                    current_oid,
                    accepted_oid,
                    f"{relative} did not remain physically divergent after Final-GO accepted",
                )

            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"],
                    text=True,
                ).strip().lower(),
                source,
                "attack changed Git identity instead of only the physical checkout namespace",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
