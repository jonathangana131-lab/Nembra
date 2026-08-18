#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HANDOFF_PATH = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"


class FieldCandidateDeveloperDirHandoffTests(unittest.TestCase):
    def test_retired_handoff_has_no_developer_dir_or_producer_activation_sequence(self):
        handoff = HANDOFF_PATH.read_text(encoding="utf-8")
        stale_activation_markers = (
            "unset DEVELOPER_DIR",
            'test -z "${DEVELOPER_DIR+x}"',
            '/usr/bin/python3 -I "$PREFLIGHT"',
            "./scripts/ci/xcode27_today_research_field_candidate.sh",
            "xcode-select",
        )

        self.assertIn("RETIRED / NON-AUTHORIZING", handoff)
        self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", handoff)
        self.assertIn("PHYSICAL STATUS: NO-GO", handoff)
        for marker in stale_activation_markers:
            with self.subTest(marker=marker):
                self.assertNotIn(marker, handoff)

    def test_retired_handoff_cannot_reintroduce_developer_dir_override(self):
        handoff = HANDOFF_PATH.read_text(encoding="utf-8")
        self.assertIsNone(
            re.search(r"(?m)^\s*(?:export\s+)?DEVELOPER_DIR=", handoff),
            "A retired handoff must not contain an executable DEVELOPER_DIR override.",
        )
        self.assertNotIn("DEVELOPER_DIR", handoff)
        self.assertIn("fresh GitHub state", handoff)
        self.assertIn("must not be reconstructed into current physical authority", handoff)


if __name__ == "__main__":
    unittest.main()
