#!/usr/bin/env python3
"""Expected-red witnesses for Final-GO physical candidate tree authority.

The current R4 recovery pins Git to the physical checkout, but still inherits a
candidate contract whose cleanliness decision comes from `git status`. Local Git
metadata is not accepted product authority: physical build-visible bytes must be
compared directly with the exact accepted tree instead.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
PRIVATE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_private_final_go_raw_tree_redteam", PRIVATE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current private-review Final-GO module")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoCandidateRawTreeRedTeamTests(unittest.TestCase):
    def _candidate_fixture(self, temporary: str):
        base = MODULE.generated._load_base_module()
        root = Path(temporary).resolve(strict=True) / "candidate"
        root.mkdir()
        subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)

        accepted_files = {
            base.INSTALLER: (
                f'PROCEDURE_ID="{base.PROC}"\n'
                f'BUNDLE_ID="{base.BUNDLE}"\n'
                "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256\n"
                "hmac.compare_digest(actual_digest, expected_digest)\n"
            ),
            base.RUNBOOK: f"PROCEDURE_ID: `{base.PROC}`\n",
            base.IDENTITY: f'static let requiredFieldProcedureIdentifier = "{base.PROC}"\n',
            "NembraApp/App/NembraCaptureEntrypoint.swift": "// accepted app source\n",
        }
        for relative, text in accepted_files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted candidate"], check=True)
        source = subprocess.check_output(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
        ).strip()
        return base, root, source

    def test_candidate_rejects_product_source_hidden_by_repository_local_exclude_metadata(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-raw-tree-") as temporary:
            base, root, source = self._candidate_fixture(temporary)
            hidden_relative = "NembraApp/App/Injected.swift"
            info_exclude = root / ".git" / "info" / "exclude"
            with info_exclude.open("a", encoding="utf-8") as handle:
                handle.write(f"\n/{hidden_relative}\n")
            hidden = root / hidden_relative
            hidden.write_text("// unaccepted build-visible product source\n", encoding="utf-8")

            with MODULE._physical_worktree_git(base):
                self.assertEqual(
                    base.git(root, "status", "--porcelain=v1", "--untracked-files=all"),
                    "",
                    "fixture must prove repository-local exclude metadata hides the physical source from status",
                )
                with self.assertRaises(
                    base.GoError,
                    msg="Final-GO candidate authority accepted physical product bytes absent from the accepted Git tree",
                ):
                    base.candidate(root, source)

    def test_candidate_truth_does_not_depend_on_git_status(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-status-authority-") as temporary:
            base, root, source = self._candidate_fixture(temporary)
            original_physical_git = MODULE._physical_git
            calls: list[tuple[str, ...]] = []

            def recording_git(repo: Path, *args: str) -> str:
                calls.append(tuple(args))
                return original_physical_git(repo, *args)

            MODULE._physical_git = recording_git
            try:
                with MODULE._physical_worktree_git(base):
                    base.candidate(root, source)
            finally:
                MODULE._physical_git = original_physical_git

            self.assertFalse(
                any(args and args[0] == "status" for args in calls),
                "Final-GO candidate truth still delegates whole-tree authority to repository-local Git status",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
