#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
RUNNER = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_private_runner.py"


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_uses_path_only_private_input(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        runner = RUNNER.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to a mode-0600 file containing the intended field iPhone UDID.}"',
            source,
        )
        self.assertIn('es80_signed_field_artifact_private_runner.py', source)
        self.assertIn(
            '--intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"',
            source,
        )
        self.assertNotIn('NEMBRA_INTENDED_FIELD_DEVICE_UDID:?', source)
        self.assertNotIn('--intended-device-udid "$NEMBRA_', source)

        # The raw identifier is read only inside the private runner and passed to the incumbent
        # inspector through an in-memory argv list, never through this process's OS argv/environment.
        self.assertIn('os.O_NOFOLLOW', runner)
        self.assertIn('before = os.fstat(descriptor)', runner)
        self.assertIn('after = os.fstat(descriptor)', runner)
        self.assertIn('inspector.main(inspector_arguments)', runner)
        self.assertIn('"--intended-device-udid", intended_device_identifier', runner)
        self.assertNotIn('os.environ[', runner)

        # The intended device remains verification input, not artifact provenance.
        self.assertNotIn('intended_device_udid=', source)
        self.assertNotIn('field_device_udid=', source)
        self.assertNotIn('ARTIFACTS_DIR="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', source)
        self.assertNotIn('BUILD_INSTANCE_ID="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', source)


if __name__ == "__main__":
    unittest.main()
