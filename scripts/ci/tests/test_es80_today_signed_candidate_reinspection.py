#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_signed_candidate_reinspection.py"
spec = importlib.util.spec_from_file_location("reinspection", MODULE_PATH)
reinspection = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(reinspection)


class SignedCandidateReinspectionTests(unittest.TestCase):
    SOURCE = "a" * 40
    RUNNER_BLOB = "b" * 40
    INSPECTOR_BLOB = "c" * 40
    RUNNER_PATH = "scripts/ci/es80_signed_field_artifact_private_runner.py"
    INSPECTOR_PATH = "scripts/ci/es80_signed_field_artifact_evidence.py"
    EXTERNAL = b'{"schemaVersion":3}\n'
    FIELD = b'{"schemaVersion":1}\n'
    INSPECTION = b'{"schemaVersion":2}\n'
    IPA = b"exact signed ipa fixture bytes"

    def make_candidate(self, root: Path) -> Path:
        inspection = root / "candidate" / "inspection"
        (inspection / "build-evidence").mkdir(parents=True)
        (inspection / "NembraCaptureExternalBuildRecord.json").write_bytes(self.EXTERNAL)
        (inspection / "NembraCaptureFieldBuildEvidenceRecord.json").write_bytes(self.FIELD)
        (inspection / "NembraCaptureSignedFieldArtifactInspection.json").write_bytes(self.INSPECTION)
        (inspection / "build-evidence" / "NembraField.ipa").write_bytes(self.IPA)
        return root / "candidate"

    def make_udid(self, root: Path) -> Path:
        path = root / "private-device-id"
        path.write_text("00008101-001234567890001E", encoding="utf-8")
        path.chmod(0o600)
        return path.resolve()

    def fake_git_text(self, repository: Path, *arguments: str, input_bytes=None) -> str:
        if arguments == ("rev-parse", "--verify", f"{self.SOURCE}^{{commit}}"):
            return self.SOURCE
        if arguments == ("rev-parse", f"{self.SOURCE}:{self.RUNNER_PATH}"):
            return self.RUNNER_BLOB
        if arguments == ("rev-parse", f"{self.SOURCE}:{self.INSPECTOR_PATH}"):
            return self.INSPECTOR_BLOB
        if arguments == ("hash-object", "--stdin"):
            if input_bytes == b"runner":
                return self.RUNNER_BLOB
            if input_bytes == b"inspector":
                return self.INSPECTOR_BLOB
        raise AssertionError((repository, arguments, input_bytes))

    def fake_git_bytes(self, repository: Path, *arguments: str) -> bytes:
        if arguments == ("cat-file", "blob", self.RUNNER_BLOB):
            return b"runner"
        if arguments == ("cat-file", "blob", self.INSPECTOR_BLOB):
            return b"inspector"
        raise AssertionError((repository, arguments))

    def copy_fresh(self, **kwargs) -> None:
        source = Path(kwargs["ipa_path"]).parent.parent
        output = Path(kwargs["output_dir"])
        (output / "build-evidence").mkdir(parents=True)
        for name in (
            "NembraCaptureExternalBuildRecord.json",
            "NembraCaptureFieldBuildEvidenceRecord.json",
            "NembraCaptureSignedFieldArtifactInspection.json",
        ):
            (output / name).write_bytes((source / name).read_bytes())
        (output / "build-evidence" / "NembraField.ipa").write_bytes(Path(kwargs["ipa_path"]).read_bytes())

    def verify(self, root: Path, *, run_side_effect=None):
        candidate = self.make_candidate(root)
        repository = root / "repository"
        repository.mkdir()
        udid = self.make_udid(root)
        with mock.patch.object(reinspection, "_git_text", side_effect=self.fake_git_text), mock.patch.object(
            reinspection, "_git_bytes", side_effect=self.fake_git_bytes
        ), mock.patch.object(
            reinspection,
            "_run_private_inspector",
            side_effect=self.copy_fresh if run_side_effect is None else run_side_effect,
        ):
            return reinspection.verify_signed_candidate_reinspection(
                candidate_root=candidate,
                expected_source_sha=self.SOURCE,
                frozen_source_repo=repository,
                private_runner_path=self.RUNNER_PATH,
                inspector_path=self.INSPECTOR_PATH,
                intended_device_udid_file=udid,
            )

    def test_exact_fresh_reinspection_is_accepted_without_private_identifier_in_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = self.verify(Path(temporary))
        self.assertEqual(result["executionCustody"], reinspection.REINSPECTION_CUSTODY)
        self.assertEqual(result["inspectorSourceCommitSHA"], self.SOURCE)
        self.assertEqual(result["privateRunnerGitBlob"], self.RUNNER_BLOB)
        self.assertEqual(result["canonicalInspectorGitBlob"], self.INSPECTOR_BLOB)
        self.assertEqual(result["retainedIPAByteCount"], len(self.IPA))
        self.assertNotIn("UDID", repr(result).upper())
        self.assertNotIn("00008101", repr(result))

    def test_one_byte_retained_metadata_edit_after_fresh_inspection_is_rejected(self):
        def mutate_after_fresh(**kwargs):
            self.copy_fresh(**kwargs)
            supplied = Path(kwargs["ipa_path"]).parent.parent / "NembraCaptureSignedFieldArtifactInspection.json"
            supplied.write_bytes(self.INSPECTION + b" ")

        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(
                reinspection.SignedCandidateReinspectionError,
                "not exact fresh accepted-source inspector output",
            ):
                self.verify(Path(temporary), run_side_effect=mutate_after_fresh)

    def test_one_byte_retained_ipa_edit_after_fresh_inspection_is_rejected(self):
        def mutate_after_fresh(**kwargs):
            self.copy_fresh(**kwargs)
            Path(kwargs["ipa_path"]).write_bytes(self.IPA + b"!")

        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(
                reinspection.SignedCandidateReinspectionError,
                "did not retain the exact candidate IPA subject",
            ):
                self.verify(Path(temporary), run_side_effect=mutate_after_fresh)

    def test_source_commit_resolution_mismatch_fails_before_runner(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.make_candidate(root)
            repository = root / "repository"
            repository.mkdir()
            udid = self.make_udid(root)
            with mock.patch.object(reinspection, "_git_text", return_value="d" * 40), mock.patch.object(
                reinspection, "_run_private_inspector"
            ) as run:
                with self.assertRaisesRegex(
                    reinspection.SignedCandidateReinspectionError,
                    "did not resolve exact accepted source",
                ):
                    reinspection.verify_signed_candidate_reinspection(
                        candidate_root=candidate,
                        expected_source_sha=self.SOURCE,
                        frozen_source_repo=repository,
                        private_runner_path=self.RUNNER_PATH,
                        inspector_path=self.INSPECTOR_PATH,
                        intended_device_udid_file=udid,
                    )
            run.assert_not_called()

    def test_relative_private_device_file_is_rejected_before_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.make_candidate(root)
            repository = root / "repository"
            repository.mkdir()
            with mock.patch.object(reinspection, "_git_text", side_effect=self.fake_git_text), mock.patch.object(
                reinspection, "_git_bytes", side_effect=self.fake_git_bytes
            ), mock.patch.object(reinspection, "_run_private_inspector") as run:
                with self.assertRaisesRegex(
                    reinspection.SignedCandidateReinspectionError,
                    "must be absolute",
                ):
                    reinspection.verify_signed_candidate_reinspection(
                        candidate_root=candidate,
                        expected_source_sha=self.SOURCE,
                        frozen_source_repo=repository,
                        private_runner_path=self.RUNNER_PATH,
                        inspector_path=self.INSPECTOR_PATH,
                        intended_device_udid_file=Path("device-id"),
                    )
            run.assert_not_called()

    def test_private_runner_executes_inspector_from_inherited_regular_descriptor(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "fresh"
            output.parent.mkdir(exist_ok=True)
            ipa = root / "candidate.ipa"
            ipa.write_bytes(b"ipa")
            private = root / "device-id"
            private.write_text("PRIVATE", encoding="utf-8")
            private.chmod(0o600)
            runner = b"import os,sys\nfd=int(sys.argv[sys.argv.index('--canonical-inspector-fd')+1])\nraw=os.read(fd,100)\nraise SystemExit(0 if raw==b'inspector-source' else 9)\n"
            reinspection._run_private_inspector(
                runner_bytes=runner,
                inspector_bytes=b"inspector-source",
                ipa_path=ipa,
                output_dir=output,
                expected_source_sha=self.SOURCE,
                intended_device_udid_file=private.resolve(),
                repository_root=root,
            )


if __name__ == "__main__":
    unittest.main()
