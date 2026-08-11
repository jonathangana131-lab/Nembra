#!/usr/bin/env python3
"""Independent exact-head regressions for index metadata deception in Final-GO."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_index_metadata_redteam", PRIVATE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current Final-GO candidate authority")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoIndexMetadataRedTeamTests(unittest.TestCase):
    def _fixture(self, temporary: str):
        base = MODULE.generated._load_base_module()
        root = Path(temporary).resolve(strict=True) / "candidate"
        root.mkdir()
        subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)
        tracked = {
            base.INSTALLER: (
                "#!/bin/bash\n"
                f'PROCEDURE_ID="{base.PROC}"\n'
                f'BUNDLE_ID="{base.BUNDLE}"\n'
                "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256\n"
                "hmac.compare_digest(actual_digest, expected_digest)\n"
            ),
            base.RUNBOOK: f"PROCEDURE_ID: `{base.PROC}`\n",
            base.IDENTITY: f'static let requiredFieldProcedureIdentifier = "{base.PROC}"\n',
            "NembraApp/App/NembraCaptureEntrypoint.swift": "// accepted app source\n",
        }
        for relative, text in tracked.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
            if relative == base.INSTALLER:
                path.chmod(0o755)
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted candidate"], check=True)
        source = subprocess.check_output(["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip().lower()
        info = root / ".git" / "info"
        info.mkdir(parents=True, exist_ok=True)
        (info / "exclude").write_text("LocalSecrets/\nPods/\nNembraCapture.xcworkspace/\nPodfile.lock\n", encoding="utf-8")
        for relative in MODULE.FIELD_INPUT_DIRECTORIES:
            (root / relative).mkdir(parents=True, exist_ok=True)
        (root / "Podfile.lock").write_text("PODS:\n", encoding="utf-8")
        return base, root, source

    def test_index_flags_cannot_hide_tracked_physical_mutation(self) -> None:
        for flag in ("--assume-unchanged", "--skip-worktree"):
            with self.subTest(flag=flag):
                with tempfile.TemporaryDirectory(prefix="nembra-final-go-index-metadata-") as temporary:
                    base, root, source = self._fixture(temporary)
                    relative = "NembraApp/App/NembraCaptureEntrypoint.swift"
                    subprocess.run(["/usr/bin/git", "-C", str(root), "update-index", flag, "--", relative], check=True)
                    (root / relative).write_text("// attacker physical mutation\n", encoding="utf-8")
                    ambient = subprocess.check_output(
                        ["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
                        text=True,
                    ).strip()
                    self.assertEqual(ambient, "", f"fixture must prove {flag} hides the mutation from ambient status")
                    with self.assertRaises(MODULE.PrivateReviewGoError):
                        with MODULE._candidate_git_custody(base, root, source):
                            self.fail(f"Final-GO admitted tracked physical mutation hidden by {flag}")

    def test_candidate_custody_does_not_delegate_whole_tree_truth_to_external_status(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-no-status-") as temporary:
            base, root, source = self._fixture(temporary)
            original_run = MODULE.subprocess.run
            git_commands: list[tuple[str, ...]] = []

            def recording_run(command, *args, **kwargs):
                if isinstance(command, (list, tuple)) and command and command[0] == "/usr/bin/git":
                    git_commands.append(tuple(str(item) for item in command))
                return original_run(command, *args, **kwargs)

            MODULE.subprocess.run = recording_run
            try:
                with MODULE._candidate_git_custody(base, root, source):
                    base.candidate(root, source)
            finally:
                MODULE.subprocess.run = original_run
            self.assertFalse(any("status" in command for command in git_commands))
            self.assertTrue(
                any("cat-file" in command for command in git_commands),
                "fixture did not exercise verified accepted-object authority",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
