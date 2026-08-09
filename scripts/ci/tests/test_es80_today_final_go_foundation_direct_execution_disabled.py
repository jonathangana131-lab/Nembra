#!/usr/bin/env python3
"""Expected-red guard: the extracted Final GO foundation must remain library-only."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_foundation.py"
spec = importlib.util.spec_from_file_location("final_go_foundation", MODULE_PATH)
foundation = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(foundation)


class FoundationDirectExecutionAuthorityTests(unittest.TestCase):
    def test_foundation_main_cannot_build_or_publish_final_go(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            argv = [
                "--candidate-root", str(root / "candidate"),
                "--expected-source-sha", "a" * 40,
                "--expected-pr-number", "833",
                "--trusted-xcode-run-id", "1001",
                "--trusted-xcode-job-id", "2002",
                "--trusted-xcode-artifact-id", "3003",
                "--trusted-xcode-artifact-archive", str(root / "artifact.zip"),
                "--independent-crosscheck-receipt", str(root / "crosscheck.json"),
                "--frozen-source-repo", str(root / "source"),
                "--tooling-repo", str(root / "tooling"),
                "--operator-attestation", str(root / "attestation.json"),
                "--output", str(output),
            ]

            def unsafe_publish(path: Path, raw: bytes) -> str:
                path.write_bytes(raw)
                return "c" * 64

            with mock.patch.object(
                foundation,
                "build_final_go_record",
                return_value={"decision": "GO", "authority": "legacy-foundation-stub"},
            ) as build, mock.patch.object(
                foundation,
                "publish_record_no_replace",
                side_effect=unsafe_publish,
            ) as publish:
                status = foundation.main(argv)

            self.assertNotEqual(
                status,
                0,
                "library foundation remained a directly executable Final GO authority",
            )
            build.assert_not_called()
            publish.assert_not_called()
            self.assertFalse(output.exists(), "library foundation emitted a Final GO pathname")


if __name__ == "__main__":
    unittest.main()
