import argparse
from datetime import datetime, timezone
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_sign_field_authorization_from_rendezvous.py"
SIGNER = Path(__file__).resolve().parents[1] / "es80_field_authorization_envelope.py"
SPEC = importlib.util.spec_from_file_location("rendezvous_signer_wrapper", SCRIPT)
assert SPEC and SPEC.loader
wrapper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wrapper)


class RendezvousSignerWrapperTests(unittest.TestCase):
    def test_delegation_matches_existing_signer_creation_cli(self) -> None:
        issued = int(datetime(2026, 8, 19, 20, 0, tzinfo=timezone.utc).timestamp()) * 1000
        args = argparse.Namespace(
            signed_evidence=Path("/private/tmp/signed-evidence.json"),
            private_key=Path("/private/tmp/authority.pem"),
            openssl=Path("/usr/bin/openssl"),
            authorization_id="12345678-1234-4abc-8def-123456789abc",
            issued_at_unix_ms=issued,
            not_before_unix_ms=issued,
            expires_at_unix_ms=issued + 600_000,
            output=Path("/private/tmp/envelope.json"),
        )
        rendezvous = {"attemptChallengeSHA256": "a" * 64}

        command = wrapper.build_signer_command(args, rendezvous)

        self.assertEqual(command[0], wrapper.sys.executable)
        self.assertEqual(Path(command[1]), SIGNER)
        self.assertNotIn("--create", command)
        self.assertIn("--signed-evidence", command)
        self.assertIn("--private-key", command)
        self.assertIn("--openssl", command)
        self.assertIn("--authorization-id", command)
        self.assertIn("--attempt-challenge-sha256", command)
        self.assertIn("--issued-at", command)
        self.assertIn("--not-before", command)
        self.assertIn("--expires-at", command)
        self.assertIn("--output", command)
        self.assertEqual(command[command.index("--issued-at") + 1], "2026-08-19T20:00:00Z")
        self.assertEqual(command[command.index("--expires-at") + 1], "2026-08-19T20:10:00Z")

        for stale in (
            "--issued-at-unix-ms",
            "--not-before-unix-ms",
            "--expires-at-unix-ms",
            "--bundle-identifier",
            "--source-commit-sha",
            "--build-identifier",
            "--build-instance-id",
            "--executable-sha256",
            "--info-plist-sha256",
            "--tuya-dependency-lock-sha256",
            "--external-build-record-sha256",
            "--signed-build-evidence-sha256",
            "--final-go-record-sha256",
            "--intended-device-pseudonym-sha256",
        ):
            self.assertNotIn(stale, command)

    def test_wrapper_accepts_only_one_stable_evidence_authority_input(self) -> None:
        destinations = {action.dest for action in wrapper.parser()._actions}
        self.assertIn("signed_evidence", destinations)
        for redundant in (
            "bundle_identifier",
            "source_commit_sha",
            "build_identifier",
            "build_instance_id",
            "executable_sha256",
            "info_plist_sha256",
            "tuya_dependency_lock_sha256",
            "external_build_record_sha256",
            "signed_build_evidence_sha256",
            "final_go_record_sha256",
            "intended_device_pseudonym_sha256",
        ):
            self.assertNotIn(redundant, destinations)

    def test_subsecond_signing_instants_are_rejected_instead_of_rounded(self) -> None:
        with self.assertRaisesRegex(ValueError, "whole-second"):
            wrapper._rfc3339_seconds_from_unix_milliseconds(1_700_000_000_001, "issued-at")

    def test_attempt_relative_chronology_is_still_enforced_before_signer_launch(self) -> None:
        with self.assertRaisesRegex(ValueError, "precedes the running app attempt"):
            wrapper.validate_signing_chronology(
                attempt_started_at=2_000_500,
                must_expire_by=2_900_500,
                issued_at=2_000_000,
                not_before=2_000_000,
                expires_at=2_100_000,
            )
        with self.assertRaisesRegex(ValueError, "exceeds the running app attempt deadline"):
            wrapper.validate_signing_chronology(
                attempt_started_at=2_000_500,
                must_expire_by=2_900_500,
                issued_at=2_001_000,
                not_before=2_001_000,
                expires_at=2_901_000,
            )

    def test_delegated_flags_are_real_signer_flags(self) -> None:
        signer_source = SIGNER.read_text(encoding="utf-8")
        expected = (
            "--signed-evidence",
            "--private-key",
            "--openssl",
            "--output",
            "--authorization-id",
            "--attempt-challenge-sha256",
            "--issued-at",
            "--not-before",
            "--expires-at",
        )
        for flag in expected:
            with self.subTest(flag=flag):
                self.assertIn(f'parser.add_argument("{flag}"', signer_source)
        self.assertNotIn('parser.add_argument("--create"', signer_source)


if __name__ == "__main__":
    unittest.main()
