#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/field/install_one_time_capture.command")
text = path.read_text(encoding="utf-8")
old_accepted = 'HELPER_ACCEPTED_BLOB="$(git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE" 2>/dev/null || true)"'
new_accepted = 'HELPER_ACCEPTED_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE" 2>/dev/null || true)"'
old_actual = 'HELPER_ACTUAL_BLOB="$(git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE" 2>/dev/null || true)"'
new_actual = 'HELPER_ACTUAL_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE" 2>/dev/null || true)"'
if text.count(old_accepted) != 1:
    raise SystemExit("expected one ordinary helper accepted-blob lookup")
if text.count(old_actual) != 1:
    raise SystemExit("expected one ordinary helper worktree blob lookup")
text = text.replace(old_accepted, new_accepted, 1).replace(old_actual, new_actual, 1)
path.write_text(text, encoding="utf-8")
