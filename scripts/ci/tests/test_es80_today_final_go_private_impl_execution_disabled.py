#!/usr/bin/env python3
"""Expected-red proof that the private Final-GO implementation is import-only.

Renaming the authority-bearing foundation implementation behind a public fail-closed wrapper must
not leave the implementation filename itself as a second executable GO endpoint.
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
IMPL_PATH = CI_DIR / "_es80_today_final_go_foundation_impl.py"


def _load_impl():
    spec = importlib.util.spec_from_file_location("nembra_private_final_go_impl_probe", IMPL_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load private Final GO implementation")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateFinalGoImplementationExecutionTests(unittest.TestCase):
    def test_private_implementation_direct_main_fails_before_builder_or_publisher(self) -> None:
        implementation = _load_impl()
        build_calls: list[dict[str, object]] = []
        publish_calls: list[tuple[Path, bytes]] = []

        def forbidden_build(**values):
            build_calls.append(values)
            return {"authority": "unsafe-private-implementation-probe"}

        def forbidden_publish(output: Path, raw: bytes, **_kwargs):
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
            stdout = io.StringIO()
            stderr = io.StringIO()
            with mock.patch.object(implementation, "build_final_go_record", side_effect=forbidden_build), mock.patch.object(
                implementation, "publish_record_no_replace", side_effect=forbidden_publish
            ), redirect_stdout(stdout), redirect_stderr(stderr):
                result = implementation.main(argv)

        self.assertEqual(result, 2, "private implementation filename must fail closed when executed")
        self.assertEqual(build_calls, [], "private executable path reached authority-bearing builder")
        self.assertEqual(publish_calls, [], "private executable path reached GO publisher")
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("non-authorizing", stderr.getvalue().lower())
        self.assertIn("es80_today_final_go_hardened.py", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
