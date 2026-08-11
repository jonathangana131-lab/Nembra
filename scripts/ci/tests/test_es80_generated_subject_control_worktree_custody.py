#!/usr/bin/env python3
"""Expected-red regression for generated-subject child control-plane worktree custody.

Parent #2638 already requires its authority worktree bytes to equal the accepted Git blobs and
rejects suppressed index tracking. The generated-subject child must not regress that boundary by
recording only HEAD:path blob identities while executing different hidden worktree bytes.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_final_go", MODULE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load generated-subject Final-GO child")
GO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GO)


class GeneratedSubjectControlWorktreeCustodyTests(unittest.TestCase):
    def test_hidden_child_issuer_replacement_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-generated-control-worktree-") as temporary:
            root = Path(temporary).resolve(strict=True)
            repository = root / "authority"
            repository.mkdir()
            subprocess.run(["/usr/bin/git", "-C", str(repository), "init", "-q"], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(repository), "config", "user.email", "capture@nembra.invalid"],
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "-C", str(repository), "config", "user.name", "Nembra Capture QA"],
                check=True,
            )

            authority_paths = (
                "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py",
                "scripts/ci/es80_authenticated_stationary_final_go.py",
                "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
                "scripts/ci/es80_today_final_go_publication.py",
                GO.WORKFLOW_PATH,
                "scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py",
            )
            for relative in authority_paths:
                path = repository / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f"accepted authority bytes: {relative}\n", encoding="utf-8")

            subprocess.run(["/usr/bin/git", "-C", str(repository), "add", "."], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(repository), "commit", "-qm", "accepted control fixture"],
                check=True,
            )
            source = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"],
                text=True,
            ).strip()

            base = GO._load_base_module()
            child_pr = 2744
            parent_pr = 2638
            child_run_id = 901
            parent_run_id = 900
            parent_sha = "1" * 40
            main_sha = "0" * 40
            child_branch = "control/v14-auth-stationary-generated-subject-r2-sol"

            responses = {
                f"/pulls/{child_pr}": {
                    "state": "open",
                    "draft": False,
                    "merged_at": None,
                    "head": {
                        "sha": source,
                        "ref": child_branch,
                        "repo": {"full_name": GO.REPO},
                    },
                    "base": {"ref": GO.PARENT_BRANCH, "sha": parent_sha},
                },
                f"/pulls/{parent_pr}": {
                    "state": "open",
                    "draft": False,
                    "merged_at": None,
                    "head": {
                        "sha": parent_sha,
                        "ref": GO.PARENT_BRANCH,
                        "repo": {"full_name": GO.REPO},
                    },
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
                f"/actions/runs/{parent_run_id}": {
                    "name": base.AUTH_WORKFLOW_NAME,
                    "path": base.AUTH_WORKFLOW_PATH,
                    "head_sha": parent_sha,
                    "status": "completed",
                    "conclusion": "success",
                    "event": "pull_request",
                    "head_branch": GO.PARENT_BRANCH,
                    "pull_requests": [{"number": parent_pr}],
                },
                f"/actions/runs/{child_run_id}": {
                    "name": GO.WORKFLOW_NAME,
                    "path": GO.WORKFLOW_PATH,
                    "head_sha": source,
                    "status": "completed",
                    "conclusion": "success",
                    "event": "pull_request",
                    "head_branch": child_branch,
                    "pull_requests": [{"number": child_pr}],
                },
            }

            def get(path: str):
                value = responses[path]
                return json.dumps(value, sort_keys=True).encode(), value

            issuer_relative = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
            issuer = repository / issuer_relative
            accepted_blob = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repository), "rev-parse", f"HEAD:{issuer_relative}"],
                text=True,
            ).strip()
            subprocess.run(
                ["/usr/bin/git", "-C", str(repository), "update-index", "--assume-unchanged", issuer_relative],
                check=True,
            )
            issuer.write_text("attacker-controlled child issuer bytes\n", encoding="utf-8")

            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(repository), "status", "--porcelain=v1", "--untracked-files=all"],
                    text=True,
                ),
                "",
                "fixture must prove ordinary cleanliness is blind to the suppressed replacement",
            )
            current_blob = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repository), "hash-object", "--no-filters", "--", issuer_relative],
                text=True,
            ).strip()
            self.assertNotEqual(current_blob, accepted_blob, "fixture replacement did not change issuer bytes")

            with self.assertRaises(
                GO.GeneratedSubjectGoError,
                msg=(
                    "generated-subject control authority accepted hidden current child issuer bytes "
                    "that differ from the exact accepted Git blob"
                ),
            ):
                GO.generated_control_plane(
                    repository,
                    child_pr,
                    child_run_id,
                    parent_pr=parent_pr,
                    parent_run_id=parent_run_id,
                    get=get,
                    base=base,
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
