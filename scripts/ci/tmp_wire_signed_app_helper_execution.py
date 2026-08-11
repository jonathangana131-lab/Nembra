#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/field/install_one_time_capture.command")
text = path.read_text(encoding="utf-8")

authority_marker = '[[ "$HELPER_ACTUAL_BLOB" == "$HELPER_ACCEPTED_BLOB" ]] || die "Signed-app install custody helper worktree bytes differ from the exact accepted Git blob."\n'
if text.count(authority_marker) != 1:
    raise SystemExit("expected exact helper authority marker once")

protected_subject = '''[[ "$HELPER_ACTUAL_BLOB" == "$HELPER_ACCEPTED_BLOB" ]] || die "Signed-app install custody helper worktree bytes differ from the exact accepted Git blob."

# Do not reopen the user-writable checkout helper after its Git authority check. Materialize the
# exact accepted Git blob through root into a private stage, seal it root-owned/non-writable before
# exposing read traversal, then re-hash that protected file to the accepted object identity. The
# same protected helper pathname is reused for both fingerprint and verify-stage authority calls.
# A same-UID process can read it but cannot replace or modify either the root-owned parent or file.
HELPER_EXECUTION_STAGE_ROOT=""
cleanup_helper_execution_subject() {
    if [[ -n "${HELPER_EXECUTION_STAGE_ROOT:-}" ]]; then
        /usr/bin/sudo /bin/rm -rf -- "$HELPER_EXECUTION_STAGE_ROOT" >/dev/null 2>&1 || true
    fi
}
trap cleanup_helper_execution_subject EXIT
HELPER_EXECUTION_STAGE_ROOT="$(/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-capture-install-helper.XXXXXX)" || \\
    die "Could not create protected signed-app custody-helper execution stage."
[[ "$HELPER_EXECUTION_STAGE_ROOT" == /private/tmp/nembra-capture-install-helper.* ]] || \\
    die "Signed-app custody-helper execution stage is outside the canonical private temporary root."
HELPER_EXECUTION_SUBJECT="$HELPER_EXECUTION_STAGE_ROOT/capture_signed_app_install_custody.py"
if ! GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git cat-file blob "$HELPER_ACCEPTED_BLOB" | \\
    /usr/bin/sudo /usr/bin/tee "$HELPER_EXECUTION_SUBJECT" >/dev/null
then
    die "Could not materialize the exact accepted signed-app custody helper Git blob."
fi
/usr/bin/sudo /usr/sbin/chown root:wheel "$HELPER_EXECUTION_SUBJECT" || \\
    die "Could not root-own the signed-app custody-helper execution subject."
/usr/bin/sudo /bin/chmod 0444 "$HELPER_EXECUTION_SUBJECT" || \\
    die "Could not seal the signed-app custody-helper execution subject read-only."
/usr/bin/sudo /bin/chmod 0755 "$HELPER_EXECUTION_STAGE_ROOT" || \\
    die "Could not expose read traversal of the protected signed-app custody-helper stage."
[[ -f "$HELPER_EXECUTION_SUBJECT" && ! -L "$HELPER_EXECUTION_SUBJECT" ]] || \\
    die "Protected signed-app custody-helper execution subject is not one real regular file."
HELPER_EXECUTION_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git hash-object --no-filters -- "$HELPER_EXECUTION_SUBJECT" 2>/dev/null || true)"
[[ "$HELPER_EXECUTION_BLOB" == "$HELPER_ACCEPTED_BLOB" ]] || \\
    die "Protected signed-app custody-helper execution bytes differ from the exact accepted Git blob."
'''
text = text.replace(authority_marker, protected_subject, 1)

old_fingerprint = '''SOURCE_APP_TREE_SHA256="$(/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" fingerprint --app "$APP")" || \\
    die "Could not bind the exact post-build signed-app tree before protected staging."'''
new_fingerprint = '''SOURCE_APP_TREE_SHA256="$(/usr/bin/python3 -I -B "$HELPER_EXECUTION_SUBJECT" fingerprint --app "$APP")" || \\
    die "Could not bind the exact post-build signed-app tree before protected staging."'''
if text.count(old_fingerprint) != 1:
    raise SystemExit("expected one mutable helper fingerprint execution")
text = text.replace(old_fingerprint, new_fingerprint, 1)

old_verify = '''STAGED_APP_TREE_SHA256="$(/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" verify-stage \\
    --stage-root "$APP_INSTALL_STAGE_ROOT" \\
    --app "$APP_INSTALL_STAGE" \\
    --expected "$SOURCE_APP_TREE_SHA256")" || \\
    die "Protected signed-app install subject failed root-owned custody or exact-tree verification."'''
new_verify = '''STAGED_APP_TREE_SHA256="$(/usr/bin/python3 -I -B "$HELPER_EXECUTION_SUBJECT" verify-stage \\
    --stage-root "$APP_INSTALL_STAGE_ROOT" \\
    --app "$APP_INSTALL_STAGE" \\
    --expected "$SOURCE_APP_TREE_SHA256")" || \\
    die "Protected signed-app install subject failed root-owned custody or exact-tree verification."'''
if text.count(old_verify) != 1:
    raise SystemExit("expected one mutable helper stage-verification execution")
text = text.replace(old_verify, new_verify, 1)

cleanup_marker = '''cleanup_install_subject() {
    if [[ -n "${INSTALL_LOG:-}" ]]; then
        /bin/rm -f -- "$INSTALL_LOG" || true
    fi
    if [[ -n "${APP_INSTALL_STAGE_ROOT:-}" ]]; then
        /usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" >/dev/null 2>&1 || true
    fi
}
trap cleanup_install_subject EXIT
'''
cleanup_replacement = '''cleanup_install_subject() {
    if [[ -n "${INSTALL_LOG:-}" ]]; then
        /bin/rm -f -- "$INSTALL_LOG" || true
    fi
    if [[ -n "${APP_INSTALL_STAGE_ROOT:-}" ]]; then
        /usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" >/dev/null 2>&1 || true
    fi
    cleanup_helper_execution_subject
}
trap cleanup_install_subject EXIT
'''
if text.count(cleanup_marker) != 1:
    raise SystemExit("expected one install-subject cleanup block")
text = text.replace(cleanup_marker, cleanup_replacement, 1)

mutable_exec = '/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py"'
if mutable_exec in text:
    raise SystemExit("mutable checkout helper execution remains after patch")

path.write_text(text, encoding="utf-8")
