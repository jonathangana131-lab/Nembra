import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_retained_install_manifest.py"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SWIFT_MANIFEST = (
    REPOSITORY_ROOT
    / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/AuthenticatedStationaryCaptureInstallManifest.swift"
)
SPEC = importlib.util.spec_from_file_location("retained_install_manifest", SCRIPT)
assert SPEC and SPEC.loader
manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manifest)


class RetainedInstallManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bindings = {
            "procedureID": manifest.PROCEDURE_ID,
            "sourceCommitSHA": "1" * 40,
            "bundleIdentifier": manifest.BUNDLE_IDENTIFIER,
            "buildIdentifier": "Capture Build V14-111111111111",
            "buildInstanceID": "12345678-1234-4abc-8def-123456789abc",
            "retainedIPASHA256": "2" * 64,
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
        self.assertEqual(value["schema"], manifest.SCHEMA)
        self.assertEqual(value["version"], manifest.SCHEMA_VERSION)
        self.assertEqual(data, manifest.canonical_json_bytes(json.loads(data)))
        self.assertFalse(data.endswith(b"\n"))
        self.assertNotIn(b'"decision"', data)
        self.assertNotIn(b'"GO"', data)
        self.assertNotIn(b'"manifestKind"', data)

    def test_python_wire_contract_matches_swift_decoder_contract(self) -> None:
        source = SWIFT_MANIFEST.read_text(encoding="utf-8")
        self.assertIn(f'public static let schema = "{manifest.SCHEMA}"', source)
        self.assertIn(
            f'public static let bundleIdentifier = "{manifest.BUNDLE_IDENTIFIER}"', source
        )
        self.assertIn(
            f"public static let maximumManifestByteCount = {manifest.MAX_MANIFEST_BYTES // 1024}_384"
            if manifest.MAX_MANIFEST_BYTES == 16_384
            else f"public static let maximumManifestByteCount = {manifest.MAX_MANIFEST_BYTES}",
            source,
        )
        for key in manifest.MANIFEST_KEYS:
            with self.subTest(key=key):
                self.assertIn(f'"{key}"', source)
        self.assertNotIn('"manifestKind"', source)
        self.assertNotIn('"signedInstallableSHA256"', source)
        self.assertIn('"retainedIPASHA256"', source)
        self.assertIn("encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]", source)
        self.assertIn(
            'wire.sourceCommitSHA != String(repeating: "0", count: 40)', source
        )
        self.assertIn(
            "wire.buildIdentifier == canonicalBuildIdentifier(for: wire.sourceCommitSHA)",
            source,
        )
        self.assertIn("isCanonicalUUIDv4(wire.buildInstanceID)", source)
        self.assertIn("isCanonicalNonzeroSHA256", source)

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
                changed["buildIdentifier"] = "Capture Build V14-bbbbbbbbbbbb"
            elif key == "buildIdentifier":
                changed[key] = "Capture Build V14-222222222222"
            elif key == "buildInstanceID":
                changed[key] = "87654321-4321-4abc-8def-123456789abc"
            else:
                changed[key] = "b" * 64
            with self.subTest(key=key):
                with self.assertRaises(manifest.RetainedInstallManifestError):
                    manifest.verify_manifest_against_expected(data, changed)

    def test_build_identifier_is_cross_bound_to_exact_source(self) -> None:
        changed = dict(self.bindings)
        changed["buildIdentifier"] = "Capture Build V14-222222222222"
        with self.assertRaisesRegex(
            manifest.RetainedInstallManifestError,
            "buildIdentifier does not match exact source commit",
        ):
            manifest.build_manifest(changed)

    def test_open_duplicate_and_noncanonical_json_are_rejected(self) -> None:
        data = manifest.build_manifest(self.bindings)
        value = json.loads(data)
        value["extra"] = True
        with self.assertRaises(manifest.RetainedInstallManifestError):
            manifest.verify_manifest_bytes(manifest.canonical_json_bytes(value))

        duplicate = b'{"schema":"x","schema":"y"}'
        with self.assertRaises(manifest.RetainedInstallManifestError):
            manifest.verify_manifest_bytes(duplicate)

        pretty = (json.dumps(json.loads(data), indent=2, sort_keys=True) + "\n").encode()
        with self.assertRaises(manifest.RetainedInstallManifestError):
            manifest.verify_manifest_bytes(pretty)

        newline = data + b"\n"
        with self.assertRaises(manifest.RetainedInstallManifestError):
            manifest.verify_manifest_bytes(newline)

    def test_malformed_identity_and_zero_digest_are_rejected(self) -> None:
        for key, value in (
            ("sourceCommitSHA", "A" * 40),
            ("sourceCommitSHA", "0" * 40),
            ("buildInstanceID", "12345678-1234-1abc-8def-123456789abc"),
            ("buildInstanceID", "12345678-1234-4abc-7def-123456789abc"),
            ("retainedIPASHA256", "0" * 64),
            ("authorizationEnvelopeSHA256", "A" * 64),
        ):
            changed = dict(self.bindings)
            changed[key] = value
            if key == "sourceCommitSHA" and value == "0" * 40:
                changed["buildIdentifier"] = "Capture Build V14-000000000000"
            with self.subTest(key=key, value=value[:8]):
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
