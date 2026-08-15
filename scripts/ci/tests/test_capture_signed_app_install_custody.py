#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/capture_signed_app_install_custody.py"
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
WORKFLOW = REPOSITORY / ".github/workflows/capture-signed-app-install-custody.yml"


def load_helper():
    spec = importlib.util.spec_from_file_location("capture_signed_app_install_custody", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load signed-app install custody helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureSignedAppInstallCustodyTests(unittest.TestCase):
    def test_fingerprint_changes_with_bundle_bytes(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-install-custody-") as temporary:
            app = Path(temporary) / "Nembra Capture.app"
            app.mkdir()
            payload = app / "subject.txt"
            payload.write_text("accepted\n", encoding="utf-8")
            first = helper.fingerprint(app)
            payload.write_text("substituted\n", encoding="utf-8")
            second = helper.fingerprint(app)
            self.assertNotEqual(first, second)

    def test_fingerprint_rejects_external_symlink(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-install-custody-") as temporary:
            root = Path(temporary)
            app = root / "Nembra Capture.app"
            app.mkdir()
            outside = root / "outside.txt"
            outside.write_text("mutable\n", encoding="utf-8")
            (app / "escape").symlink_to(outside)
            with self.assertRaises(helper.CustodyError):
                helper.fingerprint(app)

    def test_permanent_workflow_reproves_acl_strip_on_real_macos(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("macos-acl-strip-custody:", workflow)
        self.assertIn("runs-on: macos-15", workflow)
        self.assertIn("ref: ${{ github.event.pull_request.head.sha || github.sha }}", workflow)
        self.assertIn('/bin/chmod +a "$(id -un) allow write,delete,add_file,add_subdirectory,file_inherit,directory_inherit" "$source_app"', workflow)
        self.assertIn('/usr/bin/ditto --noacl "$source_app" "$stage_root/Nembra Capture.app"', workflow)
        self.assertIn('/usr/bin/find "$stage_root" -acl -print -quit', workflow)
        self.assertIn('test -z "$staged_acl"', workflow)

    def test_installer_moves_authority_to_protected_stage_before_codesign(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        markers = {
            "origin_helper": 'BUILD_ORIGIN_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1',
            "install_helper": 'SIGNED_APP_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1',
            "supervisor": '/usr/bin/sudo /usr/bin/python3 -I -c',
            "derived": '-derivedDataPath "$DERIVED_PLACEHOLDER"',
            "result": "IFS=$'\\t' read -r APP_INSTALL_STAGE_ROOT STAGED_APP_TREE_SHA256 SELECTED_XCODE_DEVELOPER_DIR SELECTED_XCTRACE SELECTED_DEVICECTL RESULT_EXTRA",
            "switch": 'APP="$APP_INSTALL_STAGE"',
            "verify_stage": '/usr/bin/python3 -I - verify-stage',
            "no_sudo": '/usr/bin/sudo -n /usr/bin/true',
            "codesign": '/usr/bin/codesign --verify --deep --strict "$APP"',
            "install": 'run_frozen_xcode_tool "$SELECTED_DEVICECTL" device install app --device "$COREDEVICE_ID" "$APP"',
        }
        indexes = {}
        for name, marker in markers.items():
            indexes[name] = source.find(marker)
            self.assertGreaterEqual(indexes[name], 0, f"installer is missing {name} custody marker")

        self.assertLess(indexes["origin_helper"], indexes["supervisor"])
        self.assertLess(indexes["install_helper"], indexes["supervisor"])
        self.assertLess(indexes["supervisor"], indexes["result"])
        self.assertLess(indexes["result"], indexes["switch"])
        self.assertLess(indexes["switch"], indexes["no_sudo"])
        self.assertLess(indexes["no_sudo"], indexes["verify_stage"])
        self.assertLess(indexes["verify_stage"], indexes["codesign"])
        self.assertLess(indexes["codesign"], indexes["install"])

        self.assertIn('DERIVED_PLACEHOLDER="__NEMBRA_PROTECTED_DERIVED__"', source)
        self.assertIn('--install-custody-helper-base64 "$SIGNED_APP_CUSTODY_HELPER_BASE64"', source)
        self.assertIn('[[ "$VERIFIED_STAGE_TREE_SHA256" == "$STAGED_APP_TREE_SHA256" ]]', source)
        self.assertIn('APP_INSTALL_STAGE_ROOT=""', source)
        self.assertIn('cleanup_install_subject()', source)
        self.assertIn('/usr/bin/sudo -n /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT"', source)
        self.assertIn('Noninteractive sudo authority remained after selected-Xcode/build-origin custody', source)
        self.assertIn('DEVELOPER_DIR="$SELECTED_XCODE_DEVELOPER_DIR"', source)
        self.assertIn('run_frozen_xcode_tool "$SELECTED_XCTRACE" list devices', source)
        self.assertIn('run_frozen_xcode_tool "$SELECTED_DEVICECTL" list devices --hide-headers', source)
        self.assertIn('run_frozen_xcode_tool "$SELECTED_DEVICECTL" device process launch', source)

        self.assertNotIn('APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"', source)
        self.assertNotIn('SOURCE_APP_TREE_SHA256=', source)
        self.assertNotIn('/usr/bin/sudo /usr/bin/ditto --noacl "$APP" "$APP_INSTALL_STAGE"', source)
        self.assertNotIn('/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-authenticated-capture-install.XXXXXX', source)
        self.assertNotIn('xcrun devicectl', source)
        self.assertNotIn('xcrun xctrace', source)
        self.assertNotIn('open -a Xcode', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
