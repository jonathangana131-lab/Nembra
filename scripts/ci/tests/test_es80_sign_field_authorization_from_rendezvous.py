import argparse
from datetime import datetime, timezone
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_sign_field_authorization_from_rendezvous.py"
SPEC = importlib.util.spec_from_file_location("sign_from_rendezvous", SCRIPT)
assert SPEC and SPEC.loader
wrapper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wrapper)


class SignFieldAuthorizationFromRendezvousTests(unittest.TestCase):
    def setUp(self) -> None:
        self.args = argparse.Namespace(
            signed_evidence=Path("/private/tmp/signed-evidence.json"),
            private_key=Path("/private/tmp/field-key.pem"),
            openssl=Path("/usr/bin/openssl"),
            output=Path("/private/tmp/signed-attempt-authorization.json"),
            authorization_id="87654321-4321-4321-8321-cba987654321",
            issued_at="2026-08-20T04:45:00Z",
            not_before="2026-08-20T04:45:00Z",
            expires_at="2026-08-20T04:55:00Z",
        )
        self.rendezvous = {
            "attemptChallengeSHA256": "a" * 64,
            "attemptStartedAtUnixMilliseconds": self.ms("2026-08-20T04:44:00Z"),
            "authorizationMustExpireByUnixMilliseconds": self.ms("2026-08-20T04:59:00Z"),
        }

    def ms(self, raw: str) -> int:
        return int(datetime.fromisoformat(raw[:-1] + "+00:00").timestamp() * 1_000)

    def test_delegate_command_uses_only_existing_signer_creation_surface(self) -> None:
        command = wrapper.build_signer_command(self.args, self.rendezvous)
        joined = " ".join(command)

        for required in (
            "--signed-evidence",
            "--private-key",
            "--openssl",
            "--output",
            "--authorization-id",
            "--attempt-challenge-sha256",
            "--issued-at",
            "--not-before",
            "--expires-at",
        ):
            with self.subTest(required=required):
                self.assertIn(required, command)

        self.assertEqual(
            command[command.index("--attempt-challenge-sha256") + 1],
            self.rendezvous["attemptChallengeSHA256"],
        )
        for forbidden in (
            "--create",
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
            "--issued-at-unix-ms",
            "--not-before-unix-ms",
            "--expires-at-unix-ms",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, command)
        self.assertNotIn("private key bytes", joined.lower())

    def test_attempt_deadline_is_inclusive_but_never_extendable(self) -> None:
        started = self.rendezvous["attemptStartedAtUnixMilliseconds"]
        deadline = self.rendezvous["authorizationMustExpireByUnixMilliseconds"]
        issued = self.ms("2026-08-20T04:45:00Z")
        not_before = issued

        wrapper.validate_signing_chronology(
            attempt_started_at=started,
            must_expire_by=deadline,
            issued_at=issued,
            not_before=not_before,
            expires_at=deadline,
        )
        with self.assertRaisesRegex(ValueError, "attempt deadline"):
            wrapper.validate_signing_chronology(
                attempt_started_at=started,
                must_expire_by=deadline,
                issued_at=issued,
                not_before=not_before,
                expires_at=deadline + 1,
            )

    def test_issued_and_not_before_cannot_precede_running_app_attempt(self) -> None:
        started = self.rendezvous["attemptStartedAtUnixMilliseconds"]
        deadline = self.rendezvous["authorizationMustExpireByUnixMilliseconds"]
        with self.assertRaisesRegex(ValueError, "issued-at precedes"):
            wrapper.validate_signing_chronology(
                attempt_started_at=started,
                must_expire_by=deadline,
                issued_at=started - 1,
                not_before=started,
                expires_at=deadline,
            )
        with self.assertRaisesRegex(ValueError, "not-before precedes"):
            wrapper.validate_signing_chronology(
                attempt_started_at=started,
                must_expire_by=deadline,
                issued_at=started,
                not_before=started - 1,
                expires_at=deadline,
            )

    def test_not_before_and_expiry_order_fail_closed(self) -> None:
        started = self.rendezvous["attemptStartedAtUnixMilliseconds"]
        deadline = self.rendezvous["authorizationMustExpireByUnixMilliseconds"]
        with self.assertRaisesRegex(ValueError, "not-before is later"):
            wrapper.validate_signing_chronology(
                attempt_started_at=started,
                must_expire_by=deadline,
                issued_at=started + 1,
                not_before=started + 2,
                expires_at=deadline,
            )
        with self.assertRaisesRegex(ValueError, "expires-at must be later"):
            wrapper.validate_signing_chronology(
                attempt_started_at=started,
                must_expire_by=deadline,
                issued_at=started + 1,
                not_before=started,
                expires_at=started + 1,
            )

    def test_timestamp_parser_requires_explicit_utc_and_preserves_milliseconds(self) -> None:
        raw = "2026-08-20T04:45:00.123Z"
        expected = self.ms(raw)
        self.assertEqual(wrapper.timestamp_unix_milliseconds(raw, "issued-at"), expected)
        for invalid in (
            "2026-08-20T04:45:00",
            "2026-08-20T04:45:00+01:00",
            "not-a-time",
            "1970-01-01T00:00:00Z",
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    wrapper.timestamp_unix_milliseconds(invalid, "issued-at")

    def test_wrapper_source_has_no_second_signing_or_evidence_assembly_path(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("subprocess.run(build_signer_command", source)
        self.assertIn("es80_field_authorization_envelope.py", source)
        self.assertNotIn("ec.ECDSA", source)
        self.assertNotIn("P256", source)
        self.assertNotIn("payloadBase64", source)
        self.assertNotIn("signatureDERBase64", source)
        self.assertNotIn("canonical_json_bytes(payload", source)
        self.assertNotIn("--attempt-challenge-sha256\", required=True", source)


if __name__ == "__main__":
    unittest.main()
