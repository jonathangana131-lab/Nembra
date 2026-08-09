#!/usr/bin/env python3
"""Expected-red guard: the legacy Final GO foundation must not remain an executable authority."""
from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
from io import StringIO
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"
spec = importlib.util.spec_from_file_location("final_go_foundation", MODULE_PATH)
foundation = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(foundation)


class LegacyFinalGoCLIDisabledTests(unittest.TestCase):
    def test_direct_foundation_cli_cannot_mint_go_even_if_legacy_seams_succeed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            output.write_bytes(b"sentinel-existing-non-authority\n")

            argv = [
                "--candidate-root", str(root / "candidate"),
                "--expected-source-sha", "1" * 40,
                "--expected-pr-number", "833",
                "--trusted-xcode-run-id", "1",
                "--trusted-xcode-job-id", "2",
                "--trusted-xcode-artifact-id", "3",
                "--trusted-xcode-artifact-archive", str(root / "artifact.zip"),
                "--independent-crosscheck-receipt", str(root / "crosscheck.json"),
                "--frozen-source-repo", str(root / "source-repo"),
                "--tooling-repo", str(root / "tooling-repo"),
                "--operator-attestation", str(root / "attestation.json"),
                "--output", str(output),
            ]

            with mock.patch.object(
                foundation,
                "build_final_go_record",
                return_value={"decision": "GO", "acceptedSourceCommitSHA": "1" * 40},
            ) as legacy_builder, mock.patch.object(
                foundation,
                "publish_record_no_replace",
                return_value="a" * 64,
            ) as legacy_publisher:
                stdout = StringIO()
                stderr = StringIO()
                with redirect_stdout(stdout), redirect_stderr(stderr):
                    result = foundation.main(argv)

            self.assertNotEqual(
                result,
                0,
                "legacy foundation CLI still returns success and can remain a Final GO authority surface",
            )
            legacy_builder.assert_not_called()
            legacy_publisher.assert_not_called()
            self.assertEqual(output.read_bytes(), b"sentinel-existing-non-authority\n")


if __name__ == "__main__":
    unittest.main()
