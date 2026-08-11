#!/usr/bin/env python3
"""V14 expected-red: accepted tracked source must remain authoritative while xcodebuild runs."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"


def load_guard():
    name = "capture_build_guard_red_team"
    spec = importlib.util.spec_from_file_location(name, GUARD)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load build guard")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def write(path: Path, payload: str = "accepted\n") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(payload, encoding="utf-8")
    return path


class CaptureTrackedSourceBuildWindowRedTeamTests(unittest.TestCase):
    def _fixture(self, root: Path):
        guard = load_guard()
        lockfile = write(root / "Podfile.lock")
        security_podspec = write(root / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec")
        security_build = root / "LocalSecrets/TuyaSDK/Build"
        write(security_build / "Security.framework/marker")
        identity_podspec = write(root / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec")
        identity_sources = root / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"
        write(identity_sources / "Config.swift")
        write(root / "LocalSecrets/TuyaRuntime/ResolvedTuyaDependencyProvenance.txt")
        write(root / "LocalSecrets/TuyaRuntime/PrivateReviewCommitment.key")
        pods = root / "Pods"
        write(pods / "Manifest.lock")
        workspace = root / "NembraCapture.xcworkspace"
        write(workspace / "contents.xcworkspacedata")
        tracked_source = write(
            root / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/Accepted.swift",
            "public let accepted = true\n",
        )
        inputs = guard.PrivateInputs(
            lockfile=lockfile,
            security_podspec=security_podspec,
            security_build=security_build,
            identity_podspec=identity_podspec,
            identity_sources=identity_sources,
            generated_pods=pods,
            generated_workspace=workspace,
        )
        return guard, inputs, tracked_source

    def test_installer_only_rechecks_tracked_source_after_guarded_build(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        build_start = source.index('say "Building SDK-integrated Nembra Capture for the intended iPhone"')
        xcode = source.index("-- /usr/bin/xcodebuild", build_start)
        post_verify = source.index(
            'verify_accepted_checkout_source "Accepted-source inputs changed while the field build was compiling.',
            xcode,
        )
        guarded_call = source[build_start:xcode]
        self.assertIn('run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE"', guarded_call)
        self.assertNotIn("verify_accepted_checkout_source", guarded_call)
        self.assertGreater(post_verify, xcode)

    def test_guard_must_watch_ordinary_accepted_tracked_source_during_build(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-tracked-source-window-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            guard, inputs, tracked_source = self._fixture(root)
            watched = set(guard._watch_paths(inputs))
            self.assertIn(
                tracked_source,
                watched,
                "accepted tracked Swift is outside vnode custody while xcodebuild runs; a transient rewrite can be consumed then restored before endpoint verification",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
