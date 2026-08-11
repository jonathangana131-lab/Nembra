#!/usr/bin/env python3
"""V14 expected-red attack witness for tracked checkout source during field xcodebuild."""
from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
BUILD_GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"


def git_blob_oid(payload: bytes) -> str:
    return hashlib.sha1(
        b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    ).hexdigest()


class CaptureFieldTrackedSourceCompilerWindowRedTeamTests(unittest.TestCase):
    def test_endpoint_reverification_cannot_prove_which_source_bytes_compiler_consumed(self) -> None:
        """Mechanically prove mutate -> consume -> restore defeats endpoint-only source checks."""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "NembraCaptureEntrypoint.swift"
            artifact = root / "compiled-source-witness.bin"
            accepted = b"struct CaptureEntrypoint { static let authority = \"accepted\" }\n"
            attacker = b"struct CaptureEntrypoint { static let authority = \"attacker\" }\n"
            accepted_oid = git_blob_oid(accepted)

            source.write_bytes(accepted)
            self.assertEqual(git_blob_oid(source.read_bytes()), accepted_oid)

            source.write_bytes(attacker)
            artifact.write_bytes(source.read_bytes())
            source.write_bytes(accepted)

            self.assertEqual(git_blob_oid(source.read_bytes()), accepted_oid)
            self.assertEqual(artifact.read_bytes(), attacker)
            self.assertNotEqual(git_blob_oid(artifact.read_bytes()), accepted_oid)

    def test_current_field_build_is_endpoint_only_for_tracked_checkout_source(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        guard = BUILD_GUARD.read_text(encoding="utf-8")

        self.assertIn(
            'verify_accepted_checkout_source "Private workspace bootstrap changed accepted-source inputs."',
            installer,
        )
        self.assertIn(
            'verify_accepted_checkout_source "Accepted-source inputs changed while the field build was compiling.',
            installer,
        )

        start = installer.index('say "Building SDK-integrated Nembra Capture for the intended iPhone"')
        end = installer.index('verify_private_tuya_inputs\nverify_accepted_checkout_source', start)
        build_window = installer[start:end]
        self.assertIn('run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE"', build_window)
        self.assertIn('-workspace NembraCapture.xcworkspace', build_window)

        self.assertIn("def _watch_paths(inputs: PrivateInputs)", guard)
        self.assertIn("generated CocoaPods workspace tree", guard)
        self.assertNotIn("accepted_source_root", guard)
        self.assertNotIn("accepted_source_sha", guard)

    def test_field_build_must_hold_tracked_source_authority_across_compiler_window(self) -> None:
        """EXPECTED RED until xcodebuild cannot consume transient tracked checkout bytes."""

        installer = INSTALLER.read_text(encoding="utf-8")
        guard = BUILD_GUARD.read_text(encoding="utf-8")
        start = installer.index('say "Building SDK-integrated Nembra Capture for the intended iPhone"')
        end = installer.index('verify_private_tuya_inputs\nverify_accepted_checkout_source', start)
        build_window = installer[start:end]

        guarded_checkout = (
            "--accepted-source-root" in build_window
            and "--accepted-source-sha" in build_window
            and "accepted_source_root" in guard
            and "accepted_source_sha" in guard
        )
        protected_stage = (
            "accepted-source-stage" in build_window.lower()
            and "-workspace NembraCapture.xcworkspace" not in build_window
        )
        self.assertTrue(
            guarded_checkout or protected_stage,
            "field xcodebuild still consumes mutable tracked checkout source between endpoint audits; "
            "bind the accepted SOURCE_SHA tree through the compiler window or build from protected accepted bytes",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
