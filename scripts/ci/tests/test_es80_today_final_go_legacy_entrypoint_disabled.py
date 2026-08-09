#!/usr/bin/env python3
"""Expected-red guard: the legacy Final GO foundation must not remain an executable authority path."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"
spec = importlib.util.spec_from_file_location("legacy_final_go", MODULE_PATH)
legacy = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(legacy)


class LegacyFinalGoEntrypointAuthorityTests(unittest.TestCase):
    def test_direct_legacy_cli_cannot_emit_go_even_if_legacy_authority_stubs_succeed(self):
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
                legacy,
                "build_final_go_record",
                return_value={"decision": "GO", "authority": "legacy-unsafe-stub"},
            ) as build, mock.patch.object(
                legacy,
                "publish_record_no_replace",
                side_effect=unsafe_publish,
            ) as publish:
                status = legacy.main(argv)

            self.assertNotEqual(
                status,
                0,
                "legacy foundation CLI remained an executable Final GO authority path",
            )
            build.assert_not_called()
            publish.assert_not_called()
            self.assertFalse(
                output.exists(),
                "legacy foundation CLI emitted a durable Final GO pathname",
            )


if __name__ == "__main__":
    unittest.main()
