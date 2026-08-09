#!/usr/bin/env python3
"""Permanent regression for validation #1579's caller-authored crosscheck bypass."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

CI_DIR = Path(__file__).resolve().parents[1]
FOUNDATION_PATH = CI_DIR / "es80_today_final_go_foundation.py"
spec = importlib.util.spec_from_file_location("foundation_crosscheck_custody", FOUNDATION_PATH)
foundation = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(foundation)


class CrosscheckReceiptCustodyTests(unittest.TestCase):
    def test_plain_json_cannot_call_semantic_crosscheck_as_independent_authority(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = root / "caller.json"
            receipt.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "authority": foundation.CROSSCHECK_AUTHORITY,
                        "status": "PASS_NOT_FINAL_GO",
                        "sourceCommitSHA": "a" * 40,
                        "physicalExperimentAuthorization": "not-granted",
                    },
                    sort_keys=True,
                ),
                encoding="utf-8",
            )
            source_repo = root / "source"
            tooling_repo = root / "tooling"
            source_repo.mkdir()
            tooling_repo.mkdir()

            with self.assertRaisesRegex(
                foundation.FinalGoError,
                "pinned producer execution",
            ):
                foundation._crosscheck_subject(
                    receipt,
                    {"sourceCommitSHA": "a" * 40},
                    source_repo,
                    tooling_repo,
                )

    def test_foundation_builder_contains_mandatory_trusted_execution_hook(self):
        source = FOUNDATION_PATH.read_text(encoding="utf-8")
        self.assertIn("trusted_execution = _trusted_crosscheck_receipt(", source)
        self.assertIn("_impl._crosscheck_subject = authenticated_crosscheck_subject", source)
        self.assertIn('subject["trustedProducerExecution"] = trusted_execution', source)
        self.assertIn("_impl._crosscheck_subject = original_crosscheck_subject", source)


if __name__ == "__main__":
    unittest.main()
