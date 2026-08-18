#!/usr/bin/env python3
from pathlib import Path
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
RUNBOOK = REPOSITORY_ROOT / "docs" / "ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md"
ATTESTATION = REPOSITORY_ROOT / "docs" / "ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md"


class PrivateFieldRunbookRetirementTests(unittest.TestCase):
    def test_retired_runbook_is_explicitly_non_authorizing_and_no_go(self):
        runbook = RUNBOOK.read_text(encoding="utf-8")

        self.assertIn("RETIRED / NON-AUTHORIZING", runbook)
        self.assertIn("PHYSICAL STATUS: NO-GO", runbook)
        self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", runbook)
        self.assertIn("do not scan the ES80", runbook)
        self.assertIn("do not run the retired passive TODAY workflow", runbook)
        self.assertIn("stationary and observational/read-only", runbook)

    def test_retired_runbook_cannot_resurrect_old_exact_subject_or_producer_path(self):
        runbook = RUNBOOK.read_text(encoding="utf-8")

        self.assertNotIn(
            "#833@a0f4a33451f61411d6e0541f2e70edea5438342d",
            runbook,
        )
        self.assertNotIn("Capture Build V14-a0f4a33451f6", runbook)
        self.assertNotIn("READY_TO_INVOKE_SIGNED_FIELD_PRODUCER", runbook)
        self.assertNotIn("scripts/ci/xcode27_today_research_field_candidate.sh", runbook)
        self.assertNotIn("scripts/ci/es80_today_final_go_hardened.py", runbook)

    def test_retired_attestation_is_treated_only_as_retirement_signal(self):
        runbook = RUNBOOK.read_text(encoding="utf-8")
        attestation = ATTESTATION.read_text(encoding="utf-8")

        self.assertIn("docs/ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md", runbook)
        self.assertIn("also retired and non-authorizing", runbook)
        self.assertIn("RETIRED / NON-AUTHORIZING", attestation)
        self.assertIn("PHYSICAL STATUS: NO-GO", attestation)
        self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", attestation)

    def test_next_legal_transition_requires_fresh_authenticated_stationary_authority(self):
        runbook = RUNBOOK.read_text(encoding="utf-8")
        transition = runbook.split("## Current legal next transition", 1)[1].split(
            "## Historical recovery", 1
        )[0]

        self.assertIn("live authenticated-stationary lineage", transition)
        self.assertIn("exact candidate", transition)
        self.assertIn("at least 45 seconds", transition)
        self.assertIn("remain **NO-GO**", transition)
        self.assertIn("Never recover an older commit", transition)


if __name__ == "__main__":
    unittest.main()
