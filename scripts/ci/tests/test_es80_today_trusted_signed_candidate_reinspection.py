#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_trusted_signed_candidate_reinspection.py"
spec = importlib.util.spec_from_file_location("signed_reinspection", MODULE_PATH)
reinspect = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(reinspect)


class TrustedSignedCandidateReinspectionTests(unittest.TestCase):
    RUNNER_PATH = "scripts/ci/private-runner.py"
    INSPECTOR_PATH = "scripts/ci/inspector.py"

    def git(self, repository: Path, *arguments: str) -> str:
        return subprocess.check_output(
            ["/usr/bin/git", "-C", str(repository), *arguments],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()

    def init_repo(self, root: Path) -> Path:
        repository = root / "source"
        repository.mkdir()
        subprocess.run(["/usr/bin/git", "-C", str(repository), "init", "-q"], check=True)
        self.git(repository, "config", "user.email", "capture-v14@example.invalid")
        self.git(repository, "config", "user.name", "Capture V14 signed reinspection test")
        return repository

    def commit_tools(self, repository: Path, runner: bytes, inspector: bytes, message: str):
        runner_path = repository / self.RUNNER_PATH
        inspector_path = repository / self.INSPECTOR_PATH
        runner_path.parent.mkdir(parents=True, exist_ok=True)
        runner_path.write_bytes(runner)
        inspector_path.write_bytes(inspector)
        self.git(repository, "add", self.RUNNER_PATH, self.INSPECTOR_PATH)
        self.git(repository, "commit", "-q", "-m", message)
        commit = self.git(repository, "rev-parse", "HEAD")
        runner_blob = self.git(repository, "rev-parse", f"{commit}:{self.RUNNER_PATH}")
        inspector_blob = self.git(repository, "rev-parse", f"{commit}:{self.INSPECTOR_PATH}")
        return commit, runner_blob, inspector_blob

    def pins(self, runner_blob: str, inspector_blob: str):
        return mock.patch.multiple(
            reinspect,
            PRIVATE_RUNNER_PATH=self.RUNNER_PATH,
            PRIVATE_RUNNER_BLOB=runner_blob,
            INSPECTOR_PATH=self.INSPECTOR_PATH,
            INSPECTOR_BLOB=inspector_blob,
        )

    def test_reviewed_tool_lookup_ignores_real_git_replacement_objects(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = self.init_repo(root)
            replacement_commit, replacement_runner, replacement_inspector = self.commit_tools(
                repository,
                b"replacement runner\n",
                b"replacement inspector\n",
                "replacement",
            )
            actual_commit, actual_runner, actual_inspector = self.commit_tools(
                repository,
                b"actual runner\n",
                b"actual inspector\n",
                "actual",
            )
            self.git(repository, "replace", actual_commit, replacement_commit)
            self.assertEqual(
                self.git(repository, "rev-parse", f"{actual_commit}:{self.RUNNER_PATH}"),
                replacement_runner,
                "attack setup must prove ordinary Git follows refs/replace",
            )

            with self.pins(actual_runner, actual_inspector):
                runner, inspector = reinspect.reviewed_tool_bytes(repository, actual_commit)

            self.assertEqual(runner, b"actual runner\n")
            self.assertEqual(inspector, b"actual inspector\n")
            self.assertNotEqual(actual_runner, replacement_runner)
            self.assertNotEqual(actual_inspector, replacement_inspector)

    def test_caller_path_fake_git_cannot_supply_reviewed_tool_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = self.init_repo(root)
            commit, runner_blob, inspector_blob = self.commit_tools(
                repository,
                b"trusted runner\n",
                b"trusted inspector\n",
                "trusted",
            )
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            marker = root / "fake-git-ran"
            fake_git = fake_bin / "git"
            fake_git.write_text(
                "#!/bin/sh\n" + f"printf ran > {str(marker)!r}\n" + "exit 99\n",
                encoding="utf-8",
            )
            fake_git.chmod(fake_git.stat().st_mode | stat.S_IXUSR)

            with self.pins(runner_blob, inspector_blob), mock.patch.dict(
                os.environ, {"PATH": str(fake_bin)}, clear=False
            ):
                runner, inspector = reinspect.reviewed_tool_bytes(repository, commit)

            self.assertEqual(runner, b"trusted runner\n")
            self.assertEqual(inspector, b"trusted inspector\n")
            self.assertFalse(marker.exists())

    def test_open_descriptor_must_still_match_reviewed_git_blob(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "tool.py"
            raw = b"reviewed bytes\n"
            path.write_bytes(raw)
            expected = reinspect._git_blob_oid(raw, "0" * 40)
            descriptor = os.open(path, os.O_RDONLY)
            try:
                reinspect._descriptor_blob_identity(descriptor, expected, len(raw))
                with self.assertRaisesRegex(
                    reinspect.TrustedSignedCandidateReinspectionError,
                    "does not match Git blob identity",
                ):
                    reinspect._descriptor_blob_identity(descriptor, "f" * 40, len(raw))
            finally:
                os.close(descriptor)

    def test_candidate_ipa_refuses_symlink_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate"
            evidence = candidate / "inspection" / "build-evidence"
            evidence.mkdir(parents=True)
            real_ipa = root / "real.ipa"
            real_ipa.write_bytes(b"ipa")
            (evidence / "NembraField.ipa").symlink_to(real_ipa)
            with self.assertRaisesRegex(
                reinspect.TrustedSignedCandidateReinspectionError,
                "regular non-symlink",
            ):
                reinspect._candidate_ipa(candidate)

    def test_descriptor_bound_runner_produces_private_fresh_candidate_layout(self):
        fake_runner = b'''import argparse, os, pathlib, shutil\np=argparse.ArgumentParser()\np.add_argument("--ipa", required=True)\np.add_argument("--output-dir", required=True)\np.add_argument("--expected-source-sha", required=True)\np.add_argument("--intended-device-udid-file", required=True)\np.add_argument("--repository-root", required=True)\np.add_argument("--canonical-inspector-fd", type=int, required=True)\na=p.parse_args()\nassert os.read(a.canonical_inspector_fd, 4096) == b"reviewed inspector\\n"\nout=pathlib.Path(a.output_dir); (out/"build-evidence").mkdir(parents=True)\nshutil.copy2(a.ipa, out/"build-evidence"/"NembraField.ipa")\nfor name in ("NembraCaptureExternalBuildRecord.json","NembraCaptureFieldBuildEvidenceRecord.json","NembraCaptureSignedFieldArtifactInspection.json"):\n    (out/name).write_text("{}\\n", encoding="utf-8")\n'''
        fake_inspector = b"reviewed inspector\n"
        runner_blob = reinspect._git_blob_oid(fake_runner, "0" * 40)
        inspector_blob = reinspect._git_blob_oid(fake_inspector, "0" * 40)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = self.init_repo(root)
            candidate = root / "candidate"
            evidence = candidate / "inspection" / "build-evidence"
            evidence.mkdir(parents=True)
            (evidence / "NembraField.ipa").write_bytes(b"exact retained ipa")
            private_device = root / "device-id"
            private_device.write_text("PRIVATE-DEVICE", encoding="utf-8")
            private_device.chmod(0o600)

            with self.pins(runner_blob, inspector_blob), mock.patch.object(
                reinspect,
                "reviewed_tool_bytes",
                return_value=(fake_runner, fake_inspector),
            ), mock.patch.object(
                reinspect,
                "_trusted_python",
                return_value=Path("/usr/bin/python3"),
            ):
                with reinspect.trusted_reinspection_candidate_root(
                    candidate_root=candidate,
                    expected_source_sha="a" * 40,
                    frozen_source_repo=repository,
                    intended_device_udid_file=private_device,
                ) as fresh:
                    self.assertEqual(
                        (fresh / "inspection/build-evidence/NembraField.ipa").read_bytes(),
                        b"exact retained ipa",
                    )
                    for name in (
                        "NembraCaptureExternalBuildRecord.json",
                        "NembraCaptureFieldBuildEvidenceRecord.json",
                        "NembraCaptureSignedFieldArtifactInspection.json",
                    ):
                        self.assertTrue((fresh / "inspection" / name).is_file())
                self.assertFalse(fresh.exists())


if __name__ == "__main__":
    unittest.main()
