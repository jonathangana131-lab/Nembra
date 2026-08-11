#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess

INSTALLER = Path("scripts/field/install_one_time_capture.command")
TEST = Path("scripts/ci/tests/test_capture_signed_app_install_custody.py")
BASE_INSTALLER_BLOB = "a7d0a0ab23d7dd9723476eb38f9f507bbc5d7672"


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True).strip()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


if git("rev-parse", f"HEAD:{INSTALLER}") != BASE_INSTALLER_BLOB:
    raise SystemExit("live installer blob drifted before protected-install materialization")

source = subprocess.check_output(
    ["git", "show", f"FETCH_HEAD:{INSTALLER}"], text=True
)
old = '''SIGNED_APP_CUSTODY_HELPER="$ROOT/scripts/ci/capture_signed_app_install_custody.py"
[[ -f "$SIGNED_APP_CUSTODY_HELPER" ]] || die "Signed-app install custody helper is missing from the exact accepted source."
SOURCE_APP_TREE_SHA256="$(/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" fingerprint --app "$APP")" || \\
    die "Could not bind the exact post-build signed-app tree before protected staging."
'''
new = '''SIGNED_APP_CUSTODY_HELPER_PATH="scripts/ci/capture_signed_app_install_custody.py"
SIGNED_APP_CUSTODY_HELPER_BLOB="$(/usr/bin/git rev-parse "$SOURCE_SHA:$SIGNED_APP_CUSTODY_HELPER_PATH" 2>/dev/null)" || \\
    die "Signed-app custody helper is missing from the exact accepted Git tree."
[[ "$SIGNED_APP_CUSTODY_HELPER_BLOB" =~ ^[0-9a-f]{40}$ ]] || die "Signed-app custody helper Git blob identity is malformed."
SIGNED_APP_CUSTODY_HELPER_SOURCE="$(
    /usr/bin/git cat-file blob "$SIGNED_APP_CUSTODY_HELPER_BLOB" || exit 1
    printf '\036'
)" || die "Could not capture signed-app custody helper from the accepted Git object."
[[ "${SIGNED_APP_CUSTODY_HELPER_SOURCE: -1}" == $'\036' ]] || die "Signed-app custody helper capture sentinel is missing."
SIGNED_APP_CUSTODY_HELPER_SOURCE="${SIGNED_APP_CUSTODY_HELPER_SOURCE%$'\036'}"
[[ "$(printf '%s' "$SIGNED_APP_CUSTODY_HELPER_SOURCE" | /usr/bin/git hash-object --stdin)" == "$SIGNED_APP_CUSTODY_HELPER_BLOB" ]] || \\
    die "Captured signed-app custody helper bytes do not match the accepted Git blob."
SOURCE_APP_TREE_SHA256="$(/usr/bin/python3 -I -c "$SIGNED_APP_CUSTODY_HELPER_SOURCE" fingerprint --app "$APP")" || \\
    die "Could not bind the exact post-build signed-app tree before protected staging."
'''
source = replace_once(source, old, new, "helper admission")
source = replace_once(
    source,
    '''STAGED_APP_TREE_SHA256="$(/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" verify-stage \\
''',
    '''STAGED_APP_TREE_SHA256="$(/usr/bin/python3 -I -c "$SIGNED_APP_CUSTODY_HELPER_SOURCE" verify-stage \\
''',
    "helper stage verification",
)
source = replace_once(
    source,
    "unset SOURCE_APP_TREE_SHA256 STAGED_APP_TREE_SHA256 SIGNED_APP_CUSTODY_HELPER APP_INSTALL_STAGE\n",
    "unset SOURCE_APP_TREE_SHA256 STAGED_APP_TREE_SHA256 SIGNED_APP_CUSTODY_HELPER_PATH SIGNED_APP_CUSTODY_HELPER_BLOB SIGNED_APP_CUSTODY_HELPER_SOURCE APP_INSTALL_STAGE\n",
    "helper cleanup",
)
INSTALLER.write_text(source, encoding="utf-8")

text = TEST.read_text(encoding="utf-8")
text = replace_once(
    text,
    'capture_signed_app_install_custody.py" fingerprint --app "$APP"',
    '-c "$SIGNED_APP_CUSTODY_HELPER_SOURCE" fingerprint --app "$APP"',
    "test fingerprint marker",
)
text = replace_once(
    text,
    'capture_signed_app_install_custody.py" verify-stage',
    '-c "$SIGNED_APP_CUSTODY_HELPER_SOURCE" verify-stage',
    "test stage marker",
)
needle = '''        self.assertLess(indexes["app"], indexes["fingerprint"])
'''
extra = '''        blob_marker = source.find('/usr/bin/git cat-file blob "$SIGNED_APP_CUSTODY_HELPER_BLOB"')
        hash_marker = source.find('/usr/bin/git hash-object --stdin')
        self.assertGreaterEqual(blob_marker, 0)
        self.assertGreaterEqual(hash_marker, 0)
        self.assertLess(blob_marker, indexes["fingerprint"])
        self.assertLess(hash_marker, indexes["fingerprint"])
        self.assertNotIn('/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py"', source)

'''
text = replace_once(text, needle, extra + needle, "test helper blob custody")
TEST.write_text(text, encoding="utf-8")
