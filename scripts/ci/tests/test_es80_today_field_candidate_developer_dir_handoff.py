#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HANDOFF_PATH = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"


class FieldCandidateDeveloperDirHandoffTests(unittest.TestCase):
    def test_handoff_clears_ambient_developer_dir_before_preflight_and_producer(self):
        handoff = HANDOFF_PATH.read_text(encoding="utf-8")
        unset_guard = "unset DEVELOPER_DIR"
        absent_guard = 'test -z "${DEVELOPER_DIR+x}"'
        preflight_invocation = '/usr/bin/python3 -I "$PREFLIGHT"'
        producer_invocation = "./scripts/ci/xcode27_today_research_field_candidate.sh"

        self.assertIn(unset_guard, handoff)
        self.assertGreaterEqual(handoff.count(absent_guard), 3)
        self.assertIn(preflight_invocation, handoff)
        self.assertIn(producer_invocation, handoff)
        self.assertLess(handoff.index(unset_guard), handoff.index(preflight_invocation))
        self.assertLess(handoff.index(unset_guard), handoff.index(producer_invocation))

        preflight_guard = handoff.rfind(absent_guard, 0, handoff.index(preflight_invocation))
        producer_guard = handoff.rfind(absent_guard, 0, handoff.index(producer_invocation))
        self.assertGreater(preflight_guard, handoff.index(unset_guard))
        self.assertGreater(producer_guard, handoff.index(preflight_invocation))

    def test_handoff_never_reintroduces_a_developer_dir_override(self):
        handoff = HANDOFF_PATH.read_text(encoding="utf-8")
        self.assertIsNone(
            re.search(r"(?m)^\s*(?:export\s+)?DEVELOPER_DIR=", handoff),
            "The signed-field handoff must select Xcode through xcode-select, not a caller DEVELOPER_DIR override.",
        )
        self.assertIn("xcode-select", handoff)
        self.assertIn("DEVELOPER_DIR", handoff)


if __name__ == "__main__":
    unittest.main()
