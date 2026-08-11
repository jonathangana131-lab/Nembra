#!/usr/bin/env python3
from pathlib import Path

installer = Path("scripts/field/install_one_time_capture.command")
source = installer.read_text(encoding="utf-8")

tool_marker = '[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."\n'
tool_replacement = tool_marker + '''[[ -x /usr/bin/sudo ]] || die "System sudo is required to create the protected signed-app install subject."\n[[ -x /usr/bin/ditto ]] || die "System ditto is required to stage the exact signed-app install subject."\n[[ -x /usr/bin/find ]] || die "System find is required to seal staged signed-app ownership without following symlinks."\n[[ -x /usr/sbin/chown ]] || die "System chown is required to root-own the staged signed-app install subject."\n'''
if source.count(tool_marker) != 1:
    raise SystemExit("tool-admission marker drifted")
source = source.replace(tool_marker, tool_replacement, 1)

app_marker = '''APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"\n[[ -d "$APP" ]] || die "Build finished but the standalone Nembra Capture.app was not found at $APP"\nAPP_INFO_PLIST="$APP/Info.plist"\n'''
app_replacement = '''APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"\n[[ -d "$APP" ]] || die "Build finished but the standalone Nembra Capture.app was not found at $APP"\nSIGNED_APP_CUSTODY_HELPER="$ROOT/scripts/ci/capture_signed_app_install_custody.py"\n[[ -f "$SIGNED_APP_CUSTODY_HELPER" ]] || die "Signed-app install custody helper is missing from the exact accepted source."\nSOURCE_APP_TREE_SHA256="$(/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" fingerprint --app "$APP")" || \\
    die "Could not bind the exact post-build signed-app tree before protected staging."\n[[ "$SOURCE_APP_TREE_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "Signed-app tree fingerprint is malformed."\n\n# devicectl reopens an app bundle by pathname. A normal DerivedData path remains mutable by the\n# invoking user after signature/provenance review, so it cannot itself be the physical install\n# authority. Snapshot the exact finite tree through root into one private staging directory. The\n# stage remains root-only while it is copied and ownership-sealed; only after sealing do we expose\n# read/traverse access to the unprivileged CoreDevice client. Every later authority check and the\n# actual install operate on this same protected pathname.\nAPP_INSTALL_STAGE_ROOT=""\nINSTALL_LOG=""\ncleanup_install_subject() {\n    if [[ -n "${INSTALL_LOG:-}" ]]; then\n        /bin/rm -f -- "$INSTALL_LOG" || true\n    fi\n    if [[ -n "${APP_INSTALL_STAGE_ROOT:-}" ]]; then\n        /usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" >/dev/null 2>&1 || true\n    fi\n}\ntrap cleanup_install_subject EXIT\nAPP_INSTALL_STAGE_ROOT="$(/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-authenticated-capture-install.XXXXXX)" || \\
    die "Could not create the root-owned signed-app install custody directory."\n[[ "$APP_INSTALL_STAGE_ROOT" == /private/tmp/nembra-authenticated-capture-install.* ]] || \\
    die "Protected signed-app install custody directory is outside the canonical private temporary root."\nAPP_INSTALL_STAGE="$APP_INSTALL_STAGE_ROOT/Nembra Capture.app"\n/usr/bin/sudo /usr/bin/ditto "$APP" "$APP_INSTALL_STAGE" || \\
    die "Could not snapshot the exact signed app into protected install custody."\n# The stage root is still root mode-0700 here, so the invoking user cannot race this seal. BSD\n# find does not follow symlinks by default; chown -h changes a symlink object rather than an\n# external target. The verifier below rejects broken/escaping links before the stage is admitted.\n/usr/bin/sudo /usr/bin/find "$APP_INSTALL_STAGE_ROOT" -exec /usr/sbin/chown -h root:wheel {} + || \\
    die "Could not root-own every protected signed-app install entry."\n/usr/bin/sudo /bin/chmod 0755 "$APP_INSTALL_STAGE_ROOT" || \\
    die "Could not expose read-only traversal of the protected signed-app install stage."\nSTAGED_APP_TREE_SHA256="$(/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py" verify-stage \\
    --stage-root "$APP_INSTALL_STAGE_ROOT" \\
    --app "$APP_INSTALL_STAGE" \\
    --expected "$SOURCE_APP_TREE_SHA256")" || \\
    die "Protected signed-app install subject failed root-owned custody or exact-tree verification."\n[[ "$STAGED_APP_TREE_SHA256" == "$SOURCE_APP_TREE_SHA256" ]] || \\
    die "Protected signed-app install subject differs from the exact post-build signed app."\nAPP="$APP_INSTALL_STAGE"\nAPP_INFO_PLIST="$APP/Info.plist"\n'''
if source.count(app_marker) != 1:
    raise SystemExit("post-build app marker drifted")
source = source.replace(app_marker, app_replacement, 1)

old_trap = '''INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-authenticated-capture-install.XXXXXX")"\ntrap 'rm -f -- "$INSTALL_LOG"' EXIT\nchmod 600 "$INSTALL_LOG"\n'''
new_trap = '''INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-authenticated-capture-install-log.XXXXXX")"\nchmod 600 "$INSTALL_LOG"\n'''
if source.count(old_trap) != 1:
    raise SystemExit("install-log trap marker drifted")
source = source.replace(old_trap, new_trap, 1)

old_cleanup = '''rm -f -- "$INSTALL_LOG"\ntrap - EXIT\n\nsay "SDK-INTEGRATED CAPTURE LAUNCHED"\n'''
new_cleanup = '''rm -f -- "$INSTALL_LOG"\nINSTALL_LOG=""\n/usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT" || die "Could not remove the protected signed-app install stage after successful launch."\nAPP_INSTALL_STAGE_ROOT=""\ntrap - EXIT\nunset SOURCE_APP_TREE_SHA256 STAGED_APP_TREE_SHA256 SIGNED_APP_CUSTODY_HELPER APP_INSTALL_STAGE\n\nsay "SDK-INTEGRATED CAPTURE LAUNCHED"\n'''
if source.count(old_cleanup) != 1:
    raise SystemExit("successful cleanup marker drifted")
source = source.replace(old_cleanup, new_cleanup, 1)
installer.write_text(source, encoding="utf-8")

test_path = Path("scripts/ci/tests/test_capture_signed_app_install_custody.py")
test_source = test_path.read_text(encoding="utf-8")
old_owner = 'owner_marker = \'/usr/bin/sudo /usr/sbin/chown -R root:wheel "$APP_INSTALL_STAGE_ROOT"\'\n'
new_owner = 'owner_marker = \'/usr/bin/sudo /usr/bin/find "$APP_INSTALL_STAGE_ROOT" -exec /usr/sbin/chown -h root:wheel {} +\'\n'
if test_source.count(old_owner) != 1:
    raise SystemExit("test owner marker drifted")
test_path.write_text(test_source.replace(old_owner, new_owner, 1), encoding="utf-8")

Path(".github/workflows/materialize-capture-signed-app-install-custody.yml").unlink()
Path("scripts/ci/materialize_capture_signed_app_install_custody.py").unlink()
