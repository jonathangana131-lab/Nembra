#!/usr/bin/env python3
"""Expected-red V14 witness for mutable private-runner execution after source preflight."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"


class CaptureFieldPrivateRunnerExecutionAuthorityRedTeamTests(unittest.TestCase):
    def test_same_path_replacement_after_preflight_executes_replacement_bytes(self) -> None:
        """Model the exact primitive used by the field installer's direct path import."""
        with tempfile.TemporaryDirectory() as directory:
            runner = Path(directory) / "accepted_runner.py"
            runner.write_text("VALUE = 'accepted'\n", encoding="utf-8")

            # A preflight byte check can be true and still provide no execution
            # custody if the later loader reopens the mutable pathname.
            accepted_bytes = runner.read_bytes()
            self.assertEqual(accepted_bytes, b"VALUE = 'accepted'\n")
            runner.write_text("VALUE = 'attacker'\n", encoding="utf-8")

            spec = importlib.util.spec_from_file_location("nembra_red_team_runner", runner)
            self.assertIsNotNone(spec)
            self.assertIsNotNone(spec.loader if spec else None)
            module = importlib.util.module_from_spec(spec)  # type: ignore[arg-type]
            spec.loader.exec_module(module)  # type: ignore[union-attr]
            self.assertEqual(module.VALUE, "attacker")

    def test_field_installer_must_not_import_private_runner_from_mutable_checkout(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        start = source.index('PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"')
        end = source.index('say "Private intended-device admission validated against Final GO digest"', start)
        admission = source[start:end]

        self.assertNotIn(
            'spec_from_file_location("nembra_private_device_reader", runner_path)',
            admission,
            "field installer audits accepted source, then reopens and executes the private intended-device runner from mutable worktree bytes",
        )
        immutable_markers = (
            'run_authority_git show "$SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner.py"',
            'run_accepted_source_python "scripts/ci/es80_signed_field_artifact_private_runner.py"',
            'run_accepted_source_python "$PRIVATE_DEVICE_RUNNER_RELATIVE"',
        )
        self.assertTrue(
            any(marker in admission for marker in immutable_markers),
            "private intended-device runner execution is not visibly bound to exact accepted Git-object bytes",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
