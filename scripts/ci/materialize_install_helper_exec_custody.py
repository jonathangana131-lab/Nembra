#!/usr/bin/env python3
from pathlib import Path

installer = Path("scripts/field/install_one_time_capture.command")
source = installer.read_text(encoding="utf-8")

old_tools = '''[[ -x /usr/bin/find ]] || die "System find is required to seal staged signed-app ownership without following symlinks."\n[[ -x /usr/sbin/chown ]] || die "System chown is required to root-own the staged signed-app install subject."\n'''
new_tools = '''[[ -x /usr/bin/find ]] || die "System find is required to seal staged signed-app ownership without following symlinks."\n[[ -x /usr/sbin/chown ]] || die "System chown is required to root-own the staged signed-app install subject."\n[[ -x /usr/bin/tee ]] || die "System tee is required to materialize the accepted custody-helper Git blob into protected staging."\n[[ -x /usr/bin/git ]] || die "System git is required to bind the custody helper to the accepted replacement-blind Git object."\n'''
if source.count(old_tools) != 1:
    raise SystemExit("installer tool marker drifted")
source = source.replace(old_tools, new_tools, 1)

start = source.index('SIGNED_APP_CUSTODY_HELPER_RELATIVE="scripts/ci/capture_signed_app_install_custody.py"')
end_marker = 'APP_INFO_PLIST="$APP/Info.plist"\n'
end = source.index(end_marker, start) + len(end_marker)
old_block = source[start:end]
new_block = r'''SIGNED_APP_CUSTODY_HELPER_RELATIVE="scripts/ci/capture_signed_app_install_custody.py"
SIGNED_APP_CUSTODY_HELPER_WORKTREE="$ROOT/$SIGNED_APP_CUSTODY_HELPER_RELATIVE"
[[ -f "$SIGNED_APP_CUSTODY_HELPER_WORKTREE" && ! -L "$SIGNED_APP_CUSTODY_HELPER_WORKTREE" ]] || die "Signed-app install custody helper is missing or symlinked in the exact accepted source."
HELPER_INDEX_VERBOSE="$(/usr/bin/git ls-files -v -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE")"
HELPER_INDEX_TAGGED="$(/usr/bin/git ls-files -t -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE")"
[[ "$HELPER_INDEX_VERBOSE" =~ ^[A-Z][[:space:]] ]] || die "Signed-app install custody helper has suppressed assume-unchanged/index authority."
[[ "$HELPER_INDEX_TAGGED" != S\ * ]] || die "Signed-app install custody helper has suppressed skip-worktree authority."
HELPER_ACCEPTED_BLOB="$(/usr/bin/env GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE" 2>/dev/null || true)"
HELPER_ACTUAL_BLOB="$(/usr/bin/env GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE" 2>/dev/null || true)"
[[ "$HELPER_ACCEPTED_BLOB" =~ ^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$ ]] || die "Signed-app install custody helper has no valid replacement-blind accepted Git blob."
[[ "$HELPER_ACTUAL_BLOB" == "$HELPER_ACCEPTED_BLOB" ]] || die "Signed-app install custody helper worktree bytes differ from the exact accepted Git blob."

# The helper itself is part of physical install authority. A point-in-time worktree hash is not
# enough because a same-UID process could replace that pathname before Python reopens it. Materialize
# the exact replacement-blind HEAD blob into the same root-owned custody root before executing it.
APP_INSTALL_STAGE_ROOT=""
INSTALL_LOG=""
cleanup_install_subject() {
    if [[ -n "${INSTALL_LOG:-}" ]]; then
        /bin/rm -f -- "$INSTALL_LOG" || true
    fi
    if [[ -n "${APP_INSTALL_STAGE_ROOT:-}" ]]; then
        /usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" >/dev/null 2>&1 || true
    fi
}
trap cleanup_install_subject EXIT
APP_INSTALL_STAGE_ROOT="$(/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-authenticated-capture-install.XXXXXX)" || \
    die "Could not create the root-owned signed-app install custody directory."
[[ "$APP_INSTALL_STAGE_ROOT" == /private/tmp/nembra-authenticated-capture-install.* ]] || \
    die "Protected signed-app install custody directory is outside the canonical private temporary root."
APP_INSTALL_CUSTODY_HELPER="$APP_INSTALL_STAGE_ROOT/capture_signed_app_install_custody.py"
if ! /usr/bin/env GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git cat-file blob "$HELPER_ACCEPTED_BLOB" | \
    /usr/bin/sudo /usr/bin/tee "$APP_INSTALL_CUSTODY_HELPER" >/dev/null
then
    die "Could not materialize the exact accepted custody-helper Git blob into protected staging."
fi
/usr/bin/sudo /usr/sbin/chown root:wheel "$APP_INSTALL_CUSTODY_HELPER" || \
    die "Could not root-own the exact staged custody helper."
/usr/bin/sudo /bin/chmod 0555 "$APP_INSTALL_CUSTODY_HELPER" || \
    die "Could not make the exact staged custody helper immutable to the invoking user."
/usr/bin/sudo /bin/chmod 0755 "$APP_INSTALL_STAGE_ROOT" || \
    die "Could not expose read-only traversal of the protected install-custody root."
STAGED_HELPER_BLOB="$(/usr/bin/env GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git hash-object --no-filters -- "$APP_INSTALL_CUSTODY_HELPER" 2>/dev/null || true)"
[[ "$STAGED_HELPER_BLOB" == "$HELPER_ACCEPTED_BLOB" ]] || \
    die "Protected custody helper bytes differ from the exact accepted replacement-blind Git blob."
SIGNED_APP_CUSTODY_HELPER="$APP_INSTALL_CUSTODY_HELPER"

SOURCE_APP_TREE_SHA256="$(/usr/bin/python3 -I "$SIGNED_APP_CUSTODY_HELPER" fingerprint --app "$APP")" || \
    die "Could not bind the exact post-build signed-app tree before protected staging."
[[ "$SOURCE_APP_TREE_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "Signed-app tree fingerprint is malformed."

# devicectl reopens an app bundle by pathname. A normal DerivedData path remains mutable by the
# invoking user after signature/provenance review, so it cannot itself be the physical install
# authority. Snapshot the exact finite tree through root into the already-protected staging root.
# Every later authority check and the actual install operate on this same protected pathname.
APP_INSTALL_STAGE="$APP_INSTALL_STAGE_ROOT/Nembra Capture.app"
/usr/bin/sudo /usr/bin/ditto "$APP" "$APP_INSTALL_STAGE" || \
    die "Could not snapshot the exact signed app into protected install custody."
# The stage root is root-owned and non-writable by the invoking UID. BSD find does not follow
# symlinks by default; chown -h changes a symlink object rather than an external target. The
# verifier rejects broken/escaping links before the staged app earns any authority.
/usr/bin/sudo /usr/bin/find "$APP_INSTALL_STAGE" -exec /usr/sbin/chown -h root:wheel {} + || \
    die "Could not root-own every protected signed-app install entry."
STAGED_HELPER_BLOB_AFTER_COPY="$(/usr/bin/env GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER" 2>/dev/null || true)"
[[ "$STAGED_HELPER_BLOB_AFTER_COPY" == "$HELPER_ACCEPTED_BLOB" ]] || \
    die "Protected custody helper changed before staged-app verification."
STAGED_APP_TREE_SHA256="$(/usr/bin/python3 -I "$SIGNED_APP_CUSTODY_HELPER" verify-stage \
    --stage-root "$APP_INSTALL_STAGE_ROOT" \
    --app "$APP_INSTALL_STAGE" \
    --expected "$SOURCE_APP_TREE_SHA256")" || \
    die "Protected signed-app install subject failed root-owned custody or exact-tree verification."
[[ "$STAGED_APP_TREE_SHA256" == "$SOURCE_APP_TREE_SHA256" ]] || \
    die "Protected signed-app install subject differs from the exact post-build signed app."
APP="$APP_INSTALL_STAGE"
APP_INFO_PLIST="$APP/Info.plist"
'''.replace('\\"', '"')
source = source[:start] + new_block + source[end:]

