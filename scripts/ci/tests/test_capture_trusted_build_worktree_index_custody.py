#!/usr/bin/env python3
"""V14 acceptance for exact-source worktree/index/process custody at trusted Xcode authority.

The frozen Simulator producer uses Git status to prove source cleanliness. Candidate-controlled
validation must never be able to hide worktree divergence behind mutable index flags, repository-
local Git metadata, ignored/untracked source, or a same-UID process that survives point-in-time
audits. The trusted workflow must bind authority to the resolver-approved commit and the real GitHub
workspace bytes before any repository-controlled validation can spawn a process in that runner.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
TRUSTED_SUBJECT = ROOT / "scripts/ci/es80_today_trusted_capture_xcode_subject.py"
AUTHORITY_STEP = "      - name: Build, test, and capture Simulator states"


class TrustedBuildWorktreeIndexCustodyTests(unittest.TestCase):
    def _initialize_fixture(self, repo: Path) -> Path:
        repo.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.email", "nembra@example.invalid"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "Nembra QA"], cwd=repo, check=True)
        source = repo / "Tracked.swift"
        source.write_text("let authority = 1\n", encoding="utf-8")
        subprocess.run(["git", "add", "Tracked.swift"], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=repo, check=True)
        return source

    def _hidden_rewrite_fixture(self, flag: str, tag: str) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            source = self._initialize_fixture(repo)
            subprocess.run(["git", "update-index", flag, "Tracked.swift"], cwd=repo, check=True)
            source.write_text("let authority = 999\n", encoding="utf-8")

            self.assertEqual(
                subprocess.check_output(
                    ["git", "status", "--porcelain=v1", "--untracked-files=all"],
                    cwd=repo,
                    text=True,
                ),
                "",
            )
            self.assertEqual(
                subprocess.check_output(["git", "ls-files", "-v", "Tracked.swift"], cwd=repo, text=True),
                f"{tag} Tracked.swift\n",
            )

    def test_assume_unchanged_attack_witness_remains_real(self) -> None:
        self._hidden_rewrite_fixture("--assume-unchanged", "h")

    def test_skip_worktree_attack_witness_remains_real(self) -> None:
        self._hidden_rewrite_fixture("--skip-worktree", "S")

    def test_info_exclude_attack_witness_remains_real(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            self._initialize_fixture(repo)
            hidden_source = repo / "Injected.swift"
            hidden_source.write_text("let injected = true\n", encoding="utf-8")
            exclude = repo / ".git" / "info" / "exclude"
            exclude.parent.mkdir(parents=True, exist_ok=True)
            with exclude.open("a", encoding="utf-8") as handle:
                handle.write("\nInjected.swift\n")

            self.assertTrue(hidden_source.is_file())
            self.assertEqual(
                subprocess.check_output(
                    ["git", "status", "--porcelain=v1", "--untracked-files=all"],
                    cwd=repo,
                    text=True,
                ),
                "",
                ".git/info/exclude can hide an untracked source from ordinary status",
            )

    def test_core_worktree_redirect_attack_witness_remains_real(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            source = self._initialize_fixture(repo)
            clean_worktree = root / "clean-worktree"
            clean_worktree.mkdir()
            shutil.copy2(source, clean_worktree / source.name)

            subprocess.run(
                ["git", "config", "core.worktree", str(clean_worktree)],
                cwd=repo,
                check=True,
            )
            source.write_text("let authority = 999\n", encoding="utf-8")

            self.assertEqual(
                subprocess.check_output(
                    ["git", "status", "--porcelain=v1", "--untracked-files=all"],
                    cwd=repo,
                    text=True,
                ),
                "",
                "repository-local core.worktree can redirect status away from the real workspace",
            )
            self.assertEqual(source.read_text(encoding="utf-8"), "let authority = 999\n")

    def test_delayed_same_uid_mutation_can_land_after_green_prebuild_audits(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            source = self._initialize_fixture(repo)
            reviewed_head = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "rev-parse", "HEAD"], text=True
            ).strip()
            expected_oid = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "rev-parse", "HEAD:Tracked.swift"], text=True
            ).strip()

            marker = repo / ".mutation-admitted"
            attacker_program = """
import pathlib
import sys
import time
marker = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
while not marker.exists():
    time.sleep(0.005)
