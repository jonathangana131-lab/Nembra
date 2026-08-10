#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HANDOFF_PATH = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"


class FieldSourceScopeTests(unittest.TestCase):
    def handoff(self) -> str:
        return HANDOFF_PATH.read_text(encoding="utf-8")

    def section_three(self) -> str:
        handoff = self.handoff()
        return handoff.split(
            "## 3. Set the signing inputs without changing the source subject",
            1,
        )[1].split(
            "## 3A. Run the accepted non-authorizing pre-signing preflight",
            1,
        )[0]

    def test_section_three_scopes_sha_and_cleanliness_to_frozen_field_source(self):
        section = self.section_three()
        self.assertIn(
            'test "$(/usr/bin/git -C "$FIELD_SOURCE" rev-parse --verify HEAD^{commit})" = "$SOURCE_SHA"',
            section,
        )
        self.assertIn(
            'test -z "$(/usr/bin/git -C "$FIELD_SOURCE" status --porcelain=v1 --untracked-files=all)"',
            section,
        )

    def test_section_three_never_uses_current_working_directory_as_source_authority(self):
        section = self.section_three()
        self.assertNotIn(
            'test "$(/usr/bin/git rev-parse --verify HEAD^{commit})" = "$SOURCE_SHA"',
            section,
        )
        self.assertNotIn(
            'test -z "$(/usr/bin/git status --porcelain=v1 --untracked-files=all)"',
            section,
        )
        self.assertIn("current working directory must never decide which source is admitted for signing", section)

    def test_helper_materialization_precedes_explicit_field_source_checks(self):
        handoff = self.handoff()
        helper_cwd = 'cd "$TOOL_REPO"'
        field_sha = '/usr/bin/git -C "$FIELD_SOURCE" rev-parse --verify HEAD^{commit}'
        self.assertIn(helper_cwd, handoff)
        self.assertIn(field_sha, handoff)
        self.assertLess(handoff.index(helper_cwd), handoff.index(field_sha))

    def test_all_bash_blocks_remain_syntactically_valid(self):
        handoff = self.handoff()
        blocks = re.findall(r"```bash\n(.*?)```", handoff, flags=re.DOTALL)
        self.assertGreaterEqual(len(blocks), 5)
        for index, block in enumerate(blocks):
            with self.subTest(block=index):
                completed = subprocess.run(
                    ("/bin/bash", "-n"),
                    input=block,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False,
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)


if __name__ == "__main__":
    unittest.main()
