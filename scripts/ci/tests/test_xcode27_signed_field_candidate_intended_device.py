#!/usr/bin/env python3
from pathlib import Path
import unittest

CI_DIR = Path(__file__).resolve().parents[1]
SCRIPT = CI_DIR / "xcode27_signed_field_candidate.sh"
PRIVATE_RUNNER = CI_DIR / "es80_signed_field_artifact_private_runner.py"


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_uses_private_file_path_not_raw_process_input(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        runner = PRIVATE_RUNNER.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to a private mode-0600 file containing the intended field iPhone UDID for verification only.}"',
            source,
        )
        self.assertIn("es80_signed_field_artifact_private_runner.py", source)
        self.assertIn(
            '--intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"',
            source,
        )
        self.assertIn("--check-private-input", source)

        # The shell may expose only the private-file path. The raw identifier must never become an
        # environment requirement or OS-visible argv value in the field producer.
        self.assertNotIn('${NEMBRA_INTENDED_FIELD_DEVICE_UDID:', source)
        self.assertNotIn('"$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('--intended-device-udid "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('python3 - "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('echo "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)

        # The wrapper turns the private-file value into an in-memory inspector argv list only after
        # opening it no-follow with restrictive permissions; it never exports that value.
        self.assertIn("os.O_NOFOLLOW", runner)
        self.assertIn("before.st_mode & 0o077", runner)
        self.assertIn("before.st_uid != os.geteuid()", runner)
        self.assertIn("_stable_file_identity(after) != _stable_file_identity(before)", runner)
        self.assertIn('"--intended-device-udid",', runner)
        self.assertIn("intended_device_identifier", runner)
        self.assertIn("inspector.main(inspector_arguments)", runner)
        self.assertNotIn("os.environ[", runner)
        self.assertNotIn("os.environ.get", runner)


if __name__ == "__main__":
    unittest.main()
