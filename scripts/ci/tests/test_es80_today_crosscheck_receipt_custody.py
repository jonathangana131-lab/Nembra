#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_crosscheck_receipt_custody.py"
spec = importlib.util.spec_from_file_location("custody", MODULE_PATH)
custody = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(custody)


class CrosscheckReceiptCustodyTests(unittest.TestCase):
    SOURCE = "a" * 40
    COMMIT = "b" * 40
    BLOB = "c" * 40
    PATH = "scripts/ci/es80_today_independent_candidate_crosscheck.py"
    TOOL = b"print('tool')\n"
    RECEIPT = b'{"status":"PASS_NOT_FINAL_GO"}\n'

    def fake_git_text(self, repository, *arguments, input_bytes=None):
        if arguments == ("rev-parse", "--verify", f"{self.COMMIT}^{{commit}}"):
            return self.COMMIT
        if arguments == ("rev-parse", f"{self.COMMIT}:{self.PATH}"):
            return self.BLOB
        if arguments == ("hash-object", "--stdin"):
            self.assertEqual(input_bytes, self.TOOL)
            return self.BLOB
        raise AssertionError((repository, arguments, input_bytes))

    def verify(self, root: Path, receipt_bytes: bytes | None = None):
        tooling = root / "tooling"
        tooling.mkdir()
        receipt = root / "receipt.json"
        receipt.write_bytes(self.RECEIPT if receipt_bytes is None else receipt_bytes)
        candidate = root / "candidate"
        with mock.patch.object(custody, "_git_text", side_effect=self.fake_git_text), mock.patch.object(
            custody, "_git_bytes", return_value=self.TOOL
        ), mock.patch.object(custody, "_run_pinned_tool", return_value=self.RECEIPT):
            return custody.verify_crosscheck_receipt_custody(
                candidate_root=candidate,
                expected_source_sha=self.SOURCE,
                receipt_path=receipt,
                tooling_repo=tooling,
                expected_tool_commit=self.COMMIT,
                expected_tool_path=self.PATH,
                expected_tool_blob=self.BLOB,
            )

    def test_exact_fresh_stdout_bytes_are_accepted(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = self.verify(Path(temporary))
        self.assertEqual(result["executionCustody"], custody.EXECUTION_CUSTODY)
        self.assertEqual(result["toolCommit"], self.COMMIT)
        self.assertEqual(result["toolGitBlob"], self.BLOB)
        self.assertEqual(len(result["receiptSHA256"]), 64)

    def test_one_byte_receipt_edit_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(
                custody.CrosscheckReceiptCustodyError,
                "not exact fresh stdout",
            ):
                self.verify(Path(temporary), self.RECEIPT + b" ")

    def test_pinned_commit_mismatch_fails_before_tool_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tooling = root / "tooling"
            tooling.mkdir()
            receipt = root / "receipt.json"
            receipt.write_bytes(self.RECEIPT)
            with mock.patch.object(custody, "_git_text", return_value="d" * 40), mock.patch.object(
                custody, "_run_pinned_tool"
            ) as run:
                with self.assertRaisesRegex(custody.CrosscheckReceiptCustodyError, "commit mismatch"):
                    custody.verify_crosscheck_receipt_custody(
                        candidate_root=root / "candidate",
                        expected_source_sha=self.SOURCE,
                        receipt_path=receipt,
                        tooling_repo=tooling,
                        expected_tool_commit=self.COMMIT,
                        expected_tool_path=self.PATH,
                        expected_tool_blob=self.BLOB,
                    )
            run.assert_not_called()

    def test_pinned_path_blob_mismatch_fails_before_tool_execution(self):
        def text(repository, *arguments, input_bytes=None):
            if arguments[0:2] == ("rev-parse", "--verify"):
                return self.COMMIT
            if arguments[0] == "rev-parse":
                return "d" * 40
            raise AssertionError(arguments)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tooling = root / "tooling"
            tooling.mkdir()
            receipt = root / "receipt.json"
            receipt.write_bytes(self.RECEIPT)
            with mock.patch.object(custody, "_git_text", side_effect=text), mock.patch.object(
                custody, "_run_pinned_tool"
            ) as run:
                with self.assertRaisesRegex(custody.CrosscheckReceiptCustodyError, "different blob"):
                    custody.verify_crosscheck_receipt_custody(
                        candidate_root=root / "candidate",
                        expected_source_sha=self.SOURCE,
                        receipt_path=receipt,
                        tooling_repo=tooling,
                        expected_tool_commit=self.COMMIT,
                        expected_tool_path=self.PATH,
                        expected_tool_blob=self.BLOB,
                    )
            run.assert_not_called()

    def test_symlink_receipt_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            real = root / "real.json"
            real.write_bytes(self.RECEIPT)
            alias = root / "receipt.json"
            alias.symlink_to(real)
            with self.assertRaisesRegex(custody.CrosscheckReceiptCustodyError, "non-symlink"):
                custody._read_regular_file_exact(alias, "receipt", max_bytes=custody.MAX_RECEIPT_BYTES)

    def test_pinned_tool_nonzero_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate"
            candidate.mkdir()
            with self.assertRaisesRegex(custody.CrosscheckReceiptCustodyError, "rejected the exact candidate"):
                custody._run_pinned_tool(b"raise SystemExit(9)\n", candidate, self.SOURCE)

    def test_pinned_tool_runs_in_closed_environment(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate"
            candidate.mkdir()
            script = b"import os\nprint(os.environ.get('NEMBRA_FORGED_ENV', 'closed'))\n"
            with mock.patch.dict(os.environ, {"NEMBRA_FORGED_ENV": "attacker"}, clear=False):
                output = custody._run_pinned_tool(script, candidate, self.SOURCE)
            self.assertEqual(output, b"closed\n")

    def test_git_lookup_ignores_caller_path_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tooling = root / "tooling"
            tooling.mkdir()
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_git = fake_bin / "git"
            fake_git.write_text(f"#!/bin/sh\nprintf '%s\\n' '{self.COMMIT}'\n", encoding="utf-8")
            fake_git.chmod(fake_git.stat().st_mode | stat.S_IXUSR)
            with mock.patch.dict(os.environ, {"PATH": str(fake_bin)}, clear=False):
                with self.assertRaises(custody.CrosscheckReceiptCustodyError):
                    custody._git_text(tooling, "rev-parse", "--verify", f"{self.COMMIT}^{{commit}}")


if __name__ == "__main__":
    unittest.main()
