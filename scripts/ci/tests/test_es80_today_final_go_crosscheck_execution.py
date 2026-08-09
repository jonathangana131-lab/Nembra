#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

CI_DIR = Path(__file__).resolve().parents[1]


def load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, CI_DIR / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


execution = load(
    "nembra_final_go_crosscheck_execution_test",
    "es80_today_final_go_crosscheck_execution.py",
)
foundation = load(
    "nembra_final_go_crosscheck_execution_foundation_test",
    "es80_today_final_go_foundation.py",
)


class PinnedCrosscheckExecutionTests(unittest.TestCase):
    SOURCE = "a" * 40
    RECEIPT = b'{"authority":"independent"}\n'
    TOOL_SOURCE = "import sys\nsys.stdout.buffer.write(b'producer')\n"

    def git(self, repository: Path, *arguments: str) -> str:
        subject = arguments[-1]
        if subject == f"{execution.PINNED_CROSSCHECK_COMMIT}^{{commit}}":
            return execution.PINNED_CROSSCHECK_COMMIT
        if subject == f"{execution.PINNED_CROSSCHECK_COMMIT}:{execution.CROSSCHECK_PATH}":
            if arguments[0] == "rev-parse":
                return execution.PINNED_CROSSCHECK_BLOB
            if arguments[0] == "show":
                return self.TOOL_SOURCE
        raise AssertionError((repository, arguments))

    def fixture(self, root: Path):
        candidate = root / "candidate"
        candidate.mkdir()
        receipt = root / "crosscheck.json"
        receipt.write_bytes(self.RECEIPT)
        tooling = root / "tooling"
        tooling.mkdir()
        return candidate, receipt, tooling

    def test_exact_pinned_execution_stdout_bytes_authorize_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate, receipt, tooling = self.fixture(root)
            calls = []

            def runner(command, **kwargs):
                calls.append((command, kwargs))
                return subprocess.CompletedProcess(command, 0, stdout=self.RECEIPT, stderr=b"")

            subject = execution.verify_pinned_crosscheck_execution(
                candidate_root=candidate,
                expected_source_sha=self.SOURCE,
                retained_receipt=receipt,
                tooling_repo=tooling,
                git=self.git,
                runner=runner,
            )

            self.assertEqual(subject["authority"], "pinned-git-blob-reexecution-exact-receipt-bytes")
            self.assertEqual(subject["toolCommit"], execution.PINNED_CROSSCHECK_COMMIT)
            self.assertEqual(subject["toolGitBlob"], execution.PINNED_CROSSCHECK_BLOB)
            self.assertEqual(subject["receiptByteCount"], len(self.RECEIPT))
            self.assertEqual(len(calls), 1)
            command, kwargs = calls[0]
            self.assertEqual(command[1:4], ["-I", "-B", "-"])
            self.assertEqual(command[-4:], ["--candidate-dir", str(candidate.resolve()), "--expected-source-sha", self.SOURCE])
            self.assertEqual(kwargs["input"], self.TOOL_SOURCE.encode())
            self.assertEqual(kwargs["check"], False)
            self.assertEqual(kwargs["timeout"], 30)
            self.assertNotIn("PYTHONPATH", kwargs["env"])

    def test_caller_receipt_must_equal_pinned_producer_stdout_exactly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate, receipt, tooling = self.fixture(root)

            def runner(command, **kwargs):
                return subprocess.CompletedProcess(command, 0, stdout=b'{"different":true}\n', stderr=b"")

            with self.assertRaisesRegex(
                execution.CrosscheckExecutionError,
                "were not emitted by the pinned producer",
            ):
                execution.verify_pinned_crosscheck_execution(
                    candidate_root=candidate,
                    expected_source_sha=self.SOURCE,
                    retained_receipt=receipt,
                    tooling_repo=tooling,
                    git=self.git,
                    runner=runner,
                )

    def test_failed_or_noisy_pinned_producer_is_not_authority(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate, receipt, tooling = self.fixture(root)

            for completed, message in (
                (subprocess.CompletedProcess([], 2, stdout=b"", stderr=b"rejected"), "rejected"),
                (subprocess.CompletedProcess([], 0, stdout=self.RECEIPT, stderr=b"warning"), "unexpected stderr"),
            ):
                with self.subTest(message=message):
                    with self.assertRaisesRegex(execution.CrosscheckExecutionError, message):
                        execution.verify_pinned_crosscheck_execution(
                            candidate_root=candidate,
                            expected_source_sha=self.SOURCE,
                            retained_receipt=receipt,
                            tooling_repo=tooling,
                            git=self.git,
                            runner=lambda *args, result=completed, **kwargs: result,
                        )

    def test_low_level_crosscheck_subject_without_candidate_root_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(foundation.FinalGoError, "exact retained candidate root"):
                foundation._crosscheck_subject(
                    root / "caller.json",
                    {"sourceCommitSHA": self.SOURCE},
                    root / "source",
                    root / "tooling",
                )

    def test_build_composition_injects_execution_bound_crosscheck_and_restores_seam(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate_root = root / "candidate"
            candidate_root.mkdir()
            receipt = root / "crosscheck.json"
            receipt.write_bytes(self.RECEIPT)
            source_repo = root / "source"
            tooling_repo = root / "tooling"
            source_repo.mkdir()
            tooling_repo.mkdir()
            candidate = {"sourceCommitSHA": self.SOURCE}
            execution_subject = {"authority": "pinned-git-blob-reexecution-exact-receipt-bytes"}
            original_impl_crosscheck = foundation._impl._crosscheck_subject

            def fake_impl_build(**kwargs):
                return foundation._impl._crosscheck_subject(
                    receipt,
                    candidate,
                    source_repo,
                    tooling_repo,
                )

            with mock.patch.object(
                foundation,
                "_verify_crosscheck_execution",
                return_value=execution_subject,
            ) as verify, mock.patch.object(
                foundation,
                "_ORIGINAL_CROSSCHECK_SUBJECT",
                return_value={"status": "PASS_NOT_FINAL_GO"},
            ) as historical, mock.patch.object(
                foundation._impl,
                "build_final_go_record",
                side_effect=fake_impl_build,
            ):
                result = foundation.build_final_go_record(candidate_root=candidate_root)

            self.assertIs(foundation._impl._crosscheck_subject, original_impl_crosscheck)
            self.assertEqual(result["producerExecution"], execution_subject)
            verify.assert_called_once()
            verify_call = verify.call_args.kwargs
            self.assertEqual(verify_call["candidate_root"], candidate_root)
            self.assertEqual(verify_call["expected_source_sha"], self.SOURCE)
            self.assertEqual(verify_call["retained_receipt"], receipt)
            historical.assert_called_once()


if __name__ == "__main__":
    unittest.main()
