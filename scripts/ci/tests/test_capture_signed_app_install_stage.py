#!/usr/bin/env python3
"""Source-contract tests for frozen signed-app install custody."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
HELPER = ROOT / "Scripts/capture_signed_app_install_stage.py"

spec = importlib.util.spec_from_file_location("install_stage", HELPER)
assert spec and spec.loader
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class SignedAppInstallStageTests(unittest.TestCase):
    def test_relative_symlink_policy_stays_inside_app(self) -> None:
        app = Path("/tmp/Nembra Capture.app")
        self.assertTrue(stage._symlink_stays_inside(app, app / "Frameworks/A.framework/A", "Versions/Current/A"))
        self.assertTrue(stage._symlink_stays_inside(app, app / "Frameworks/A.framework/Versions/Current", "A"))
        self.assertFalse(stage._symlink_stays_inside(app, app / "escape", "../outside"))
        self.assertFalse(stage._symlink_stays_inside(app, app / "escape", "/private/etc/passwd"))

    def test_privileged_helper_never_reads_mutable_source_as_root(self) -> None:
        source = HELPER.read_text(encoding="utf-8")
        self.assertIn("os.fchdir(payload_fd)", source)
        self.assertIn("os.setgid(gid)", source)
        self.assertIn("os.setuid(uid)", source)
        self.assertIn('os.execve("/usr/bin/ditto"', source)
        self.assertLess(source.index("os.setuid(uid)"), source.index('os.execve("/usr/bin/ditto"')))
        self.assertIn("os.chmod(outer, 0o700)", source)
        self.assertIn("_freeze_tree(app, uid, gid)", source)
        self.assertIn("_verify_frozen_tree(app, gid)", source)
        self.assertIn("meta.st_nlink != 1", source)
        self.assertIn("mode & 0o222", source)
        self.assertIn("_symlink_stays_inside", source)

    def test_installer_verifies_frozen_subject_then_installs_same_path(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        git_blob = 'git show "${SOURCE_SHA}:Scripts/capture_signed_app_install_stage.py"'
        stage_call = 'stage --source "$BUILT_APP" --uid "$FIELD_UID" --gid "$FIELD_GID"'
        app_info = 'APP_INFO_PLIST="$APP/Info.plist"'
        codesign = '/usr/bin/codesign --verify --deep --strict "$APP"'
        open_xcode = 'open -a Xcode "$ROOT/NembraCapture.xcworkspace"'
        verify_call = 'verify --app "$APP" --gid "$FIELD_GID"'
        install_call = 'xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP"'
        cleanup_call = 'cleanup --stage-root "$INSTALL_STAGE_ROOT"'
        launch = 'say "Launching privately provisioned Capture on the intended iPhone"'

        for marker in (git_blob, stage_call, app_info, codesign, open_xcode, verify_call, install_call, cleanup_call, launch):
            self.assertIn(marker, source, marker)

        git_blob_index = source.index(git_blob)
        stage_index = source.index(stage_call)
        app_info_index = source.index(app_info)
        codesign_index = source.index(codesign)
        open_index = source.index(open_xcode)
        verify_index = source.index(verify_call, open_index)
        install_index = source.index(install_call, open_index)
        cleanup_index = source.index(cleanup_call, install_index)
        launch_index = source.index(launch)

        self.assertLess(git_blob_index, stage_index)
        self.assertLess(stage_index, app_info_index)
        self.assertLess(app_info_index, codesign_index)
        self.assertLess(codesign_index, open_index)
        self.assertLess(open_index, verify_index)
        self.assertLess(verify_index, install_index)
        self.assertLess(install_index, cleanup_index)
        self.assertLess(cleanup_index, launch_index)

        self.assertNotIn('sudo /usr/bin/python3 -I "$ROOT/Scripts/capture_signed_app_install_stage.py"', source)
        self.assertIn('/usr/bin/sudo /usr/bin/python3 -I -c "$INSTALL_STAGE_HELPER_SOURCE"', source)
        self.assertIn('/usr/bin/python3 -I -c "$INSTALL_STAGE_HELPER_SOURCE" verify', source)
        self.assertIn('trap \'rm -f -- "$INSTALL_LOG"; cleanup_install_stage\' EXIT', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
