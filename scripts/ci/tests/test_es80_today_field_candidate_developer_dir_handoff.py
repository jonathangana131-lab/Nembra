#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HANDOFF_PATH = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"


class FieldCandidateDeveloperDirHandoffTests(unittest.TestCase):
    def test_retired_handoff_has_no_xcode_selection_or_producer_recipe(self):
        handoff = HANDOFF_PATH.read_text(encoding="utf-8")

        self.assertIn("RETIRED / NON-AUTHORIZING", handoff)
        self.assertIn("PHYSICAL STATUS: NO-GO", handoff)
        self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", handoff)
        self.assertNotIn("unset DEVELOPER_DIR", handoff)
        self.assertNotIn("xcode-select", handoff)
        self.assertNotIn("xcode27_today_research_field_candidate.sh", handoff)
        self.assertNotIn("```bash", handoff)

    def test_retired_handoff_cannot_reintroduce_a_developer_dir_override(self):
        handoff = HANDOFF_PATH.read_text(encoding="utf-8")
        self.assertIsNone(
            re.search(r"(?m)^\s*(?:export\s+)?DEVELOPER_DIR=", handoff),
            "A retired field handoff must not contain an executable Xcode-selection recipe.",
        )
        self.assertIn("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md", handoff)
        self.assertIn("Do not recover an older commit", handoff)


if __name__ == "__main__":
    unittest.main()
