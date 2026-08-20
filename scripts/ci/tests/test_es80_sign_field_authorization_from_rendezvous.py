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
        return int(datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        ).timestamp()) * 1_000

    def test_delegate_command_uses_only_frozen_existing_signer_creation_surface(self) -> None:
        frozen_signer = Path("/private/frozen/es80_field_authorization_envelope.py")
        command = wrapper.build_signer_command(self.args, self.rendezvous, frozen_signer)
        joined = " ".join(command)

        self.assertEqual(command[0], "/usr/bin/python3")
        self.assertEqual(command[1], str(frozen_signer))
        for required in (
            "--signed-evidence", "--private-key", "--openssl", "--output",
            "--authorization-id", "--attempt-challenge-sha256", "--issued-at",
            "--not-before", "--expires-at",
        ):
            with self.subTest(required=required):
                self.assertIn(required, command)

        self.assertEqual(
            command[command.index("--attempt-challenge-sha256") + 1],
            self.rendezvous["attemptChallengeSHA256"],
        )
        for forbidden in (
            "--create", "--bundle-identifier", "--source-commit-sha", "--build-identifier",
            "--build-instance-id", "--executable-sha256", "--info-plist-sha256",
            "--tuya-dependency-lock-sha256", "--external-build-record-sha256",
            "--signed-build-evidence-sha256", "--final-go-record-sha256",
            "--intended-device-pseudonym-sha256", "--issued-at-unix-ms",
            "--not-before-unix-ms", "--expires-at-unix-ms",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, command)
        self.assertNotIn("private key bytes", joined.lower())

    def test_attempt_deadline_is_inclusive_but_never_extendable(self) -> None:
        started = self.rendezvous["attemptStartedAtUnixMilliseconds"]
        deadline = self.rendezvous["authorizationMustExpireByUnixMilliseconds"]
        issued = self.ms("2026-08-20T04:45:00Z")
        not_before = self.ms("2026-08-20T04:46:00Z")

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
                attempt_started_at=started, must_expire_by=deadline,
                issued_at=started - 1, not_before=started, expires_at=deadline,
            )
        with self.assertRaisesRegex(ValueError, "not-before precedes the running app attempt"):
            wrapper.validate_signing_chronology(
                attempt_started_at=started, must_expire_by=deadline,
                issued_at=started, not_before=started - 1, expires_at=deadline,
            )

    def test_signer_order_allows_future_not_before_but_not_past_not_before(self) -> None:
        started = self.rendezvous["attemptStartedAtUnixMilliseconds"]
        deadline = self.rendezvous["authorizationMustExpireByUnixMilliseconds"]
        issued = started + 1_000
        not_before = issued + 1_000
        expires = not_before + 1_000

        wrapper.validate_signing_chronology(
            attempt_started_at=started, must_expire_by=deadline,
            issued_at=issued, not_before=not_before, expires_at=expires,
        )
        with self.assertRaisesRegex(ValueError, "not-before precedes issued-at"):
            wrapper.validate_signing_chronology(
                attempt_started_at=started, must_expire_by=deadline,
                issued_at=issued, not_before=issued - 1, expires_at=expires,
            )
        with self.assertRaisesRegex(ValueError, "later than not-before"):
            wrapper.validate_signing_chronology(
                attempt_started_at=started, must_expire_by=deadline,
                issued_at=issued, not_before=not_before, expires_at=not_before,
            )

    def test_timestamp_parser_matches_signer_canonical_utc_seconds(self) -> None:
        raw = "2026-08-20T04:45:00Z"
        self.assertEqual(wrapper.timestamp_unix_milliseconds(raw, "issued-at"), self.ms(raw))
        for invalid in (
            "2026-8-20T04:45:00Z",
            "2026-08-2T04:45:00Z",
            "2026-08-20T4:45:00Z",
            "2026-08-20T04:5:00Z",
            "2026-08-20T04:45:0Z",
            "2026-08-20T04:45:00.123Z",
            "2026-08-20T04:45:00",
            "2026-08-20T04:45:00+01:00",
            "not-a-time",
            "1970-01-01T00:00:00Z",
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    wrapper.timestamp_unix_milliseconds(invalid, "issued-at")

    def test_wrapper_freezes_signing_code_and_has_no_second_signing_path(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("accepted_execution_bundle", source)
        self.assertIn('"cat-file", "blob"', source)
        self.assertIn("_git_blob_sha(blob) != blob_id", source)
        self.assertIn("es80_field_authorization_envelope.py", source)
        self.assertIn('PYTHON = Path("/usr/bin/python3")', source)
        self.assertNotIn("ec.ECDSA", source)
        self.assertNotIn("P256", source)
        self.assertNotIn("payloadBase64", source)
        self.assertNotIn("signatureDERBase64", source)
        self.assertNotIn("canonical_json_bytes(payload", source)
        self.assertNotIn("--attempt-challenge-sha256\", required=True", source)
        self.assertNotIn("sys.executable,", source)
        self.assertNotIn("str(SIGNER)", source)


if __name__ == "__main__":
    unittest.main()
