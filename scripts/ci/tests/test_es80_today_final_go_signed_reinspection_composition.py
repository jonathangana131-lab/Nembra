#!/usr/bin/env python3
"""V14 regression for signed-field candidate authority composition."""
from pathlib import Path
import unittest

CI_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = CI_DIR.parents[1]
HARDENED = CI_DIR / "es80_today_final_go_hardened.py"
FINAL_GO_QA = REPO_ROOT / ".github/workflows/capture-today-final-go-qa.yml"


class SignedCandidateReinspectionCompositionTests(unittest.TestCase):
    def test_hardened_final_go_invokes_native_ipa_reinspection_before_foundation(self) -> None:
        source = HARDENED.read_text(encoding="utf-8")
        self.assertIn('"es80_today_signed_candidate_reinspection.py"', source)
        self.assertIn(".verify_signed_candidate_reinspection(", source)
        self.assertLess(
            source.index(".verify_signed_candidate_reinspection("),
            source.index("foundation.build_final_go_record("),
            "fresh Apple signing/provisioning reinspection must occur before foundation candidate promotion",
        )
        self.assertIn("_cross_bind_signed_candidate(record, signed_reinspection)", source)

    def test_main_final_go_qa_covers_the_reinspection_composition_boundary(self) -> None:
        workflow = FINAL_GO_QA.read_text(encoding="utf-8")
        self.assertIn("scripts/ci/es80_today_signed_candidate_reinspection.py", workflow)
        self.assertIn("test_es80_today_final_go_signed_reinspection_composition.py", workflow)
        self.assertIn(
            "Require signed candidate native reinspection composition",
            workflow,
        )


if __name__ == "__main__":
    unittest.main()
