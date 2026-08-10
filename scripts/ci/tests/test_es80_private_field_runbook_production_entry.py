#!/usr/bin/env python3
from pathlib import Path
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
RUNBOOK = REPOSITORY_ROOT / "docs" / "ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md"


class PrivateFieldRunbookProductionEntryTests(unittest.TestCase):
    def test_private_signing_blocker_routes_through_canonical_production_handoff(self):
        runbook = RUNBOOK.read_text(encoding="utf-8")
        blockers = runbook.split("## Current NO-GO blockers", 1)[1].split(
            "## Final GO Record", 1
        )[0]

        self.assertIn(
            "docs/ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md",
            blockers,
        )
        self.assertIn(
            "Do not invoke the TODAY wrapper directly from this runbook.",
            blockers,
        )
        self.assertIn("descriptor-bound ExportOptions custody/coherence", blockers)
        self.assertIn("`DEVELOPER_DIR` / `xcode-select` coherence gate", blockers)
        self.assertIn("PENDING PRIVATE SIGNING SURFACE", blockers)

    def test_next_legal_transition_cannot_bypass_canonical_production_gate(self):
        runbook = RUNBOOK.read_text(encoding="utf-8")
        handoff = runbook.split(
            "## Private signed-candidate handoff — next legal transition", 1
        )[1].split("## Preflight once Final GO exists", 1)[0]

        self.assertIn(
            "docs/ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md",
            handoff,
        )
        self.assertIn("mandatory production entrypoint", handoff)
        self.assertIn("READY_TO_INVOKE_SIGNED_FIELD_PRODUCER", handoff)
        self.assertIn(
            "do not invoke `scripts/ci/xcode27_today_research_field_candidate.sh` directly",
            handoff.lower(),
        )
        self.assertNotIn(
            "3. Run `scripts/ci/xcode27_today_research_field_candidate.sh`",
            handoff,
        )
        self.assertIn(
            "docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md",
            handoff,
        )
        self.assertIn("scripts/ci/es80_today_final_go_hardened.py", handoff)

    def test_frozen_subject_and_physical_no_go_remain_explicit(self):
        runbook = RUNBOOK.read_text(encoding="utf-8")
        self.assertIn(
            "#833@a0f4a33451f61411d6e0541f2e70edea5438342d",
            runbook,
        )
        self.assertIn("NO-GO / DO NOT RUN / DO NOT SCAN", runbook)
        self.assertIn("First real ES80 artifact: **NOT YET COLLECTED**", runbook)
        self.assertIn("Signed intended-device Research Field Build: **NOT YET PRODUCED", runbook)


if __name__ == "__main__":
    unittest.main()
