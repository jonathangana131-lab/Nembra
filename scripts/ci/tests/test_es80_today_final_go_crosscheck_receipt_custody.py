#!/usr/bin/env python3
"""Regression: caller-authored PASS JSON cannot impersonate the independent producer."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

CI_DIR = Path(__file__).resolve().parents[1]
FOUNDATION_PATH = CI_DIR / "es80_today_final_go_foundation.py"
spec = importlib.util.spec_from_file_location("nembra_crosscheck_receipt_custody", FOUNDATION_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load Final GO foundation")
final_go = importlib.util.module_from_spec(spec)
spec.loader.exec_module(final_go)


class CrosscheckReceiptCustodyTests(unittest.TestCase):
    SOURCE = "a" * 40

    def git_result(self, repository: Path, *arguments: str) -> str:
        subject = arguments[-1]
        if subject == f"{final_go.PINNED_CROSSCHECK_COMMIT}^{{commit}}":
            return final_go.PINNED_CROSSCHECK_COMMIT
        if subject == f"{final_go.PINNED_CROSSCHECK_COMMIT}:{final_go.CROSSCHECK_PATH}":
            if arguments[0] == "rev-parse":
                return final_go.PINNED_CROSSCHECK_BLOB
            if arguments[0] == "show":
                # Represents the exact independently pinned producer source returned by closed Git
                # custody in this unit boundary. Its output intentionally differs from caller JSON.
                return "print('{}')"
        raise AssertionError((repository, arguments))

    def test_plain_json_cannot_claim_independent_crosscheck_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate_root = root / "candidate"
            candidate_root.mkdir()
            source_repo = root / "source"
            tooling_repo = root / "tooling"
            source_repo.mkdir()
            tooling_repo.mkdir()
            receipt = root / "caller-crosscheck.json"
            receipt.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "authority": final_go.CROSSCHECK_AUTHORITY,
                        "status": "PASS_NOT_FINAL_GO",
                        "sourceCommitSHA": self.SOURCE,
                        "callerAuthored": True,
                    },
                    sort_keys=True,
                )
                + "\n",
                encoding="utf-8",
            )

            # Direct `_crosscheck_subject` consumes the implementation's closed Git seam. The
            # higher-level build composer is what temporarily maps the public seam into it.
            with mock.patch.object(final_go._impl, "_git", side_effect=self.git_result):
                with self.assertRaisesRegex(
                    final_go.FinalGoError,
                    "were not emitted by the pinned producer",
                ):
                    final_go._crosscheck_subject(
                        receipt,
                        {"sourceCommitSHA": self.SOURCE},
                        source_repo,
                        tooling_repo,
                        candidate_root=candidate_root,
                    )


if __name__ == "__main__":
    unittest.main()
