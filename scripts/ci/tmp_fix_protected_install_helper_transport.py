#!/usr/bin/env python3
from pathlib import Path

INSTALLER = Path("scripts/field/install_one_time_capture.command")
TEST = Path("scripts/ci/tests/test_capture_signed_app_install_custody.py")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


source = INSTALLER.read_text(encoding="utf-8")
old = '''SIGNED_APP_CUSTODY_HELPER_SOURCE="$(
    /usr/bin/git cat-file blob "$SIGNED_APP_CUSTODY_HELPER_BLOB" || exit 1
    printf '
'
)" || die "Could not capture signed-app custody helper from the accepted Git object."
[[ "${SIGNED_APP_CUSTODY_HELPER_SOURCE: -1}" == $'
' ]] || die "Signed-app custody helper capture sentinel is missing."
SIGNED_APP_CUSTODY_HELPER_SOURCE="${SIGNED_APP_CUSTODY_HELPER_SOURCE%$'
'}"
[[ "$(printf '%s' "$SIGNED_APP_CUSTODY_HELPER_SOURCE" | /usr/bin/git hash-object --stdin)" == "$SIGNED_APP_CUSTODY_HELPER_BLOB" ]] || \\
    die "Captured signed-app custody helper bytes do not match the accepted Git blob."
SOURCE_APP_TREE_SHA256="$(/usr/bin/python3 -I -c "$SIGNED_APP_CUSTODY_HELPER_SOURCE" fingerprint --app "$APP")" || \\
    die "Could not bind the exact post-build signed-app tree before protected staging."
'''
new = '''SIGNED_APP_CUSTODY_HELPER_BASE64="$(/usr/bin/git cat-file blob "$SIGNED_APP_CUSTODY_HELPER_BLOB" | /usr/bin/base64)" || \\
    die "Could not capture signed-app custody helper from the accepted Git object."
[[ -n "$SIGNED_APP_CUSTODY_HELPER_BASE64" ]] || die "Captured signed-app custody helper is empty."
[[ "$(printf '%s' "$SIGNED_APP_CUSTODY_HELPER_BASE64" | /usr/bin/base64 -D | /usr/bin/git hash-object --stdin)" == "$SIGNED_APP_CUSTODY_HELPER_BLOB" ]] || \\
    die "Decoded signed-app custody helper bytes do not match the accepted Git blob."
SOURCE_APP_TREE_SHA256="$(printf '%s' "$SIGNED_APP_CUSTODY_HELPER_BASE64" | /usr/bin/base64 -D | /usr/bin/python3 -I - fingerprint --app "$APP")" || \\
    die "Could not bind the exact post-build signed-app tree before protected staging."
'''
source = replace_once(source, old, new, "raw helper transport")
source = replace_once(
    source,
    '''STAGED_APP_TREE_SHA256="$(/usr/bin/python3 -I -c "$SIGNED_APP_CUSTODY_HELPER_SOURCE" verify-stage \\
''',
    '''STAGED_APP_TREE_SHA256="$(printf '%s' "$SIGNED_APP_CUSTODY_HELPER_BASE64" | /usr/bin/base64 -D | /usr/bin/python3 -I - verify-stage \\
''',
    "stage helper transport",
)
source = replace_once(
    source,
    "unset SOURCE_APP_TREE_SHA256 STAGED_APP_TREE_SHA256 SIGNED_APP_CUSTODY_HELPER_PATH SIGNED_APP_CUSTODY_HELPER_BLOB SIGNED_APP_CUSTODY_HELPER_SOURCE APP_INSTALL_STAGE\n",
    "unset SOURCE_APP_TREE_SHA256 STAGED_APP_TREE_SHA256 SIGNED_APP_CUSTODY_HELPER_PATH SIGNED_APP_CUSTODY_HELPER_BLOB SIGNED_APP_CUSTODY_HELPER_BASE64 APP_INSTALL_STAGE\n",
    "helper transport cleanup",
)
INSTALLER.write_text(source, encoding="utf-8")

text = TEST.read_text(encoding="utf-8")
text = replace_once(
    text,
    'fingerprint_marker = \'-c "$SIGNED_APP_CUSTODY_HELPER_SOURCE" fingerprint --app "$APP"\'',
    'fingerprint_marker = \'/usr/bin/python3 -I - fingerprint --app "$APP"\'',
    "fingerprint marker",
)
text = replace_once(
    text,
    'verify_stage_marker = \'-c "$SIGNED_APP_CUSTODY_HELPER_SOURCE" verify-stage\'',
    'verify_stage_marker = \'/usr/bin/python3 -I - verify-stage\'',
    "stage marker",
)
text = replace_once(
    text,
    '''        hash_marker = source.find('/usr/bin/git hash-object --stdin')
''',
    '''        decode_marker = source.find('/usr/bin/base64 -D')
        hash_marker = source.find('/usr/bin/git hash-object --stdin')
''',
    "decode marker",
)
text = replace_once(
    text,
    '''        self.assertGreaterEqual(hash_marker, 0)
        self.assertLess(blob_marker, indexes["fingerprint"])
        self.assertLess(hash_marker, indexes["fingerprint"])
''',
    '''        self.assertGreaterEqual(decode_marker, 0)
        self.assertGreaterEqual(hash_marker, 0)
        self.assertLess(blob_marker, indexes["fingerprint"])
        self.assertLess(decode_marker, indexes["fingerprint"])
        self.assertLess(hash_marker, indexes["fingerprint"])
''',
    "helper ordering assertions",
)
text = replace_once(
    text,
    '''        self.assertNotIn('/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py"', source)
''',
    '''        self.assertNotIn('/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py"', source)
        self.assertNotIn('SIGNED_APP_CUSTODY_HELPER_SOURCE=', source)
        self.assertIn('SIGNED_APP_CUSTODY_HELPER_BASE64=', source)
        self.assertIn("/usr/bin/base64 -D | /usr/bin/python3 -I - fingerprint", source)
        self.assertIn("/usr/bin/base64 -D | /usr/bin/python3 -I - verify-stage", source)
''',
    "transport regression assertions",
)
TEST.write_text(text, encoding="utf-8")
