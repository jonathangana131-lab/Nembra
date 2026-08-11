#!/usr/bin/env python3
"""Independent #2886 replay against #2898 accepted-Git runner execution custody."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"


class CaptureFieldPrivateRunnerExecution2898Tests(unittest.TestCase):
    def test_mutable_path_reopen_primitive_still_executes_replacement_bytes(self) -> None:
        """Preserve the original attack premise independently of production markers."""
        with tempfile.TemporaryDirectory() as directory:
            runner = Path(directory) / "accepted_runner.py"
            runner.write_text("VALUE = 'accepted'\n", encoding="utf-8")
            self.assertEqual(runner.read_bytes(), b"VALUE = 'accepted'\n")
            runner.write_text("VALUE = 'attacker'\n", encoding="utf-8")

            spec = importlib.util.spec_from_file_location("nembra_red_team_runner", runner)
            self.assertIsNotNone(spec)
            self.assertIsNotNone(spec.loader if spec else None)
            module = importlib.util.module_from_spec(spec)  # type: ignore[arg-type]
            spec.loader.exec_module(module)  # type: ignore[union-attr]
            self.assertEqual(module.VALUE, "attacker")

    def test_2898_executes_runner_only_from_exact_accepted_git_bytes(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        start = source.index('PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"')
        end = source.index('say "Private intended-device admission validated against Final GO digest"', start)
        admission = source[start:end]

        # The compatibility pathname marker may remain temporarily, but it may not
        # become an execution/read subject anywhere in the admission window.
        self.assertNotIn('[[ -f "$PRIVATE_DEVICE_RUNNER" ]]', admission)
        self.assertNotIn('"$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"', admission)
        self.assertNotIn("spec_from_file_location", admission)
        self.assertNotIn("exec_module", admission)

        self.assertIn(
            'run_authority_git show "$SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner.py"',
            admission,
        )
        self.assertIn('/usr/bin/env -i', admission)
        self.assertIn('/usr/bin/python3 -I -B -c', admission)
        self.assertIn('source = sys.stdin.buffer.read(2 * 1024 * 1024 + 1)', admission)
        self.assertIn('if not source or len(source) > 2 * 1024 * 1024:', admission)
        self.assertIn('module = ModuleType("nembra_private_device_reader")', admission)
        self.assertIn('exec(compile(source, module.__file__, "exec"), module.__dict__)', admission)
        self.assertIn('reader = getattr(module, "read_private_identifier", None)', admission)
        self.assertIn('if not callable(reader):', admission)

        # Raw device identifier stays a value returned from the accepted reader;
        # only its accepted digest is deliberately passed into the closed child env.
        self.assertIn('NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"', admission)
        self.assertNotIn('NEMBRA_INTENDED_FIELD_DEVICE_UDID="$DEVICE_UDID"', admission)


if __name__ == "__main__":
    unittest.main(verbosity=2)
