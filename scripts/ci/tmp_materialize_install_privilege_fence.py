#!/usr/bin/env python3
from pathlib import Path

# Temporary self-deleting materializer. The workflow validates the resulting permanent files.
INSTALLER = Path("scripts/field/install_one_time_capture.command")
TEST = Path("scripts/ci/tests/test_capture_signed_app_install_custody.py")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


source = INSTALLER.read_text(encoding="utf-8")
source = replace_once(
    source,
    '''    if [[ -n "${APP_INSTALL_STAGE_ROOT:-}" ]]; then
        /usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" >/dev/null 2>&1 || true
    fi
''',
    '''    if [[ -n "${APP_INSTALL_STAGE_ROOT:-}" ]]; then
        if ! /usr/bin/sudo -n /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" >/dev/null 2>&1; then
            printf '%s\\n' "Protected signed-app stage retained at $APP_INSTALL_STAGE_ROOT; remove it later with sudo after this run is no longer authoritative." >&2
        fi
    fi
''',
    "noninteractive trap cleanup",
)
source = replace_once(
    source,
    '''[[ "$STAGED_APP_TREE_SHA256" == "$SOURCE_APP_TREE_SHA256" ]] || \\
    die "Protected signed-app install subject differs from the exact post-build signed app."
APP="$APP_INSTALL_STAGE"
''',
    '''[[ "$STAGED_APP_TREE_SHA256" == "$SOURCE_APP_TREE_SHA256" ]] || \\
    die "Protected signed-app install subject differs from the exact post-build signed app."
# The protected stage is now the only install subject. Revoke the successful staging
# elevation before any signature/provenance review or CoreDevice side effect so a
# same-UID actor cannot reuse this run's sudo timestamp to mutate the root-owned tree.
/usr/bin/sudo -K || die "Could not invalidate staging elevation before signed-app admission."
if /usr/bin/sudo -n /usr/bin/true >/dev/null 2>&1; then
    die "Noninteractive sudo authority remained after invalidation; do not install from this stage."
fi
APP="$APP_INSTALL_STAGE"
''',
    "privilege fence before staged authority",
)
source = replace_once(
    source,
    '''/usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" || die "Could not remove the protected signed-app install stage after successful launch."
APP_INSTALL_STAGE_ROOT=""
trap - EXIT
''',
    '''if /usr/bin/sudo -n /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" >/dev/null 2>&1; then
    APP_INSTALL_STAGE_ROOT=""
else
    printf '%s\\n' "Protected signed-app stage retained at $APP_INSTALL_STAGE_ROOT; remove it later with sudo after this run is no longer authoritative." >&2
fi
trap - EXIT
''',
    "noninteractive success cleanup",
)
INSTALLER.write_text(source, encoding="utf-8")

text = TEST.read_text(encoding="utf-8")
text = replace_once(
    text,
    '''        switch_marker = 'APP="$APP_INSTALL_STAGE"'
        codesign_marker = '/usr/bin/codesign --verify --deep --strict "$APP"'
''',
    '''        revoke_marker = '/usr/bin/sudo -K'
        no_sudo_marker = '/usr/bin/sudo -n /usr/bin/true'
        switch_marker = 'APP="$APP_INSTALL_STAGE"'
        codesign_marker = '/usr/bin/codesign --verify --deep --strict "$APP"'
''',
    "test privilege markers",
)
text = replace_once(
    text,
    '''            ("verify_stage", verify_stage_marker),
            ("switch", switch_marker),
''',
    '''            ("verify_stage", verify_stage_marker),
            ("revoke", revoke_marker),
            ("no_sudo", no_sudo_marker),
            ("switch", switch_marker),
''',
    "test privilege ordering inputs",
)
text = replace_once(
    text,
    '''        self.assertLess(indexes["owner"], indexes["verify_stage"])
        self.assertLess(indexes["verify_stage"], indexes["switch"])
        self.assertLess(indexes["switch"], indexes["codesign"])
''',
    '''        self.assertLess(indexes["owner"], indexes["verify_stage"])
        self.assertLess(indexes["verify_stage"], indexes["revoke"])
        self.assertLess(indexes["revoke"], indexes["no_sudo"])
        self.assertLess(indexes["no_sudo"], indexes["switch"])
        self.assertLess(indexes["switch"], indexes["codesign"])
''',
    "test privilege ordering assertions",
)
text = replace_once(
    text,
    '''        self.assertIn('/usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT"', source)
''',
    '''        self.assertNotIn('/usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT"', source)
        self.assertIn('/usr/bin/sudo -n /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT"', source)
        self.assertIn('Noninteractive sudo authority remained after invalidation', source)
''',
    "test cleanup privilege contract",
)
TEST.write_text(text, encoding="utf-8")
