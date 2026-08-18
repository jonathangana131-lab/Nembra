#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HANDOFF_PATH = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"


class FieldSourceScopeTests(unittest.TestCase):
    def handoff(self) -> str:
        return HANDOFF_PATH.read_text(encoding="utf-8")

    def test_retired_handoff_has_no_frozen_field_source_command_sequence(self):
        handoff = self.handoff()
        stale_source_markers = (
            "## 3. Set the signing inputs without changing the source subject",
            "## 3A. Run the accepted non-authorizing pre-signing preflight",
            'test "$(/usr/bin/git -C "$FIELD_SOURCE" rev-parse --verify HEAD^{commit})" = "$SOURCE_SHA"',
            'test -z "$(/usr/bin/git -C "$FIELD_SOURCE" status --porcelain=v1 --untracked-files=all)"',
            'cd "$TOOL_REPO"',
            '/usr/bin/git -C "$FIELD_SOURCE" rev-parse --verify HEAD^{commit}',
        )

        self.assertIn("RETIRED / NON-AUTHORIZING", handoff)
        self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", handoff)
        self.assertIn("fresh GitHub state", handoff)
        for marker in stale_source_markers:
            with self.subTest(marker=marker):
                self.assertNotIn(marker, handoff)

    def test_retired_handoff_does_not_expose_an_alternate_source_authority_recipe(self):
        handoff = self.handoff()
        self.assertNotIn("FIELD_SOURCE=", handoff)
        self.assertNotIn("SOURCE_SHA=", handoff)
        self.assertNotIn("git clone", handoff)
        self.assertNotIn("git checkout", handoff)
        self.assertIn("old exact-head green run", handoff)
        self.assertIn("cannot substitute for the exact current candidate", handoff)

    def test_retired_handoff_contains_no_executable_bash_blocks(self):
        handoff = self.handoff()
        blocks = re.findall(r"```bash\n(.*?)```", handoff, flags=re.DOTALL)
        self.assertEqual(blocks, [])


if __name__ == "__main__":
    unittest.main()
