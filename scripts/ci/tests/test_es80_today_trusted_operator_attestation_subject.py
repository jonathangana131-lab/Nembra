#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_trusted_operator_attestation_subject.py"
spec = importlib.util.spec_from_file_location("trusted_operator", MODULE_PATH)
trusted = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(trusted)


class TrustedOperatorAttestationSubjectTests(unittest.TestCase):
    NOW = datetime(2026, 8, 9, 6, 0, 0, tzinfo=timezone.utc)
    RECORDED = NOW - timedelta(minutes=2)
    COMMENTED = NOW - timedelta(minutes=1)
    PR = 833
    COMMENT_ID = 123456
    SOURCE = "a" * 40
    IPA = "b" * 64
    INSTANCE = "12345678-1234-1234-1234-123456789abc"
    RECORD_SHA = "c" * 64
    ATTESTATION_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    def subject(self):
        return {
            "recordSHA256": self.RECORD_SHA,
            "attestationID": self.ATTESTATION_ID,
            "recordedAtUTC": self.RECORDED.isoformat().replace("+00:00", "Z"),
            "simulatorArtifactReview": "INSPECTED_NO_TODAY_BLOCKER",
            "installationRoute": "exact-retained-ipa-via-xcode-device-management",
            "preInstallRetainedIPASHA256": self.IPA,
            "postInstallRetainedIPASHA256": self.IPA,
            "runtimeRendezvousMatched": True,
            "packageResearchAdmissionObserved": True,
            "ordinaryGeneralBuildAuthority": "NO-GO",
            "preflightHealth": "READY",
            "chargerState": "DISCONNECTED",
            "motionState": "STATIONARY",
        }

    def candidate(self):
        return {
            "sourceCommitSHA": self.SOURCE,
            "retainedIPASHA256": self.IPA,
            "buildInstanceID": self.INSTANCE,
        }

    def comment(self, **overrides):
        base = {
            "id": self.COMMENT_ID,
            "issue_url": f"https://api.github.com/repos/{trusted.REPOSITORY}/issues/{self.PR}",
            "user": {"login": trusted.REPOSITORY_OWNER, "type": "User"},
            "author_association": "OWNER",
            "created_at": self.COMMENTED.isoformat().replace("+00:00", "Z"),
            "updated_at": self.COMMENTED.isoformat().replace("+00:00", "Z"),
            "body": trusted.expected_comment_body(self.subject(), self.candidate()),
        }
        base.update(overrides)
        return base

    def github(self, comment=None):
        value = self.comment() if comment is None else comment
        raw = json.dumps(value, sort_keys=True).encode("utf-8")

        def get(path: str):
            self.assertEqual(path, f"/issues/comments/{self.COMMENT_ID}")
            return raw, value

        return get

    def verify(self, *, comment=None, subject=None, candidate=None, comment_id=None):
        return trusted.verify_trusted_operator_attestation_subject(
            parsed_subject=self.subject() if subject is None else subject,
            candidate=self.candidate() if candidate is None else candidate,
            expected_pr_number=self.PR,
            comment_id=self.COMMENT_ID if comment_id is None else comment_id,
            github_get_json=self.github(comment),
            now_utc=self.NOW,
        )

    def test_owner_comment_binds_exact_human_observation_without_promoting_machine_truth(self):
        result = self.verify()
        self.assertEqual(result["authority"], trusted.AUTHORITY)
        self.assertEqual(result["classification"], trusted.CLASSIFICATION)
        self.assertEqual(result["operatorObservationRecordSHA256"], self.RECORD_SHA)
        self.assertEqual(result["candidateBinding"]["sourceCommitSHA"], self.SOURCE)
        self.assertEqual(result["candidateBinding"]["retainedIPASHA256"], self.IPA)
        self.assertEqual(
            result["operatorDeclaredProcedureState"]["chargerState"],
            "OPERATOR_DECLARED_DISCONNECTED",
        )
        self.assertEqual(
            result["operatorDeclaredProcedureState"]["runtimeRendezvous"],
            "OPERATOR_OBSERVED_MATCHED",
        )
        self.assertIn("authorship/custody", result["machineTruthBoundary"])
        self.assertNotIn("runtimeRendezvousMatched", result)

    def test_plain_local_json_digest_without_owner_comment_is_not_enough(self):
        with self.assertRaises(trusted.TrustedOperatorAttestationError):
            trusted.verify_trusted_operator_attestation_subject(
                parsed_subject=self.subject(),
                candidate=self.candidate(),
                expected_pr_number=self.PR,
                comment_id=0,
                github_get_json=lambda path: (_ for _ in ()).throw(AssertionError(path)),
                now_utc=self.NOW,
            )

    def test_rejects_non_owner_author(self):
        comment = self.comment(user={"login": "someone-else", "type": "User"})
        with self.assertRaisesRegex(trusted.TrustedOperatorAttestationError, "repository owner"):
            self.verify(comment=comment)

    def test_rejects_non_owner_association_even_with_owner_login(self):
        comment = self.comment(author_association="COLLABORATOR")
        with self.assertRaisesRegex(trusted.TrustedOperatorAttestationError, "OWNER association"):
            self.verify(comment=comment)

    def test_rejects_comment_attached_to_different_pr(self):
        comment = self.comment(
            issue_url=f"https://api.github.com/repos/{trusted.REPOSITORY}/issues/999"
        )
        with self.assertRaisesRegex(trusted.TrustedOperatorAttestationError, "expected Capture PR"):
            self.verify(comment=comment)

    def test_rejects_edited_comment(self):
        comment = self.comment(
            updated_at=(self.COMMENTED + timedelta(seconds=1)).isoformat().replace("+00:00", "Z")
        )
        with self.assertRaisesRegex(trusted.TrustedOperatorAttestationError, "edited after creation"):
            self.verify(comment=comment)

    def test_rejects_stale_comment(self):
        old = self.NOW - timedelta(minutes=31)
        comment = self.comment(
            created_at=old.isoformat().replace("+00:00", "Z"),
            updated_at=old.isoformat().replace("+00:00", "Z"),
        )
        with self.assertRaisesRegex(trusted.TrustedOperatorAttestationError, "stale"):
            self.verify(comment=comment)

    def test_rejects_comment_that_predates_observation(self):
        earlier = self.RECORDED - timedelta(seconds=1)
        comment = self.comment(
            created_at=earlier.isoformat().replace("+00:00", "Z"),
            updated_at=earlier.isoformat().replace("+00:00", "Z"),
        )
        with self.assertRaisesRegex(trusted.TrustedOperatorAttestationError, "predates"):
            self.verify(comment=comment)

    def test_rejects_comment_too_far_after_observation(self):
        late = self.RECORDED + timedelta(minutes=11)
        comment = self.comment(
            created_at=late.isoformat().replace("+00:00", "Z"),
            updated_at=late.isoformat().replace("+00:00", "Z"),
        )
        with self.assertRaisesRegex(trusted.TrustedOperatorAttestationError, "too far removed"):
            self.verify(comment=comment)

    def test_rejects_body_that_does_not_bind_exact_record_digest(self):
        comment = self.comment(
            body=trusted.expected_comment_body(self.subject(), self.candidate()).replace(
                self.RECORD_SHA, "d" * 64
            )
        )
        with self.assertRaisesRegex(trusted.TrustedOperatorAttestationError, "does not bind"):
            self.verify(comment=comment)

    def test_rejects_body_that_does_not_bind_exact_candidate_source(self):
        comment = self.comment(
            body=trusted.expected_comment_body(self.subject(), self.candidate()).replace(
                self.SOURCE, "e" * 40
            )
        )
        with self.assertRaisesRegex(trusted.TrustedOperatorAttestationError, "does not bind"):
            self.verify(comment=comment)

    def test_rejects_missing_raw_api_custody_bytes(self):
        def github_get_json(path: str):
            return b"", self.comment()

        with self.assertRaisesRegex(trusted.TrustedOperatorAttestationError, "response bytes"):
            trusted.verify_trusted_operator_attestation_subject(
                parsed_subject=self.subject(),
                candidate=self.candidate(),
                expected_pr_number=self.PR,
                comment_id=self.COMMENT_ID,
                github_get_json=github_get_json,
                now_utc=self.NOW,
            )


if __name__ == "__main__":
    unittest.main()
