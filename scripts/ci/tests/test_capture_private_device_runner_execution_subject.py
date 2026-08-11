#!/usr/bin/env python3
"""Regression for field-installer private-device runner execution custody."""
from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"

VULNERABLE_RUNNER_ASSIGNMENT = (
    'PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"'
)
VULNERABLE_PATH_IMPORT = 'spec = importlib.util.spec_from_file_location("nembra_private_device_reader", runner_path)'


class PrivateDeviceRunnerExecutionSubjectTests(unittest.TestCase):
    def test_installer_executes_exact_accepted_runner_bytes_not_checkout_path(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertNotIn(VULNERABLE_RUNNER_ASSIGNMENT, source)
        self.assertNotIn(VULNERABLE_PATH_IMPORT, source)

        accepted = 'PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git rev-parse "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_RELATIVE"'
        materialize = 'PRIVATE_DEVICE_RUNNER="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git cat-file blob "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB"'
        canonical_base64 = "/usr/bin/base64 | /usr/bin/tr -d '\\r\\n'"
        verify = 'printf \'%s\' "$PRIVATE_DEVICE_RUNNER" | /usr/bin/base64 -D | GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git hash-object --stdin'
        execute = 'runner_source = base64.b64decode(sys.argv[1], validate=True)'
        compile_marker = 'compile(runner_source, "<accepted-private-device-runner>", "exec", dont_inherit=True)'
        interpreter = '/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER"'
        self.assertIn(accepted, source)
        self.assertIn(materialize, source)
        self.assertIn(canonical_base64, source)
        self.assertIn(verify, source)
        self.assertIn(execute, source)
        self.assertIn(compile_marker, source)
        self.assertIn(interpreter, source)
        self.assertIn('GIT_NO_REPLACE_OBJECTS=1', source)

    def test_runner_blob_is_captured_before_device_authority_interpreter(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        blob = source.find("PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB=")
        bytes_marker = source.find('PRIVATE_DEVICE_RUNNER="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git cat-file blob')
        interpreter = source.find('if ! DEVICE_UDID="$(/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER"')
        self.assertGreaterEqual(blob, 0)
        self.assertGreater(bytes_marker, blob)
        self.assertGreater(interpreter, bytes_marker)
        self.assertNotIn("import importlib.util", source[source.find("if ! DEVICE_UDID="):interpreter + 2500])


if __name__ == "__main__":
    unittest.main(verbosity=2)
