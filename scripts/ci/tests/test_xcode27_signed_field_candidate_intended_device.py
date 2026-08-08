#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_is_required_validated_and_not_persisted(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_FIELD_DEVICE_UDID:?Set NEMBRA_FIELD_DEVICE_UDID to the intended field iPhone identifier for verification only.}"',
            source,
        )
        self.assertIn(
            'NEMBRA_FIELD_DEVICE_UDID="$NEMBRA_FIELD_DEVICE_UDID" python3 -',
            source,
        )
        self.assertIn(
            '--intended-device-udid "$NEMBRA_FIELD_DEVICE_UDID"',
            source,
        )
        self.assertIn('must not contain whitespace or control characters', source)
        self.assertNotIn('field_device_udid=', source)
        self.assertNotIn('intended_device_udid=', source)
        self.assertNotIn('echo "$NEMBRA_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('echo $NEMBRA_FIELD_DEVICE_UDID', source)
        self.assertIn('Verification-only field-device identifier leaked into retained evidence schema', source)


if __name__ == "__main__":
    unittest.main()
