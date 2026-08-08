#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
PRIVATE_RUNNER = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_private_runner.py"


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_is_required_through_private_path_only_input(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        runner = PRIVATE_RUNNER.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to an absolute private mode-0600 file containing the verification-only intended field iPhone UDID.}"',
            source,
        )
        self.assertIn('unset NEMBRA_INTENDED_FIELD_DEVICE_UDID', source)
        self.assertIn('es80_signed_field_artifact_private_runner.py', source)
        self.assertIn('--validate-private-input', source)
        self.assertIn(
            '--intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"',
            source,
        )
        self.assertNotIn('NEMBRA_INTENDED_FIELD_DEVICE_UDID:?Set', source)
        self.assertNotIn('python3 - "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('--intended-device-udid "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)

        # The verification value is read only inside the runner after a no-follow descriptor open.
        # It must never become an OS-visible child-process argument or environment value.
        self.assertIn('os.O_NOFOLLOW', runner)
        self.assertIn('before = os.fstat(descriptor)', runner)
        self.assertIn('after = os.fstat(descriptor)', runner)
        self.assertIn('before_identity != after_identity', runner)
        self.assertIn('inspector.main(inspector_arguments)', runner)
        self.assertNotIn('subprocess', runner)
        self.assertNotIn('os.environ', runner)

        # The intended device remains an admission input, not artifact provenance. Do not serialize,
        # echo, hash, or derive an output path from the private verification file or its contents.
        self.assertNotIn('intended_device_udid=', source)
        self.assertNotIn('field_device_udid=', source)
        self.assertNotIn('echo "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"', source)
        self.assertNotIn('ARTIFACTS_DIR="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', source)
        self.assertNotIn('BUILD_INSTANCE_ID="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', source)


if __name__ == "__main__":
    unittest.main()
