#!/usr/bin/env python3
import importlib.util
import inspect
from pathlib import Path
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_hardened.py"
spec = importlib.util.spec_from_file_location("hardened_signed_reinspection", MODULE_PATH)
hardened = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(hardened)


class FinalGoSignedReinspectionCompositionTests(unittest.TestCase):
    def candidate(self):
        return {
            "signedArtifactInspectionSHA256": "1" * 64,
            "retainedIPASHA256": "2" * 64,
            "retainedIPAByteCount": 123456,
            "executableSHA256": "3" * 64,
            "infoPlistSHA256": "4" * 64,
            "teamIdentifier": "ABCDEFGHIJ",
            "provisioningProfileSHA256": "5" * 64,
            "provisioningProfileUUID": "profile-uuid",
            "provisioningProfileExpirationUTC": "2026-12-31T23:59:59Z",
            "codeDirectoryHash": "6" * 40,
        }

    def fresh(self):
        candidate = self.candidate()
        return {
            "authority": hardened.signed_candidate_reinspection.REINSPECTION_AUTHORITY,
            "inspectionRecordSHA256": candidate["signedArtifactInspectionSHA256"],
            "signedInstallableSHA256": candidate["retainedIPASHA256"],
            "ipaByteCount": candidate["retainedIPAByteCount"],
            "bundleIdentifier": hardened.foundation.BUNDLE_ID,
            "platformName": "iphoneos",
            "supportedPlatforms": ["iPhoneOS"],
            "teamIdentifier": candidate["teamIdentifier"],
            "signingAuthorities": ["Apple Development: Nembra"],
            "codeDirectoryHash": candidate["codeDirectoryHash"],
            "provisioningProfileSHA256": candidate["provisioningProfileSHA256"],
            "provisioningProfileUUID": candidate["provisioningProfileUUID"],
            "provisioningProfileExpirationUTC": candidate["provisioningProfileExpirationUTC"],
            "provisioningApplicationIdentifier": (
                f"{candidate['teamIdentifier']}.{hardened.foundation.BUNDLE_ID}"
            ),
            "executableSHA256": candidate["executableSHA256"],
            "infoPlistSHA256": candidate["infoPlistSHA256"],
        }

    def test_matching_independent_native_facts_crossbind(self):
        hardened._require_fresh_signed_candidate_match(self.candidate(), self.fresh())

    def test_rejects_any_promoted_candidate_fact_divergence(self):
        bindings = {
            "inspectionRecordSHA256": "signedArtifactInspectionSHA256",
            "signedInstallableSHA256": "retainedIPASHA256",
            "ipaByteCount": "retainedIPAByteCount",
            "executableSHA256": "executableSHA256",
            "infoPlistSHA256": "infoPlistSHA256",
            "teamIdentifier": "teamIdentifier",
            "provisioningProfileSHA256": "provisioningProfileSHA256",
            "provisioningProfileUUID": "provisioningProfileUUID",
            "provisioningProfileExpirationUTC": "provisioningProfileExpirationUTC",
            "codeDirectoryHash": "codeDirectoryHash",
        }
        for fresh_key in bindings:
            with self.subTest(fresh_key=fresh_key):
                fresh = self.fresh()
                fresh[fresh_key] = 0 if fresh_key == "ipaByteCount" else "diverged"
                with self.assertRaisesRegex(
                    hardened.FinalGoError,
                    f"fresh signed-candidate reinspection diverged from foundation subject: {fresh_key}",
                ):
                    hardened._require_fresh_signed_candidate_match(self.candidate(), fresh)

    def test_rejects_non_native_or_non_device_authority(self):
        cases = {
            "authority": "caller-authored-signing-json",
            "bundleIdentifier": "com.example.not-nembra",
            "platformName": "iphonesimulator",
            "supportedPlatforms": ["iPhoneSimulator"],
            "provisioningApplicationIdentifier": "ABCDEFGHIJ.com.example.not-nembra",
            "signingAuthorities": [],
        }
        for key, value in cases.items():
            with self.subTest(key=key):
                fresh = self.fresh()
                fresh[key] = value
                with self.assertRaises(hardened.FinalGoError):
                    hardened._require_fresh_signed_candidate_match(self.candidate(), fresh)

    def test_authority_builder_mechanically_consumes_native_reinspection_and_fails_on_bypass(self):
        source = inspect.getsource(hardened.build_final_go_record)
        self.assertIn(
            "signed_candidate_reinspection.verify_signed_candidate_reinspection(",
            source,
        )
        self.assertIn("foundation._candidate_subject = signed_candidate_adapter", source)
        self.assertIn("foundation._candidate_subject = original_candidate_subject", source)
        self.assertIn("if fresh_reinspection is None:", source)
        self.assertIn(
            'raise FinalGoError("hardened Final GO did not consume fresh signed-candidate reinspection")',
            source,
        )


if __name__ == "__main__":
    unittest.main()
