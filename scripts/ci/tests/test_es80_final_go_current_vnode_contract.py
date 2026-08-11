#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
from types import SimpleNamespace
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("private_review_final_go_current_vnode", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current private-review Final-GO module")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoCurrentVnodeContractTests(unittest.TestCase):
    def _initialize_generated_candidate(self, root: Path, *, current: bool):
        generated = MODULE.generated
        base = generated._load_base_module()
        vnode_path = (
            MODULE.CURRENT_VNODE_WORKFLOW_PATH
            if current
            else MODULE.RETIRED_VNODE_WORKFLOW_PATH
        )
        vnode_name = (
            MODULE.CURRENT_VNODE_WORKFLOW
            if current
            else MODULE.RETIRED_VNODE_WORKFLOW
        )
        tracked = {
            "Scripts/bootstrap_capture_tuya_sdk.sh": (
                generated.GENERATED_ENV + "\n"
                "capture_cocoapods_generated_build_subject.py\n"
            ),
            generated.GENERATED_HELPER_PATH: generated.GENERATED_SCHEMA + "\n",
            "Scripts/capture_tuya_private_input_provenance.py": "# provenance helper\n",
            "Scripts/capture_tuya_private_input_build_guard.py": (
                "capture_cocoapods_generated_build_subject.py\n"
                "_verify_accepted_generated_build_subject\n"
                "require_accepted_generated_subject=True\n"
                "_require_real_checkout_ancestry\n"
                "_ensure_fd_budget\n"
                "KQ_NOTE_ATTRIB\n"
            ),
            "scripts/field/install_one_time_capture.command": (
                "bootstrap_capture_tuya_sdk.sh\n"
                "capture_tuya_private_input_build_guard.py\n"
            ),
            generated.GENERATED_BUILD_WORKFLOW_PATH: (
                "name: Capture CocoaPods Build Subject Authority\n"
                "Require exact generated CocoaPods build authority\n"
                "test_capture_private_input_ancestor_retarget.py\n"
            ),
            vnode_path: (
                f"name: {vnode_name}\n"
                "Real macOS chmod vnode evidence\n"
                "runs-on: macos-15\n"
            ),
        }
        subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)
        for relative, text in tracked.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "generated candidate"], check=True)
        source = subprocess.check_output(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
        ).strip().lower()
        return base, source

    def test_current_vnode_candidate_is_admitted_without_retired_alias(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-vnode-current-") as temporary:
            root = Path(temporary).resolve(strict=True)
            base, source = self._initialize_generated_candidate(root, current=True)
            accepted = "ab" * 32
            result = MODULE._current_generated_candidate_authority(
                root,
                source,
                accepted,
                base=base,
                derive_subject=lambda *_args: accepted,
            )
            self.assertIn(MODULE.CURRENT_VNODE_WORKFLOW, result["requiredCandidateWorkflows"])
            self.assertNotIn(MODULE.RETIRED_VNODE_WORKFLOW, result["requiredCandidateWorkflows"])
            self.assertIn(MODULE.CURRENT_VNODE_WORKFLOW_PATH, result["gitBlobs"])
            self.assertNotIn(MODULE.RETIRED_VNODE_WORKFLOW_PATH, result["gitBlobs"])

    def test_retired_convergence_only_candidate_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-vnode-retired-") as temporary:
            root = Path(temporary).resolve(strict=True)
            base, source = self._initialize_generated_candidate(root, current=False)
            accepted = "ab" * 32
            with self.assertRaises(MODULE.generated.GeneratedSubjectGoError):
                MODULE._current_generated_candidate_authority(
                    root,
                    source,
                    accepted,
                    base=base,
                    derive_subject=lambda *_args: accepted,
                )

    def test_semantic_fragments_are_bound_to_accepted_git_bytes(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-vnode-git-bytes-") as temporary:
            root = Path(temporary).resolve(strict=True)
            base, source = self._initialize_generated_candidate(root, current=True)
            accepted = "ab" * 32
            original_read_text = Path.read_text
            original_git_bytes = base.git_bytes
            seen: set[str] = set()

            def forbidden_read_text(subject: Path, *args, **kwargs):
                if subject == root or root in subject.parents:
                    raise AssertionError("current vnode semantic authority reopened worktree text")
                return original_read_text(subject, *args, **kwargs)

            def recording_git_bytes(repo: Path, *args: str):
                if len(args) == 2 and args[0] == "show":
                    seen.add(args[1])
                return original_git_bytes(repo, *args)

            Path.read_text = forbidden_read_text
            base.git_bytes = recording_git_bytes
            try:
                result = MODULE._current_generated_candidate_authority(
                    root,
                    source,
                    accepted,
                    base=base,
                    derive_subject=lambda *_args: accepted,
                )
            finally:
                base.git_bytes = original_git_bytes
                Path.read_text = original_read_text

            expected = {f"{source}:{relative}" for relative in MODULE.CURRENT_GENERATED_AUTHORITY_PATHS}
            self.assertEqual(seen, expected)
            self.assertEqual(result[MODULE.generated.GENERATED_KEY], accepted)

    def test_current_adapter_changes_only_vnode_contract_and_restores_parent(self):
        generated = MODULE.generated
        original = (
            generated.VNODE_WORKFLOW,
            generated.VNODE_WORKFLOW_PATH,
            generated.GENERATED_ACCEPTANCE_WORKFLOWS,
            generated.GENERATED_AUTHORITY_PATHS,
            generated.candidate_generated_authority,
        )
        base = SimpleNamespace(WORKFLOWS=("Base Gate",), WORKFLOW_PATHS={"Base Gate": "base.yml"})
        with MODULE._current_vnode_authority():
            self.assertEqual(generated.VNODE_WORKFLOW, MODULE.CURRENT_VNODE_WORKFLOW)
            self.assertEqual(generated.VNODE_WORKFLOW_PATH, MODULE.CURRENT_VNODE_WORKFLOW_PATH)
            self.assertIs(generated.candidate_generated_authority, MODULE._current_generated_candidate_authority)
            self.assertIn(
                (MODULE.CURRENT_VNODE_WORKFLOW, MODULE.CURRENT_VNODE_WORKFLOW_PATH),
                generated.GENERATED_ACCEPTANCE_WORKFLOWS,
            )
            self.assertNotIn(
                (MODULE.RETIRED_VNODE_WORKFLOW, MODULE.RETIRED_VNODE_WORKFLOW_PATH),
                generated.GENERATED_ACCEPTANCE_WORKFLOWS,
            )
            self.assertIn(MODULE.CURRENT_VNODE_WORKFLOW_PATH, generated.GENERATED_AUTHORITY_PATHS)
            self.assertNotIn(MODULE.RETIRED_VNODE_WORKFLOW_PATH, generated.GENERATED_AUTHORITY_PATHS)
            with generated._candidate_workflow_requirements(base):
                self.assertIn(MODULE.CURRENT_VNODE_WORKFLOW, base.WORKFLOWS)
                self.assertNotIn(MODULE.RETIRED_VNODE_WORKFLOW, base.WORKFLOWS)
                self.assertEqual(base.WORKFLOW_PATHS[MODULE.CURRENT_VNODE_WORKFLOW], MODULE.CURRENT_VNODE_WORKFLOW_PATH)
            self.assertEqual(base.WORKFLOWS, ("Base Gate",))
            self.assertEqual(base.WORKFLOW_PATHS, {"Base Gate": "base.yml"})
        self.assertEqual(
            (
                generated.VNODE_WORKFLOW,
                generated.VNODE_WORKFLOW_PATH,
                generated.GENERATED_ACCEPTANCE_WORKFLOWS,
                generated.GENERATED_AUTHORITY_PATHS,
                generated.candidate_generated_authority,
            ),
            original,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
