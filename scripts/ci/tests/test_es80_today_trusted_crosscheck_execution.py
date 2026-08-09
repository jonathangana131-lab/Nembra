#!/usr/bin/env python3
"""Adversarial runtime tests for trusted Final GO crosscheck execution custody."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_trusted_crosscheck_execution.py"
spec = importlib.util.spec_from_file_location("trusted_crosscheck_execution", MODULE_PATH)
trusted = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(trusted)


class TrustedCrosscheckExecutionTests(unittest.TestCase):
    SOURCE = "a" * 40
    PRODUCER_PATH = "scripts/ci/es80_today_independent_candidate_crosscheck.py"

    def _git(self, repository: Path, *arguments: str) -> str:
        return subprocess.check_output(
            ["/usr/bin/git", "-C", str(repository), *arguments],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()

    def _init_repository(self, root: Path) -> Path:
        repository = root / "tooling"
        repository.mkdir()
        subprocess.run(["/usr/bin/git", "-C", str(repository), "init", "-q"], check=True)
        self._git(repository, "config", "user.email", "capture-v14@example.invalid")
        self._git(repository, "config", "user.name", "Capture V14 trusted-crosscheck test")
        return repository

    def _write_producer(self, repository: Path, marker: str) -> tuple[str, str]:
        path = repository / self.PRODUCER_PATH
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "#!/usr/bin/env python3\n"
            "import argparse, json\n"
            "parser = argparse.ArgumentParser()\n"
            "parser.add_argument('--candidate-dir', required=True)\n"
            "parser.add_argument('--expected-source-sha', required=True)\n"
            "args = parser.parse_args()\n"
            f"record = {{'marker': {marker!r}, 'sourceCommitSHA': args.expected_source_sha, 'status': 'PASS_NOT_FINAL_GO'}}\n"
            "print(json.dumps(record, indent=2, sort_keys=True))\n",
            encoding="utf-8",
        )
        self._git(repository, "add", self.PRODUCER_PATH)
        self._git(repository, "commit", "-q", "-m", f"producer {marker}")
        commit = self._git(repository, "rev-parse", "HEAD")
        blob = self._git(repository, "rev-parse", f"{commit}:{self.PRODUCER_PATH}")
        return commit, blob

    def _pin(self, commit: str, blob: str):
        return mock.patch.multiple(
            trusted,
            PINNED_CROSSCHECK_COMMIT=commit,
            PINNED_CROSSCHECK_BLOB=blob,
            CROSSCHECK_PATH=self.PRODUCER_PATH,
        )

    def test_executes_exact_pinned_blob_and_returns_canonical_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = self._init_repository(root)
            commit, blob = self._write_producer(repository, "trusted")
            candidate = root / "candidate"
            candidate.mkdir()

            with self._pin(commit, blob):
                raw, record = trusted.execute_trusted_crosscheck(
                    tooling_repo=repository,
                    candidate_dir=candidate,
                    expected_source_sha=self.SOURCE,
                )

            self.assertEqual(record["marker"], "trusted")
            self.assertEqual(record["sourceCommitSHA"], self.SOURCE)
            self.assertEqual(record["status"], "PASS_NOT_FINAL_GO")
            self.assertEqual(raw, (json.dumps(record, indent=2, sort_keys=True) + "\n").encode())

    def test_real_git_replace_ref_cannot_substitute_pinned_producer_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = self._init_repository(root)
            trusted_commit, trusted_blob = self._write_producer(repository, "replacement")
            actual_commit, actual_blob = self._write_producer(repository, "actual")
            self.assertNotEqual(trusted_blob, actual_blob)

            self._git(repository, "replace", actual_commit, trusted_commit)
            self.assertEqual(
                self._git(repository, "rev-parse", f"{actual_commit}:{self.PRODUCER_PATH}"),
                trusted_blob,
                "attack setup must prove ordinary Git follows refs/replace",
            )

            candidate = root / "candidate"
            candidate.mkdir()
            with self._pin(actual_commit, actual_blob):
                raw = trusted.pinned_crosscheck_bytes(repository)
                executed_raw, record = trusted.execute_trusted_crosscheck(
                    tooling_repo=repository,
                    candidate_dir=candidate,
                    expected_source_sha=self.SOURCE,
                )

            self.assertIn(b"'actual'", raw)
            self.assertNotIn(b"'replacement'", raw)
            self.assertEqual(record["marker"], "actual")
            self.assertIn(b'"marker": "actual"', executed_raw)

    def test_caller_path_cannot_replace_git_or_python_interpreter(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = self._init_repository(root)
            commit, blob = self._write_producer(repository, "system-tools")
            candidate = root / "candidate"
            candidate.mkdir()

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            marker = root / "poisoned"
            for name in ("git", "python3"):
                fake = fake_bin / name
                fake.write_text(
                    "#!/bin/sh\n"
                    f"printf poisoned > {str(marker)!r}\n"
                    "exit 97\n",
                    encoding="utf-8",
                )
                fake.chmod(fake.stat().st_mode | stat.S_IXUSR)

            with self._pin(commit, blob), mock.patch.dict(
                os.environ,
                {"PATH": str(fake_bin), "BASH_ENV": str(root / "attacker-bash-env")},
                clear=False,
            ):
                _, record = trusted.execute_trusted_crosscheck(
                    tooling_repo=repository,
                    candidate_dir=candidate,
                    expected_source_sha=self.SOURCE,
                )

            self.assertEqual(record["marker"], "system-tools")
            self.assertFalse(marker.exists(), "caller PATH tool executed inside trusted custody")

    def test_git_object_bytes_must_reproduce_pinned_blob_identity(self) -> None:
        responses = iter(
            [
                trusted.PINNED_CROSSCHECK_COMMIT,
                trusted.PINNED_CROSSCHECK_BLOB,
                b"forged object bytes",
            ]
        )
        with mock.patch.object(trusted, "_git", side_effect=lambda *args, **kwargs: next(responses)):
            with self.assertRaisesRegex(
                trusted.TrustedCrosscheckExecutionError,
                "do not reproduce reviewed Git blob identity",
            ):
                trusted.pinned_crosscheck_bytes(Path("/unused"))

    def test_rejects_noncanonical_producer_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = self._init_repository(root)
            path = repository / self.PRODUCER_PATH
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                "#!/usr/bin/env python3\n"
                "import argparse\n"
                "parser = argparse.ArgumentParser()\n"
                "parser.add_argument('--candidate-dir', required=True)\n"
                "parser.add_argument('--expected-source-sha', required=True)\n"
                "parser.parse_args()\n"
                "print('{\\\"status\\\": \\\"PASS_NOT_FINAL_GO\\\"}')\n",
                encoding="utf-8",
            )
            self._git(repository, "add", self.PRODUCER_PATH)
            self._git(repository, "commit", "-q", "-m", "noncanonical producer")
            commit = self._git(repository, "rev-parse", "HEAD")
            blob = self._git(repository, "rev-parse", f"{commit}:{self.PRODUCER_PATH}")
            candidate = root / "candidate"
            candidate.mkdir()

            with self._pin(commit, blob):
                with self.assertRaisesRegex(
                    trusted.TrustedCrosscheckExecutionError,
                    "not canonical deterministic JSON",
                ):
                    trusted.execute_trusted_crosscheck(
                        tooling_repo=repository,
                        candidate_dir=candidate,
                        expected_source_sha=self.SOURCE,
                    )


if __name__ == "__main__":
    unittest.main()
