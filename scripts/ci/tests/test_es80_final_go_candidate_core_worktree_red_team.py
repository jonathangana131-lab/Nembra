#!/usr/bin/env python3
"""Expected-red witness for Final-GO candidate checkout/worktree authority.

A repository-local core.worktree can make Git cleanliness describe a clean decoy
while the physical candidate directory that the field build consumes contains
other modified product source. Final-GO must bind the whole candidate checkout
to the exact accepted source, not only a small set of explicitly re-hashed
control files.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
PRIVATE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_private_final_go_core_worktree_redteam", PRIVATE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current private-review Final-GO module")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoCandidateCoreWorktreeRedTeamTests(unittest.TestCase):
    def test_candidate_rejects_clean_decoy_when_physical_product_source_is_modified(self) -> None:
        base = MODULE.generated._load_base_module()
        app_source = "NembraApp/App/NembraCaptureEntrypoint.swift"
        accepted_files = {
            base.INSTALLER: (
                f'PROCEDURE_ID="{base.PROC}"\n'
                f'BUNDLE_ID="{base.BUNDLE}"\n'
                "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256\n"
                "hmac.compare_digest(actual_digest, expected_digest)\n"
            ),
            base.RUNBOOK: f"PROCEDURE_ID: `{base.PROC}`\n",
            base.IDENTITY: f'static let requiredFieldProcedureIdentifier = "{base.PROC}"\n',
            app_source: "// accepted app source\n",
        }

        with tempfile.TemporaryDirectory(prefix="nembra-final-go-core-worktree-") as temporary:
            outer = Path(temporary).resolve(strict=True)
            physical = outer / "physical-candidate"
            decoy = outer / "accepted-decoy"
            physical.mkdir()
            decoy.mkdir()

            subprocess.run(["/usr/bin/git", "-C", str(physical), "init", "-q"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(physical), "config", "user.email", "capture@nembra.invalid"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(physical), "config", "user.name", "Nembra Capture QA"], check=True)

            for relative, text in accepted_files.items():
                path = physical / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(physical), "add", "."], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(physical), "commit", "-qm", "accepted candidate"], check=True)
            source = subprocess.check_output(
                ["/usr/bin/git", "-C", str(physical), "rev-parse", "HEAD"], text=True
            ).strip()

            for relative in accepted_files:
                src = physical / relative
                dst = decoy / relative
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, dst)

            subprocess.run(
                ["/usr/bin/git", "-C", str(physical), "config", "core.worktree", str(decoy)],
                check=True,
            )
            attacked = physical / app_source
            attacked.write_text("// attacker-controlled physical app source\n", encoding="utf-8")

            self.assertEqual(
                base.git(physical, "status", "--porcelain=v1", "--untracked-files=all"),
                "",
                "fixture must prove repository-local core.worktree hides the physical source rewrite from candidate cleanliness",
            )
            self.assertNotEqual(attacked.read_bytes(), (decoy / app_source).read_bytes())

            with self.assertRaises(
                base.GoError,
                msg="Final-GO candidate authority accepted a physical product tree different from the clean Git worktree subject",
            ):
                base.candidate(physical, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
