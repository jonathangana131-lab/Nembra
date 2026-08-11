#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"


def run_git(root: Path, *args: str, env: dict[str, str] | None = None) -> str:
    completed = subprocess.run(
        ["git", *args],
        cwd=root,
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return completed.stdout.strip()


class CaptureFieldInstallerInfoExcludeRedTeamTests(unittest.TestCase):
    def test_info_exclude_hides_untracked_swift_from_fresh_index_status(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-info-exclude-") as temporary:
            root = Path(temporary)
            run_git(root, "init", "-q")
            run_git(root, "config", "user.name", "Nembra Red Team")
            run_git(root, "config", "user.email", "redteam@example.invalid")
            source_dir = root / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture"
            source_dir.mkdir(parents=True)
            (source_dir / "Accepted.swift").write_text("public let accepted = true\n", encoding="utf-8")
            run_git(root, "add", ".")
            run_git(root, "commit", "-qm", "accepted source")
            accepted_sha = run_git(root, "rev-parse", "HEAD")

            injected = source_dir / "Injected.swift"
            injected.write_text("public let attackerCompiled = true\n", encoding="utf-8")
            info_exclude = root / ".git/info/exclude"
            info_exclude.write_text(
                "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/Injected.swift\n",
                encoding="utf-8",
            )

            authority_index = root / "authority.index"
            env = {
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "LANG": "C",
                "LC_ALL": "C",
                "GIT_NO_REPLACE_OBJECTS": "1",
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_INDEX_FILE": str(authority_index),
            }
            base = [
                f"--git-dir={root / '.git'}",
                f"--work-tree={root}",
                "-c", f"core.worktree={root}",
                "-c", "core.fsmonitor=false",
                "-c", "core.untrackedCache=false",
                "-c", "core.fileMode=true",
                "-c", "core.excludesFile=/dev/null",
            ]
            subprocess.run(["git", *base, "read-tree", accepted_sha], env=env, check=True)
            status = subprocess.run(
                ["git", *base, "status", "--porcelain=v1", "--untracked-files=all"],
                env=env,
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            ).stdout.strip()
            self.assertEqual(status, "", "fixture must prove .git/info/exclude can hide injected Swift")
            self.assertTrue(injected.is_file())

    def test_field_installer_must_audit_build_visible_untracked_bytes_outside_git_excludes(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertIn("GIT_INDEX_FILE=\"$authority_index\"", source)
        self.assertIn("status --porcelain=v1 --untracked-files=all", source)
        self.assertTrue(
            "ls-tree -r -z" in source or "info/exclude" in source and "reject" in source.lower(),
            "fresh-index status still trusts .git/info/exclude; field authority needs a raw/build-visible workspace audit or an equivalent explicit exclusion fence",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
