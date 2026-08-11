#!/usr/bin/env python3
from pathlib import Path

installer = Path("scripts/field/install_one_time_capture.command")
source = installer.read_text(encoding="utf-8")
old = '''SIGNED_APP_CUSTODY_HELPER="$ROOT/scripts/ci/capture_signed_app_install_custody.py"\n[[ -f "$SIGNED_APP_CUSTODY_HELPER" ]] || die "Signed-app install custody helper is missing from the exact accepted source."\nSOURCE_APP_TREE_SHA256="$(/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" fingerprint --app "$APP")" || \\
'''
new = '''SIGNED_APP_CUSTODY_HELPER_RELATIVE="scripts/ci/capture_signed_app_install_custody.py"\nSIGNED_APP_CUSTODY_HELPER="$ROOT/$SIGNED_APP_CUSTODY_HELPER_RELATIVE"\n[[ -f "$SIGNED_APP_CUSTODY_HELPER" && ! -L "$SIGNED_APP_CUSTODY_HELPER" ]] || die "Signed-app install custody helper is missing or symlinked in the exact accepted source."\nHELPER_INDEX_VERBOSE="$(git ls-files -v -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE")"\nHELPER_INDEX_TAGGED="$(git ls-files -t -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE")"\n[[ "$HELPER_INDEX_VERBOSE" =~ ^[A-Z][[:space:]] ]] || die "Signed-app install custody helper has suppressed assume-unchanged/index authority."\n[[ "$HELPER_INDEX_TAGGED" != S\ * ]] || die "Signed-app install custody helper has suppressed skip-worktree authority."\nHELPER_ACCEPTED_BLOB="$(git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE" 2>/dev/null || true)"\nHELPER_ACTUAL_BLOB="$(git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE" 2>/dev/null || true)"\n[[ "$HELPER_ACCEPTED_BLOB" =~ ^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$ ]] || die "Signed-app install custody helper has no valid accepted Git blob."\n[[ "$HELPER_ACTUAL_BLOB" == "$HELPER_ACCEPTED_BLOB" ]] || die "Signed-app install custody helper worktree bytes differ from the exact accepted Git blob."\nSOURCE_APP_TREE_SHA256="$(/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" fingerprint --app "$APP")" || \\
'''
if source.count(old) != 1:
    raise SystemExit("helper admission marker drifted")
installer.write_text(source.replace(old, new, 1), encoding="utf-8")

test = Path("scripts/ci/tests/test_capture_signed_app_install_custody.py")
text = test.read_text(encoding="utf-8")
needle = '''        self.assertIn('[[ "$STAGED_APP_TREE_SHA256" == "$SOURCE_APP_TREE_SHA256" ]]', source)\n'''
replacement = '''        self.assertIn('git ls-files -v -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)\n        self.assertIn('git ls-files -t -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)\n        self.assertIn('git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)\n        self.assertIn('git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)\n        self.assertLess(source.find('HELPER_ACTUAL_BLOB='), indexes["fingerprint"])\n        self.assertIn('[[ "$STAGED_APP_TREE_SHA256" == "$SOURCE_APP_TREE_SHA256" ]]', source)\n'''
if text.count(needle) != 1:
    raise SystemExit("test assertion marker drifted")
test.write_text(text.replace(needle, replacement, 1), encoding="utf-8")

Path(".github/workflows/materialize-capture-signed-app-helper-self-binding.yml").unlink()
Path("scripts/ci/materialize_capture_signed_app_helper_self_binding.py").unlink()
