#!/usr/bin/env python3
"""Expected-red V14 regression for signed-field candidate authority composition.

The independent retained-IPA reinspection helper is useful only if the one canonical hardened Final
GO executable actually invokes it before the private foundation is allowed to promote caller-supplied
signed-artifact inspection JSON into the accepted candidate subject.
"""
from pathlib import Path
import unittest

CI_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = CI_DIR.parents[1]
HARDENED = CI_DIR / "es80_today_final_go_hardened.py"
FINAL_GO_QA = REPO_ROOT / ".github/workflows/capture-today-final-go-qa.yml"


class SignedCandidateReinspectionCompositionTests(unittest.TestCase):
    def test_hardened_final_go_invokes_native_ipa_reinspection_before_foundation(self) -> None:
        source = HARDENED.read_text(encoding="utf-8")

        self.assertIn(
            '"es80_today_signed_candidate_reinspection.py"',
            source,
            "canonical Final GO must load the independent signed-IPA reinspection implementation",
        )
        self.assertIn(
            ".verify_signed_candidate_reinspection(",
            source,
            "canonical Final GO must execute independent reinspection of the exact retained IPA",
        )

        reinspection_call = source.index(".verify_signed_candidate_reinspection(")
        foundation_call = source.index("foundation.build_final_go_record(")
        self.assertLess(
            reinspection_call,
            foundation_call,
            "fresh Apple signing/provisioning reinspection must occur before foundation candidate promotion",
        )

    def test_main_final_go_qa_covers_the_reinspection_composition_boundary(self) -> None:
        workflow = FINAL_GO_QA.read_text(encoding="utf-8")
        self.assertIn(
            "scripts/ci/es80_today_signed_candidate_reinspection.py",
            workflow,
            "canonical Final GO QA must rerun when the reinspection authority changes",
        )
        self.assertIn(
            "test_es80_today_final_go_signed_reinspection_composition.py",
            workflow,
            "canonical Final GO QA must own the composition regression, not only the helper's isolated QA",
        )


if __name__ == "__main__":
    unittest.main()
