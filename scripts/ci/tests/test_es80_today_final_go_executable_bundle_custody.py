#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
ATTESTATION = REPOSITORY_ROOT / "docs" / "ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md"
HARDENER = REPOSITORY_ROOT / "scripts" / "ci" / "es80_today_final_go_hardened.py"

ACCEPTED_HEAD = "4506bf3b0a523ca03fc09e968f34d4359e34bf91"
ACCEPTED_RUNS = ("31312717529", "31312717536")
ACCEPTED_JOBS = ("93242924865", "93242924588")
BUNDLE = {
    "scripts/ci/es80_today_final_go_hardened.py": "1b9560bad5a8a1ceb2934f91621be231f20a8a17",
    "scripts/ci/_es80_today_final_go_foundation_impl.py": "11a571b4439829f2c3bfe94b46e0598600238d89",
    "scripts/ci/es80_today_trusted_capture_xcode_subject.py": "94d19c37d632f4d25a06cd031ff4a8c65ff1edb5",
    "scripts/ci/es80_today_final_go_publication.py": "1593f00e5950935ed8c1b0514ae11f69be3a6f50",
    "scripts/ci/es80_today_crosscheck_receipt_custody.py": "3bea883a17c9a34e8d9dd5b258824d29257886f2",
    "scripts/ci/es80_today_trusted_signed_candidate_reinspection.py": "179cb50cb1f32595722cd2a53df47111a2ca6a45",
}


class FinalGoExecutableBundleCustodyTests(unittest.TestCase):
    def handoff(self) -> str:
        return ATTESTATION.read_text(encoding="utf-8")

    def test_handoff_pins_exact_hosted_green_tooling_head(self):
        handoff = self.handoff()
        self.assertIn(f"FINAL_GO_TOOLING_HEAD='{ACCEPTED_HEAD}'", handoff)
        self.assertIn("exact hosted-green #1730 head", handoff)
        for subject in (*ACCEPTED_RUNS, *ACCEPTED_JOBS):
            with self.subTest(subject=subject):
                self.assertIn(subject, handoff)

    def test_handoff_checks_exact_tree_and_raw_checkout_bytes_for_every_authority_module(self):
        handoff = self.handoff()
        self.assertIn('status --porcelain=v1 --untracked-files=all', handoff)
        self.assertIn('rev-parse --verify "$FINAL_GO_TOOLING_HEAD:$path"', handoff)
        self.assertIn('hash-object --no-filters -- "$path"', handoff)
        for path, blob in BUNDLE.items():
            with self.subTest(path=path):
                self.assertIn(f"verify_final_go_blob {path} {blob}", handoff)

    def test_current_authority_module_bytes_still_equal_accepted_bundle(self):
        for relative_path, expected_blob in BUNDLE.items():
            with self.subTest(path=relative_path):
                completed = subprocess.run(
                    (
                        "/usr/bin/git",
                        "-C",
                        str(REPOSITORY_ROOT),
                        "hash-object",
                        "--no-filters",
                        "--",
                        relative_path,
                    ),
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False,
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(completed.stdout.strip(), expected_blob)

    def test_hardener_loads_only_the_pinned_local_authority_siblings(self):
        source = HARDENER.read_text(encoding="utf-8")
        expected_loaded_names = {
            "_es80_today_final_go_foundation_impl.py",
            "es80_today_trusted_capture_xcode_subject.py",
            "es80_today_final_go_publication.py",
            "es80_today_crosscheck_receipt_custody.py",
            "es80_today_trusted_signed_candidate_reinspection.py",
        }
        loaded_names = set(re.findall(r'_load\(\s*"[^"]+",\s*"([^"]+\.py)"\s*\)', source))
        self.assertEqual(loaded_names, expected_loaded_names)

    def test_invocation_uses_isolated_python_from_verified_worktree_and_same_tooling_repo(self):
        handoff = self.handoff()
        invocation = '/usr/bin/python3 -I "$FINAL_GO_TOOLING_SOURCE/scripts/ci/es80_today_final_go_hardened.py"'
        tooling_argument = '--tooling-repo "$FINAL_GO_TOOLING_SOURCE"'
        self.assertGreaterEqual(handoff.count(invocation), 2)
        self.assertIn(tooling_argument, handoff)
        self.assertIn("Do **not** run a moving `main`", handoff)
        self.assertIn("PHYSICAL EXPERIMENT ONE REMAINS NO-GO", handoff)


if __name__ == "__main__":
    unittest.main()
