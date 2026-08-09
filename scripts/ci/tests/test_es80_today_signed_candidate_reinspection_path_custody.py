#!/usr/bin/env python3
"""Regression for retained signed-IPA reinspection pathname custody.

The helper first reads/authenticates one stable IPA byte subject. Apple extraction must consume those
same bytes (or a stable descriptor-backed materialization of them), not reopen the caller-controlled
retained path.
"""
from __future__ import annotations

import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

MODULE = Path(__file__).resolve().parents[1] / "es80_today_signed_candidate_reinspection.py"
spec = importlib.util.spec_from_file_location("signed_reinspection", MODULE)
reinspection = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(reinspection)


def ipa_bytes(marker: bytes) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("Payload/Nembra.app/marker.txt", marker)
    return output.getvalue()


class SignedCandidateReinspectionPathCustodyTests(unittest.TestCase):
    def test_extraction_consumes_authenticated_ipa_bytes_not_reopened_candidate_path(self) -> None:
        authenticated = ipa_bytes(b"authenticated-A\n")
        substituted = ipa_bytes(b"substituted-B\n")

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            retained = root / "NembraField.ipa"
            destination = root / "extract"
            destination.mkdir()
            retained.write_bytes(authenticated)

            def simulated_ditto(arguments: list[str]) -> subprocess.CompletedProcess[bytes]:
                self.assertEqual(arguments[:3], ["/usr/bin/ditto", "-x", "-k"])
                source = Path(arguments[3])
                target = Path(arguments[4])

                # Mutate the original retained path after `_extract_ipa` has already accepted A.
                # The authority-producing source must remain the stable descriptor-backed A bytes.
                retained.write_bytes(substituted)
                self.assertNotEqual(source, retained)
                self.assertTrue(str(source).startswith("/dev/fd/"))
                with zipfile.ZipFile(source, "r") as archive:
                    archive.extractall(target)
                return subprocess.CompletedProcess(arguments, 0, b"", b"")

            app = reinspection._extract_ipa(
                retained,
                authenticated,
                destination,
                simulated_ditto,
            )
            marker = (app / "marker.txt").read_bytes()

            self.assertEqual(
                marker,
                b"authenticated-A\n",
                "Apple-tool extraction reopened or substituted the retained IPA after descriptor admission",
            )


if __name__ == "__main__":
    unittest.main()