target.write_bytes(b"let authority = 999\\n")
"""
            attacker = subprocess.Popen(
                ["/usr/bin/python3", "-c", attacker_program, str(marker), str(source)]
            )
            self.addCleanup(lambda: attacker.poll() is None and attacker.kill())

            trusted_index = repo / ".git" / "nembra-private-index"
            env = os.environ.copy()
            env["GIT_INDEX_FILE"] = str(trusted_index)
            subprocess.run(
                ["/usr/bin/git", "-C", str(repo), "read-tree", reviewed_head],
                check=True,
                env=env,
            )
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(repo), "status", "--porcelain=v1", "--untracked-files=all"],
                    text=True,
                    env=env,
                ),
                "",
            )
            self.assertEqual(
                hashlib.sha1(
                    b"blob " + str(source.stat().st_size).encode("ascii") + b"\0" + source.read_bytes()
                ).hexdigest(),
                expected_oid,
            )

            marker.write_text("go\n", encoding="utf-8")
            attacker.wait(timeout=5)
            self.assertEqual(source.read_text(encoding="utf-8"), "let authority = 999\n")
            self.assertNotEqual(
                hashlib.sha1(
                    b"blob " + str(source.stat().st_size).encode("ascii") + b"\0" + source.read_bytes()
                ).hexdigest(),
                expected_oid,
            )

    def _authority_step(self) -> str:
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(AUTHORITY_STEP, source)
        start = source.index(AUTHORITY_STEP)
        remainder = source[start + len(AUTHORITY_STEP):]
        next_step = remainder.find("\n      - name: ")
        return remainder if next_step < 0 else remainder[:next_step]

    def test_authority_build_precedes_repository_controlled_prevalidation_in_same_job(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8")
        authority = source.index(AUTHORITY_STEP)
        repository_controlled_steps = (
            "      - name: Validate project structure",
            "      - name: Validate core package",
            "      - name: Validate Capture package",
            "      - name: Validate signed field evidence tooling",
            "      - name: Validate signed field candidate producer source",
            "      - name: Validate offline field authorization signer",
        )
        for step in repository_controlled_steps:
            with self.subTest(step=step):
                self.assertLess(
                    authority,
                    source.index(step),
                    "trusted authority build must precede repository-controlled validation in the same runner namespace",
                )

    def test_authority_build_uses_fresh_resolver_bound_index(self) -> None:
        step = self._authority_step()
        self.assertIn("EXPECTED_HEAD_SHA: ${{ needs.resolve.outputs.head_sha }}", step)
        self.assertIn("GIT_INDEX_FILE=\"$trusted_index\"", step)
        self.assertRegex(step, r"/usr/bin/git\s+read-tree\s+\"\$EXPECTED_HEAD_SHA\"")
        self.assertIn("-c core.fsmonitor=false", step)
        self.assertIn("-c core.ignorestat=false", step)
        self.assertIn("-c core.filemode=true", step)
        self.assertIn("status --porcelain=v1 --untracked-files=all", step)
        self.assertIn('test -z "$trusted_status"', step)

    def test_authority_build_binds_git_to_real_workspace_and_purges_hidden_untracked_bytes(self) -> None:
        step = self._authority_step()
        self.assertIn('GIT_DIR="$GITHUB_WORKSPACE/.git"', step)
        self.assertIn('GIT_WORK_TREE="$GITHUB_WORKSPACE"', step)
        self.assertIn("core.worktree", step)
        self.assertIn("core.bare", step)
        self.assertRegex(step, r"clean\s+-ffdx")

    def test_authority_build_checks_raw_workspace_bytes_not_only_git_status(self) -> None:
        step = self._authority_step()
        self.assertIn("ls-tree", step)
        self.assertIn("hashlib.sha1", step)
        self.assertIn("blob ", step)
        self.assertIn("os.lstat", step)
        self.assertIn("raw workspace", step.lower())

    def test_pinned_producer_inherits_fresh_index_and_explicit_workspace_git_binding(self) -> None:
        step = self._authority_step()
        producer_pipe = step[step.index("/usr/bin/git cat-file blob"):]
        self.assertIn("GIT_INDEX_FILE=\"$trusted_index\"", producer_pipe)
        self.assertIn('GIT_DIR="$GITHUB_WORKSPACE/.git"', producer_pipe)
        self.assertIn('GIT_WORK_TREE="$GITHUB_WORKSPACE"', producer_pipe)
        self.assertIn("GIT_CONFIG_NOSYSTEM=1", producer_pipe)
        self.assertIn("GIT_CONFIG_GLOBAL=/dev/null", producer_pipe)
        self.assertIn("GIT_NO_REPLACE_OBJECTS=1", producer_pipe)
        self.assertIn("core.worktree", producer_pipe)
        self.assertIn("core.bare", producer_pipe)
        for key in ("core.fsmonitor", "core.ignorestat", "core.filemode"):
            self.assertIn(key, producer_pipe)

    def test_fresh_index_is_removed_on_every_shell_exit(self) -> None:
        step = self._authority_step()
        self.assertRegex(step, r'trusted_index="\$\(/usr/bin/mktemp -t nembra-capture-index\)"')
        self.assertIn("trap '/bin/rm -f -- \"$trusted_index\"' EXIT", step)

    def test_hardened_workflow_blob_is_the_exact_final_go_pin(self) -> None:
        workflow_bytes = WORKFLOW.read_bytes()
        actual_blob = hashlib.sha1(
            f"blob {len(workflow_bytes)}\0".encode("ascii") + workflow_bytes
        ).hexdigest()
        subject = TRUSTED_SUBJECT.read_text(encoding="utf-8")
        match = re.search(r'^TRUSTED_WORKFLOW_BLOB_SHA = "([0-9a-f]{40})"$', subject, re.MULTILINE)
        self.assertIsNotNone(match, "Final GO subject has no canonical trusted workflow blob pin")
        self.assertEqual(actual_blob, match.group(1))


if __name__ == "__main__":
    unittest.main()
