#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_trusted_signed_candidate_subject.py"
spec = importlib.util.spec_from_file_location("trusted_signed_candidate", MODULE_PATH)
trusted = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(trusted)


class TrustedSignedCandidateSubjectTests(unittest.TestCase):
    SOURCE = trusted.FROZEN_CAPTURE_SOURCE_COMMIT

    def make_candidate(self, root: Path, prefix: str = "candidate") -> Path:
        candidate = root / prefix
        inspection = candidate / "inspection"
        (inspection / "build-evidence").mkdir(parents=True)
        (inspection / trusted.EXTERNAL_RECORD_NAME).write_bytes(b"external\n")
        (inspection / trusted.FIELD_RECORD_NAME).write_bytes(b"field\n")
        (inspection / trusted.INSPECTION_NAME).write_bytes(b"inspection\n")
        (inspection / trusted.IPA_RELATIVE_PATH).write_bytes(b"real-ipa-bytes\n")
        return candidate

    def test_frozen_tool_bytes_reprove_commit_path_blob_and_source_bytes(self):
        repository = Path("/frozen")
        raw = b"print('trusted')\n"

        def git_text(repo: Path, *arguments: str) -> str:
            self.assertEqual(repo, repository)
            if arguments == ("rev-parse", "--verify", f"{self.SOURCE}^{{commit}}"):
                return self.SOURCE
            if arguments == ("rev-parse", f"{self.SOURCE}:{trusted.INSPECTOR_PATH}"):
                return trusted.INSPECTOR_BLOB
            self.fail(arguments)

        def git_bytes(repo: Path, *arguments: str, input_bytes=None) -> bytes:
            self.assertEqual(repo, repository)
            if arguments == ("cat-file", "blob", trusted.INSPECTOR_BLOB):
                self.assertIsNone(input_bytes)
                return raw
            if arguments == ("hash-object", "--stdin"):
                self.assertEqual(input_bytes, raw)
                return (trusted.INSPECTOR_BLOB + "\n").encode()
            self.fail(arguments)

        with mock.patch.object(trusted, "_git_text", side_effect=git_text), mock.patch.object(
            trusted, "_git_bytes", side_effect=git_bytes
        ):
            self.assertEqual(
                trusted._frozen_tool_bytes(
                    repository,
                    source_commit=self.SOURCE,
                    path=trusted.INSPECTOR_PATH,
                    expected_blob=trusted.INSPECTOR_BLOB,
                ),
                raw,
            )

    def test_rejects_different_frozen_source_even_if_shape_is_valid(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.make_candidate(root)
            frozen = root / "frozen"
            frozen.mkdir()
            with self.assertRaisesRegex(trusted.TrustedSignedCandidateError, "frozen #833"):
                trusted.verify_trusted_signed_candidate(
                    candidate_root=candidate,
                    expected_source_sha="a" * 40,
                    frozen_source_repo=frozen,
                    intended_device_udid_file=root / "private-device",
                    semantic_builder=lambda trusted_root: trusted_root,
                )

    def test_production_execution_refuses_non_macos_before_any_apple_claim(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.make_candidate(root)
            retained = candidate / "inspection" / trusted.IPA_RELATIVE_PATH
            trusted_root = root / "trusted"
            trusted_root.mkdir()
            frozen = root / "frozen"
            frozen.mkdir()
            with mock.patch.object(trusted.sys, "platform", "linux"):
                with self.assertRaisesRegex(trusted.TrustedSignedCandidateError, "requires macOS"):
                    trusted._execute_frozen_apple_inspector(
                        private_runner_bytes=b"runner",
                        inspector_bytes=b"inspector",
                        retained_ipa=retained,
                        expected_source_sha=self.SOURCE,
                        intended_device_udid_file=root / "private-device",
                        frozen_source_repo=frozen,
                        trusted_candidate_root=trusted_root,
                    )

    def test_execution_uses_exact_runner_stdin_inspector_fd_and_private_device_file_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.make_candidate(root)
            retained = candidate / "inspection" / trusted.IPA_RELATIVE_PATH
            trusted_root = root / "trusted"
            trusted_root.mkdir()
            frozen = root / "frozen"
            frozen.mkdir()
            private_device = root / "private-device"
            private_device.write_text("secret-device-id", encoding="utf-8")
            private_device.chmod(0o600)
            completed = subprocess.CompletedProcess(args=[], returncode=0, stdout=b"", stderr=b"")

            def fake_run(command, **kwargs):
                output_index = command.index("--output-dir") + 1
                output = Path(command[output_index])
                output.mkdir(parents=True)
                return completed

            with mock.patch.object(trusted.sys, "platform", "darwin"), mock.patch.object(
                trusted.subprocess, "run", side_effect=fake_run
            ) as run:
                trusted._execute_frozen_apple_inspector(
                    private_runner_bytes=b"runner-source",
                    inspector_bytes=b"inspector-source",
                    retained_ipa=retained,
                    expected_source_sha=self.SOURCE,
                    intended_device_udid_file=private_device,
                    frozen_source_repo=frozen,
                    trusted_candidate_root=trusted_root,
                )

            command = run.call_args.args[0]
            kwargs = run.call_args.kwargs
            self.assertEqual(command[:3], ["/usr/bin/python3", "-I", "-"])
            self.assertIn("--canonical-inspector-fd", command)
            self.assertIn("--intended-device-udid-file", command)
            self.assertIn(str(private_device), command)
            self.assertNotIn("secret-device-id", command)
            self.assertEqual(kwargs["input"], b"runner-source")
            self.assertEqual(kwargs["cwd"], Path("/"))
            self.assertEqual(kwargs["env"]["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
            self.assertEqual(kwargs["env"]["PYTHONNOUSERSITE"], "1")
            self.assertEqual(len(kwargs["pass_fds"]), 1)

    def test_reinspection_failure_never_replays_private_runner_stderr(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.make_candidate(root)
            retained = candidate / "inspection" / trusted.IPA_RELATIVE_PATH
            trusted_root = root / "trusted"
            trusted_root.mkdir()
            frozen = root / "frozen"
            frozen.mkdir()
            private_device = root / "private-device"
            private_device.write_text("secret-device-id", encoding="utf-8")
            private_device.chmod(0o600)
            completed = subprocess.CompletedProcess(
                args=[], returncode=2, stdout=b"", stderr=b"secret-device-id must never escape"
            )
            with mock.patch.object(trusted.sys, "platform", "darwin"), mock.patch.object(
                trusted.subprocess, "run", return_value=completed
            ):
                with self.assertRaisesRegex(
                    trusted.TrustedSignedCandidateError,
                    "rejected the retained IPA",
                ) as caught:
                    trusted._execute_frozen_apple_inspector(
                        private_runner_bytes=b"runner-source",
                        inspector_bytes=b"inspector-source",
                        retained_ipa=retained,
                        expected_source_sha=self.SOURCE,
                        intended_device_udid_file=private_device,
                        frozen_source_repo=frozen,
                        trusted_candidate_root=trusted_root,
                    )
            self.assertNotIn("secret-device-id", str(caught.exception))

    def test_compare_rejects_forged_inspection_even_when_other_files_match(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.make_candidate(root, "candidate")
            verified = self.make_candidate(root, "verified")
            (candidate / "inspection" / trusted.INSPECTION_NAME).write_bytes(b"forged-inspection\n")
            with self.assertRaisesRegex(trusted.TrustedSignedCandidateError, "not byte-identical"):
                trusted._compare_retained_handoff(candidate, verified)

    def test_verify_builds_semantics_only_from_fresh_trusted_reinspection_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.make_candidate(root)
            frozen = root / "frozen"
            frozen.mkdir()
            private_device = root / "private-device"
            private_device.write_text("device-id", encoding="utf-8")
            private_device.chmod(0o600)
            seen: list[Path] = []

            def fake_execute(**kwargs):
                trusted_root = kwargs["trusted_candidate_root"]
                inspection = trusted_root / "inspection"
                (inspection / "build-evidence").mkdir(parents=True)
                source = candidate / "inspection"
                for relative in trusted.RETAINED_RELATIVE_PATHS:
                    destination = inspection / relative
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes((source / relative).read_bytes())

            def semantic_builder(trusted_root: Path):
                seen.append(trusted_root)
                self.assertNotEqual(trusted_root, candidate)
                self.assertTrue((trusted_root / "inspection" / trusted.INSPECTION_NAME).is_file())
                return {"semantic": "trusted"}

            with mock.patch.object(trusted, "_frozen_tool_bytes", side_effect=[b"runner", b"inspector"]), mock.patch.object(
                trusted, "_execute_frozen_apple_inspector", side_effect=fake_execute
            ):
                semantic, subject = trusted.verify_trusted_signed_candidate(
                    candidate_root=candidate,
                    expected_source_sha=self.SOURCE,
                    frozen_source_repo=frozen,
                    intended_device_udid_file=private_device,
                    semantic_builder=semantic_builder,
                )

            self.assertEqual(semantic, {"semantic": "trusted"})
            self.assertEqual(len(seen), 1)
            self.assertFalse(seen[0].exists(), "trusted temporary candidate must be retired after synchronous semantics")
            self.assertEqual(subject["authority"], trusted.TRUSTED_REINSPECTION_AUTHORITY)
            self.assertEqual(subject["candidateSourceCommitSHA"], self.SOURCE)
            self.assertEqual(subject["privateRunnerGitBlob"], trusted.PRIVATE_RUNNER_BLOB)
            self.assertEqual(subject["canonicalInspectorGitBlob"], trusted.INSPECTOR_BLOB)
            self.assertEqual(subject["physicalExperimentAuthorization"], "not-granted")
            self.assertEqual(
                set(subject["retainedHandoffByteIdentity"]),
                {str(item) for item in trusted.RETAINED_RELATIVE_PATHS},
            )


if __name__ == "__main__":
    unittest.main()
