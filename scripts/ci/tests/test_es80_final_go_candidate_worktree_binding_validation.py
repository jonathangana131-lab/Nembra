#!/usr/bin/env python3
"""Independent validation for #2890 Final-GO physical-worktree binding."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
PRIVATE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_private_final_go_worktree_validation", PRIVATE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current private-review Final-GO module")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoCandidateWorktreeBindingValidation(unittest.TestCase):
    def test_physical_worktree_custody_rejects_dirty_physical_tree_hidden_by_core_worktree(self) -> None:
        base = MODULE.generated._load_base_module()
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-worktree-validation-") as temporary:
            outer = Path(temporary).resolve(strict=True)
            physical = outer / "physical"
            decoy = outer / "decoy"
            physical.mkdir()
            decoy.mkdir()

            subprocess.run(["/usr/bin/git", "-C", str(physical), "init", "-q"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(physical), "config", "user.email", "capture@nembra.invalid"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(physical), "config", "user.name", "Nembra Capture QA"], check=True)

            relative = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
            accepted = physical / relative
            accepted.parent.mkdir(parents=True, exist_ok=True)
            accepted.write_text("// accepted app source\n", encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(physical), "add", "."], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(physical), "commit", "-qm", "accepted"], check=True)
            source = subprocess.check_output(
                ["/usr/bin/git", "-C", str(physical), "rev-parse", "HEAD"], text=True
            ).strip()

            decoy_file = decoy / relative
            decoy_file.parent.mkdir(parents=True, exist_ok=True)
            decoy_file.write_text("// accepted app source\n", encoding="utf-8")
            subprocess.run(
                ["/usr/bin/git", "-C", str(physical), "config", "core.worktree", str(decoy)], check=True
            )
            accepted.write_text("// changed physical app source\n", encoding="utf-8")

            self.assertEqual(
                base.git(physical, "status", "--porcelain=v1", "--untracked-files=all"),
                "",
                "fixture must prove inherited ambient Git describes the clean decoy",
            )
            inherited_git = base.git
            inherited_git_bytes = base.git_bytes
            with MODULE._physical_worktree_git(base):
                status = base.git(physical, "status", "--porcelain=v1", "--untracked-files=all")
                self.assertIn(str(relative), status)
                with self.assertRaises(base.GoError):
                    base.candidate(physical, source)
            self.assertIs(base.git, inherited_git)
            self.assertIs(base.git_bytes, inherited_git_bytes)

    def test_final_go_build_wraps_all_candidate_authority_windows(self) -> None:
        source = PRIVATE.read_text(encoding="utf-8")
        self.assertGreaterEqual(
            source.count("with _physical_worktree_git(base):"),
            2,
            "pre/post private candidate admission must both be physically bound",
        )
        self.assertIn(
            "with _generated_extensions(review=pre_review), _physical_worktree_git(base):",
            source,
            "generated Final-GO composition must run under the same physical worktree custody",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
