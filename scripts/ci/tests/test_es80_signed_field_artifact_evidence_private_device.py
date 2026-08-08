#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

WRAPPER = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence_private_device.py"

spec = importlib.util.spec_from_file_location("private_device_runner", WRAPPER)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load private device runner")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class PrivateDeviceEvidenceRunnerTests(unittest.TestCase):
    def private_file(self, root: Path, value: bytes) -> Path:
        path = root / "device-id.secret"
        path.write_bytes(value)
        os.chmod(path, 0o600)
        return path

    def test_reads_private_identifier_without_normalizing_it(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-device-") as temporary:
            path = self.private_file(Path(temporary), b"00008101-001234567890001E")
            self.assertEqual(
                runner.read_private_device_identifier(path),
                "00008101-001234567890001E",
            )

    def test_rejects_group_or_world_accessible_secret(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-device-") as temporary:
            path = self.private_file(Path(temporary), b"00008101-001234567890001E")
            os.chmod(path, 0o644)
            with self.assertRaisesRegex(ValueError, "group/world accessible"):
                runner.read_private_device_identifier(path)

    def test_rejects_symlink_secret(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-device-") as temporary:
            root = Path(temporary)
            target = self.private_file(root, b"00008101-001234567890001E")
            link = root / "device-id-link"
            link.symlink_to(target)
            with self.assertRaisesRegex(ValueError, "non-symlink"):
                runner.read_private_device_identifier(link)

    def test_rejects_whitespace_or_control_characters(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-device-") as temporary:
            root = Path(temporary)
            for index, value in enumerate((
                b"00008101-001234567890001E\n",
                b" 00008101-001234567890001E",
                b"00008101-001234567890001E\x00",
            )):
                path = root / f"device-id-{index}.secret"
                path.write_bytes(value)
                os.chmod(path, 0o600)
                with self.assertRaises(ValueError):
                    runner.read_private_device_identifier(path)

    def test_wrapper_never_spawns_canonical_inspector_with_raw_identifier(self):
        source = WRAPPER.read_text(encoding="utf-8")
        self.assertNotIn("subprocess", source)
        self.assertIn("canonical.main(", source)
        self.assertIn('"--intended-device-udid",', source)
        self.assertIn("device_identifier,", source)
        self.assertNotIn("print(device_identifier", source)


if __name__ == "__main__":
    unittest.main()