old_unset = 'unset SOURCE_APP_TREE_SHA256 STAGED_APP_TREE_SHA256 SIGNED_APP_CUSTODY_HELPER APP_INSTALL_STAGE\n'
new_unset = 'unset SOURCE_APP_TREE_SHA256 STAGED_APP_TREE_SHA256 SIGNED_APP_CUSTODY_HELPER SIGNED_APP_CUSTODY_HELPER_WORKTREE SIGNED_APP_CUSTODY_HELPER_RELATIVE APP_INSTALL_CUSTODY_HELPER APP_INSTALL_STAGE HELPER_ACCEPTED_BLOB HELPER_ACTUAL_BLOB STAGED_HELPER_BLOB STAGED_HELPER_BLOB_AFTER_COPY\n'
if source.count(old_unset) != 1:
    raise SystemExit("installer success cleanup marker drifted")
source = source.replace(old_unset, new_unset, 1)
installer.write_text(source, encoding="utf-8")

# Strengthen source-contract tests so the helper's own execution subject cannot regress to a
# mutable checkout path between a blob check and Python execution.
test = Path("scripts/ci/tests/test_capture_signed_app_install_custody.py")
text = test.read_text(encoding="utf-8")
text = text.replace(
    'fingerprint_marker = \'capture_signed_app_install_custody.py" fingerprint --app "$APP"\'\n',
    'fingerprint_marker = \'"$SIGNED_APP_CUSTODY_HELPER" fingerprint --app "$APP"\'\n',
    1,
)
text = text.replace(
    'verify_stage_marker = \'capture_signed_app_install_custody.py" verify-stage\'\n',
    'verify_stage_marker = \'"$SIGNED_APP_CUSTODY_HELPER" verify-stage\'\n',
    1,
)
old_assertions = '''        self.assertIn('git ls-files -v -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)\n        self.assertIn('git ls-files -t -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)\n        self.assertIn('git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)\n        self.assertIn('git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)\n        self.assertLess(source.find('HELPER_ACTUAL_BLOB='), indexes["fingerprint"])\n'''
new_assertions = '''        helper_blob = source.find('GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE"')\n        helper_materialize = source.find('GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git cat-file blob "$HELPER_ACCEPTED_BLOB"')\n        helper_stage_hash = source.find('git hash-object --no-filters -- "$APP_INSTALL_CUSTODY_HELPER"')\n        helper_switch = source.find('SIGNED_APP_CUSTODY_HELPER="$APP_INSTALL_CUSTODY_HELPER"')\n        for marker in (helper_blob, helper_materialize, helper_stage_hash, helper_switch):\n            self.assertGreaterEqual(marker, 0)\n        self.assertIn('/usr/bin/git ls-files -v -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)\n        self.assertIn('/usr/bin/git ls-files -t -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)\n        self.assertLess(source.find('HELPER_ACTUAL_BLOB='), helper_materialize)\n        self.assertLess(helper_blob, helper_materialize)\n        self.assertLess(helper_materialize, helper_stage_hash)\n        self.assertLess(helper_stage_hash, helper_switch)\n        self.assertLess(helper_switch, indexes["fingerprint"])\n        self.assertNotIn('/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py"', source)\n'''
if text.count(old_assertions) != 1:
    raise SystemExit("helper execution assertions drifted")
text = text.replace(old_assertions, new_assertions, 1)
test.write_text(text, encoding="utf-8")
