#!/usr/bin/env python3
from pathlib import Path
import subprocess
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY_ROOT / "scripts/field/install_one_time_capture.command"


class RetainedInstallInstallerChronologyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = INSTALLER.read_text(encoding="utf-8")

    def test_shell_source_is_syntactically_valid(self) -> None:
        completed = subprocess.run(
            ["/bin/bash", "-n", str(INSTALLER)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_preinstall_contract_requires_canonical_manifest_and_stable_subjects(self) -> None:
        for required in (
            "NEMBRA_ACCEPTED_SOURCE_COMMIT_SHA",
            "NEMBRA_RETAINED_IPA_PATH",
            "NEMBRA_RETAINED_IPA_SHA256",
            "NEMBRA_RETAINED_INSTALL_MANIFEST_PATH",
            "NEMBRA_RETAINED_INSTALL_MANIFEST_SHA256",
            "NEMBRA_ACCEPTED_BUILD_SUBJECT_PATH",
            "NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_PATH",
            "NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_PATH",
            "NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT_PATH",
            "NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_PATH",
            "es80_retained_install_cross_binding.py",
            "verify_cross_binding(",
            "accepted_source_commit_sha=accepted_source_sha",
            "PREINSTALL_RETAINED_SUBJECTS_BOUND_NOT_INSTALL_AUTHORITY",
        ):
            with self.subTest(required=required):
                self.assertIn(required, self.source)

    def test_future_attempt_envelope_is_not_a_preinstall_input(self) -> None:
        for forbidden in (
            "NEMBRA_CURRENT_PROCEDURE_AUTHORIZATION_ENVELOPE_PATH",
            "NEMBRA_CURRENT_PROCEDURE_AUTHORIZATION_ENVELOPE_SHA256",
            "NEMBRA_FIELD_AUTHORIZATION_ENVELOPE_PATH",
            "NEMBRA_FIELD_AUTHORIZATION_ENVELOPE_SHA256",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, self.source)
        self.assertIn("fresh process-local challenge", self.source)
        self.assertIn("must be created only after the installed app emits its fresh challenge", self.source)

    def test_migration_has_no_device_or_install_execution_primitive(self) -> None:
        for forbidden in (
            "devicectl",
            "xcrun",
            "DEVICE_UDID",
            "install app",
            "bootstrap_capture_tuya_sdk",
            "capture_accepted_git_source_base64",
            "EXPECTED_SOURCE_SHA=",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, self.source)
        self.assertIn("No device was contacted and no app was installed", self.source)

    def test_legacy_unreachable_installer_tail_is_deleted(self) -> None:
        stop = self.source.rfind('die "Installation remains blocked:')
        self.assertGreater(stop, 0)
        tail = self.source[stop:]
        self.assertNotIn("git rev-parse", tail)
        self.assertNotIn("codesign", tail)
        self.assertNotIn("security cms", tail)
        self.assertNotIn("plutil", tail)
        self.assertNotIn("python3 -c", tail)
        self.assertTrue(self.source.rstrip().endswith('RETAINED_INSTALL_CONTRACT_STATUS"'))

    def test_retained_inputs_keep_no_follow_hash_mode_custody(self) -> None:
        self.assertIn('no_follow = getattr(os, "O_NOFOLLOW", None)', self.source)
        self.assertIn("stat.S_ISREG(before.st_mode)", self.source)
        self.assertIn("before.st_nlink != 1", self.source)
        self.assertIn("before.st_uid != os.geteuid()", self.source)
        self.assertIn("hmac.compare_digest(digest.hexdigest(), expected)", self.source)
        self.assertIn("identity(after) != identity(before)", self.source)

    def test_verifier_modules_execute_from_independently_accepted_git_commit(self) -> None:
        self.assertIn('"GIT_NO_REPLACE_OBJECTS": "1"', self.source)
        self.assertIn(
            'git("rev-parse", "--verify", f"{accepted_source_sha}^{{commit}}")',
            self.source,
        )
        self.assertIn('f"{accepted_source_sha}:{path}"', self.source)
        self.assertIn('git("cat-file", "blob", blob)', self.source)
        self.assertIn('git("hash-object", "--stdin", input_data=source)', self.source)
        self.assertIn("immutable_git_source(manifest_source_path)", self.source)
        self.assertIn("immutable_git_source(helper_source_path)", self.source)
        self.assertIn('exec(compile(text, module.__file__, "exec"), module.__dict__)', self.source)
        self.assertNotIn('git("rev-parse", "HEAD")', self.source)
        self.assertNotIn("spec_from_file_location", self.source)
        self.assertNotIn("helper_path = root /", self.source)


if __name__ == "__main__":
    unittest.main()
