import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_retained_install_manifest.py"
CROSS_BINDING_TEST = Path(__file__).resolve().with_name(
    "test_es80_retained_install_cross_binding.py"
)
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
        self.source_sha = "1" * 40
        self.bindings = {
            "procedureID": manifest.PROCEDURE_ID,
            "sourceCommitSHA": self.source_sha,
            "bundleIdentifier": manifest.BUNDLE_IDENTIFIER,
            "buildIdentifier": f"Capture Build V14-{self.source_sha[:12]}",
            # Runtime build identity treats this as an opaque UUID-shaped rendezvous value.
            "buildInstanceID": "12345678-90ab-cdef-1234-567890abcdef",
            "retainedIPASHA256": "2" * 64,
            "executableSHA256": "3" * 64,
            "infoPlistSHA256": "4" * 64,
            "tuyaDependencyLockSHA256": "5" * 64,
            "externalBuildRecordSHA256": "6" * 64,
            "signedBuildEvidenceSHA256": "7" * 64,
            "finalGORecordSHA256": "8" * 64,
            "intendedDevicePseudonymSHA256": "9" * 64,
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
        self.assertNotIn(b'"authorizationEnvelopeSHA256"', data)

    def test_python_contract_pins_package_owned_semantics(self) -> None:
        if not PACKAGE_VERIFIER.exists():
            self.skipTest("package source requires a repository checkout")
        source = PACKAGE_VERIFIER.read_text(encoding="utf-8")
        self.assertIn(f'public static let schema = "{manifest.SCHEMA}"', source)
        self.assertIn(
            f'public static let bundleIdentifier = "{manifest.BUNDLE_IDENTIFIER}"', source
        )
        self.assertIn(
            f"public static let maximumManifestByteCount = {manifest.MAX_MANIFEST_BYTES:,}".replace(",", "_"),
            source,
        )
        self.assertIn('let expectedBuildIdentifier = "Capture Build V14-', source)
        self.assertIn('("retainedIPASHA256", wire.retainedIPASHA256)', source)
        self.assertIn('wire.sourceCommitSHA != String(repeating: "0", count: 40)', source)
        self.assertIn('value != String(repeating: "0", count: 64)', source)
        self.assertIn("normalizedBuildInstanceID(wire.buildInstanceID) == wire.buildInstanceID", source)
        self.assertNotIn("bytes[14] == 0x34", source)
        self.assertNotIn('"signedInstallableSHA256"', source)
        self.assertNotIn("authorizationEnvelopeSHA256", source)

    def test_future_attempt_envelope_is_not_a_preinstall_binding(self) -> None:
        self.assertNotIn("authorizationEnvelopeSHA256", manifest.BINDING_KEYS)
        self.assertNotIn("authorizationEnvelopeSHA256", manifest.DIGEST_KEYS)
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("fresh process-local challenge", source)
        self.assertNotIn('"authorizationEnvelopeSHA256",', source)

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
                changed[key] = "Capture Build V14-deadbeefdead"
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

    def test_package_owned_semantic_restrictions_are_mirrored(self) -> None:
        cases = (
            ("sourceCommitSHA", "0" * 40),
            ("sourceCommitSHA", "A" * 40),
            ("bundleIdentifier", "com.example.wrong"),
            ("buildIdentifier", "Capture Build test"),
            ("buildInstanceID", "12345678-1234-zzzz-8def-123456789abc"),
            ("buildInstanceID", "12345678-1234-abcd-8def-123456789ab"),
            ("retainedIPASHA256", "0" * 64),
            ("retainedIPASHA256", "A" * 64),
        )
        for key, value in cases:
            changed = dict(self.bindings)
            changed[key] = value
            with self.subTest(key=key, value=value):
                with self.assertRaises(manifest.RetainedInstallManifestError):
                    manifest.build_manifest(changed)

    def test_build_instance_is_opaque_uuid_shaped_not_uuid_version_authority(self) -> None:
        generic = dict(self.bindings)
        generic["buildInstanceID"] = "12345678-1234-abcd-1def-123456789abc"
        value = manifest.verify_manifest_bytes(manifest.build_manifest(generic))
        self.assertEqual(value["buildInstanceID"], generic["buildInstanceID"])

    def test_manifest_reader_rejects_symlinked_or_multi_link_paths(self) -> None:
        data = manifest.build_manifest(self.bindings)
        with tempfile.TemporaryDirectory() as name:
            root = Path(name).resolve()
            real_dir = root / "real"
            real_dir.mkdir()
            subject = real_dir / "manifest.json"
            subject.write_bytes(data)

            final_symlink = root / "final-symlink.json"
            final_symlink.symlink_to(subject)
            with self.assertRaises(manifest.RetainedInstallManifestError):
                manifest._read_manifest(final_symlink)

            parent_symlink = root / "parent-symlink"
            parent_symlink.symlink_to(real_dir, target_is_directory=True)
            with self.assertRaises(manifest.RetainedInstallManifestError):
                manifest._read_manifest(parent_symlink / "manifest.json")

            hard_link = root / "hard-link.json"
            os.link(subject, hard_link)
            with self.assertRaises(manifest.RetainedInstallManifestError):
                manifest._read_manifest(hard_link)

            with self.assertRaises(manifest.RetainedInstallManifestError):
                manifest._read_manifest(Path("relative-manifest.json"))

    def test_cli_validation_never_reports_install_or_physical_authority(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            path = Path(name).resolve() / "manifest.json"
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

    def test_cross_binding_suite_is_part_of_required_manifest_validation(self) -> None:
        result = subprocess.run(
            [sys.executable, "-I", str(CROSS_BINDING_TEST)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            result.returncode,
            0,
            msg=f"cross-binding suite failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )

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
