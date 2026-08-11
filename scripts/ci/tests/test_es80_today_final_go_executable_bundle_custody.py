#!/usr/bin/env python3
from __future__ import annotations

import ast
from pathlib import Path
import subprocess
import sys
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
ATTESTATION = REPOSITORY_ROOT / "docs" / "ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md"
HARDENER = REPOSITORY_ROOT / "scripts" / "ci" / "es80_today_final_go_hardened.py"


class FinalGoExecutableBundleCustodyTests(unittest.TestCase):
    def handoff(self) -> str:
        return ATTESTATION.read_text(encoding="utf-8")

    def test_operator_handoff_is_explicitly_retired_and_non_authorizing(self):
        handoff = self.handoff()
        self.assertIn("RETIRED / NON-AUTHORIZING", handoff)
        self.assertIn("ES80-FINGERPRINT-v1", handoff)
        self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", handoff)
        self.assertIn("PHYSICAL STATUS: NO-GO", handoff)
        self.assertIn("do not run the old passive workflow", handoff)
        self.assertNotIn("FINAL_GO_TOOLING_HEAD=", handoff)
        self.assertNotIn("verify_final_go_blob", handoff)
        self.assertNotIn("/usr/bin/python3 -I \"$FINAL_GO_TOOLING_SOURCE/scripts/ci/es80_today_final_go_hardened.py\"", handoff)

    def test_retired_hardener_real_execution_fails_before_publication(self):
        completed = subprocess.run(
            (
                sys.executable,
                str(HARDENER),
                "--output",
                "/tmp/nembra-retired-final-go-custody-test.json",
            ),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(completed.stdout, "")
        self.assertIn("retired ES80-FINGERPRINT-v1 Final GO authority is non-authorizing", completed.stderr)
        self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", completed.stderr)
        self.assertNotIn("TODAY Final GO record:", completed.stderr)

    def test_retirement_fence_precedes_old_builder_and_publisher_in_main(self):
        tree = ast.parse(HARDENER.read_text(encoding="utf-8"))
        main = next(
            node
            for node in tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "main"
        )
        calls = [
            node.func.id
            for node in ast.walk(main)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
        ]
        self.assertNotIn("build_final_go_record", calls)
        self.assertNotIn("publish_record_no_replace", calls)
        source = ast.get_source_segment(HARDENER.read_text(encoding="utf-8"), main) or ""
        self.assertIn("RETIRED_DIRECT_EXECUTION_MESSAGE", source)

    def test_historical_validator_loads_only_local_authority_siblings(self):
        tree = ast.parse(HARDENER.read_text(encoding="utf-8"))
        expected_loaded_names = {
            "_es80_today_final_go_foundation_impl.py",
            "es80_today_trusted_capture_xcode_subject.py",
            "es80_today_final_go_publication.py",
            "es80_today_crosscheck_receipt_custody.py",
            "es80_today_trusted_signed_candidate_reinspection.py",
        }
        loaded_names: set[str] = set()
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            if not isinstance(node.func, ast.Name) or node.func.id != "_load":
                continue
            if len(node.args) < 2:
                self.fail("historical Final GO _load call lost its explicit filename argument")
            filename = node.args[1]
            if not isinstance(filename, ast.Constant) or not isinstance(filename.value, str):
                self.fail("historical Final GO _load filename must remain a static string")
            loaded_names.add(filename.value)
        self.assertEqual(loaded_names, expected_loaded_names)


if __name__ == "__main__":
    unittest.main()
