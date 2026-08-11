#!/usr/bin/env python3
"""V14 attack witnesses and production contract for field-installer Git/execution authority."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
BOOTSTRAP = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"


class CaptureFieldInstallerGitAuthorityRedTeamTests(unittest.TestCase):
    def _make_repository(self, path: Path) -> Path:
        path.mkdir(parents=True)
        subprocess.run(["git", "init", "-q"], cwd=path, check=True)
        subprocess.run(["git", "config", "user.email", "nembra@example.invalid"], cwd=path, check=True)
        subprocess.run(["git", "config", "user.name", "Nembra Red Team"], cwd=path, check=True)
        bootstrap = path / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
        bootstrap.parent.mkdir(parents=True)
        bootstrap.write_text("#!/bin/bash\necho accepted-bootstrap\n", encoding="utf-8")
        subprocess.run(["git", "add", "Scripts/bootstrap_capture_tuya_sdk.sh"], cwd=path, check=True)
        subprocess.run(["git", "commit", "-qm", "accepted fixture"], cwd=path, check=True)
        return bootstrap

    def _clone_and_mutate(self, accepted: Path, attacked: Path) -> tuple[str, Path]:
        subprocess.run(["git", "clone", "-q", str(accepted), str(attacked)], check=True)
        accepted_sha = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=accepted, text=True
        ).strip()
        attacked_bootstrap = attacked / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
        attacked_bootstrap.write_text("#!/bin/bash\necho attacker-bootstrap\n", encoding="utf-8")
        self.assertNotEqual(
            attacked_bootstrap.read_bytes(),
            (accepted / "Scripts" / "bootstrap_capture_tuya_sdk.sh").read_bytes(),
        )
        return accepted_sha, attacked_bootstrap

    def test_ambient_git_dir_and_work_tree_can_validate_other_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            accepted = root / "accepted"
            attacked = root / "attacked"
            self._make_repository(accepted)
            accepted_sha, attacked_bootstrap = self._clone_and_mutate(accepted, attacked)

            env = os.environ.copy()
            env["GIT_DIR"] = str(accepted / ".git")
            env["GIT_WORK_TREE"] = str(accepted)
            observed_sha = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=attacked, env=env, text=True
            ).strip()
            observed_status = subprocess.check_output(
                ["git", "status", "--porcelain=v1", "--untracked-files=all"],
                cwd=attacked,
                env=env,
                text=True,
            )

            self.assertEqual(observed_sha, accepted_sha)
            self.assertEqual(observed_status, "")
            self.assertIn("attacker-bootstrap", attacked_bootstrap.read_text(encoding="utf-8"))

    def test_repository_core_worktree_can_hide_real_checkout_rewrite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            accepted = root / "accepted"
            attacked = root / "attacked"
            self._make_repository(accepted)
            accepted_sha, attacked_bootstrap = self._clone_and_mutate(accepted, attacked)

            subprocess.run(
                ["git", "config", "core.worktree", str(accepted)],
                cwd=attacked,
                check=True,
            )
            observed_sha = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=attacked, text=True
            ).strip()
            observed_status = subprocess.check_output(
                ["git", "status", "--porcelain=v1", "--untracked-files=all"],
                cwd=attacked,
                text=True,
            )

            self.assertEqual(observed_sha, accepted_sha)
            self.assertEqual(observed_status, "")
            self.assertIn("attacker-bootstrap", attacked_bootstrap.read_text(encoding="utf-8"))

    def test_field_installer_binds_git_authority_to_real_checkout_and_raw_bytes(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")

        self.assertNotIn('SOURCE_SHA="$(git rev-parse HEAD |', source)
        self.assertNotIn('[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]]', source)
        self.assertNotIn('"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"', source)

        for marker in (
            'AUTHORITY_GIT_DIR="$ROOT/.git"',
            'GIT_DIR="$AUTHORITY_GIT_DIR"',
            'GIT_WORK_TREE="$ROOT"',
            'GIT_CONFIG_NOSYSTEM=1',
            'GIT_CONFIG_GLOBAL=/dev/null',
            'GIT_NO_REPLACE_OBJECTS=1',
            'GIT_INDEX_FILE="$authority_index"',
            'read-tree "$SOURCE_SHA"',
            'status --porcelain=v1 --untracked-files=no',
            'ls-tree", "-r", "-z", source_sha',
            'hashlib.sha1(',
            'raw accepted checkout blob mismatch',
            'untracked accepted-source path outside field-input allowlist',
        ):
            self.assertIn(marker, source, f"missing field Git-authority marker: {marker}")
        self.assertGreaterEqual(
            source.count("verify_accepted_checkout_source"),
            4,
            "source authority must be proved before bootstrap, after bootstrap, and after build",
        )

    def test_bootstrap_executes_only_from_exact_accepted_git_bytes(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")

        self.assertIn('run_accepted_source_bash "Scripts/bootstrap_capture_tuya_sdk.sh"', installer)
        self.assertIn('run_authority_git show "$SOURCE_SHA:$relative_path"', installer)
        self.assertIn("/bin/bash --noprofile --norc -p -c 'source /dev/stdin'", installer)
        self.assertIn('SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"', bootstrap)
        self.assertNotIn('dirname "${BASH_SOURCE[0]}"', bootstrap)


if __name__ == "__main__":
    unittest.main(verbosity=2)
