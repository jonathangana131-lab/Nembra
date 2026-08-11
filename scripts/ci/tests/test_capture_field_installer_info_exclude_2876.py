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


class CaptureFieldInstallerInfoExclude2876Tests(unittest.TestCase):
    def test_info_exclude_really_hides_untracked_swift_from_fresh_index_status(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-info-exclude-2876-") as temporary:
            fixture = Path(temporary)
            root = fixture / "repo"
            root.mkdir()
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
            (root / ".git/info/exclude").write_text(
                "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/Injected.swift\n",
                encoding="utf-8",
            )

            authority_index = fixture / "authority.index"
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

    def test_2876_has_independent_build_visible_filesystem_audit(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        for marker in (
            'ls-tree", "-r", "-z", source_sha',
            "raw accepted checkout blob mismatch",
            "os.walk(root, topdown=True, followlinks=False)",
            "untracked accepted-source path outside field-input allowlist",
            'field_input_directories = ("LocalSecrets", "Pods", "NembraCapture.xcworkspace")',
            'relative == "Podfile.lock"',
        ):
            self.assertIn(marker, source, f"#2876 is missing independent workspace-authority marker: {marker}")
        self.assertIn('status --porcelain=v1 --untracked-files=no', source)
        self.assertNotIn('status --porcelain=v1 --untracked-files=all', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
