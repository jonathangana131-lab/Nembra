#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HANDOFF_PATH = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"


class FieldSourceScopeTests(unittest.TestCase):
    def handoff(self) -> str:
        return HANDOFF_PATH.read_text(encoding="utf-8")

    def test_retired_handoff_has_no_frozen_field_source_execution_scope(self):
        handoff = self.handoff()

        self.assertIn("RETIRED / NON-AUTHORIZING", handoff)
        self.assertIn("PHYSICAL STATUS: NO-GO", handoff)
        self.assertIn("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md", handoff)
        self.assertNotIn("FIELD_SOURCE=", handoff)
        self.assertNotIn('git -C "$FIELD_SOURCE"', handoff)
        self.assertNotIn("SOURCE_SHA='a0f4", handoff)

    def test_retired_handoff_contains_no_materialization_or_shell_blocks(self):
        handoff = self.handoff()

        self.assertNotIn('cd "$TOOL_REPO"', handoff)
        self.assertNotIn("```bash", handoff)
        self.assertNotIn("READY_TO_INVOKE_SIGNED_FIELD_PRODUCER", handoff)
        self.assertIn("Historical TODAY producer/helper scripts", handoff)
        self.assertIn("Do not recover an older commit", handoff)


if __name__ == "__main__":
    unittest.main()
