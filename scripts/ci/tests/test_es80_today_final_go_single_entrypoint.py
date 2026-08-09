#!/usr/bin/env python3
"""Expected-red proof that the legacy Final GO CLI cannot remain an authority path.

V14 requires one canonical external Final GO executable path. The hardened entrypoint may reuse the
foundation as a library, but invoking es80_today_final_go_record.py directly must fail closed before
its legacy PR-controlled Xcode subject or publication path can mint a GO record.
"""
from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest import mock

CI_DIR = Path(__file__).resolve().parents[1]
FOUNDATION_PATH = CI_DIR / "es80_today_final_go_record.py"


def _load_foundation():
    spec = importlib.util.spec_from_file_location("nembra_final_go_legacy_entrypoint_probe", FOUNDATION_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Final GO foundation")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FinalGoSingleEntrypointTests(unittest.TestCase):
    def test_legacy_cli_fails_closed_before_building_or_publishing_authority(self) -> None:
        foundation = _load_foundation()
        build_calls: list[dict[str, object]] = []
        publish_calls: list[tuple[Path, bytes]] = []

        def forbidden_legacy_build(**values):
            build_calls.append(values)
            return {"authority": "legacy-unsafe-probe"}

        def forbidden_legacy_publish(output: Path, raw: bytes, **_kwargs):
            publish_calls.append((output, raw))
            return "0" * 64

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            argv = [
                "--candidate-root", str(root / "candidate"),
                "--expected-source-sha", "1" * 40,
                "--expected-pr-number", "833",
                "--trusted-xcode-run-id", "1",
                "--trusted-xcode-job-id", "2",
                "--trusted-xcode-artifact-id", "3",
                "--trusted-xcode-artifact-archive", str(root / "artifact.zip"),
                "--independent-crosscheck-receipt", str(root / "crosscheck.json"),
                "--frozen-source-repo", str(root / "source"),
                "--tooling-repo", str(root / "tooling"),
                "--operator-attestation", str(root / "attestation.json"),
                "--output", str(root / "FinalGO.json"),
            ]
            stderr = io.StringIO()
            stdout = io.StringIO()
            with mock.patch.object(foundation, "build_final_go_record", side_effect=forbidden_legacy_build), mock.patch.object(
                foundation, "publish_record_no_replace", side_effect=forbidden_legacy_publish
            ), redirect_stdout(stdout), redirect_stderr(stderr):
                result = foundation.main(argv)

        self.assertEqual(result, 2, "legacy Final GO CLI must be a fail-closed compatibility boundary")
        self.assertEqual(build_calls, [], "legacy CLI reached its unsafe Final GO builder")
        self.assertEqual(publish_calls, [], "legacy CLI reached its unsafe Final GO publisher")
        self.assertIn("hardened", stderr.getvalue().lower())
        self.assertEqual(stdout.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
