#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go_2709.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_final_go_2709", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load selected generated-subject Final-GO adapter")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SOURCE = "1" * 40
DIGEST = "ab" * 32
BLOB = "2" * 40


class AdapterTests(unittest.TestCase):
    def test_selected_helper_cli_has_no_superseded_digest_subcommand(self):
        observed = {}

        def fake_run(command, **kwargs):
            observed["command"] = list(command)
            observed["kwargs"] = kwargs
            return SimpleNamespace(returncode=0, stdout=DIGEST + "\n", stderr="")

        with mock.patch.object(MODULE.subprocess, "run", side_effect=fake_run):
            value = MODULE._current_generated_subject(Path("/candidate"))
        self.assertEqual(value, DIGEST)
        command = observed["command"]
        self.assertIn("/candidate/Scripts/capture_cocoapods_generated_build_subject.py", command)
        self.assertNotIn("digest", command)
        self.assertEqual(command[-6:], [
            "--lockfile", "/candidate/Podfile.lock",
            "--pods", "/candidate/Pods",
            "--workspace", "/candidate/NembraCapture.xcworkspace",
        ])
        self.assertEqual(observed["kwargs"]["env"], {"PATH": "/usr/bin:/bin"})

    def _candidate_contents(self) -> dict[str, str]:
        return {
            "Scripts/bootstrap_capture_tuya_sdk.sh": (
                MODULE.core.GENERATED_ENV
                + "\ncapture_cocoapods_generated_build_subject.py\n"
            ),
            MODULE.GENERATED_HELPER_PATH: MODULE.GENERATED_SCHEMA + "\n",
            "Scripts/capture_tuya_private_input_provenance.py": "provenance\n",
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
            MODULE.GENERATED_BUILD_WORKFLOW_PATH: (
                "Require exact generated CocoaPods build authority\n"
                "test_capture_private_input_ancestor_retarget.py\n"
            ),
            MODULE.VNODE_WORKFLOW_PATH: (
                "Real macOS chmod vnode evidence\n"
                "macos-15\n"
            ),
        }

    def _candidate_base(self, root: Path):
        def fake_git(repo, *args):
            self.assertEqual(repo, root)
            if args == ("rev-parse", "HEAD"):
                return SOURCE
            if args == ("status", "--porcelain=v1", "--untracked-files=all"):
                return ""
            if args[0] == "rev-parse" and args[1].startswith("HEAD:"):
                return BLOB
            if args[:3] == ("hash-object", "--no-filters", "--"):
                return BLOB
            raise AssertionError(args)

        return SimpleNamespace(canon=MODULE.core._load_base_module().canon, git=fake_git)

    def test_candidate_authority_requires_converged_guard_and_workflow_sources(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-2709-") as temporary:
            root = Path(temporary)
            contents = self._candidate_contents()
            for relative, content in contents.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")

            base = self._candidate_base(root)
            result = MODULE.candidate_generated_authority(
                root,
                SOURCE,
                DIGEST,
                base=base,
                derive_subject=lambda _: DIGEST,
            )
            self.assertEqual(result["implementation"], MODULE.GENERATED_HELPER_PATH)
            self.assertEqual(result[MODULE.core.GENERATED_KEY], DIGEST)
            self.assertEqual(set(result["gitBlobs"]), set(MODULE.GENERATED_AUTHORITY_PATHS))

            guard = root / "Scripts/capture_tuya_private_input_build_guard.py"
            accepted_guard = guard.read_text(encoding="utf-8")
            guard.write_text(accepted_guard.replace("KQ_NOTE_ATTRIB\n", ""), encoding="utf-8")
            with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
                MODULE.candidate_generated_authority(
                    root,
                    SOURCE,
                    DIGEST,
                    base=base,
                    derive_subject=lambda _: DIGEST,
                )

            guard.write_text(accepted_guard, encoding="utf-8")
            with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
                MODULE.candidate_generated_authority(
                    root,
                    SOURCE,
                    DIGEST,
                    base=base,
                    derive_subject=lambda _: "cd" * 32,
                )

    def test_candidate_workflow_requirements_extend_exact_parent_set_and_restore(self):
        parent = MODULE.core._load_base_module()
        original_workflows = parent.WORKFLOWS
        original_paths = parent.WORKFLOW_PATHS
        with MODULE._candidate_workflow_requirements(parent):
            for name, path in MODULE.GENERATED_ACCEPTANCE_WORKFLOWS:
                self.assertIn(name, parent.WORKFLOWS)
                self.assertEqual(parent.WORKFLOW_PATHS[name], path)
            self.assertEqual(
                set(parent.WORKFLOWS),
                set(original_workflows) | {name for name, _ in MODULE.GENERATED_ACCEPTANCE_WORKFLOWS},
            )
        self.assertIs(parent.WORKFLOWS, original_workflows)
        self.assertIs(parent.WORKFLOW_PATHS, original_paths)

    def test_candidate_workflow_requirements_fail_closed_on_path_collision(self):
        parent = MODULE.core._load_base_module()
        parent.WORKFLOWS = (*parent.WORKFLOWS, MODULE.GENERATED_BUILD_WORKFLOW)
        parent.WORKFLOW_PATHS = {
            **parent.WORKFLOW_PATHS,
            MODULE.GENERATED_BUILD_WORKFLOW: ".github/workflows/wrong.yml",
        }
        with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
            with MODULE._candidate_workflow_requirements(parent):
                pass

    def test_adapter_keeps_current_parent_sealed_installer_identity(self):
        parent = MODULE.core._load_base_module()
        sealed_installer = parent.installer
        original_environment = parent.installer_environment
        saved_candidate = MODULE.core.candidate_generated_authority
        saved_control = MODULE.core.generated_control_plane
        saved_build = MODULE.core.build

        def review_adapter(*args, **kwargs):
            del args, kwargs
            return {"authority": MODULE.core.REVIEW_AUTHORITY}

        with MODULE.core._parent_extensions(
            parent,
            accepted_generated_digest=DIGEST,
            review_adapter=review_adapter,
        ):
            self.assertIs(parent.installer, sealed_installer)
            self.assertIs(parent.installer.__globals__["installer_environment"], parent.installer_environment)
            self.assertIsNot(parent.installer_environment, original_environment)
            with MODULE._install_adapter():
                self.assertIs(parent.installer, sealed_installer)
                self.assertIs(MODULE.core.candidate_generated_authority, MODULE.candidate_generated_authority)
                self.assertIs(MODULE.core.generated_control_plane, MODULE.generated_control_plane)
                self.assertIs(MODULE.core.build, MODULE.build)
                self.assertIs(parent.installer.__globals__["installer_environment"], parent.installer_environment)

        self.assertIs(parent.installer, sealed_installer)
        self.assertIs(parent.installer_environment, original_environment)
        self.assertIs(MODULE.core.candidate_generated_authority, saved_candidate)
        self.assertIs(MODULE.core.generated_control_plane, saved_control)
        self.assertIs(MODULE.core.build, saved_build)

    def test_build_requires_and_retains_generated_workflow_acceptance(self):
        observed = {}

        def fake_core_build(*args, **kwargs):
            del args
            base = kwargs["base_module"]
            observed["derive_subject"] = kwargs["derive_subject"]
            observed["workflows_during_build"] = base.WORKFLOWS
            software = [
                {"name": name, "path": base.WORKFLOW_PATHS[name]}
                for name in base.WORKFLOWS
            ]
            return {
                "generatedBuildSubjectCandidate": {
                    "implementation": MODULE.GENERATED_HELPER_PATH,
                },
                "softwareAcceptance": software,
            }

        parent = MODULE.core._load_base_module()
        original_workflows = parent.WORKFLOWS
        original_paths = parent.WORKFLOW_PATHS
        with mock.patch.object(MODULE, "_ORIGINAL_BUILD", side_effect=fake_core_build):
            result = MODULE.build(base_module=parent)
        self.assertIs(observed["derive_subject"], MODULE._current_generated_subject)
        for name, _ in MODULE.GENERATED_ACCEPTANCE_WORKFLOWS:
            self.assertIn(name, observed["workflows_during_build"])
            self.assertIn(name, result["requiredGeneratedBuildWorkflowAcceptance"])
        self.assertIs(parent.WORKFLOWS, original_workflows)
        self.assertIs(parent.WORKFLOW_PATHS, original_paths)

    def test_build_rejects_record_that_drops_generated_workflow_acceptance(self):
        parent = MODULE.core._load_base_module()

        def fake_core_build(*args, **kwargs):
            del args, kwargs
            return {
                "generatedBuildSubjectCandidate": {
                    "implementation": MODULE.GENERATED_HELPER_PATH,
                },
                "softwareAcceptance": [],
            }

        with mock.patch.object(MODULE, "_ORIGINAL_BUILD", side_effect=fake_core_build):
            with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
                MODULE.build(base_module=parent)


if __name__ == "__main__":
    unittest.main(verbosity=2)
