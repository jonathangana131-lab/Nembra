import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_retained_install_manifest.py"
SPEC = importlib.util.spec_from_file_location("retained_install_manifest", SCRIPT)
assert SPEC and SPEC.loader
manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manifest)


class RetainedInstallManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bindings = {
            "procedureID": manifest.PROCEDURE_ID,
            "bundleIdentifier": manifest.BUNDLE_IDENTIFIER,
            "sourceCommitSHA": "1" * 40,
            "buildIdentifier": "Capture Build test",
            "buildInstanceID": "12345678-1234-4abc-8def-123456789abc",
            "signedInstallableSHA256": "2" * 64,
            "executableSHA256": "3" * 64,
            "infoPlistSHA256": "4" * 64,
            "tuyaDependencyLockSHA256": "5" * 64,
            "externalBuildRecordSHA256": "6" * 64,
            "signedBuildEvidenceSHA256": "7" * 64,
            "finalGORecordSHA256": "8" * 64,
            "intendedDevicePseudonymSHA256": "9" * 64,
            "authorizationEnvelopeSHA256": "a" * 64,
        }

    def test_round_trip_is_closed_canonical_and_explicitly_nonauthorizing(self) -> None:
        data = manifest.build_manifest(self.bindings)
        value = manifest.verify_manifest_against_expected(data, self.bindings)
        self.assertEqual(value["manifestKind"], manifest.MANIFEST_KIND)
        self.assertEqual(data, manifest.canonical_json_bytes(json.loads(data)))
        self.assertNotIn(b'"decision"', data)
        self.assertNotIn(b'"GO"', data)

    def test_every_exact_binding_drift_is_rejected(self) -> None:
        data = manifest.build_manifest(self.bindings)
        for key in manifest.BINDING_KEYS:
            changed = dict(self.bindings)
            if key == "procedureID":
                changed[key] = "wrong-procedure"
            elif key == "bundleIdentifier":
                changed[key] = "com.example.wrong"
            elif key == "sourceCommitSHA":
                changed[key] = "b" * 40
            elif key == "buildIdentifier":
                changed[key] = "Other Build"
            elif key == "buildInstanceID":
                changed[key] = "87654321-4321-4abc-8def-123456789abc"
            else:
                changed[key] = "b" * 64
            with self.subTest(key=key):
                with self.assertRaises(manifest.RetainedInstallManifestError):
                    manifest.verify_manifest_against_expected(data, changed)

    def test_open_duplicate_and_noncanonical_json_are_rejected(self) -> None:
        data = manifest.build_manifest(self.bindings)
        value = json.loads(data)
        value["extra"] = True
        with self.assertRaises(manifest.RetainedInstallManifestError):
            manifest.verify_manifest_bytes(manifest.canonical_json_bytes(value))

        duplicate = b'{"schema":"x","schema":"y"}\n'
        with self.assertRaises(manifest.RetainedInstallManifestError):
            manifest.verify_manifest_bytes(duplicate)

        compact = json.dumps(json.loads(data), sort_keys=True, separators=(",", ":")).encode()
        with self.assertRaises(manifest.RetainedInstallManifestError):
            manifest.verify_manifest_bytes(compact)

    def test_malformed_identity_and_zero_digest_are_rejected(self) -> None:
        for key, value in (
            ("sourceCommitSHA", "A" * 40),
            ("buildInstanceID", "12345678-1234-1abc-8def-123456789abc"),
            ("signedInstallableSHA256", "0" * 64),
            ("authorizationEnvelopeSHA256", "A" * 64),
        ):
            changed = dict(self.bindings)
            changed[key] = value
            with self.subTest(key=key):
                with self.assertRaises(manifest.RetainedInstallManifestError):
                    manifest.build_manifest(changed)

    def test_cli_validation_never_reports_install_or_physical_authority(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / "manifest.json"
            path.write_bytes(manifest.build_manifest(self.bindings))
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--validate", str(path)],
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertEqual(
            result.stdout.strip(),
            "VALID_NOT_INSTALL_AUTHORITY: retained-install manifest structure",
        )
        self.assertNotIn("physical", result.stdout.lower())
        self.assertNotIn(" go", result.stdout.lower())

    def test_source_has_no_device_install_network_or_signing_primitive(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        for forbidden in (
            "devicectl",
            "xcodebuild",
            "SecItem",
            "CoreBluetooth",
            "writeValue",
            "subprocess.",
            "urllib",
            "requests.",
            "openssl",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
