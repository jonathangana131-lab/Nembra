#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_trusted_crosscheck_subject.py"
spec = importlib.util.spec_from_file_location("trusted_crosscheck", MODULE_PATH)
trusted = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(trusted)


class TrustedCrosscheckSubjectTests(unittest.TestCase):
    SOURCE = "a" * 40

    def produced_receipt(self, **overrides) -> bytes:
        value = {
            "authority": trusted.CROSSCHECK_AUTHORITY,
            "status": "PASS_NOT_FINAL_GO",
            "sourceCommitSHA": self.SOURCE,
            "physicalExperimentAuthorization": "not-granted",
        }
        value.update(overrides)
        return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()

    def test_accepts_only_exact_pinned_execution_output_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate"
            tooling = root / "tooling"
            candidate.mkdir()
            tooling.mkdir()
            produced = self.produced_receipt()
            supplied = root / "receipt.json"
            supplied.write_bytes(produced)

            with mock.patch.object(trusted, "_pinned_tool_bytes", return_value=b"trusted source") as source, mock.patch.object(
                trusted, "_execute_pinned_tool", return_value=produced
            ) as execute:
                subject = trusted.verify_trusted_crosscheck_receipt(
                    candidate_root=candidate,
                    expected_source_sha=self.SOURCE,
                    supplied_receipt_path=supplied,
                    tooling_repo=tooling,
                )

        source.assert_called_once_with(tooling)
        execute.assert_called_once_with(b"trusted source", candidate, self.SOURCE)
        self.assertEqual(subject["authority"], trusted.TRUSTED_EXECUTION_AUTHORITY)
        self.assertEqual(subject["toolCommit"], trusted.PINNED_CROSSCHECK_COMMIT)
        self.assertEqual(subject["toolGitBlob"], trusted.PINNED_CROSSCHECK_BLOB)
        self.assertEqual(subject["producerOutputSHA256"], hashlib.sha256(produced).hexdigest())
        self.assertEqual(subject["producerOutputByteCount"], len(produced))
        self.assertEqual(subject["physicalExperimentAuthorization"], "not-granted")

    def test_rejects_semantically_equal_but_byte_different_caller_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate"
            tooling = root / "tooling"
            candidate.mkdir()
            tooling.mkdir()
            produced = self.produced_receipt()
            supplied = root / "receipt.json"
            supplied.write_bytes(json.dumps(json.loads(produced), sort_keys=True).encode())

            with mock.patch.object(trusted, "_pinned_tool_bytes", return_value=b"trusted source"), mock.patch.object(
                trusted, "_execute_pinned_tool", return_value=produced
            ):
                with self.assertRaisesRegex(trusted.TrustedCrosscheckError, "byte-identical"):
                    trusted.verify_trusted_crosscheck_receipt(
                        candidate_root=candidate,
                        expected_source_sha=self.SOURCE,
                        supplied_receipt_path=supplied,
                        tooling_repo=tooling,
                    )

    def test_rejects_producer_output_for_different_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate"
            tooling = root / "tooling"
            candidate.mkdir()
            tooling.mkdir()
            produced = self.produced_receipt(sourceCommitSHA="b" * 40)
            supplied = root / "receipt.json"
            supplied.write_bytes(produced)

            with mock.patch.object(trusted, "_pinned_tool_bytes", return_value=b"trusted source"), mock.patch.object(
                trusted, "_execute_pinned_tool", return_value=produced
            ):
                with self.assertRaisesRegex(trusted.TrustedCrosscheckError, "source does not match"):
                    trusted.verify_trusted_crosscheck_receipt(
                        candidate_root=candidate,
                        expected_source_sha=self.SOURCE,
                        supplied_receipt_path=supplied,
                        tooling_repo=tooling,
                    )

    def test_rejects_producer_output_that_widens_physical_authority(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate"
            tooling = root / "tooling"
            candidate.mkdir()
            tooling.mkdir()
            produced = self.produced_receipt(physicalExperimentAuthorization="granted")
            supplied = root / "receipt.json"
            supplied.write_bytes(produced)

            with mock.patch.object(trusted, "_pinned_tool_bytes", return_value=b"trusted source"), mock.patch.object(
                trusted, "_execute_pinned_tool", return_value=produced
            ):
                with self.assertRaisesRegex(trusted.TrustedCrosscheckError, "widened physical authority"):
                    trusted.verify_trusted_crosscheck_receipt(
                        candidate_root=candidate,
                        expected_source_sha=self.SOURCE,
                        supplied_receipt_path=supplied,
                        tooling_repo=tooling,
                    )

    def test_rejects_duplicate_keys_in_trusted_output(self):
        raw = (
            b'{"authority":"' + trusted.CROSSCHECK_AUTHORITY.encode() + b'",'
            b'"status":"PASS_NOT_FINAL_GO","status":"PASS_NOT_FINAL_GO",'
            b'"sourceCommitSHA":"' + self.SOURCE.encode() + b'",'
            b'"physicalExperimentAuthorization":"not-granted"}\n'
        )
        with self.assertRaisesRegex(trusted.TrustedCrosscheckError, "duplicate key"):
            trusted._strict_json_object(raw)

    def test_rejects_symlink_handoff_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate"
            tooling = root / "tooling"
            candidate.mkdir()
            tooling.mkdir()
            target = root / "real.json"
            target.write_bytes(self.produced_receipt())
            link = root / "receipt.json"
            link.symlink_to(target)

            with mock.patch.object(trusted, "_pinned_tool_bytes", return_value=b"trusted source"), mock.patch.object(
                trusted, "_execute_pinned_tool", return_value=self.produced_receipt()
            ):
                with self.assertRaisesRegex(trusted.TrustedCrosscheckError, "regular non-symlink"):
                    trusted.verify_trusted_crosscheck_receipt(
                        candidate_root=candidate,
                        expected_source_sha=self.SOURCE,
                        supplied_receipt_path=link,
                        tooling_repo=tooling,
                    )

    def test_pinned_source_reproves_commit_blob_and_exact_bytes(self):
        tooling = Path("/tooling")
        source = b"print('trusted')\n"

        def git_text(repository: Path, *arguments: str) -> str:
            self.assertEqual(repository, tooling)
            if arguments == ("rev-parse", "--verify", f"{trusted.PINNED_CROSSCHECK_COMMIT}^{{commit}}"):
                return trusted.PINNED_CROSSCHECK_COMMIT
            if arguments == ("rev-parse", f"{trusted.PINNED_CROSSCHECK_COMMIT}:{trusted.PINNED_CROSSCHECK_PATH}"):
                return trusted.PINNED_CROSSCHECK_BLOB
            self.fail(arguments)

        def git_bytes(repository: Path, *arguments: str, input_bytes=None) -> bytes:
            self.assertEqual(repository, tooling)
            if arguments == ("cat-file", "blob", trusted.PINNED_CROSSCHECK_BLOB):
                self.assertIsNone(input_bytes)
                return source
            if arguments == ("hash-object", "--stdin"):
                self.assertEqual(input_bytes, source)
                return (trusted.PINNED_CROSSCHECK_BLOB + "\n").encode()
            self.fail(arguments)

        with mock.patch.object(trusted, "_git_text", side_effect=git_text), mock.patch.object(
            trusted, "_git_bytes", side_effect=git_bytes
        ):
            self.assertEqual(trusted._pinned_tool_bytes(tooling), source)

    def test_execution_uses_absolute_isolated_python_and_source_stdin(self):
        candidate = Path("/candidate")
        tool_bytes = b"print('{}')\n"
        output = self.produced_receipt()
        completed = subprocess.CompletedProcess(args=[], returncode=0, stdout=output, stderr=b"")

        with mock.patch.object(trusted, "_real_directory", return_value=candidate), mock.patch.object(
            trusted.subprocess, "run", return_value=completed
        ) as run:
            self.assertEqual(trusted._execute_pinned_tool(tool_bytes, candidate, self.SOURCE), output)

        call = run.call_args
        self.assertEqual(
            call.args[0],
            [
                "/usr/bin/python3",
                "-I",
                "-",
                "--candidate-dir",
                str(candidate),
                "--expected-source-sha",
                self.SOURCE,
            ],
        )
        self.assertEqual(call.kwargs["input"], tool_bytes)
        self.assertEqual(call.kwargs["cwd"], Path("/"))
        environment = call.kwargs["env"]
        self.assertEqual(environment["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
        self.assertEqual(environment["PYTHONNOUSERSITE"], "1")


if __name__ == "__main__":
    unittest.main()
