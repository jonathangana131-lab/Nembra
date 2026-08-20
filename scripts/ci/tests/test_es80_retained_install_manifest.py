import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_retained_install_manifest.py"
PACKAGE_VERIFIER = (
    Path(__file__).resolve().parents[3]
    / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture"
    / "AuthenticatedStationaryCaptureInstallManifest.swift"
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
            "bundleIdentifier": "com.jonathangana131.nembra.capturelearn",
            "buildIdentifier": "Capture Build test",
            "buildInstanceID": "12345678-1234-abcd-8def-123456789abc",
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

    def test_round_trip_is_closed_compact_and_explicitly_nonauthorizing(self) -> None:
        data = manifest.build_manifest(self.bindings)
        value = manifest.verify_manifest_against_expected(data, self.bindings)
        self.assertEqual(value["schema"], manifest.SCHEMA)
        self.assertEqual(data, manifest.canonical_json_bytes(json.loads(data)))
        self.assertNotIn(b"\n", data)
        self.assertNotIn(b'"decision"', data)
        self.assertNotIn(b'"GO"', data)
        self.assertNotIn(b'"manifestKind"', data)

    def test_python_wire_contract_matches_package_verifier_source(self) -> None:
        if not PACKAGE_VERIFIER.exists():
            self.skipTest("package source requires a repository checkout")
        source = PACKAGE_VERIFIER.read_text(encoding="utf-8")
        self.assertIn(f'public static let schema = "{manifest.SCHEMA}"', source)
        self.assertIn(
            f"public static let maximumManifestByteCount = {manifest.MAX_MANIFEST_BYTES:,}".replace(",", "_"),
            source,
        )
        for key in ("retainedIPASHA256", *manifest.DIGEST_KEYS[1:]):
            self.assertIn(f'"{key}"', source)
        self.assertNotIn('"signedInstallableSHA256"', source)

    def test_every_exact_binding_drift_is_rejected(self) -> None:
        data = manifest.build_manifest(self.bindings)
        for key in manifest.BINDING_KEYS:
            changed = dict(self.bindings)
            if key == "procedureID":
                changed[key] = "wrong-procedure"
            elif key == "sourceCommitSHA":
                changed[key] = "b" * 40
            elif key == "bundleIdentifier":
                changed[key] = "com.example.wrong"
            elif key == "buildIdentifier":
                changed[key] = "Other Build"
            elif key == "buildInstanceID":
                changed[key] = "87654321-4321-abcd-8def-123456789abc"
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

        duplicate = b'{"schema":"x","schema":"y"}'
        with self.assertRaises(manifest.RetainedInstallManifestError):
            manifest.verify_manifest_bytes(duplicate)

        pretty = json.dumps(json.loads(data), sort_keys=True, indent=2).encode()
        with self.assertRaises(manifest.RetainedInstallManifestError):
            manifest.verify_manifest_bytes(pretty)

        with self.assertRaises(manifest.RetainedInstallManifestError):
            manifest.verify_manifest_bytes(data + b"\n")

    def test_malformed_identity_is_rejected_but_wire_does_not_invent_stricter_semantics(self) -> None:
        for key, value in (
            ("sourceCommitSHA", "A" * 40),
            ("buildInstanceID", "12345678-1234-zzzz-8def-123456789abc"),
            ("retainedIPASHA256", "A" * 64),
            ("authorizationEnvelopeSHA256", "A" * 64),
            ("bundleIdentifier", "com.example bad"),
        ):
            changed = dict(self.bindings)
            changed[key] = value
            with self.subTest(key=key):
                with self.assertRaises(manifest.RetainedInstallManifestError):
                    manifest.build_manifest(changed)

        zero_digest = dict(self.bindings)
        zero_digest["retainedIPASHA256"] = "0" * 64
        manifest.verify_manifest_bytes(manifest.build_manifest(zero_digest))

        generic_instance = dict(self.bindings)
        generic_instance["buildInstanceID"] = "12345678-90ab-cdef-1234-567890abcdef"
        manifest.verify_manifest_bytes(manifest.build_manifest(generic_instance))

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
