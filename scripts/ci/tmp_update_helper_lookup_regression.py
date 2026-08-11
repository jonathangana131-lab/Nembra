#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/ci/tests/test_capture_signed_app_install_custody.py")
text = path.read_text(encoding="utf-8")
old_accepted = "accepted_blob = 'HELPER_ACCEPTED_BLOB=\"$(git rev-parse \"HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE\"'"
new_accepted = "accepted_blob = 'HELPER_ACCEPTED_BLOB=\"$(GIT_NO_REPLACE_OBJECTS=1 git rev-parse \"HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE\"'"
old_actual = "actual_blob = 'HELPER_ACTUAL_BLOB=\"$(git hash-object --no-filters -- \"$SIGNED_APP_CUSTODY_HELPER_RELATIVE\"'"
new_actual = "actual_blob = 'HELPER_ACTUAL_BLOB=\"$(GIT_NO_REPLACE_OBJECTS=1 git hash-object --no-filters -- \"$SIGNED_APP_CUSTODY_HELPER_RELATIVE\"'"
old_assert_accepted = "self.assertIn('git rev-parse \"HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE\"', source)"
new_assert_accepted = "self.assertIn('GIT_NO_REPLACE_OBJECTS=1 git rev-parse \"HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE\"', source)"
old_assert_actual = "self.assertIn('git hash-object --no-filters -- \"$SIGNED_APP_CUSTODY_HELPER_RELATIVE\"', source)"
new_assert_actual = "self.assertIn('GIT_NO_REPLACE_OBJECTS=1 git hash-object --no-filters -- \"$SIGNED_APP_CUSTODY_HELPER_RELATIVE\"', source)"
for old in (old_accepted, old_actual, old_assert_accepted, old_assert_actual):
    if text.count(old) != 1:
        raise SystemExit(f"expected exactly one regression marker: {old}")
text = text.replace(old_accepted, new_accepted, 1)
text = text.replace(old_actual, new_actual, 1)
text = text.replace(old_assert_accepted, new_assert_accepted, 1)
text = text.replace(old_assert_actual, new_assert_actual, 1)
path.write_text(text, encoding="utf-8")
