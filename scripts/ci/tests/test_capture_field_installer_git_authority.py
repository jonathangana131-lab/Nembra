#!/usr/bin/env python3
"""Current-line acceptance for field-installer Git and bootstrap execution authority."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
BOOTSTRAP = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"
AUTHORITY_BEGIN = "# BEGIN NEMBRA_FIELD_GIT_AUTHORITY_PY"
AUTHORITY_END = "# END NEMBRA_FIELD_GIT_AUTHORITY_PY"
BOOTSTRAP_BEGIN = "# BEGIN NEMBRA_ACCEPTED_BOOTSTRAP_RUNNER_PY"
BOOTSTRAP_END = "# END NEMBRA_ACCEPTED_BOOTSTRAP_RUNNER_PY"


def extract_python_block(source: str, begin: str, end: str) -> str:
    if source.count(begin) != 1 or source.count(end) != 1:
        raise AssertionError(f"expected one production block: {begin} .. {end}")
    body = source.split(begin, 1)[1].split(end, 1)[0]
    return body.strip("\n") + "\n"


class CaptureFieldInstallerGitAuthorityTests(unittest.TestCase):
    def _make_repository(self, path: Path, *, bootstrap_body: str | None = None) -> Path:
        path.mkdir(parents=True)
        subprocess.run(["git", "init", "-q"], cwd=path, check=True)
        subprocess.run(["git", "config", "user.email", "nembra@example.invalid"], cwd=path, check=True)
        subprocess.run(["git", "config", "user.name", "Nembra Authority QA"], cwd=path, check=True)
        gitignore = path / ".gitignore"
        gitignore.write_text(
            "LocalSecrets/\nPods/\nNembraCapture.xcworkspace/\nPodfile.lock\n",
            encoding="utf-8",
        )
        bootstrap = path / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
        bootstrap.parent.mkdir(parents=True)
        bootstrap.write_text(
            bootstrap_body
            or "#!/bin/bash\nprintf 'accepted-bootstrap:%s\\n' \"${NEMBRA_CAPTURE_ACCEPTED_REPO_ROOT:-missing}\"\n",
            encoding="utf-8",
        )
        bootstrap.chmod(0o755)
        subprocess.run(
            ["git", "add", ".gitignore", "Scripts/bootstrap_capture_tuya_sdk.sh"],
            cwd=path,
            check=True,
        )
        subprocess.run(["git", "commit", "-qm", "accepted fixture"], cwd=path, check=True)
        return bootstrap

    def _clone_and_mutate(self, accepted: Path, attacked: Path) -> tuple[str, Path]:
        subprocess.run(["git", "clone", "-q", str(accepted), str(attacked)], check=True)
        accepted_sha = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=accepted, text=True
        ).strip()
        attacked_bootstrap = attacked / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
        attacked_bootstrap.write_text("#!/bin/bash\necho attacker-bootstrap\n", encoding="utf-8")
        attacked_bootstrap.chmod(0o755)
        return accepted_sha, attacked_bootstrap

    def _write_extracted(self, directory: Path, begin: str, end: str, name: str) -> Path:
        source = INSTALLER.read_text(encoding="utf-8")
        path = directory / name
        path.write_text(extract_python_block(source, begin, end), encoding="utf-8")
        return path

    def _run_authority(
        self,
        script: Path,
        checkout: Path,
        expected_sha: str,
        *,
        environment: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        if environment:
            env.update(environment)
        return subprocess.run(
            [sys.executable, "-I", str(script), str(checkout), expected_sha],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            check=False,
        )

    def test_resolver_bound_authority_accepts_exact_clean_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            self._make_repository(repo)
            expected_sha = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=repo, text=True
            ).strip()
            authority = self._write_extracted(root, AUTHORITY_BEGIN, AUTHORITY_END, "authority.py")
            result = self._run_authority(authority, repo, expected_sha)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), expected_sha)

    def test_ambient_git_dir_and_work_tree_cannot_validate_other_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            accepted = root / "accepted"
            attacked = root / "attacked"
            self._make_repository(accepted)
            expected_sha, attacked_bootstrap = self._clone_and_mutate(accepted, attacked)
            authority = self._write_extracted(root, AUTHORITY_BEGIN, AUTHORITY_END, "authority.py")
            result = self._run_authority(
                authority,
                attacked,
                expected_sha,
                environment={
                    "GIT_DIR": str(accepted / ".git"),
                    "GIT_WORK_TREE": str(accepted),
                },
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("attacker-bootstrap", attacked_bootstrap.read_text(encoding="utf-8"))

    def test_repository_core_worktree_cannot_hide_real_checkout_rewrite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            accepted = root / "accepted"
            attacked = root / "attacked"
            self._make_repository(accepted)
            expected_sha, _ = self._clone_and_mutate(accepted, attacked)
            subprocess.run(
                ["git", "config", "core.worktree", str(accepted)], cwd=attacked, check=True
            )
            authority = self._write_extracted(root, AUTHORITY_BEGIN, AUTHORITY_END, "authority.py")
            result = self._run_authority(authority, attacked, expected_sha)
            self.assertNotEqual(result.returncode, 0)

    def test_fresh_index_and_raw_bytes_reject_assume_unchanged_rewrite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            bootstrap = self._make_repository(repo)
            expected_sha = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=repo, text=True
            ).strip()
            subprocess.run(
                ["git", "update-index", "--assume-unchanged", "Scripts/bootstrap_capture_tuya_sdk.sh"],
                cwd=repo,
                check=True,
            )
            bootstrap.write_text("#!/bin/bash\necho hidden-attacker-bootstrap\n", encoding="utf-8")
            authority = self._write_extracted(root, AUTHORITY_BEGIN, AUTHORITY_END, "authority.py")
            result = self._run_authority(authority, repo, expected_sha)
            self.assertNotEqual(result.returncode, 0)

    def test_filesystem_audit_rejects_info_exclude_hidden_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            self._make_repository(repo)
            expected_sha = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=repo, text=True
            ).strip()
            injected = repo / "Injected.swift"
            injected.write_text("let injected = true\n", encoding="utf-8")
            exclude = repo / ".git" / "info" / "exclude"
            exclude.parent.mkdir(parents=True, exist_ok=True)
            with exclude.open("a", encoding="utf-8") as handle:
                handle.write("\nInjected.swift\n")
            self.assertEqual(
                subprocess.check_output(
                    ["git", "status", "--porcelain=v1", "--untracked-files=all"],
                    cwd=repo,
                    text=True,
                ),
                "",
                "attack witness requires ordinary status to miss the hidden source",
            )
            authority = self._write_extracted(root, AUTHORITY_BEGIN, AUTHORITY_END, "authority.py")
            result = self._run_authority(authority, repo, expected_sha)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unexpected path", result.stderr)

    def test_filesystem_audit_allows_only_declared_private_and_generated_roots(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            self._make_repository(repo)
            expected_sha = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=repo, text=True
            ).strip()
            (repo / "LocalSecrets" / "TuyaSDK").mkdir(parents=True)
            (repo / "LocalSecrets" / "TuyaSDK" / "secret.bin").write_bytes(b"private")
            (repo / "Pods" / "Generated").mkdir(parents=True)
            (repo / "Pods" / "Generated" / "input.xcconfig").write_text("A=1\n", encoding="utf-8")
            (repo / "NembraCapture.xcworkspace").mkdir()
            (repo / "NembraCapture.xcworkspace" / "contents.xcworkspacedata").write_text(
                "workspace\n", encoding="utf-8"
            )
            (repo / "Podfile.lock").write_text("LOCK\n", encoding="utf-8")
            authority = self._write_extracted(root, AUTHORITY_BEGIN, AUTHORITY_END, "authority.py")
            result = self._run_authority(authority, repo, expected_sha)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_bootstrap_runner_executes_exact_git_blob_not_mutated_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            bootstrap = self._make_repository(repo)
            expected_sha = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=repo, text=True
            ).strip()
            bootstrap.write_text("#!/bin/bash\necho attacker-bootstrap\n", encoding="utf-8")
            runner = self._write_extracted(root, BOOTSTRAP_BEGIN, BOOTSTRAP_END, "runner.py")
            result = subprocess.run(
                [
                    sys.executable,
                    "-I",
                    str(runner),
                    str(repo),
                    expected_sha,
                    "Scripts/bootstrap_capture_tuya_sdk.sh",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "GIT_DIR": str(root / "non-authority-gitdir")},
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), f"accepted-bootstrap:{repo.resolve()}")
            self.assertNotIn("attacker-bootstrap", result.stdout)

    def test_product_source_requires_explicit_authority_and_captured_bootstrap(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")

        self.assertNotIn('SOURCE_SHA="$(git rev-parse HEAD |', installer)
        self.assertNotIn('[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]]', installer)
        self.assertNotIn('"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"', installer)
        self.assertIn(AUTHORITY_BEGIN, installer)
        self.assertIn(BOOTSTRAP_BEGIN, installer)
        self.assertIn('GIT_DIR": str(git_dir)', installer)
        self.assertIn('GIT_WORK_TREE": str(root)', installer)
        self.assertIn('"GIT_NO_REPLACE_OBJECTS": "1"', installer)
        self.assertIn('"GIT_CONFIG_NOSYSTEM": "1"', installer)
        self.assertIn('"GIT_CONFIG_GLOBAL": "/dev/null"', installer)
        self.assertIn('"GIT_INDEX_FILE"', installer)
        self.assertIn('"read-tree", expected', installer)
        self.assertIn('status", "--porcelain=v1", "--untracked-files=all"', installer)
        self.assertIn('raw workspace blob mismatch', installer)
        self.assertIn('unexpected path outside accepted/private/generated roots', installer)
        self.assertIn('hashlib.sha1(', installer)
        self.assertIn('b"blob "', installer)
        self.assertIn('os.execve(', installer)
        self.assertIn('"/bin/bash"', installer)
        self.assertIn('"NEMBRA_CAPTURE_ACCEPTED_REPO_ROOT"', installer)
        self.assertIn('NEMBRA_CAPTURE_ACCEPTED_REPO_ROOT', bootstrap)
        self.assertIn('SCRIPT_DIR="$REPO_ROOT/Scripts"', bootstrap)


if __name__ == "__main__":
    unittest.main(verbosity=2)
