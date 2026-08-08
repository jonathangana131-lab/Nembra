#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_is_required_and_used_only_for_verification(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID to the intended field iPhone UDID for verification only.}"',
            source,
        )
        self.assertIn(
            'python3 - "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"',
            source,
            "Validate the verification-only device identifier before spending a signed archive/export cycle.",
        )
        self.assertIn(
            '--intended-device-udid "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"',
            source,
        )

        # The intended device is an admission input, not artifact provenance. Do not serialize,
        # echo, hash, or derive an output path from the private verification value.
        self.assertNotIn('intended_device_udid=', source)
        self.assertNotIn('field_device_udid=', source)
        self.assertNotIn('echo "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('ARTIFACTS_DIR="$NEMBRA_INTENDED_FIELD_DEVICE_UDID', source)
        self.assertNotIn('BUILD_INSTANCE_ID="$NEMBRA_INTENDED_FIELD_DEVICE_UDID', source)


if __name__ == "__main__":
    unittest.main()
