#!/usr/bin/env python3
"""Exact-current regression for Final-GO control-plane worktree custody.

The fixture intentionally uses ``assume-unchanged`` to prove that ordinary clean
status is not authority for the executable control-plane bytes. Final-GO must
bind the actual no-filter worktree bytes to the exact accepted ``HEAD:<path>``
blobs before those modules can participate in physical authorization.
"""
from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Callable

MODULE = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_control_worktree", MODULE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Final-GO issuer")
go = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(go)


class ControlPlaneWorktreeCustodyTests(unittest.TestCase):
    def git(self, repo: Path, *args: str) -> str:
        return subprocess.run(
            ["/usr/bin/git", "-C", str(repo), *args],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={"PATH": "/usr/bin:/bin", "GIT_NO_REPLACE_OBJECTS": "1"},
        ).stdout.strip()

    def fixture(
        self, root: Path
    ) -> tuple[Path, str, int, Callable[[str], tuple[bytes, dict]]]:
        repo = root / "authority"
        repo.mkdir()
        self.git(repo, "init", "-q")
        self.git(repo, "config", "user.email", "capture-redteam@nembra.invalid")
        self.git(repo, "config", "user.name", "Nembra Capture Red Team")

        required_paths = (
            "scripts/ci/es80_authenticated_stationary_final_go.py",
            "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
            "scripts/ci/es80_today_final_go_publication.py",
            go.AUTH_WORKFLOW_PATH,
            "scripts/ci/tests/test_es80_authenticated_stationary_final_go.py",
        )
        for relative in required_paths:
            destination = repo / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(f"accepted bytes for {relative}\n", encoding="utf-8")

        self.git(repo, "add", ".")
        self.git(repo, "commit", "-qm", "accepted Final-GO fixture")
        source = self.git(repo, "rev-parse", "HEAD")
        main_sha = "0" * 40
        run_id = 9001
        pr_number = 2638
        branch = "control/v14-auth-stationary-final-go-sol"
        responses = {
            f"/pulls/{pr_number}": {
                "state": "open",
                "draft": False,
                "merged_at": None,
                "head": {
                    "sha": source,
                    "ref": branch,
                    "repo": {"full_name": go.REPO},
                },
                "base": {"ref": "main"},
            },
            "/branches/main": {"commit": {"sha": main_sha}},
            f"/compare/{main_sha}...{source}": {
                "status": "ahead",
                "merge_base_commit": {"sha": main_sha},
            },
            f"/actions/runs/{run_id}": {
                "name": go.AUTH_WORKFLOW_NAME,
                "path": go.AUTH_WORKFLOW_PATH,
                "head_sha": source,
                "status": "completed",
                "conclusion": "success",
                "event": "push",
                "head_branch": branch,
                "pull_requests": [],
            },
        }

        def fake_get(path: str) -> tuple[bytes, dict]:
            value = responses[path]
            return json.dumps(value).encode("utf-8"), value

        return repo, source, run_id, fake_get

    def test_hidden_signed_artifact_module_worktree_replacement_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-control-worktree-current-") as temporary:
            repo, source, run_id, fake_get = self.fixture(Path(temporary))
            accepted = go.control_plane(repo, 2638, run_id, fake_get)
            self.assertEqual(accepted["sourceCommitSHA"], source)

            target = "scripts/ci/es80_authenticated_stationary_signed_artifact.py"
            self.git(repo, "update-index", "--assume-unchanged", "--", target)
            (repo / target).write_text(
                "def retain_and_reinspect(*args, **kwargs):\n"
                "    return {'authority': 'forged-worktree-module'}\n",
                encoding="utf-8",
            )

            self.assertEqual(
                self.git(repo, "status", "--porcelain=v1", "--untracked-files=all"),
                "",
            )
            self.assertNotEqual(
                self.git(repo, "hash-object", "--no-filters", "--", target),
                self.git(repo, "rev-parse", f"HEAD:{target}"),
            )
            with self.assertRaises(
                go.GoError,
                msg="Final-GO must bind current control worktree bytes to accepted Git blobs",
            ):
                go.control_plane(repo, 2638, run_id, fake_get)


if __name__ == "__main__":
    unittest.main(verbosity=2)
