#!/usr/bin/env python3
from __future__ import annotations

import json
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
PRIVATE = "cd" * 32
BLOB = "2" * 40


class AdapterTests(unittest.TestCase):
    def test_selected_generated_helper_cli_has_no_superseded_digest_subcommand(self):
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

    def test_private_review_helper_rebinds_only_the_opaque_accepted_commitment(self):
        observed = {}

        def fake_run(command, **kwargs):
            observed["command"] = list(command)
            observed["kwargs"] = kwargs
            return SimpleNamespace(returncode=0, stdout=PRIVATE + "\n", stderr="")

        with mock.patch.object(MODULE.subprocess, "run", side_effect=fake_run):
            value = MODULE._current_private_commitment(Path("/candidate"), PRIVATE)
        self.assertEqual(value, PRIVATE)
        command = observed["command"]
        self.assertIn("/candidate/Scripts/capture_tuya_private_input_review.py", command)
        self.assertIn("verify", command)
        self.assertIn("--accepted-commitment", command)
        self.assertEqual(command[command.index("--accepted-commitment") + 1], PRIVATE)
        self.assertIn("/candidate/LocalSecrets/TuyaRuntime/PrivateInputReviewKey.bin", command)
        self.assertNotIn("AppKey", " ".join(command))
        self.assertNotIn("AppSecret", " ".join(command))
        self.assertEqual(observed["kwargs"]["env"], {"PATH": "/usr/bin:/bin"})

        for invalid in (PRIVATE.upper(), "a" * 63, "g" * 64):
            with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
                MODULE._current_private_commitment(Path("/candidate"), invalid)

    def _candidate_contents(self) -> dict[str, str]:
        return {
            "Scripts/bootstrap_capture_tuya_sdk.sh": (
                MODULE.core.GENERATED_ENV
                + "\n"
                + MODULE.PRIVATE_ENV
                + "\ncapture_cocoapods_generated_build_subject.py\n"
                + "capture_tuya_private_input_review.py\n"
            ),
            MODULE.GENERATED_HELPER_PATH: MODULE.GENERATED_SCHEMA + "\n",
            "Scripts/capture_tuya_private_input_provenance.py": "provenance\n",
            MODULE.PRIVATE_HELPER_PATH: MODULE.PRIVATE_SCHEMA + "\n",
            "Scripts/capture_tuya_private_input_build_guard.py": (
                "capture_cocoapods_generated_build_subject.py\n"
                "capture_tuya_private_input_review.py\n"
                "_verify_accepted_generated_build_subject\n"
                "_verify_accepted_private_input_subject\n"
                "require_accepted_generated_subject=True\n"
                "require_accepted_private_subject=True\n"
                "_authority_bound_initial_snapshot\n"
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
            MODULE.PRIVATE_REVIEW_WORKFLOW_PATH: (
                "Bind reviewed private generation before field build\n"
                "test_capture_private_input_review_authority_closure.py\n"
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

    def test_candidate_source_requires_generated_private_ancestry_and_vnode_authority(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-private-") as temporary:
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

            private = MODULE.candidate_private_authority(
                root,
                SOURCE,
                PRIVATE,
                base=base,
                verify_private=lambda _root, accepted: accepted,
            )
            self.assertEqual(private[MODULE.PRIVATE_KEY], PRIVATE)
            self.assertEqual(private["implementation"], MODULE.PRIVATE_HELPER_PATH)

            guard = root / "Scripts/capture_tuya_private_input_build_guard.py"
            accepted_guard = guard.read_text(encoding="utf-8")
            for fragment in ("KQ_NOTE_ATTRIB\n", "require_accepted_private_subject=True\n"):
                guard.write_text(accepted_guard.replace(fragment, ""), encoding="utf-8")
                with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
                    MODULE.candidate_generated_authority(
                        root,
                        SOURCE,
                        DIGEST,
                        base=base,
                        derive_subject=lambda _: DIGEST,
                    )
                guard.write_text(accepted_guard, encoding="utf-8")

    def _visual(self):
        return {
            "runID": 11,
            "artifactID": 12,
            "screenshots": {
                "unprovisioned-dark-standard": {"sha256": "11" * 32},
                "unprovisioned-dark-accessibility-xxxl": {"sha256": "22" * 32},
            },
        }

    def _review_get(self, payload: dict[str, object]):
        body = json.dumps(payload, sort_keys=True)

        def get(path: str):
            self.assertEqual(path, "/pulls/7/reviews/9")
            return b"", {
                "id": 9,
                "node_id": "review-node",
                "body": body,
                "state": "APPROVED",
                "commit_id": SOURCE,
                "user": {"login": MODULE.core.OWNER},
                "author_association": "OWNER",
                "submitted_at": "2026-08-11T04:00:00Z",
            }

        return get

    def _review_payload(self):
        visual = self._visual()
        return {
            "schemaVersion": 4,
            "authority": MODULE.REVIEW_AUTHORITY,
            "sourceCommitSHA": SOURCE,
            "visualRunID": visual["runID"],
            "visualArtifactID": visual["artifactID"],
            "standardScreenshotSHA256": visual["screenshots"]["unprovisioned-dark-standard"]["sha256"],
            "accessibilityScreenshotSHA256": visual["screenshots"]["unprovisioned-dark-accessibility-xxxl"]["sha256"],
            "tuyaDependencyLockSHA256": "33" * 32,
            MODULE.core.GENERATED_KEY: DIGEST,
            MODULE.PRIVATE_KEY: PRIVATE,
            "verdict": "accepted",
        }

    def test_owner_review_v4_binds_opaque_private_commitment_exactly(self):
        base = MODULE.core._load_base_module()
        payload = self._review_payload()
        record = MODULE.review_v4(7, 9, SOURCE, self._visual(), self._review_get(payload), base=base)
        self.assertEqual(record[MODULE.PRIVATE_KEY], PRIVATE)
        self.assertEqual(record["authority"], MODULE.REVIEW_AUTHORITY)
        self.assertNotIn("privateKey", record)
        self.assertNotIn("privateProvenance", record)

        for bad in (PRIVATE.upper(), "a" * 63):
            rejected = dict(payload)
            rejected[MODULE.PRIVATE_KEY] = bad
            with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
                MODULE.review_v4(7, 9, SOURCE, self._visual(), self._review_get(rejected), base=base)

        extra = dict(payload)
        extra["rawPrivateFingerprint"] = "forbidden"
        with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
            MODULE.review_v4(7, 9, SOURCE, self._visual(), self._review_get(extra), base=base)

    def test_candidate_workflow_requirements_extend_three_exact_gates_and_restore(self):
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
        parent.WORKFLOWS = (*parent.WORKFLOWS, MODULE.PRIVATE_REVIEW_WORKFLOW)
        parent.WORKFLOW_PATHS = {
            **parent.WORKFLOW_PATHS,
            MODULE.PRIVATE_REVIEW_WORKFLOW: ".github/workflows/wrong.yml",
        }
        with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
            with MODULE._candidate_workflow_requirements(parent):
                pass

    def test_private_environment_adapter_carries_only_exact_opaque_token(self):
        parent = MODULE.core._load_base_module()
        parent.installer_environment = lambda _device, _device_digest, _lock: {"BASE": "1"}
        environment = MODULE._private_environment_adapter(parent, DIGEST, PRIVATE)(
            Path("/device"), "device-digest", "44" * 32
        )
        self.assertEqual(environment[MODULE.core.GENERATED_ENV], DIGEST)
        self.assertEqual(environment[MODULE.PRIVATE_ENV], PRIVATE)
        self.assertNotIn("PrivateInputReviewKey.bin", environment.values())
        self.assertNotIn("AppSecret", " ".join(environment.values()))

        parent.installer_environment = lambda _device, _device_digest, _lock: {
            MODULE.PRIVATE_ENV: PRIVATE
        }
        with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
            MODULE._private_environment_adapter(parent, DIGEST, PRIVATE)(
                Path("/device"), "device-digest", "44" * 32
            )

    def test_private_core_extensions_preserve_sealed_installer_and_restore_all_seams(self):
        parent = MODULE.core._load_base_module()
        sealed_installer = parent.installer
        original_environment = parent.installer_environment
        original_signed = parent.retained_signed_artifact
        original_reinspect = parent.retained_signed_artifact_reinspect
        saved_review = MODULE.core.review_v3
        saved_candidate = MODULE.core.candidate_generated_authority
        saved_environment_adapter = MODULE.core._environment_adapter
        state: dict[str, str] = {}

        parent.installer_environment = lambda _device, _device_digest, _lock: {"BASE": "1"}
        parent.retained_signed_artifact = lambda *args, **kwargs: {"artifact": "first"}
        parent.retained_signed_artifact_reinspect = lambda *args, **kwargs: {"artifact": "second"}
        staged_environment = parent.installer_environment
        staged_signed = parent.retained_signed_artifact
        staged_reinspect = parent.retained_signed_artifact_reinspect

        with mock.patch.object(
            MODULE,
            "review_v4",
            return_value={"authority": MODULE.REVIEW_AUTHORITY, MODULE.PRIVATE_KEY: PRIVATE},
        ):
            with MODULE._private_core_extensions(parent, state):
                self.assertIs(parent.installer, sealed_installer)
                observed = MODULE.core.review_v3()
                self.assertEqual(observed[MODULE.PRIVATE_KEY], PRIVATE)
                self.assertEqual(state[MODULE.PRIVATE_KEY], PRIVATE)
                environment = MODULE.core._environment_adapter(parent, DIGEST)(
                    Path("/device"), "device", "44" * 32
                )
                self.assertEqual(environment[MODULE.PRIVATE_ENV], PRIVATE)
                self.assertEqual(parent.retained_signed_artifact()[MODULE.PRIVATE_KEY], PRIVATE)
                self.assertEqual(parent.retained_signed_artifact_reinspect()[MODULE.PRIVATE_KEY], PRIVATE)

        self.assertIs(MODULE.core.review_v3, saved_review)
        self.assertIs(MODULE.core.candidate_generated_authority, saved_candidate)
        self.assertIs(MODULE.core._environment_adapter, saved_environment_adapter)
        self.assertIs(parent.installer, sealed_installer)
        self.assertIs(parent.installer_environment, staged_environment)
        self.assertIs(parent.retained_signed_artifact, staged_signed)
        self.assertIs(parent.retained_signed_artifact_reinspect, staged_reinspect)
        parent.installer_environment = original_environment
        parent.retained_signed_artifact = original_signed
        parent.retained_signed_artifact_reinspect = original_reinspect

    def test_build_requires_and_retains_private_review_and_all_workflows(self):
        parent = MODULE.core._load_base_module()
        parent.retained_signed_artifact = lambda *args, **kwargs: {"artifact": "signed"}
        parent.retained_signed_artifact_reinspect = lambda *args, **kwargs: {"artifact": "reinspected"}
        observed = {}

        def fake_review(*args, **kwargs):
            del args, kwargs
            return {"authority": MODULE.REVIEW_AUTHORITY, MODULE.PRIVATE_KEY: PRIVATE}

        def fake_core_build(*args, **kwargs):
            del args
            base = kwargs["base_module"]
            observed["derive_subject"] = kwargs["derive_subject"]
            observed["workflows"] = base.WORKFLOWS
            review = MODULE.core.review_v3()
            signed = base.retained_signed_artifact()
            software = [
                {"name": name, "path": base.WORKFLOW_PATHS[name]}
                for name in base.WORKFLOWS
            ]
            return {
                "generatedBuildSubjectCandidate": {
                    "implementation": MODULE.GENERATED_HELPER_PATH,
                    MODULE.PRIVATE_KEY: PRIVATE,
                    "privateInputReviewCandidate": {MODULE.PRIVATE_KEY: PRIVATE},
                },
                "visualReview": review,
                "retainedSignedFieldArtifact": signed,
                "softwareAcceptance": software,
            }

        with (
            mock.patch.object(MODULE, "review_v4", side_effect=fake_review),
            mock.patch.object(MODULE, "_ORIGINAL_BUILD", side_effect=fake_core_build),
        ):
            result = MODULE.build(base_module=parent)
        self.assertIs(observed["derive_subject"], MODULE._current_generated_subject)
        for name, _ in MODULE.GENERATED_ACCEPTANCE_WORKFLOWS:
            self.assertIn(name, observed["workflows"])
            self.assertIn(name, result["requiredGeneratedBuildWorkflowAcceptance"])
        self.assertEqual(result[MODULE.PRIVATE_ACCEPTED_KEY], PRIVATE)
        self.assertEqual(result["retainedSignedFieldArtifact"][MODULE.PRIVATE_KEY], PRIVATE)
        self.assertEqual(result["schemaVersion"], 3)
        self.assertEqual(result["authority"], MODULE.FINAL_AUTHORITY)

    def test_build_rejects_record_that_drops_private_workflow_or_signed_commitment(self):
        parent = MODULE.core._load_base_module()
        parent.retained_signed_artifact = lambda *args, **kwargs: {"artifact": "signed"}
        parent.retained_signed_artifact_reinspect = lambda *args, **kwargs: {"artifact": "reinspected"}

        def fake_review(*args, **kwargs):
            del args, kwargs
            return {"authority": MODULE.REVIEW_AUTHORITY, MODULE.PRIVATE_KEY: PRIVATE}

        def fake_core_build(*args, **kwargs):
            del args
            base = kwargs["base_module"]
            review = MODULE.core.review_v3()
            software = [
                {"name": name, "path": base.WORKFLOW_PATHS[name]}
                for name in base.WORKFLOWS
                if name != MODULE.PRIVATE_REVIEW_WORKFLOW
            ]
            return {
                "generatedBuildSubjectCandidate": {
                    "implementation": MODULE.GENERATED_HELPER_PATH,
                    MODULE.PRIVATE_KEY: PRIVATE,
                    "privateInputReviewCandidate": {MODULE.PRIVATE_KEY: PRIVATE},
                },
                "visualReview": review,
                "retainedSignedFieldArtifact": {"artifact": "signed"},
                "softwareAcceptance": software,
            }

        with (
            mock.patch.object(MODULE, "review_v4", side_effect=fake_review),
            mock.patch.object(MODULE, "_ORIGINAL_BUILD", side_effect=fake_core_build),
        ):
            with self.assertRaises(MODULE.core.GeneratedSubjectGoError):
                MODULE.build(base_module=parent)


if __name__ == "__main__":
    unittest.main(verbosity=2)
