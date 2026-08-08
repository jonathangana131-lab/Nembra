#!/usr/bin/env python3
"""Regression for the canonical signed-field exact-input snapshot boundary."""

from __future__ import annotations

import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence.py"


def load_inspector():
    spec = importlib.util.spec_from_file_location("nembra_signed_field_exact_subject", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load signed-field inspector")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SignedFieldArtifactExactSubjectTests(unittest.TestCase):
    def test_main_inspects_and_retains_only_the_private_snapshot(self) -> None:
        inspector = load_inspector()
        source_sha = "a" * 40
        original = b"exact field candidate bytes"
        mutated_source = b"source changed after snapshot"

        with tempfile.TemporaryDirectory(prefix="nembra-exact-subject-main-test-") as temporary:
            root = Path(temporary)
            source = root / "candidate.ipa"
            source.write_bytes(original)
            output = root / "evidence"
            observed: dict[str, object] = {}

            field_record = {
                "sourceCommitSHA": source_sha,
                "buildInstanceID": "12345678-1234-4abc-8def-1234567890ab",
                "signedInstallableSHA256": hashlib.sha256(original).hexdigest(),
            }
            inspection = {
                "field_build_record": field_record,
                "signing_inspection": {
                    "signedInstallableSHA256": hashlib.sha256(original).hexdigest(),
                    "ipaByteCount": len(original),
                },
            }

            def fake_inspect(path: Path, expected_source_sha: str, *, intended_device_udid: str):
                observed["inspect_path"] = path
                observed["inspect_bytes"] = path.read_bytes()
                source.write_bytes(mutated_source)
                observed["snapshot_after_source_mutation"] = path.read_bytes()
                return inspection

            def fake_write(path: Path, output_dir: Path, accepted_inspection: dict):
                observed["write_path"] = path
                observed["write_bytes"] = path.read_bytes()
                return {
                    "external_record": output_dir / "external.json",
                    "field_build_record": output_dir / "field.json",
                    "signing_inspection": output_dir / "inspection.json",
                    "retained_ipa": output_dir / "build-evidence" / "NembraField.ipa",
                }

            with (
                patch.object(inspector._core, "inspect_ipa", side_effect=fake_inspect),
                patch.object(inspector._core, "write_outputs", side_effect=fake_write),
            ):
                result = inspector.main([
                    "--ipa",
                    str(source),
                    "--output-dir",
                    str(output),
                    "--expected-source-sha",
                    source_sha,
                    "--intended-device-udid",
                    "00008101-001234567890001E",
                ])

            self.assertEqual(result, 0)
            self.assertNotEqual(observed["inspect_path"], source)
            self.assertEqual(observed["inspect_path"], observed["write_path"])
            self.assertEqual(observed["inspect_bytes"], original)
            self.assertEqual(observed["snapshot_after_source_mutation"], original)
            self.assertEqual(observed["write_bytes"], original)
            self.assertEqual(source.read_bytes(), mutated_source)


if __name__ == "__main__":
    unittest.main()
