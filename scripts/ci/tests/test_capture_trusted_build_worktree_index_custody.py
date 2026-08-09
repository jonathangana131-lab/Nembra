#!/usr/bin/env python3
"""V14 acceptance for exact-source worktree/index custody at trusted Xcode authority.

The frozen Simulator producer uses Git status to prove source cleanliness. Candidate-controlled
validation must never be able to hide worktree divergence behind mutable index flags, repository-
local Git metadata, or ignored/untracked source. The trusted workflow must bind authority to the
resolver-approved commit *and* the real GitHub workspace bytes immediately before execution.
"""
from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
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

    def _authority_step(self) -> str:
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(AUTHORITY_STEP, source)
        start = source.index(AUTHORITY_STEP)
        remainder = source[start + len(AUTHORITY_STEP):]
        next_step = remainder.find("\n      - name: ")
        return remainder if next_step < 0 else remainder[:next_step]

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


if __name__ == "__main__":
    unittest.main()
