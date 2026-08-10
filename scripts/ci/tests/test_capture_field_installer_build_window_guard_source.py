#!/usr/bin/env python3
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"
GUARD = ROOT / "Scripts" / "capture_tuya_private_input_build_guard.py"


class CaptureFieldInstallerBuildWindowGuardSourceTests(unittest.TestCase):
    def test_installer_runs_xcodebuild_inside_private_input_guard(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        start = source.index('say "Building private authenticated Capture for the intended iPhone"')
        end = source.index('APP_PATH=', start)
        build = source[start:end]
        self.assertIn('TUYA_BUILD_WINDOW_GUARD=', source)
        self.assertIn('/usr/bin/python3 -I "$TUYA_BUILD_WINDOW_GUARD"', build)
        self.assertIn('--lockfile "$ROOT/Podfile.lock"', build)
        self.assertIn('--security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec"', build)
        self.assertIn('--security-build "$TUYA_PRIVATE_SDK/Build"', build)
        self.assertIn('--identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec"', build)
        self.assertIn('--identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig"', build)
        self.assertIn('-- xcodebuild -workspace NembraCapture.xcworkspace', build)
        self.assertEqual(build.count('xcodebuild -workspace NembraCapture.xcworkspace'), 1)

    def test_guard_keeps_existing_post_build_crypto_verify(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        build = source.index('say "Building private authenticated Capture for the intended iPhone"')
        post = source.index('verify_private_tuya_inputs', build)
        app = source.index('APP_PATH=', build)
        self.assertLess(build, post)
        self.assertLess(post, app)
        self.assertIn('private inputs changed while xcodebuild was running', source)

    def test_guard_source_is_present_and_mac_vnode_specific(self) -> None:
        source = GUARD.read_text(encoding="utf-8")
        self.assertIn('class KqueueVnodeBackend', source)
        self.assertIn('select.KQ_FILTER_VNODE', source)
        self.assertIn('private build input mutation was observed while xcodebuild was running', source)
        self.assertIn('final_snapshot = inputs.generation_snapshot()', source)


if __name__ == "__main__":
    unittest.main()
