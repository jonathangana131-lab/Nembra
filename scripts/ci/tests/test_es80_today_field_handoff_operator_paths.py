#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
PRODUCTION_PATH = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"
CUSTODY_PATH = REPOSITORY_ROOT / "docs" / "ES80_TODAY_PRIVATE_DEVICE_INPUT_CUSTODY.md"


class FieldHandoffOperatorPathsTests(unittest.TestCase):
    HELPER_COMMIT = "b479d851a54437ef394a4901c69db2d829d280e4"
    HELPER_BLOB = "62b719e8d9afb34da6d35d696e80edf926442696"
    FROZEN_SOURCE = "a0f4a33451f61411d6e0541f2e70edea5438342d"
    FILENAME_ASSIGNMENT = 'UDID_FILENAME="es80-intended-device-$(/usr/bin/uuidgen).udid"'
    FILE_ASSIGNMENT = 'UDID_FILE="$PRIVATE_DIR/$UDID_FILENAME"'
    FILENAME_ARGUMENT = '--filename "$UDID_FILENAME"'

    def production(self) -> str:
        return PRODUCTION_PATH.read_text(encoding="utf-8")

    def custody(self) -> str:
        return CUSTODY_PATH.read_text(encoding="utf-8")

    def test_production_section_three_checks_exact_frozen_checkout_not_tooling_cwd(self):
        handoff = self.production()
        section = handoff.split("## 3. Set the signing inputs without changing the source subject", 1)[1]
        section = section.split("## 3A. Run the accepted non-authorizing pre-signing preflight", 1)[0]

        sha_check = 'test "$(/usr/bin/git -C "$FIELD_SOURCE" rev-parse --verify HEAD^{commit})" = "$SOURCE_SHA"'
        clean_check = 'test -z "$(/usr/bin/git -C "$FIELD_SOURCE" status --porcelain=v1 --untracked-files=all)"'
        self.assertIn(sha_check, section)
        self.assertIn(clean_check, section)
        self.assertNotIn('test "$(/usr/bin/git rev-parse --verify HEAD^{commit})" = "$SOURCE_SHA"', section)
        self.assertNotIn('test -z "$(/usr/bin/git status --porcelain=v1 --untracked-files=all)"', section)

    def test_both_operator_docs_bind_one_fresh_filename_to_path_and_helper_argument(self):
        for path, text in ((PRODUCTION_PATH, self.production()), (CUSTODY_PATH, self.custody())):
            with self.subTest(path=path.name):
                self.assertIn(self.FILENAME_ASSIGNMENT, text)
                self.assertIn(self.FILE_ASSIGNMENT, text)
                self.assertIn(self.FILENAME_ARGUMENT, text)
                self.assertNotIn('UDID_FILE="$PRIVATE_DIR/es80-intended-device.udid"', text)
                self.assertLess(text.index(self.FILENAME_ASSIGNMENT), text.index(self.FILE_ASSIGNMENT))
                self.assertLess(text.index(self.FILE_ASSIGNMENT), text.index(self.FILENAME_ARGUMENT))

    def test_both_operator_docs_pin_same_current_nondestructive_helper(self):
        for path, text in ((PRODUCTION_PATH, self.production()), (CUSTODY_PATH, self.custody())):
            with self.subTest(path=path.name):
                self.assertIn(self.HELPER_COMMIT, text)
                self.assertIn(self.HELPER_BLOB, text)
                self.assertIn("never unlinks a pathname", text)
                self.assertIn("zero-length spent subject", text)
                self.assertIn(self.FROZEN_SOURCE, text)
                self.assertIn("PHYSICAL EXPERIMENT ONE REMAINS NO-GO", text)

    def test_all_operator_bash_blocks_are_syntactically_valid(self):
        for path, text in ((PRODUCTION_PATH, self.production()), (CUSTODY_PATH, self.custody())):
            blocks = re.findall(r"```bash\n(.*?)```", text, flags=re.DOTALL)
            self.assertGreaterEqual(len(blocks), 1, path.name)
            for index, block in enumerate(blocks):
                with self.subTest(path=path.name, block=index):
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
