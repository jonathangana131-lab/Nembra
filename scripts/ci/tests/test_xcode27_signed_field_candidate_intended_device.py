#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_is_required_only_at_verification_boundary(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_FIELD_DEVICE_UDID:?Set NEMBRA_FIELD_DEVICE_UDID to the intended field iPhone UDID for verification only.}"',
            source,
        )
        self.assertIn(
            '--intended-device-udid "$NEMBRA_FIELD_DEVICE_UDID"',
            source,
        )
        self.assertEqual(
            source.count("NEMBRA_FIELD_DEVICE_UDID"),
            2,
            "The verification-only field-device UDID must not be echoed, persisted, hashed into evidence, or reused outside the canonical inspector call.",
        )


if __name__ == "__main__":
    unittest.main()
