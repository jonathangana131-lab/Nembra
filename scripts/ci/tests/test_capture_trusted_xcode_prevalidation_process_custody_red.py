#!/usr/bin/env python3
"""Expected-red witness for trusted Capture prevalidation process custody.

The trusted Xcode job currently executes repository-controlled validation code before the
authority-producing build, then audits the worktree immediately before that build. A validation
process can survive those checks and mutate tracked source after the final pre-build audit but before
Xcode consumes it. A clean check-before-use is therefore not a process-isolation boundary.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
TRUSTED_WORKFLOW = ROOT / ".github" / "workflows" / "capture-xcode27-trusted-command.yml"


def git_blob_oid(payload: bytes) -> str:
    return hashlib.sha1(
        b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    ).hexdigest()


class TrustedXcodePrevalidationProcessCustodyRedTests(unittest.TestCase):
    def test_delayed_same_uid_mutation_can_land_after_green_prebuild_audits(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            subprocess.run(["/usr/bin/git", "init", "-q", str(repo)], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(repo), "config", "user.email", "capture@example.invalid"],
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "-C", str(repo), "config", "user.name", "Capture QA"],
                check=True,
            )

            tracked = repo / "Tracked.swift"
            reviewed = b"let trustedAuthority = 1\n"
            substituted = b"let trustedAuthority = 999\n"
            tracked.write_bytes(reviewed)
            subprocess.run(["/usr/bin/git", "-C", str(repo), "add", "Tracked.swift"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(repo), "commit", "-qm", "reviewed"], check=True)
            reviewed_head = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "rev-parse", "HEAD"], text=True
            ).strip()
            expected_oid = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "rev-parse", "HEAD:Tracked.swift"], text=True
            ).strip()
            self.assertEqual(expected_oid, git_blob_oid(reviewed))

            marker = repo / ".mutation-admitted"
            attacker = subprocess.Popen(
                [
                    "/usr/bin/python3",
                    "-c",
                    (
                        "import pathlib,sys,time; "
                        "marker=pathlib.Path(sys.argv[1]); target=pathlib.Path(sys.argv[2]); "
                        "\nwhile not marker.exists(): time.sleep(0.005); "
                        "target.write_bytes(b'let trustedAuthority = 999\\n')"
                    ),
                    str(marker),
                    str(tracked),
                ]
            )
            self.addCleanup(lambda: attacker.poll() is None and attacker.kill())

            # Model the resolver-bound status check using a fresh private index.
            trusted_index = repo / ".git" / "nembra-private-index"
            env = os.environ.copy()
            env["GIT_INDEX_FILE"] = str(trusted_index)
            subprocess.run(
                ["/usr/bin/git", "-C", str(repo), "read-tree", reviewed_head],
                check=True,
                env=env,
            )
            status = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "status", "--porcelain=v1", "--untracked-files=all"],
                text=True,
                env=env,
            )
            self.assertEqual(status, "")

            # Model the raw tracked-byte audit and the producer's own clean-status admission.
            self.assertEqual(git_blob_oid(tracked.read_bytes()), expected_oid)
            producer_status = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "status", "--porcelain=v1", "--untracked-files=all"],
                text=True,
                env=env,
            )
            self.assertEqual(producer_status, "")

            # A repository-controlled process that survived earlier validation wakes only after both
            # checks have gone green. The next consumer can now observe unreviewed source bytes.
            marker.write_text("go\n", encoding="utf-8")
            attacker.wait(timeout=5)
            consumed = tracked.read_bytes()
            self.assertEqual(consumed, substituted)
            self.assertNotEqual(git_blob_oid(consumed), expected_oid)

    def test_authority_build_precedes_repository_controlled_prevalidation_in_same_job(self) -> None:
        workflow = TRUSTED_WORKFLOW.read_text(encoding="utf-8")
        authority = workflow.index("- name: Build, test, and capture Simulator states")

        repository_controlled_steps = (
            "- name: Validate project structure",
            "- name: Validate core package",
            "- name: Validate Capture package",
            "- name: Validate signed field evidence tooling",
            "- name: Validate signed field candidate producer source",
            "- name: Validate offline field authorization signer",
        )
        for step in repository_controlled_steps:
            with self.subTest(step=step):
                candidate_execution = workflow.index(step)
                self.assertLess(
                    authority,
                    candidate_execution,
                    "trusted authority build must happen before repository-controlled prevalidation "
                    "in the same runner process namespace, or those validations must move to a "
                    "separate job/runner boundary",
                )


if __name__ == "__main__":
    unittest.main()
