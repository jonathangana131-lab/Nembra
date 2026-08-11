#!/usr/bin/env python3
"""Expected-red witness for finite Final-GO endpoint rehash loops.

#3024 proves the selected Final-GO parent can accept a tracked pathname that is
replaced after its descriptor-bound read/reproof. A tempting repair is to add a
second (or repeated) unsynchronised hash pass. That does not create atomicity:
a same-UID writer can present accepted bytes for every finite read and replace
the pathname again immediately after each read completes.

This witness keeps the production read primitive real. Before every
`_physical_blob_oid` call it restores exact accepted bytes to the tracked
pathname. It then calls the real production helper, allowing the real no-follow
descriptor read, stable-stat checks, namespace rebind, and blob computation to
finish. Immediately after that successful admission it atomically replaces the
pathname with attacker bytes again. Current production (and any finite
unsynchronised endpoint rehash loop using this primitive) must remain RED.

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
SPEC = importlib.util.spec_from_file_location("nembra_final_go_rehash_loop_subject", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current Final-GO subject")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

ACCEPTED_BYTES = b"// exact accepted Final-GO bytes\n"
ATTACKER_BYTES = b"// attacker bytes between every endpoint read\n"


class FinalGoRehashLoopRedTeamTests(unittest.TestCase):
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
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-rehash-control-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            tracked.write_bytes(ATTACKER_BYTES)
            tracked.chmod(0o644)
            with self.assertRaisesRegex(RuntimeError, "physical tracked bytes differ"):
                MODULE._audit_candidate_tree(root, source)

    def test_restore_before_each_read_then_mutate_after_each_read_still_wins(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-rehash-loop-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)

            accepted_entries = MODULE._tree_entries(root, source)
            self.assertEqual(set(accepted_entries), {"A.swift"})
            accepted_mode, accepted_oid = accepted_entries["A.swift"]
            self.assertEqual(accepted_mode, b"100644")

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

                # Present the exact accepted object before *every* authoritative
                # endpoint read, regardless of how many rehash passes production
                # attempts. The real production helper then performs its complete
                # descriptor/stable-stat/namespace proof on those accepted bytes.
                self._atomic_replace(tracked, ACCEPTED_BYTES, sandbox, read_count * 2)
                result = original(current_root, relative, mode, expected_oid)
                self.assertEqual(result, accepted_oid)

                # Re-diverge only after the real per-subject admission returned.
                self._atomic_replace(tracked, ATTACKER_BYTES, sandbox, read_count * 2 + 1)
                read_count += 1
                return result

            MODULE._physical_blob_oid = race_every_physical_read
            try:
                result_entries = MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._physical_blob_oid = original

            self.assertGreaterEqual(read_count, 1, "whole-tree audit never exercised the physical read primitive")
            self.assertEqual(result_entries["A.swift"], (accepted_mode, accepted_oid))
            self.assertTrue(tracked.is_file())
            self.assertFalse(tracked.is_symlink())
            self.assertEqual(stat.S_IMODE(tracked.stat().st_mode), 0o644)
            self.assertEqual(tracked.read_bytes(), ATTACKER_BYTES)

            final_oid = original(root, "A.swift", accepted_mode, accepted_oid)
            self.assertNotEqual(
                final_oid,
                accepted_oid,
                "race did not leave the physical candidate divergent after Final-GO accepted it",
            )
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
                ).strip().lower(),
                source,
                "attack changed accepted Git identity instead of only physical candidate bytes",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
