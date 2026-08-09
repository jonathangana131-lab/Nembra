#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_hardened.py"
spec = importlib.util.spec_from_file_location("hardened", MODULE_PATH)
hardened = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(hardened)


class HardenedFinalGoCompositionTests(unittest.TestCase):
    SOURCE = "a" * 40
    WORKFLOW_SOURCE = "b" * 40

    def kwargs(self, root: Path):
        return {
            "candidate_root": root / "candidate",
            "expected_source_sha": self.SOURCE,
            "expected_pr_number": 833,
            "trusted_xcode_run_id": 1001,
            "trusted_xcode_job_id": 2002,
            "trusted_xcode_artifact_id": 3003,
            "trusted_xcode_artifact_archive": root / "artifact.zip",
            "independent_crosscheck_receipt": root / "crosscheck.json",
            "frozen_source_repo": root / "source",
            "tooling_repo": root / "tooling",
            "operator_attestation": root / "attestation.json",
            "intended_device_udid_file": root / "private-device-id",
            "github_get_json": lambda path: (b"{}", {}),
            "private_rendezvous_state_dir": root / "state",
        }

    def trusted_subject(self):
        return {
            "authority": "default-branch-owner-command-v1",
            "candidateSourceCommitSHA": self.SOURCE,
            "workflowSourceCommitSHA": self.WORKFLOW_SOURCE,
        }

    def private_subject(self):
        return {
            "authority": hardened.private_rendezvous.AUTHORITY,
            "intendedDeviceMembershipVerified": True,
            "connectedDeviceProbeVerified": True,
            "installedBundleIdentifier": hardened.foundation.BUNDLE_ID,
            "oneTimeObservationConsumption": "CONSUMED",
            "rawIntendedDeviceIdentifierPublished": False,
            "physicalResultCollected": False,
            "preflightHealth": "READY",
            "chargerState": "DISCONNECTED",
            "motionState": "STATIONARY",
        }

    def fake_foundation(self, **kwargs):
        xcode = hardened.foundation._trusted_xcode_subject(
            source=kwargs["expected_source_sha"],
            expected_pr_number=kwargs["expected_pr_number"],
            run_id=kwargs["trusted_xcode_run_id"],
            job_id=kwargs["trusted_xcode_job_id"],
            artifact_id=kwargs["trusted_xcode_artifact_id"],
            artifact_archive_path=kwargs["trusted_xcode_artifact_archive"],
            github_get_json=kwargs["github_get_json"],
        )
        field = hardened.foundation._operator_attestation(
            kwargs["operator_attestation"],
            {
                "sourceCommitSHA": kwargs["expected_source_sha"],
                "retainedIPASHA256": "c" * 64,
            },
            kwargs.get("now_utc"),
        )
        return {
            "acceptedSourceCommitSHA": kwargs["expected_source_sha"],
            "trustedXcodeAcceptance": xcode,
            "exactRetainedIPAInstallAndRuntimeAttestation": field,
        }

    def test_composition_replaces_both_authority_seams_and_restores_them(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original_xcode = hardened.foundation._trusted_xcode_subject
            original_operator = hardened.foundation._operator_attestation
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ) as verify_xcode, mock.patch.object(
                hardened.private_rendezvous,
                "verify_private_field_rendezvous",
                return_value=self.private_subject(),
            ) as verify_field:
                record = hardened.build_final_go_record(**self.kwargs(root))

            self.assertIs(hardened.foundation._trusted_xcode_subject, original_xcode)
            self.assertIs(hardened.foundation._operator_attestation, original_operator)
            self.assertEqual(record["trustedXcodeAcceptance"], self.trusted_subject())
            self.assertEqual(
                record["exactRetainedIPAInstallAndRuntimeAttestation"],
                self.private_subject(),
            )
            verify_xcode.assert_called_once()
            verify_field.assert_called_once()
            field_call = verify_field.call_args.kwargs
            self.assertEqual(field_call["candidate_root"], root / "candidate")
            self.assertEqual(field_call["intended_device_udid_file"], root / "private-device-id")
            self.assertIs(
                field_call["operator_validator"],
                hardened.foundation.validate_operator_observation,
            )
            self.assertEqual(field_call["state_dir"], root / "state")

    def test_trusted_xcode_failure_becomes_final_go_error_and_restores_both_seams(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original_xcode = hardened.foundation._trusted_xcode_subject
            original_operator = hardened.foundation._operator_attestation
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                side_effect=hardened.trusted_xcode.TrustedCaptureXcodeError("untrusted workflow"),
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "untrusted workflow"):
                    hardened.build_final_go_record(**self.kwargs(root))
            self.assertIs(hardened.foundation._trusted_xcode_subject, original_xcode)
            self.assertIs(hardened.foundation._operator_attestation, original_operator)

    def test_private_rendezvous_failure_becomes_final_go_error_and_restores_both_seams(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original_xcode = hardened.foundation._trusted_xcode_subject
            original_operator = hardened.foundation._operator_attestation
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ), mock.patch.object(
                hardened.private_rendezvous,
                "verify_private_field_rendezvous",
                side_effect=hardened.private_rendezvous.PrivateFieldRendezvousError(
                    "intended device is not live"
                ),
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "intended device is not live"):
                    hardened.build_final_go_record(**self.kwargs(root))
            self.assertIs(hardened.foundation._trusted_xcode_subject, original_xcode)
            self.assertIs(hardened.foundation._operator_attestation, original_operator)

    def test_rejects_subject_that_aliases_workflow_source_to_candidate_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            aliased = self.trusted_subject()
            aliased["workflowSourceCommitSHA"] = self.SOURCE
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=aliased,
            ), mock.patch.object(
                hardened.private_rendezvous,
                "verify_private_field_rendezvous",
                return_value=self.private_subject(),
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "remain independent"):
                    hardened.build_final_go_record(**self.kwargs(root))

    def test_rejects_private_subject_without_one_time_consumption(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            field = self.private_subject()
            field["oneTimeObservationConsumption"] = "NOT_CONSUMED"
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ), mock.patch.object(
                hardened.private_rendezvous,
                "verify_private_field_rendezvous",
                return_value=field,
            ):
                with self.assertRaisesRegex(
                    hardened.FinalGoError,
                    "oneTimeObservationConsumption mismatch",
                ):
                    hardened.build_final_go_record(**self.kwargs(root))

    def test_rejects_private_subject_that_publishes_raw_device_identifier(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            field = self.private_subject()
            field["rawIntendedDeviceIdentifierPublished"] = True
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ), mock.patch.object(
                hardened.private_rendezvous,
                "verify_private_field_rendezvous",
                return_value=field,
            ):
                with self.assertRaisesRegex(
                    hardened.FinalGoError,
                    "rawIntendedDeviceIdentifierPublished mismatch",
                ):
                    hardened.build_final_go_record(**self.kwargs(root))

    def test_workflow_blob_lookup_reuses_foundation_closed_git_boundary(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            with mock.patch.object(
                hardened.foundation,
                "_git",
                return_value="e" * 40,
            ) as git:
                value = hardened._workflow_blob_sha_at_commit(
                    repository,
                    "a" * 40,
                    hardened.trusted_xcode.TRUSTED_WORKFLOW_PATH,
                )

            self.assertEqual(value, "e" * 40)
            git.assert_called_once_with(
                repository,
                "rev-parse",
                f"{'a' * 40}:{hardened.trusted_xcode.TRUSTED_WORKFLOW_PATH}",
            )

    def test_workflow_blob_lookup_does_not_trust_caller_path_git(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_git = fake_bin / "git"
            fake_git.write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' '{hardened.trusted_xcode.TRUSTED_WORKFLOW_BLOB_SHA}'\n",
                encoding="utf-8",
            )
            fake_git.chmod(fake_git.stat().st_mode | stat.S_IXUSR)
            tooling_repo = root / "tooling-repo"
            tooling_repo.mkdir()

            with mock.patch.dict(os.environ, {"PATH": str(fake_bin)}, clear=False):
                with self.assertRaises(hardened.FinalGoError):
                    hardened._workflow_blob_sha_at_commit(
                        tooling_repo,
                        "c" * 40,
                        hardened.trusted_xcode.TRUSTED_WORKFLOW_PATH,
                    )

    def test_production_cli_requires_private_device_identifier_and_exposes_no_state_override(self):
        help_text = ""
        with self.assertRaises(SystemExit):
            with mock.patch.object(
                hardened.argparse.ArgumentParser,
                "print_help",
                side_effect=lambda *args, **kwargs: None,
            ):
                hardened._args(["--help"])
        parser_source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertIn('"--intended-device-udid-file"', parser_source)
        self.assertNotIn('"--private-rendezvous-state-dir"', parser_source)
        self.assertEqual(help_text, "")

    def test_publication_delegates_only_to_failure_atomic_primitive(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "FinalGO.json"
            raw = b'{"decision":"GO"}\n'
            with mock.patch.object(
                hardened.publication,
                "publish_record_no_replace",
                return_value="c" * 64,
            ) as publish:
                self.assertEqual(hardened.publish_record_no_replace(output, raw), "c" * 64)
            publish.assert_called_once_with(output, raw)


if __name__ == "__main__":
    unittest.main()
