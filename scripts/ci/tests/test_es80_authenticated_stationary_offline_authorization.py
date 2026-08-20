#!/usr/bin/env python3
from __future__ import annotations

import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CI = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CI))
import es80_field_authorization_envelope as authorization  # noqa: E402
import es80_signed_field_artifact_evidence as evidence  # noqa: E402


class AuthenticatedStationaryOfflineAuthorizationTests(unittest.TestCase):
    openssl = Path("/usr/bin/openssl")
    source = "1" * 40
    instance = "12345678-1234-4234-9234-123456789abc"
    executable = "2" * 64
    plist = "3" * 64
    authorization_id = "87654321-4321-4321-8321-cba987654321"
    challenge = "9" * 64
    issued = "2026-08-19T20:00:00Z"
    expires = "2026-08-19T20:10:00Z"
    active = datetime(2026, 8, 19, 20, 1, tzinfo=timezone.utc)

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-auth-tests-")
        self.directory = Path(self.temporary.name)
        os.chmod(self.directory, 0o700)
        self.key = self.directory / "synthetic-private-authority.pem"
        self.public = self.directory / "synthetic-public-authority.pem"
        subprocess.run(
            [str(self.openssl), "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(self.key)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        os.chmod(self.key, 0o600)
        subprocess.run(
            [str(self.openssl), "pkey", "-in", str(self.key), "-pubout", "-out", str(self.public)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def make_evidence(self, *, ipa: bytes = b"synthetic signed IPA\n") -> bytes:
        tuya = b"synthetic Tuya lock\n"
        pseudonym = b"synthetic intended-device pseudonym\n"
        common = {
            "schemaVersion": 1,
            "procedureID": evidence.PROCEDURE_ID,
            "bundleIdentifier": evidence.BUNDLE_ID,
            "sourceCommitSHA": self.source,
            "buildIdentifier": "capture-authorized-stationary-test",
            "buildInstanceID": self.instance,
            "executableSHA256": self.executable,
            "infoPlistSHA256": self.plist,
            "tuyaDependencyLockSHA256": evidence.sha256_hex(tuya),
        }
        external = evidence.canonical_json_bytes(common)
        final_go = evidence.canonical_json_bytes({
            **common,
            "decision": "GO",
            "signedInstallableSHA256": evidence.sha256_hex(ipa),
            "intendedDevicePseudonymSHA256": evidence.sha256_hex(pseudonym),
        })
        return evidence.build_evidence(
            ipa=ipa, tuya_lock=tuya, external_record=external, final_go_record=final_go,
            intended_device_pseudonym=pseudonym, source_commit_sha=self.source,
            build_identifier=common["buildIdentifier"], build_instance_id=self.instance,
            executable_sha256=self.executable, info_plist_sha256=self.plist,
        )

    def make_envelope(self, subject: bytes | None = None) -> tuple[bytes, bytes]:
        subject = subject or self.make_evidence()
        envelope = authorization.create_envelope_bytes(
            signed_evidence=subject, authorization_id=self.authorization_id,
            attempt_challenge_sha256=self.challenge, issued_at=self.issued,
            not_before=self.issued, expires_at=self.expires,
            private_key_path=self.key, openssl_path=self.openssl,
        )
        return envelope, subject

    def verify(self, envelope: bytes, subject: bytes, **overrides):
        values = {
            "now": self.active,
            "expected_authorization_id": self.authorization_id,
            "expected_attempt_challenge_sha256": self.challenge,
        }
        values.update(overrides)
        return authorization.verify_envelope_bytes(
            envelope, signed_evidence=subject, public_key_path=self.public,
            openssl_path=self.openssl, **values,
        )

    def test_canonical_round_trip_binds_every_exact_subject_and_one_off1(self):
        envelope, subject = self.make_envelope()
        payload = self.verify(envelope, subject)
        artifact = evidence.verify_evidence_bytes(subject)
        self.assertEqual(payload["procedureID"], "ES80-AUTHENTICATED-STATIONARY-v1")
        self.assertEqual(payload["bundleIdentifier"], "com.jonathangana131.nembra.capturelearn")
        self.assertEqual(payload["maximumOFF1Starts"], 1)
        self.assertEqual(payload["signedBuildEvidenceSHA256"], evidence.sha256_hex(subject))
        self.assertEqual(payload["issuedAtUnixMilliseconds"], 1_787_169_600_000)
        self.assertEqual(payload["notBeforeUnixMilliseconds"], 1_787_169_600_000)
        self.assertEqual(payload["expiresAtUnixMilliseconds"], 1_787_170_200_000)
        for key in (
            "sourceCommitSHA", "buildIdentifier", "buildInstanceID", "executableSHA256",
            "infoPlistSHA256", "tuyaDependencyLockSHA256", "externalBuildRecordSHA256",
            "finalGORecordSHA256", "intendedDevicePseudonymSHA256",
        ):
            self.assertEqual(payload[key], artifact[key])
        self.assertEqual(
            authorization.canonical_json_bytes(json.loads(envelope)), envelope,
            "envelope must have one deterministic canonical representation",
        )

    def test_offline_signer_contract_matches_the_swift_application_verifier(self):
        swift = (
            CI.parents[1]
            / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture"
            / "AuthenticatedStationaryCaptureFieldAuthorization.swift"
        ).read_text()
        self.assertEqual(
            authorization.canonical_json_bytes({"version": 1, "schema": "test"}),
            b'{"schema":"test","version":1}',
        )
        self.assertIn(f'"{authorization.ENVELOPE_SCHEMA}"', swift)
        self.assertIn(f'"{authorization.PAYLOAD_SCHEMA}"', swift)
        self.assertIn("encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]", swift)
        for key in authorization.ENVELOPE_KEYS | authorization.PAYLOAD_KEYS:
            self.assertIn(f'"{key}"', swift, f"Swift verifier is missing signed field {key}")

    def test_evidence_rejects_extra_duplicate_noncanonical_and_wrong_subjects(self):
        subject = self.make_evidence()
        value = json.loads(subject)
        value["physicalGO"] = True
        with self.assertRaises(evidence.EvidenceError):
            evidence.verify_evidence_bytes(evidence.canonical_json_bytes(value))
        duplicated = subject.replace(b'{\n  "buildIdentifier"', b'{\n  "schemaVersion": 1,\n  "buildIdentifier"', 1)
        with self.assertRaises(evidence.EvidenceError):
            evidence.verify_evidence_bytes(duplicated)
        with self.assertRaises(evidence.EvidenceError):
            evidence.verify_evidence_bytes(json.dumps(json.loads(subject)).encode())
        value = json.loads(subject); value["procedureID"] = "synthetic-wrong-procedure"
        with self.assertRaises(evidence.EvidenceError):
            evidence.verify_evidence_bytes(evidence.canonical_json_bytes(value))

    def test_envelope_rejects_extra_duplicate_truncated_and_noncanonical_json(self):
        envelope, subject = self.make_envelope()
        value = json.loads(envelope); value["physicalGO"] = True
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            self.verify(authorization.canonical_json_bytes(value), subject)
        duplicated = envelope.replace(
            b'{"payloadBase64"',
            b'{"schema":"duplicate","payloadBase64"',
            1,
        )
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            self.verify(duplicated, subject)
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            self.verify(envelope[:-5], subject)
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            self.verify(json.dumps(json.loads(envelope)).encode(), subject)
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            self.verify(b" " * (authorization.MAX_ENVELOPE_BYTES + 1), subject)

    def test_payload_rejects_replay_unsafe_count_extra_fields_and_signature_tamper(self):
        envelope, subject = self.make_envelope()
        outer = json.loads(envelope)
        payload = json.loads(base64.b64decode(outer["payloadBase64"]))
        payload["maximumOFF1Starts"] = 2
        outer["payloadBase64"] = base64.b64encode(
            authorization.canonical_json_bytes(payload)
        ).decode()
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            self.verify(authorization.canonical_json_bytes(outer), subject)
        payload["maximumOFF1Starts"] = 1; payload["unreviewedAuthority"] = True
        outer["payloadBase64"] = base64.b64encode(
            authorization.canonical_json_bytes(payload)
        ).decode()
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            self.verify(authorization.canonical_json_bytes(outer), subject)
        outer = json.loads(envelope)
        outer["payloadBase64"] = base64.b64encode(
            b" " * (authorization.MAX_PAYLOAD_BYTES + 1)
        ).decode()
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            self.verify(authorization.canonical_json_bytes(outer), subject)
        original = json.loads(envelope)
        signature = bytearray(base64.b64decode(original["signatureDERBase64"])); signature[-1] ^= 1
        original["signatureDERBase64"] = base64.b64encode(signature).decode()
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            self.verify(authorization.canonical_json_bytes(original), subject)

    def test_wrong_attempt_challenge_evidence_key_and_time_fail_closed(self):
        envelope, subject = self.make_envelope()
        for overrides in (
            {"expected_authorization_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"},
            {"expected_attempt_challenge_sha256": "a" * 64},
            {"now": datetime(2026, 8, 19, 20, 11, tzinfo=timezone.utc)},
        ):
            with self.assertRaises(authorization.AuthorizationEnvelopeError):
                self.verify(envelope, subject, **overrides)
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            self.verify(envelope, self.make_evidence(ipa=b"different synthetic IPA\n"))
        unrelated = self.directory / "unrelated.pem"
        subprocess.run(
            [str(self.openssl), "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(unrelated)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        unrelated_public = self.directory / "unrelated-public.pem"
        subprocess.run(
            [str(self.openssl), "pkey", "-in", str(unrelated), "-pubout", "-out", str(unrelated_public)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            authorization.verify_envelope_bytes(
                envelope, signed_evidence=subject, public_key_path=unrelated_public,
                openssl_path=self.openssl, now=self.active,
            )

    def test_chronology_and_canonical_identifiers_fail_before_signing(self):
        subject = self.make_evidence()
        cases = (
            {"authorization_id": "not-a-uuid"},
            {"attempt_challenge_sha256": "ABC"},
            {"issued_at": "2026-08-19T20:00:00+00:00"},
            {"not_before": "2026-08-19T20:11:00Z"},
            {"expires_at": "2026-08-19T21:00:00Z"},
        )
        base = {
            "signed_evidence": subject, "authorization_id": self.authorization_id,
            "attempt_challenge_sha256": self.challenge, "issued_at": self.issued,
            "not_before": self.issued, "expires_at": self.expires,
            "private_key_path": self.key, "openssl_path": self.openssl,
        }
        for change in cases:
            with self.assertRaises(authorization.AuthorizationEnvelopeError):
                authorization.create_envelope_bytes(**{**base, **change})

    def test_private_key_custody_and_no_replace_are_fail_closed(self):
        subject = self.make_evidence()
        os.chmod(self.key, 0o644)
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            authorization.create_envelope_bytes(
                signed_evidence=subject, authorization_id=self.authorization_id,
                attempt_challenge_sha256=self.challenge, issued_at=self.issued,
                not_before=self.issued, expires_at=self.expires,
                private_key_path=self.key, openssl_path=self.openssl,
            )
        os.chmod(self.key, 0o600)
        envelope, _ = self.make_envelope(subject)
        output = self.directory / "authorization.json"
        authorization.publish_no_replace(output, envelope)
        self.assertEqual(oct(output.stat().st_mode & 0o777), "0o600")
        with self.assertRaises(authorization.AuthorizationEnvelopeError):
            authorization.publish_no_replace(output, envelope)

    def test_cli_has_no_production_key_generator_and_errors_do_not_leak_key(self):
        source = (CI / "es80_field_authorization_envelope.py").read_text()
        self.assertNotIn("--generate-key", source)
        self.assertNotIn('"privateKey"', source)
        subject_path = self.directory / "evidence.json"; subject_path.write_bytes(self.make_evidence())
        output = self.directory / "out.json"
        os.chmod(self.key, 0o644)
        result = subprocess.run(
            [sys.executable, str(CI / "es80_field_authorization_envelope.py"),
             "--signed-evidence", str(subject_path), "--private-key", str(self.key),
             "--openssl", str(self.openssl), "--output", str(output),
             "--authorization-id", self.authorization_id,
             "--attempt-challenge-sha256", self.challenge,
             "--issued-at", self.issued, "--not-before", self.issued, "--expires-at", self.expires],
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertNotIn(str(self.key), result.stdout + result.stderr)
        self.assertNotIn("BEGIN EC PRIVATE KEY", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
