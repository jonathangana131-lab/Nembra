#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label} anchor count={count}")
    return text.replace(old, new, 1)


installer_path = Path("scripts/field/install_one_time_capture.command")
installer = installer_path.read_text()
installer = replace_once(
    installer,
    '''APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"
[[ -d "$APP" ]] || die "Build finished but the standalone Nembra Capture.app was not found at $APP"
APP_INFO_PLIST="$APP/Info.plist"
''',
    '''BUILT_APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"
[[ -d "$BUILT_APP" ]] || die "Build finished but the standalone Nembra Capture.app was not found at $BUILT_APP"
INSTALL_STAGE_HELPER_SOURCE="$(/usr/bin/git -C "$ROOT" show "${SOURCE_SHA}:Scripts/capture_signed_app_install_stage.py")" || \
    die "Could not load the exact accepted signed-app install staging helper from Git object authority."
[[ -n "$INSTALL_STAGE_HELPER_SOURCE" ]] || die "Accepted signed-app install staging helper was empty."
FIELD_UID="$(/usr/bin/id -u)"
FIELD_GID="$(/usr/bin/id -g)"
[[ "$FIELD_UID" =~ ^[1-9][0-9]*$ && "$FIELD_GID" =~ ^[0-9]+$ ]] || die "Could not determine the invoking field-user identity for signed-app staging."
APP="$(/usr/bin/sudo /usr/bin/python3 -I -c "$INSTALL_STAGE_HELPER_SOURCE" stage \
    --source "$BUILT_APP" --uid "$FIELD_UID" --gid "$FIELD_GID")" || \
    die "Could not create a root-owned frozen install subject from the just-built Capture app."
case "$APP" in
    /private/var/tmp/nembra-capture-install-*/payload/"Nembra Capture.app") ;;
    *) die "Signed-app staging returned a noncanonical install subject path." ;;
esac
INSTALL_STAGE_ROOT="${APP%/payload/Nembra Capture.app}"
cleanup_install_stage() {
    if [[ -n "${INSTALL_STAGE_ROOT:-}" ]]; then
        /usr/bin/sudo /usr/bin/python3 -I -c "$INSTALL_STAGE_HELPER_SOURCE" cleanup \
            --stage-root "$INSTALL_STAGE_ROOT" >/dev/null 2>&1 || true
    fi
}
trap cleanup_install_stage EXIT
/usr/bin/python3 -I -c "$INSTALL_STAGE_HELPER_SOURCE" verify --app "$APP" --gid "$FIELD_GID" || \
    die "Frozen signed-app install subject failed custody verification before field authority checks."
say "Root-owned frozen install subject staged; all signature, provenance, entitlement, and install checks now use this exact app path"
APP_INFO_PLIST="$APP/Info.plist"
''',
    "installer app",
)
installer = replace_once(
    installer,
    '''say "Installing SDK-integrated Capture on the intended iPhone"
open -a Xcode "$ROOT/NembraCapture.xcworkspace" >/dev/null 2>&1 || true
INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-authenticated-capture-install.XXXXXX")"
trap 'rm -f -- "$INSTALL_LOG"' EXIT
chmod 600 "$INSTALL_LOG"
''',
    '''say "Installing SDK-integrated Capture on the intended iPhone"
open -a Xcode "$ROOT/NembraCapture.xcworkspace" >/dev/null 2>&1 || true
/usr/bin/python3 -I -c "$INSTALL_STAGE_HELPER_SOURCE" verify --app "$APP" --gid "$FIELD_GID" || \
    die "Frozen signed-app install subject custody changed before devicectl. Refusing installation."
INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-authenticated-capture-install.XXXXXX")"
trap 'rm -f -- "$INSTALL_LOG"; cleanup_install_stage' EXIT
chmod 600 "$INSTALL_LOG"
''',
    "installer install",
)
installer = replace_once(
    installer,
    '''say "Launching privately provisioned Capture on the intended iPhone"
''',
    '''/usr/bin/python3 -I -c "$INSTALL_STAGE_HELPER_SOURCE" verify --app "$APP" --gid "$FIELD_GID" || \
    die "Frozen signed-app install subject custody changed while devicectl was installing it. Physical build authority is invalid."
/usr/bin/sudo /usr/bin/python3 -I -c "$INSTALL_STAGE_HELPER_SOURCE" cleanup \
    --stage-root "$INSTALL_STAGE_ROOT" || die "The frozen signed-app install staging subject could not be retired after installation."
INSTALL_STAGE_ROOT=""

say "Launching privately provisioned Capture on the intended iPhone"
''',
    "installer launch",
)
installer_path.write_text(installer)

