#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"
spec = importlib.util.spec_from_file_location('final_go', MODULE_PATH)
final_go = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(final_go)


class FinalGoRecordTests(unittest.TestCase):
    SOURCE = 'a' * 40
    BUILD = 'Capture Build V14-' + SOURCE[:12]
    INSTANCE = '11111111-2222-3333-4444-555555555555'
    EXEC = 'b' * 64
    PLIST = 'c' * 64
    TEAM = 'ABCDE12345'

    def make_candidate(self, root: Path):
        inspection = root / 'inspection'
        evidence = inspection / 'build-evidence'
        evidence.mkdir(parents=True)
        ipa = b'exact-retained-ipa'
        (evidence / 'NembraField.ipa').write_bytes(ipa)
        ipa_sha = hashlib.sha256(ipa).hexdigest()
        external = {
            'schemaVersion': 3,
            'buildIdentifier': self.BUILD,
            'buildInstanceID': self.INSTANCE,
            'sourceCommitSHA': self.SOURCE,
            'executableSHA256': self.EXEC,
            'infoPlistSHA256': self.PLIST,
            'experimentRecipeID': final_go.RECIPE,
            'procedureVersion': final_go.PROCEDURE,
        }
        external_raw = (json.dumps(external, sort_keys=True) + '\n').encode()
        (inspection / final_go.EXTERNAL_RECORD_NAME).write_bytes(external_raw)
        external_sha = hashlib.sha256(external_raw).hexdigest()
        field = {
            'schemaVersion': 1,
            'externalBuildRecordSHA256': external_sha,
            'signedInstallableSHA256': ipa_sha,
            'signedInstallableKind': 'ipa',
            'buildIdentifier': self.BUILD,
            'buildInstanceID': self.INSTANCE,
            'sourceCommitSHA': self.SOURCE,
            'executableSHA256': self.EXEC,
            'infoPlistSHA256': self.PLIST,
            'experimentRecipeID': final_go.RECIPE,
            'procedureVersion': final_go.PROCEDURE,
        }
        field_raw = (json.dumps(field, sort_keys=True) + '\n').encode()
        (inspection / final_go.FIELD_RECORD_NAME).write_bytes(field_raw)
        field_sha = hashlib.sha256(field_raw).hexdigest()
        signed = {
            'schemaVersion': 2,
            'authority': 'signed-field-artifact-inspection-not-field-authorization',
            'fieldBuildEvidenceRecordSHA256': field_sha,
            'externalBuildRecordSHA256': external_sha,
            'signedInstallableSHA256': ipa_sha,
            'signedInstallableKind': 'ipa',
            'buildIdentifier': self.BUILD,
            'buildInstanceID': self.INSTANCE,
            'sourceCommitSHA': self.SOURCE,
            'executableSHA256': self.EXEC,
            'infoPlistSHA256': self.PLIST,
            'experimentRecipeID': final_go.RECIPE,
            'procedureVersion': final_go.PROCEDURE,
            'bundleIdentifier': final_go.BUNDLE_ID,
            'platformName': 'iphoneos',
            'supportedPlatforms': ['iPhoneOS'],
            'teamIdentifier': self.TEAM,
            'provisioningApplicationIdentifier': f'{self.TEAM}.{final_go.BUNDLE_ID}',
            'provisioningProfileSHA256': 'e' * 64,
            'provisioningProfileUUID': 'PROFILE-UUID',
            'provisioningProfileExpirationUTC': '2027-08-09T00:00:00Z',
            'signingAuthorities': ['Apple Development: Nembra'],
        }
        (inspection / final_go.INSPECTION_NAME).write_text(json.dumps(signed), encoding='utf-8')
        return ipa_sha

    def kwargs(self, root: Path, ipa_sha: str):
        return dict(
            candidate_root=root,
            expected_source_sha=self.SOURCE,
            installed_ipa_sha256=ipa_sha,
            expected_development_team=self.TEAM,
            visible_recipe=final_go.RECIPE,
            visible_build_identifier=self.BUILD,
            visible_source_sha=self.SOURCE,
            visible_build_instance_id=self.INSTANCE,
            installed_without_rebuild=True,
            terminal_software_acceptance=True,
            retained_app_evidence_inspected=True,
            intended_device_membership_accepted=True,
            no_application_write_authority=True,
            observed_device=final_go.BASELINE_DEVICE,
            observed_os=final_go.BASELINE_OS,
            research_admission_live=True,
            canonical_coordinator_permitted=True,
            preflight_healthy=True,
            charger_disconnected=True,
            stationary=True,
        )

    def test_emits_go_only_for_exact_candidate_and_runtime_rendezvous(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            record = final_go.build_final_go_record(**self.kwargs(root, ipa_sha))
            self.assertEqual(record['decision'], 'GO')
            self.assertEqual(record['acceptedSourceCommitSHA'], self.SOURCE)
            self.assertEqual(record['retainedIPASHA256'], ipa_sha)
            self.assertEqual(record['experimentRecipeID'], final_go.RECIPE)
            self.assertEqual(record['procedureVersion'], 'V14')
            self.assertFalse(record['physicalResultCollected'])

    def test_rejects_installed_ipa_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values['installed_ipa_sha256'] = 'd' * 64
            with self.assertRaisesRegex(final_go.FinalGoError, 'installed IPA digest mismatch'):
                final_go.build_final_go_record(**values)

    def test_rejects_visible_build_instance_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values['visible_build_instance_id'] = '99999999-2222-3333-4444-555555555555'
            with self.assertRaisesRegex(final_go.FinalGoError, 'visible pre-scan build-instance ID mismatch'):
                final_go.build_final_go_record(**values)

    def test_rejects_false_preflight_confirmation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values['charger_disconnected'] = False
            with self.assertRaisesRegex(final_go.FinalGoError, 'chargerFreshlyDeclaredDisconnected'):
                final_go.build_final_go_record(**values)

    def test_rejects_mutated_external_record_after_field_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            path = root / 'inspection' / final_go.EXTERNAL_RECORD_NAME
            external = json.loads(path.read_text())
            external['schemaVersion'] = 4
            path.write_text(json.dumps(external), encoding='utf-8')
            with self.assertRaisesRegex(final_go.FinalGoError, 'external schema version mismatch'):
                final_go.build_final_go_record(**self.kwargs(root, ipa_sha))

    def test_rejects_missing_terminal_software_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values['terminal_software_acceptance'] = False
            with self.assertRaisesRegex(final_go.FinalGoError, 'terminalSoftwareAcceptanceForExactSource'):
                final_go.build_final_go_record(**values)

    def test_rejects_wrong_baseline_device(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values['observed_device'] = 'iPhone 13'
            with self.assertRaisesRegex(final_go.FinalGoError, 'observed baseline device mismatch'):
                final_go.build_final_go_record(**values)

    def test_rejects_profile_expired_before_final_go(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            path = root / 'inspection' / final_go.INSPECTION_NAME
            inspection = json.loads(path.read_text())
            inspection['provisioningProfileExpirationUTC'] = '2020-01-01T00:00:00Z'
            path.write_text(json.dumps(inspection), encoding='utf-8')
            with self.assertRaisesRegex(final_go.FinalGoError, 'provisioning profile expired before Final GO'):
                final_go.build_final_go_record(**self.kwargs(root, ipa_sha))


if __name__ == '__main__':
    unittest.main()
