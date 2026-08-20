import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_retained_install_cross_binding.py"
SPEC = importlib.util.spec_from_file_location("retained_install_cross_binding", SCRIPT)
assert SPEC and SPEC.loader
cross = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cross)


def pretty(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8") + b"\n"


class RetainedInstallCrossBindingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = "1" * 40
        self.build = f"Capture Build V14-{self.source[:12]}"
        self.instance = "12345678-1234-4abc-8def-123456789abc"
        self.exe = "2" * 64
        self.info = "3" * 64
        self.ipa = "4" * 64
        self.tuya = "5" * 64
        self.pseudonym = "6" * 64
        common = {
            "schemaVersion": cross.SUBJECT_SCHEMA_VERSION,
            "procedureID": cross.manifest_contract.PROCEDURE_ID,
            "bundleIdentifier": cross.manifest_contract.BUNDLE_IDENTIFIER,
            "sourceCommitSHA": self.source,
            "buildIdentifier": self.build,
            "buildInstanceID": self.instance,
            "executableSHA256": self.exe,
            "infoPlistSHA256": self.info,
            "tuyaDependencyLockSHA256": self.tuya,
        }

        self.external = pretty(common)
        self.external_sha = cross.sha256_hex(self.external)

        self.final_go = pretty({
            **common,
            "decision": "GO",
            "signedInstallableSHA256": self.ipa,
            "intendedDevicePseudonymSHA256": self.pseudonym,
        })
        self.final_go_sha = cross.sha256_hex(self.final_go)

        self.evidence = pretty({
            **common,
            "evidenceKind": cross.EVIDENCE_KIND,
            "signedInstallableKind": cross.SIGNED_INSTALLABLE_KIND,
            "signedInstallableSHA256": self.ipa,
            "externalBuildRecordSHA256": self.external_sha,
            "finalGORecordSHA256": self.final_go_sha,
            "intendedDevicePseudonymSHA256": self.pseudonym,
        })
        self.evidence_sha = cross.sha256_hex(self.evidence)

        self.manifest = cross.manifest_contract.build_manifest({
            "procedureID": cross.manifest_contract.PROCEDURE_ID,
            "sourceCommitSHA": self.source,
            "bundleIdentifier": cross.manifest_contract.BUNDLE_IDENTIFIER,
            "buildIdentifier": self.build,
            "buildInstanceID": self.instance,
            "retainedIPASHA256": self.ipa,
            "executableSHA256": self.exe,
            "infoPlistSHA256": self.info,
            "tuyaDependencyLockSHA256": self.tuya,
            "externalBuildRecordSHA256": self.external_sha,
            "signedBuildEvidenceSHA256": self.evidence_sha,
            "finalGORecordSHA256": self.final_go_sha,
            "intendedDevicePseudonymSHA256": self.pseudonym,
        })
        self.manifest_sha = cross.sha256_hex(self.manifest)

    def verify(self, **overrides):
        args = {
            "install_manifest_data": self.manifest,
            "external_build_record_data": self.external,
            "signed_build_evidence_data": self.evidence,
            "final_go_record_data": self.final_go,
            "accepted_install_manifest_sha256": self.manifest_sha,
            "accepted_retained_ipa_sha256": self.ipa,
            "accepted_external_build_record_sha256": self.external_sha,
            "accepted_signed_build_evidence_sha256": self.evidence_sha,
            "accepted_final_go_record_sha256": self.final_go_sha,
            "accepted_tuya_lock_sha256": self.tuya,
            "accepted_intended_device_pseudonym_sha256": self.pseudonym,
        }
        args.update(overrides)
        return cross.verify_cross_binding(**args)

    def test_exact_stable_subjects_cross_bind_without_authority(self) -> None:
        value = self.verify()
        self.assertEqual(value["retainedIPASHA256"], self.ipa)
        source = SCRIPT.read_text(encoding="utf-8")
        for forbidden in (
            "devicectl", "xcodebuild", "CoreBluetooth", "writeValue",
            "publicKeyX963Representation", "authorizationEnvelopeSHA256",
        ):
            self.assertNotIn(forbidden, source)

    def test_independently_accepted_digest_drift_fails_closed(self) -> None:
        for key in (
            "accepted_install_manifest_sha256",
            "accepted_retained_ipa_sha256",
            "accepted_external_build_record_sha256",
            "accepted_signed_build_evidence_sha256",
            "accepted_final_go_record_sha256",
            "accepted_tuya_lock_sha256",
            "accepted_intended_device_pseudonym_sha256",
        ):
            with self.subTest(key=key):
                with self.assertRaises(cross.RetainedInstallCrossBindingError):
                    self.verify(**{key: "a" * 64})

    def test_external_build_tuple_drift_fails_closed(self) -> None:
        value = json.loads(self.external)
        value["executableSHA256"] = "a" * 64
        drifted = pretty(value)
        with self.assertRaises(cross.RetainedInstallCrossBindingError):
            self.verify(
                external_build_record_data=drifted,
                accepted_external_build_record_sha256=cross.sha256_hex(drifted),
            )

    def test_signed_evidence_drift_fails_closed_even_when_its_digest_is_reaccepted(self) -> None:
        value = json.loads(self.evidence)
        value["signedInstallableSHA256"] = "a" * 64
        drifted = pretty(value)
        with self.assertRaises(cross.RetainedInstallCrossBindingError):
            self.verify(
                signed_build_evidence_data=drifted,
                accepted_signed_build_evidence_sha256=cross.sha256_hex(drifted),
            )

    def test_final_go_must_stay_go_and_exact_subject_bound(self) -> None:
        value = json.loads(self.final_go)
        value["decision"] = "NO-GO"
        drifted = pretty(value)
        with self.assertRaises(cross.RetainedInstallCrossBindingError):
            self.verify(
                final_go_record_data=drifted,
                accepted_final_go_record_sha256=cross.sha256_hex(drifted),
            )

    def test_noncanonical_subject_json_fails_closed(self) -> None:
        with self.assertRaises(cross.RetainedInstallCrossBindingError):
            self.verify(external_build_record_data=self.external.rstrip(b"\n"))

    def test_external_subject_is_the_signed_field_evidence_common_schema(self) -> None:
        self.assertEqual(set(json.loads(self.external)), cross.EXTERNAL_KEYS)
        self.assertNotIn("experimentRecipeID", cross.EXTERNAL_KEYS)
        self.assertNotIn("procedureVersion", cross.EXTERNAL_KEYS)

    def test_path_cross_binding_keeps_digest_and_semantics_on_one_descriptor_read(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name).resolve()
            os.chmod(root, 0o700)
            manifest_path = root / "manifest.json"
            external_path = root / "external.json"
            evidence_path = root / "evidence.json"
            final_path = root / "final-go.json"
            for path, data, mode in (
                (manifest_path, self.manifest, 0o600),
                (external_path, self.external, 0o644),
                (evidence_path, self.evidence, 0o644),
                (final_path, self.final_go, 0o600),
            ):
                path.write_bytes(data)
                os.chmod(path, mode)

            value = cross.verify_cross_binding_paths(
                install_manifest_path=manifest_path,
                external_build_record_path=external_path,
                signed_build_evidence_path=evidence_path,
                final_go_record_path=final_path,
                accepted_install_manifest_sha256=self.manifest_sha,
                accepted_retained_ipa_sha256=self.ipa,
                accepted_external_build_record_sha256=self.external_sha,
                accepted_signed_build_evidence_sha256=self.evidence_sha,
                accepted_final_go_record_sha256=self.final_go_sha,
                accepted_tuya_lock_sha256=self.tuya,
                accepted_intended_device_pseudonym_sha256=self.pseudonym,
            )
            self.assertEqual(value["sourceCommitSHA"], self.source)

            symlink = root / "external-symlink.json"
            symlink.symlink_to(external_path)
            with self.assertRaises(cross.RetainedInstallCrossBindingError):
                cross.verify_cross_binding_paths(
                    install_manifest_path=manifest_path,
                    external_build_record_path=symlink,
                    signed_build_evidence_path=evidence_path,
                    final_go_record_path=final_path,
                    accepted_install_manifest_sha256=self.manifest_sha,
                    accepted_retained_ipa_sha256=self.ipa,
                    accepted_external_build_record_sha256=self.external_sha,
                    accepted_signed_build_evidence_sha256=self.evidence_sha,
                    accepted_final_go_record_sha256=self.final_go_sha,
                    accepted_tuya_lock_sha256=self.tuya,
                    accepted_intended_device_pseudonym_sha256=self.pseudonym,
                )

            with self.assertRaisesRegex(
                cross.RetainedInstallCrossBindingError,
                "independently accepted external build record digest mismatch",
            ):
                cross._read_exact_subject(
                    external_path,
                    "a" * 64,
                    label="external build record",
                    access_policy="public",
                    maximum_bytes=cross.MAX_JSON_BYTES,
                )

            os.chmod(final_path, 0o644)
            with self.assertRaisesRegex(
                cross.RetainedInstallCrossBindingError,
                "permissions are too broad",
            ):
                cross._read_exact_subject(
                    final_path,
                    self.final_go_sha,
                    label="Final-GO record",
                    access_policy="private",
                    maximum_bytes=cross.MAX_JSON_BYTES,
                )


if __name__ == "__main__":
    unittest.main()
