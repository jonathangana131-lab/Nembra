#!/usr/bin/env python3
"""Expected-red proof that Final GO accepts non-IPA bytes as a signed field candidate."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

TEST_DIR = Path(__file__).resolve().parent
CI_DIR = TEST_DIR.parent


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


foundation = load(
    "nembra_final_go_signed_candidate_authenticity_red_foundation",
    CI_DIR / "es80_today_final_go_foundation.py",
)
fixture_module = load(
    "nembra_final_go_signed_candidate_authenticity_red_fixture",
    TEST_DIR / "test_es80_today_final_go_record.py",
)
fixture_module.final_go = foundation


class SignedCandidateAuthenticityExpectedRedTests(unittest.TestCase):
    def test_non_ipa_bytes_cannot_be_promoted_by_caller_authored_inspection_json(self):
        fixture = fixture_module.FinalGoRecordTests(
            methodName="test_valid_exact_subjects_emit_go_but_no_physical_result"
        )

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture.make_candidate(root)
            candidate_root = root / "candidate"
            ipa = candidate_root / "inspection" / foundation.IPA_RELATIVE_PATH

            # This is the repository's existing nominal-green fixture: literal bytes, not a ZIP/IPA.
            self.assertEqual(ipa.read_bytes(), b"exact-retained-ipa")

            # V14 contract: caller-authored inspection metadata must not be able to manufacture
            # Apple signing/provisioning authority for bytes that are not even an IPA container.
            # Current _candidate_subject hashes the bytes and trusts matching JSON claims, so this
            # assertion is intentionally RED until the exact retained IPA is independently
            # inspected or its inspection receipt has non-caller-forgeable producer/custody proof.
            with self.assertRaises(foundation.FinalGoError):
                foundation._candidate_subject(candidate_root, fixture.SOURCE, fixture.NOW)


if __name__ == "__main__":
    unittest.main()
