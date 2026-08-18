#!/usr/bin/env python3
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class CaptureFieldStrictAcceptedRootWiringTests(unittest.TestCase):
    def test_review_only_bootstrap_emits_both_preacceptance_subjects(self):
        source = (ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh").read_text()
        self.assertIn("Generated/private compiler-input manifest SHA-256: $GENERATED_MANIFEST_SHA256", source)
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_GENERATED_MANIFEST_SHA256", source)
        self.assertIn('[[ "$GENERATED_MANIFEST_SHA256" == "$ACCEPTED_GENERATED_MANIFEST_SHA256" ]]', source)
        self.assertIn('"$ACCEPTED_BUILD_INPUT_HELPER" manifest', source)
        self.assertIn("This review-only mode never", source)

    def test_field_installer_requires_and_transports_preaccepted_manifest(self):
        source = (ROOT / "scripts/field/install_one_time_capture.command").read_text()
        self.assertIn("Final GO must provide NEMBRA_CAPTURE_ACCEPTED_GENERATED_MANIFEST_SHA256", source)
        self.assertIn('--accepted-generated-manifest-sha256 "$NEMBRA_CAPTURE_ACCEPTED_GENERATED_MANIFEST_SHA256"', source)
        self.assertNotIn("capture_accepted_build_input_snapshot.py manifest", source)

    def test_orchestrator_uses_digest_to_make_strict_root_and_native_lease(self):
        source = (ROOT / "scripts/ci/capture_selected_xcode_build_orchestrator.py").read_text()
        self.assertIn("if accepted_generated_manifest_sha256 is not None:", source)
        self.assertIn("private_subjects = (accepted_root,)", source)
        self.assertIn("use_native_darwin_acl=(accepted_root is not None)", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
