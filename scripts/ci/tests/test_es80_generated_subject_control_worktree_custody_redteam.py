#!/usr/bin/env python3
"""Adversarial proof that generated-subject child authority must bind current worktree bytes."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ADAPTER_PATH = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go_2709.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_worktree_redteam", ADAPTER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load generated-subject Final-GO adapter")
adapter = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = adapter
SPEC.loader.exec_module(adapter)
base = adapter.core._load_base_module()


def git(repo: Path, *args: str) -> str:
    environment = {"PATH": "/usr/bin:/bin", "GIT_NO_REPLACE_OBJECTS": "1"}
    return subprocess.run(
        ["/usr/bin/git", "-C", str(repo), *args],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
    ).stdout.strip()


class GeneratedSubjectControlWorktreeCustodyRedTeam(unittest.TestCase):
    def test_hidden_child_authority_module_replacement_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-generated-child-worktree-") as temporary:
            repo = Path(temporary)
            git(repo, "init", "-q")
            git(repo, "config", "user.name", "nembra-redteam")
            git(repo, "config", "user.email", "nembra-redteam@invalid.example")

            authority_paths = (
                "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py",
                "scripts/ci/es80_authenticated_stationary_generated_subject_final_go_2709.py",
                "scripts/ci/es80_authenticated_stationary_final_go.py",
                "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
                "scripts/ci/es80_today_final_go_publication.py",
                adapter.core.WORKFLOW_PATH,
                "scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py",
            )
            for relative in authority_paths:
                path = repo / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f"accepted bytes for {relative}\n", encoding="utf-8")
            git(repo, "add", ".")
            git(repo, "commit", "-qm", "accepted generated-subject control fixture")
            source = git(repo, "rev-parse", "HEAD")

            parent_sha = "2" * 40
            main_sha = "3" * 40
            child_pr = 2744
            parent_pr = 2638
            child_run = 220
            parent_run = 110
            branch = "control/v14-auth-stationary-generated-subject-r2-sol"

            responses = {
                f"/pulls/{child_pr}": {
                    "state": "open",
                    "draft": False,
                    "merged_at": None,
                    "head": {"sha": source, "ref": branch, "repo": {"full_name": adapter.core.REPO}},
                    "base": {"sha": parent_sha, "ref": adapter.core.PARENT_BRANCH},
                },
                f"/pulls/{parent_pr}": {
                    "state": "open",
                    "draft": False,
                    "merged_at": None,
                    "head": {"sha": parent_sha, "ref": adapter.core.PARENT_BRANCH, "repo": {"full_name": adapter.core.REPO}},
                    "base": {"ref": "main"},
                },
                "/branches/main": {"commit": {"sha": main_sha}},
                f"/compare/{main_sha}...{parent_sha}": {
                    "status": "ahead",
                    "merge_base_commit": {"sha": main_sha},
                },
                f"/compare/{parent_sha}...{source}": {
                    "status": "ahead",
                    "merge_base_commit": {"sha": parent_sha},
                },
                f"/actions/runs/{parent_run}": {
                    "name": base.AUTH_WORKFLOW_NAME,
                    "path": base.AUTH_WORKFLOW_PATH,
                    "head_sha": parent_sha,
                    "status": "completed",
                    "conclusion": "success",
                    "event": "push",
                    "head_branch": adapter.core.PARENT_BRANCH,
                    "pull_requests": [],
                },
                f"/actions/runs/{child_run}": {
                    "name": adapter.core.WORKFLOW_NAME,
                    "path": adapter.core.WORKFLOW_PATH,
                    "head_sha": source,
                    "status": "completed",
                    "conclusion": "success",
                    "event": "pull_request",
                    "head_branch": branch,
                    "pull_requests": [{"number": child_pr}],
                },
            }

            def get(path: str):
                return json.dumps(responses[path]).encode("utf-8"), responses[path]

            baseline = adapter.generated_control_plane(
                repo,
                child_pr,
                child_run,
                parent_pr=parent_pr,
                parent_run_id=parent_run,
                get=get,
                base=base,
            )
            self.assertEqual(baseline["sourceCommitSHA"], source)

            target = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
            git(repo, "update-index", "--assume-unchanged", "--", target)
            (repo / target).write_text(
                "def forged_authority():\n    return 'attacker-controlled-current-bytes'\n",
                encoding="utf-8",
            )
            self.assertEqual(git(repo, "status", "--porcelain=v1", "--untracked-files=all"), "")
            self.assertNotEqual(
                git(repo, "hash-object", "--no-filters", "--", target),
                git(repo, "rev-parse", f"HEAD:{target}"),
            )

            with self.assertRaises(
                adapter.core.GeneratedSubjectGoError,
                msg=(
                    "generated-subject Final-GO child accepted hidden current authority bytes "
                    "that differ from its recorded HEAD blob"
                ),
            ):
                adapter.generated_control_plane(
                    repo,
                    child_pr,
                    child_run,
                    parent_pr=parent_pr,
                    parent_run_id=parent_run,
                    get=get,
                    base=base,
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
