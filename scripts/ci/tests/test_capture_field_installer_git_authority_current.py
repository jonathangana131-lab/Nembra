#!/usr/bin/env python3
"""Executable acceptance tests for the field installer's Git/execution authority fence."""

from __future__ import annotations

import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"


def installer_source() -> str:
    return INSTALLER.read_text(encoding="utf-8")


def extract(source: str, start_marker: str, end_marker: str) -> str:
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


class CaptureFieldInstallerGitAuthorityCurrentTests(unittest.TestCase):
    def make_repository(self, path: Path) -> tuple[str, Path]:
        path.mkdir(parents=True)
        subprocess.run(["git", "init", "-q"], cwd=path, check=True)
        subprocess.run(["git", "config", "user.email", "nembra@example.invalid"], cwd=path, check=True)
        subprocess.run(["git", "config", "user.name", "Nembra Authority Test"], cwd=path, check=True)
        bootstrap = path / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
        bootstrap.parent.mkdir(parents=True)
        bootstrap.write_text("#!/bin/bash\nprintf 'accepted-bootstrap\\n'\n", encoding="utf-8")
        bootstrap.chmod(0o755)
        subprocess.run(["git", "add", "Scripts/bootstrap_capture_tuya_sdk.sh"], cwd=path, check=True)
        subprocess.run(["git", "commit", "-qm", "accepted field fixture"], cwd=path, check=True)
        sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=path, text=True).strip()
        return sha, bootstrap

    def clone_attacked(self, accepted: Path, attacked: Path) -> tuple[str, Path]:
        subprocess.run(["git", "clone", "-q", str(accepted), str(attacked)], check=True)
        sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=attacked, text=True).strip()
        bootstrap = attacked / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
        bootstrap.write_text("#!/bin/bash\nprintf 'attacker-bootstrap\\n'\n", encoding="utf-8")
        bootstrap.chmod(0o755)
        return sha, bootstrap

    def run_authority_status(self, attacked: Path, sha: str, env: dict[str, str]) -> str:
        source = installer_source()
        authority = extract(
            source,
            'AUTHORITY_GIT_DIR="$ROOT/.git"',
            'SOURCE_SHA="$(authority_git rev-parse',
        )
        script = f"""
set -euo pipefail
ROOT={shlex.quote(str(attacked))}
die() {{ printf 'ERROR: %s\\n' "$*" >&2; exit 1; }}
{authority}
SOURCE_SHA={shlex.quote(sha)}
authority_git_status
"""
        completed = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-p", "-c", script],
            cwd=attacked,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        return completed.stdout

    def test_fresh_authority_index_ignores_caller_git_selection(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-field-git-env-") as directory:
            root = Path(directory)
            accepted = root / "accepted"
            attacked = root / "attacked"
            self.make_repository(accepted)
            sha, _ = self.clone_attacked(accepted, attacked)
            env = os.environ.copy()
            env["GIT_DIR"] = str(accepted / ".git")
            env["GIT_WORK_TREE"] = str(accepted)
            env["GIT_INDEX_FILE"] = str(root / "attacker-index")
            status = self.run_authority_status(attacked, sha, env)
            self.assertIn("Scripts/bootstrap_capture_tuya_sdk.sh", status)

    def test_command_line_worktree_binding_overrides_repository_core_worktree(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-field-core-worktree-") as directory:
            root = Path(directory)
            accepted = root / "accepted"
            attacked = root / "attacked"
            self.make_repository(accepted)
            sha, _ = self.clone_attacked(accepted, attacked)
            subprocess.run(
                ["git", "config", "core.worktree", str(accepted)],
                cwd=attacked,
                check=True,
            )
            status = self.run_authority_status(attacked, sha, os.environ.copy())
            self.assertIn("Scripts/bootstrap_capture_tuya_sdk.sh", status)

    def test_bootstrap_executes_exact_git_blob_not_mutated_worktree_path(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-field-bootstrap-blob-") as directory:
            repo = Path(directory) / "repo"
            sha, bootstrap = self.make_repository(repo)
            bootstrap.write_text("#!/bin/bash\nprintf 'attacker-bootstrap\\n'\n", encoding="utf-8")
            source = installer_source()
            runner = extract(
                source,
                "run_accepted_source_bash() {",
                "\n# The intended-device identifier",
            )
            script = f"""
set -euo pipefail
ROOT={shlex.quote(str(repo))}
SOURCE_SHA={shlex.quote(sha)}
{runner}
run_accepted_source_bash "Scripts/bootstrap_capture_tuya_sdk.sh"
"""
            env = os.environ.copy()
            env["GIT_DIR"] = str(Path(directory) / "attacker-does-not-exist")
            env["GIT_WORK_TREE"] = str(Path(directory) / "attacker-worktree")
            completed = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-p", "-c", script],
                cwd=repo,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
            self.assertEqual(completed.stdout, "accepted-bootstrap\n")
            self.assertNotIn("attacker-bootstrap", completed.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
