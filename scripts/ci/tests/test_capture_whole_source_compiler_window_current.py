#!/usr/bin/env python3
"""Exploit-positive classifier for the current whole-source compiler window.

The field installer may prove accepted Git state at endpoints, but the build still runs
from the field-owned checkout. A same-UID actor can therefore mutate tracked source,
let xcodebuild consume it, restore accepted bytes, and leave endpoint equality intact.
SUCCESS in this diagnostic means the current production carrier remains RED.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


class CaptureWholeSourceCompilerWindowCurrentTests(unittest.TestCase):
    def test_endpoint_equality_cannot_prove_consumed_bytes(self) -> None:
        accepted = b"accepted swift source\n"
        attacker = b"transient attacker source\n"
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "A.swift"
            path.write_bytes(accepted)
            before = _sha(path.read_bytes())

            path.write_bytes(attacker)
            consumed = path.read_bytes()
            path.write_bytes(accepted)

            after = _sha(path.read_bytes())
            self.assertEqual(before, after)
            self.assertEqual(path.read_bytes(), accepted)
            self.assertEqual(consumed, attacker)
            self.assertNotEqual(_sha(consumed), before)

    def test_current_carrier_still_builds_from_field_owned_checkout(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")

        # Exact accepted helper transport is useful but does not freeze the tracked
        # workspace xcodebuild subsequently opens relative to the live repository cwd.
        self.assertIn("--source-sha \"$SOURCE_SHA\"", installer)
        self.assertIn("-- /usr/bin/xcodebuild", installer)
        self.assertIn("-workspace NembraCapture.xcworkspace", installer)

        protected_source_markers = (
            "NEMBRA_ACCEPTED_SOURCE_ROOT",
            "accepted_source_root",
            "source_stage_root",
            "protected_source_root",
            "frozen_source_root",
        )
        self.assertFalse(
            any(marker in installer for marker in protected_source_markers),
            "production appears to have gained a protected accepted-source stage; re-review this classifier instead of preserving exploit-positive success",
        )

    def test_private_guard_scope_is_not_whole_tracked_source_custody(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        for marker in (
            '--lockfile "$ROOT/Podfile.lock"',
            '--security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec"',
            '--security-build "$TUYA_PRIVATE_SDK/Build"',
            '--identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec"',
            '--identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig"',
        ):
            self.assertIn(marker, installer)
        self.assertNotIn('--tracked-source-root', installer)
        self.assertNotIn('--accepted-source-root', installer)


if __name__ == "__main__":
    unittest.main(verbosity=2)
