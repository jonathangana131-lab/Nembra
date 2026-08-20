#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_install_manifest.py"
SPEC = importlib.util.spec_from_file_location("install_manifest", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
install_manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(install_manifest)


class InstallManifestContractTests(unittest.TestCase):
    source_sha = "a" * 40

    def make_fixture(self, root: Path) -> tuple[Path, Path, dict[str, object]]:
        ipa = root / "NembraField.ipa"
        ipa.write_bytes(b"retained-signed-ipa-fixture\n")
        ipa_sha = hashlib.sha256(ipa.read_bytes()).hexdigest()
        payload = install_manifest._fixture_manifest(
            source_sha=self.source_sha,
            ipa_sha256=ipa_sha,
        )
        manifest = root / "install-manifest.json"
        manifest.write_bytes(install_manifest._canonical_json_bytes(payload))
        return manifest, ipa, payload

    def test_valid_manifest_is_non_authorizing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            manifest, ipa, _ = self.make_fixture(Path(temporary))
            result = install_manifest.validate_manifest(
                manifest,
                ipa,
                expected_source_sha=self.source_sha,
            )
            self.assertEqual(result["status"], "VALID_RETAINED_IPA_MANIFEST")
            self.assertEqual(
                result["authority"],
                "retained-signed-ipa-install-manifest-not-physical-authorization",
            )
            self.assertEqual(result["physicalExperimentAuthorization"], "not-granted")

    def test_manifest_is_closed_against_extra_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest, ipa, payload = self.make_fixture(root)
            payload["permitsPhysicalProcedure"] = True
            manifest.write_bytes(install_manifest._canonical_json_bytes(payload))
            with self.assertRaises(install_manifest.InstallManifestError):
                install_manifest.validate_manifest(
                    manifest,
                    ipa,
                    expected_source_sha=self.source_sha,
                )

    def test_duplicate_json_key_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = root / "duplicate.json"
            manifest.write_text('{"schemaVersion":1,"schemaVersion":1}\n', encoding="utf-8")
            with self.assertRaises(install_manifest.InstallManifestError):
                install_manifest.load_manifest(manifest)

    def test_noncanonical_json_bytes_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest, ipa, payload = self.make_fixture(root)
            manifest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
            with self.assertRaises(install_manifest.InstallManifestError):
                install_manifest.validate_manifest(
                    manifest,
                    ipa,
                    expected_source_sha=self.source_sha,
                )

    def test_tampered_ipa_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            manifest, ipa, _ = self.make_fixture(Path(temporary))
            ipa.write_bytes(b"different-retained-ipa\n")
            with self.assertRaises(install_manifest.InstallManifestError):
                install_manifest.validate_manifest(
                    manifest,
                    ipa,
                    expected_source_sha=self.source_sha,
                )

    def test_wrong_source_or_build_label_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest, ipa, payload = self.make_fixture(root)
            payload["buildIdentifier"] = "Capture Build V14-deadbeefdead"
            manifest.write_bytes(install_manifest._canonical_json_bytes(payload))
            with self.assertRaises(install_manifest.InstallManifestError):
                install_manifest.validate_manifest(
                    manifest,
                    ipa,
                    expected_source_sha=self.source_sha,
                )

            manifest.write_bytes(
                install_manifest._canonical_json_bytes(
                    install_manifest._fixture_manifest(
                        source_sha=self.source_sha,
                        ipa_sha256=hashlib.sha256(ipa.read_bytes()).hexdigest(),
                    )
                )
            )
            with self.assertRaises(install_manifest.InstallManifestError):
                install_manifest.validate_manifest(
                    manifest,
                    ipa,
                    expected_source_sha="3" * 40,
                )

    def test_symlinked_manifest_or_ipa_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest, ipa, _ = self.make_fixture(root)
            manifest_link = root / "manifest-link.json"
            ipa_link = root / "ipa-link.ipa"
            manifest_link.symlink_to(manifest)
            ipa_link.symlink_to(ipa)

            with self.assertRaises(install_manifest.InstallManifestError):
                install_manifest.validate_manifest(
                    manifest_link,
                    ipa,
                    expected_source_sha=self.source_sha,
                )
            with self.assertRaises(install_manifest.InstallManifestError):
                install_manifest.validate_manifest(
                    manifest,
                    ipa_link,
                    expected_source_sha=self.source_sha,
                )


if __name__ == "__main__":
    unittest.main()
