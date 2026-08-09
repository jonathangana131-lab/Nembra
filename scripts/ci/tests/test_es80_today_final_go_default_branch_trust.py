#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"
spec = importlib.util.spec_from_file_location("final_go", MODULE_PATH)
final_go = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(final_go)


class FinalGoDefaultBranchTrustTests(unittest.TestCase):
    SOURCE = "a" * 40
    WORKFLOW_SOURCE = "b" * 40
    RUN_ID = 123456
    JOB_ID = 654321
    ARTIFACT_ID = 777777
    PR = 833
    INSTANCE = "11111111-2222-3333-4444-555555555555"

    def make_archive(self, root: Path) -> tuple[Path, str, int]:
        archive_path = root / "xcode.zip"
        record = {
            "schemaVersion": 3,
            "buildIdentifier": "Capture Build V14-" + self.SOURCE[:12],
            "buildInstanceID": self.INSTANCE,
            "sourceCommitSHA": self.SOURCE,
            "executableSHA256": "c" * 64,
            "infoPlistSHA256": "d" * 64,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
        }
        raw = (json.dumps(record, sort_keys=True) + "\n").encode()
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(final_go.EXTERNAL_RECORD_NAME, raw)
        archive_raw = archive_path.read_bytes()
        return archive_path, hashlib.sha256(archive_raw).hexdigest(), len(archive_raw)

    def pr_controlled_github(self, archive_sha: str, archive_size: int):
        # This reproduces the currently accepted authority shape: a same-repository
        # pull_request workflow whose definition may itself come from the candidate
        # PR. Exact source/artifact matching does not make that workflow definition
        # an independent trusted authority.
        run = {
            "id": self.RUN_ID,
            "name": "Xcode 27 PR Exact-Head QA",
            "path": ".github/workflows/xcode27-pr-command.yml",
            "event": "pull_request",
            "head_sha": self.SOURCE,
            "status": "completed",
            "conclusion": "success",
            "run_attempt": 1,
            "run_number": 42,
            "repository": {"full_name": final_go.REPOSITORY},
            "head_repository": {"full_name": final_go.REPOSITORY},
            "pull_requests": [{"number": self.PR}],
        }
        required = [
            "Reject stale PR head before scarce Mac work",
            "Verify immutable PR head",
            "Build, test, and capture Simulator states",
            "Verify retained Capture build evidence",
            "Reject head movement before acceptance completion",
        ]
        job = {
            "id": self.JOB_ID,
            "run_id": self.RUN_ID,
            "run_attempt": 1,
            "workflow_name": "Xcode 27 PR Exact-Head QA",
            "name": "Build, test, and capture exact PR head",
            "head_sha": self.SOURCE,
            "status": "completed",
            "conclusion": "success",
            "labels": ["xcode-27"],
            "run_url": f"https://api.github.com/repos/{final_go.REPOSITORY}/actions/runs/{self.RUN_ID}",
            "url": f"https://api.github.com/repos/{final_go.REPOSITORY}/actions/jobs/{self.JOB_ID}",
            "steps": [{"name": name, "conclusion": "success"} for name in required],
        }
        artifact = {
            "id": self.ARTIFACT_ID,
            "name": f"nembra-xcode27-pr-{self.PR}-42-1",
            "expired": False,
            "digest": f"sha256:{archive_sha}",
            "size_in_bytes": archive_size,
            "workflow_run": {"id": self.RUN_ID, "head_sha": self.SOURCE},
        }
        records = {
            f"/actions/runs/{self.RUN_ID}": run,
            f"/actions/jobs/{self.JOB_ID}": job,
            f"/actions/artifacts/{self.ARTIFACT_ID}": artifact,
        }

        def get(path: str):
            value = records[path]
            return json.dumps(value, sort_keys=True).encode(), value

        return get

    def test_pr_controlled_exact_head_workflow_is_not_final_go_authority(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, archive_sha, archive_size = self.make_archive(root)
            github = self.pr_controlled_github(archive_sha, archive_size)

            with self.assertRaises(
                final_go.FinalGoError,
                msg=(
                    "A candidate PR must not be able to manufacture its own trusted Xcode "
                    "authority merely by preserving expected workflow/job/step names."
                ),
            ):
                final_go._trusted_xcode_subject(
                    source=self.SOURCE,
                    expected_pr_number=self.PR,
                    run_id=self.RUN_ID,
                    job_id=self.JOB_ID,
                    artifact_id=self.ARTIFACT_ID,
                    artifact_archive_path=archive,
                    github_get_json=github,
                )

    def test_canonical_trusted_subject_is_default_branch_capture_command(self):
        self.assertEqual(
            final_go.TRUSTED_WORKFLOW_NAME,
            "Capture Trusted Xcode 27 Exact-Head QA",
        )
        self.assertEqual(
            final_go.TRUSTED_WORKFLOW_PATH,
            ".github/workflows/capture-xcode27-trusted-command.yml",
        )
        self.assertEqual(
            final_go.TRUSTED_JOB_NAME,
            "Build, test, and capture trusted exact Capture head",
        )
        self.assertEqual(final_go.TRUSTED_ARTIFACT_PREFIX, "nembra-capture-xcode27-")


if __name__ == "__main__":
    unittest.main()