workflow_path = Path(".github/workflows/capture-field-build-provenance.yml")
workflow = workflow_path.read_text()
if "capture_signed_app_install_stage.py" not in workflow:
    workflow = replace_once(
        workflow,
        '''      - Scripts/capture_tuya_private_input_build_guard.py
      - scripts/ci/tests/test_capture_tuya_private_input_provenance.py
''',
        '''      - Scripts/capture_tuya_private_input_build_guard.py
      - Scripts/capture_signed_app_install_stage.py
      - scripts/ci/tests/test_capture_tuya_private_input_provenance.py
      - scripts/ci/tests/test_capture_signed_app_install_stage.py
''',
        "workflow paths",
    )
    workflow = replace_once(
        workflow,
        '''          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py
          /usr/bin/python3 scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py
''',
        '''          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py Scripts/capture_signed_app_install_stage.py scripts/ci/tests/test_capture_signed_app_install_stage.py
          /usr/bin/python3 scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py
          /usr/bin/python3 scripts/ci/tests/test_capture_signed_app_install_stage.py
''',
        "workflow validation",
    )
    workflow = replace_once(
        workflow,
        '''          private_identity_provisioner='Scripts/provision_capture_tuya_identity.sh'
          ignore='.gitignore'
''',
        '''          private_identity_provisioner='Scripts/provision_capture_tuya_identity.sh'
          signed_app_stage='Scripts/capture_signed_app_install_stage.py'
          ignore='.gitignore'
''',
        "workflow source variable",
    )
    workflow = replace_once(
        workflow,
        '''          test -f "$private_identity_provisioner"
          grep -Fq 'RECIPE_ID = "ES80-FINGERPRINT-v1"' "$signed_field_inspector"
''',
        '''          test -f "$private_identity_provisioner"
          test -f "$signed_app_stage"
          grep -Fq 'RECIPE_ID = "ES80-FINGERPRINT-v1"' "$signed_field_inspector"
          grep -Fq 'os.setuid(uid)' "$signed_app_stage"
          grep -Fq 'os.execve("/usr/bin/ditto"' "$signed_app_stage"
          grep -Fq '_verify_frozen_tree(app, gid)' "$signed_app_stage"
''',
        "workflow helper contract",
    )
    workflow = replace_once(
        workflow,
        '''          grep -Fq 'devicectl device install app --device "$COREDEVICE_ID"' "$installer"
          grep -Fq -- '--device "$COREDEVICE_ID"' "$installer"
''',
        '''          grep -Fq 'devicectl device install app --device "$COREDEVICE_ID"' "$installer"
          grep -Fq -- '--device "$COREDEVICE_ID"' "$installer"
          grep -Fq 'git -C "$ROOT" show "${SOURCE_SHA}:Scripts/capture_signed_app_install_stage.py"' "$installer"
          grep -Fq 'stage --source "$BUILT_APP" --uid "$FIELD_UID" --gid "$FIELD_GID"' "$installer"
          grep -Fq 'verify --app "$APP" --gid "$FIELD_GID"' "$installer"
          grep -Fq 'cleanup --stage-root "$INSTALL_STAGE_ROOT"' "$installer"
''',
        "workflow install contract",
    )

    lines = workflow.splitlines()
    matched = 0
    for index, line in enumerate(lines):
        if "grep -Fq" in line and 'rm -f -- "$INSTALL_LOG"' in line and " EXIT" in line:
            lines[index] = line.replace(
                'rm -f -- "$INSTALL_LOG"',
                'rm -f -- "$INSTALL_LOG"; cleanup_install_stage',
            )
            matched += 1
    if matched != 1:
        raise SystemExit(f"workflow install trap line count={matched}")
    workflow = "\n".join(lines) + "\n"
workflow_path.write_text(workflow)
