#!/usr/bin/env python3
from __future__ import annotations

import ast
import hashlib
import importlib.util
import inspect
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_final_go", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load generated-subject Final-GO module")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SOURCE = "1" * 40
PARENT = "2" * 40
MAIN = "3" * 40
BLOB = "4" * 40
DIGEST = "ab" * 32
LOCK = "cd" * 32
STANDARD = "5" * 64
ACCESSIBILITY = "6" * 64


class TinyBase:
    AUTH_WORKFLOW_NAME = "Capture Authenticated Stationary Final GO"
    AUTH_WORKFLOW_PATH = ".github/workflows/capture-authenticated-stationary-final-go.yml"

    @staticmethod
    def pos(value, label):
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise RuntimeError(label)
        return value

    @staticmethod
    def canon(value, label):
        if not isinstance(value, str) or len(value) != 40 or any(c not in "0123456789abcdefABCDEF" for c in value):
            raise RuntimeError(label)
        return value.lower()

    @staticmethod
    def obj(raw, label):
        del label
        return json.loads(raw)

    @staticmethod
    def sha(raw):
        return hashlib.sha256(raw).hexdigest()


class GeneratedSubjectFinalGoR3Tests(unittest.TestCase):
    def visual(self):
        return {
            "runID": 123,
            "artifactID": 456,
            "screenshots": {
                "unprovisioned-dark-standard": {"sha256": STANDARD},
                "unprovisioned-dark-accessibility-xxxl": {"sha256": ACCESSIBILITY},
            },
        }

    def review_get(self, *, generated=DIGEST, owner=MODULE.OWNER, association="OWNER"):
        body = json.dumps(
            {
                "schemaVersion": 3,
                "authority": MODULE.REVIEW_AUTHORITY,
                "sourceCommitSHA": SOURCE,
                "visualRunID": 123,
                "visualArtifactID": 456,
                "standardScreenshotSHA256": STANDARD,
                "accessibilityScreenshotSHA256": ACCESSIBILITY,
                "tuyaDependencyLockSHA256": LOCK,
                MODULE.GENERATED_KEY: generated,
                "verdict": "accepted",
            },
            separators=(",", ":"),
        )

        def get(path):
            self.assertEqual(path, "/pulls/2612/reviews/77")
            return b"{}", {
                "id": 77,
                "state": "APPROVED",
                "commit_id": SOURCE,
                "user": {"login": owner},
                "author_association": association,
                "submitted_at": "2026-08-11T05:00:00Z",
                "node_id": "PRR_v3",
                "body": body,
            }

        return get

    def test_single_v3_owner_review_binds_pixels_lock_and_generated_subject(self):
        result = MODULE.review_v3(
            2612,
            77,
            SOURCE,
            self.visual(),
            self.review_get(),
            base=TinyBase,
        )
        self.assertEqual(result["authority"], MODULE.REVIEW_AUTHORITY)
        self.assertEqual(result["tuyaDependencyLockSHA256"], LOCK)
        self.assertEqual(result[MODULE.GENERATED_KEY], DIGEST)

    def test_v3_review_rejects_uppercase_or_nonowner_generated_authority(self):
        with self.assertRaises(MODULE.GeneratedSubjectGoError):
            MODULE.review_v3(
                2612,
                77,
                SOURCE,
                self.visual(),
                self.review_get(generated=DIGEST.upper()),
                base=TinyBase,
            )
        with self.assertRaises(MODULE.GeneratedSubjectGoError):
            MODULE.review_v3(
                2612,
                77,
                SOURCE,
                self.visual(),
                self.review_get(owner="attacker", association="CONTRIBUTOR"),
                base=TinyBase,
            )

    def test_child_control_plane_pins_exact_parent_modules_and_uses_parent_module_authority(self):
        with tempfile.TemporaryDirectory(prefix="nembra-generated-control-r3-") as temporary:
            root = Path(temporary)
            for relative in MODULE.CHILD_AUTHORITY_PATHS:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(relative + "\n", encoding="utf-8")

            def fake_git(repo, *args):
                self.assertEqual(repo, root)
                if args == ("rev-parse", "HEAD"):
                    return SOURCE
                if args == ("status", "--porcelain=v1", "--untracked-files=all"):
                    return ""
                if args[0] == "rev-parse" and (args[1].startswith(f"{SOURCE}:") or args[1].startswith(f"{PARENT}:")):
                    return BLOB
                if args[:2] == ("ls-files", "-v"):
                    return "H " + args[-1]
                if args[:2] == ("ls-files", "-t"):
                    return "H " + args[-1]
                if args[:3] == ("hash-object", "--no-filters", "--"):
                    return BLOB
                raise AssertionError(args)

            base = SimpleNamespace(
                canon=TinyBase.canon,
                pos=TinyBase.pos,
                git=fake_git,
                AUTH_WORKFLOW_NAME=TinyBase.AUTH_WORKFLOW_NAME,
                AUTH_WORKFLOW_PATH=TinyBase.AUTH_WORKFLOW_PATH,
            )

            def get(path):
                if path == "/pulls/3000":
                    return b"{}", {
                        "state": "open",
                        "draft": False,
                        "merged_at": None,
                        "head": {"sha": SOURCE, "ref": "control/generated-r3", "repo": {"full_name": MODULE.REPO}},
                        "base": {"sha": PARENT, "ref": MODULE.PARENT_BRANCH},
                    }
                if path == "/pulls/2638":
                    return b"{}", {
                        "state": "open",
                        "draft": False,
                        "merged_at": None,
                        "head": {"sha": PARENT, "ref": MODULE.PARENT_BRANCH, "repo": {"full_name": MODULE.REPO}},
                        "base": {"ref": "main"},
                    }
                if path == "/branches/main":
                    return b"{}", {"commit": {"sha": MAIN}}
                if path == f"/compare/{MAIN}...{PARENT}":
                    return b"{}", {"status": "ahead", "merge_base_commit": {"sha": MAIN}}
                if path == f"/compare/{PARENT}...{SOURCE}":
                    return b"{}", {"status": "ahead", "merge_base_commit": {"sha": PARENT}}
                if path == "/actions/runs/10":
                    return b"{}", {
                        "name": TinyBase.AUTH_WORKFLOW_NAME,
                        "path": TinyBase.AUTH_WORKFLOW_PATH,
                        "head_sha": PARENT,
                        "status": "completed",
                        "conclusion": "success",
                        "event": "push",
                        "head_branch": MODULE.PARENT_BRANCH,
                        "pull_requests": [],
                    }
                if path == "/actions/runs/20":
                    return b"{}", {
                        "name": MODULE.WORKFLOW_NAME,
                        "path": MODULE.WORKFLOW_PATH,
                        "head_sha": SOURCE,
                        "status": "completed",
                        "conclusion": "success",
                        "event": "pull_request",
                        "head_branch": "control/generated-r3",
                        "pull_requests": [{"number": 3000}],
                    }
                raise AssertionError(path)

            record = MODULE.generated_control_plane(
                root,
                3000,
                20,
                parent_pr=2638,
                parent_run_id=10,
                get=get,
                base=base,
            )
            self.assertEqual(record["authority"], "nembra-authenticated-stationary-go-control-plane-v1")
            self.assertEqual(record["extensionAuthority"], MODULE.CONTROL_EXTENSION)
            self.assertEqual(record["parentSourceCommitSHA"], PARENT)
            self.assertEqual(
                record["requiredCandidateWorkflows"],
                [name for name, _ in MODULE.GENERATED_ACCEPTANCE_WORKFLOWS],
            )
            for relative in MODULE.PARENT_PINNED_PATHS:
                self.assertEqual(record["gitBlobs"][relative], BLOB)

    def test_candidate_authority_requires_converged_generated_workflows_and_guard(self):
        with tempfile.TemporaryDirectory(prefix="nembra-generated-candidate-r3-") as temporary:
            root = Path(temporary)
            contents = {
                "Scripts/bootstrap_capture_tuya_sdk.sh": MODULE.GENERATED_ENV + "\ncapture_cocoapods_generated_build_subject.py\n",
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
                "scripts/field/install_one_time_capture.command": "bootstrap_capture_tuya_sdk.sh\ncapture_tuya_private_input_build_guard.py\n",
                MODULE.GENERATED_BUILD_WORKFLOW_PATH: (
                    "name: Capture CocoaPods Build Subject Authority\n"
                    "Require exact generated CocoaPods build authority\n"
                    "test_capture_private_input_ancestor_retarget.py\n"
                ),
                MODULE.VNODE_WORKFLOW_PATH: (
                    "name: Capture CocoaPods Vnode Attribute Convergence\n"
                    "Real macOS chmod vnode evidence\n"
                    "runs-on: macos-15\n"
                ),
            }
            for relative, content in contents.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")

            def fake_git(repo, *args):
                self.assertEqual(repo, root)
                if args == ("rev-parse", "HEAD"):
                    return SOURCE
                if args == ("status", "--porcelain=v1", "--untracked-files=all"):
                    return ""
                if args[0] == "rev-parse" and args[1].startswith(f"{SOURCE}:"):
                    return BLOB
                if args[:2] == ("ls-files", "-v"):
                    return "H " + args[-1]
                if args[:2] == ("ls-files", "-t"):
                    return "H " + args[-1]
                if args[:3] == ("hash-object", "--no-filters", "--"):
                    return BLOB
                raise AssertionError(args)

            base = SimpleNamespace(canon=TinyBase.canon, git=fake_git)
            record = MODULE.candidate_generated_authority(
                root,
                SOURCE,
                DIGEST,
                base=base,
                derive_subject=lambda *_: DIGEST,
            )
            self.assertEqual(record["implementation"], MODULE.GENERATED_HELPER_PATH)
            self.assertEqual(record[MODULE.GENERATED_KEY], DIGEST)
            self.assertEqual(
                record["requiredCandidateWorkflows"],
                [name for name, _ in MODULE.GENERATED_ACCEPTANCE_WORKFLOWS],
            )
            self.assertEqual(set(record["gitBlobs"]), set(MODULE.GENERATED_AUTHORITY_PATHS))

            guard = root / "Scripts/capture_tuya_private_input_build_guard.py"
            guard.write_text(guard.read_text(encoding="utf-8").replace("KQ_NOTE_ATTRIB\n", ""), encoding="utf-8")
            with self.assertRaises(MODULE.GeneratedSubjectGoError):
                MODULE.candidate_generated_authority(
                    root,
                    SOURCE,
                    DIGEST,
                    base=base,
                    derive_subject=lambda *_: DIGEST,
                )

    def test_candidate_workflow_requirements_extend_and_restore_parent_exact_set(self):
        base = MODULE._load_base_module()
        original_workflows = base.WORKFLOWS
        original_paths = dict(base.WORKFLOW_PATHS)
        with MODULE._candidate_workflow_requirements(base):
            for name, path in MODULE.GENERATED_ACCEPTANCE_WORKFLOWS:
                self.assertIn(name, base.WORKFLOWS)
                self.assertEqual(base.WORKFLOW_PATHS[name], path)
            self.assertEqual(len(base.WORKFLOWS), len(original_workflows) + 2)
        self.assertEqual(base.WORKFLOWS, original_workflows)
        self.assertEqual(base.WORKFLOW_PATHS, original_paths)

    def test_parent_extension_preserves_sealed_installer_and_default_module_functions(self):
        base = MODULE._load_base_module()
        sealed_installer = base.installer
        retained = base.retained_signed_artifact
        reinspect = base.retained_signed_artifact_reinspect
        publication = base.publication
        original_environment = base.installer_environment
        original_review = base.review

        def review_adapter(*args, **kwargs):
            del args, kwargs
            return {"authority": MODULE.REVIEW_AUTHORITY}

        with MODULE._parent_extensions(
            base,
            accepted_generated_digest=DIGEST,
            review_adapter=review_adapter,
        ):
            self.assertIs(base.installer, sealed_installer)
            self.assertIs(base.retained_signed_artifact, retained)
            self.assertIs(base.retained_signed_artifact_reinspect, reinspect)
            self.assertIs(base.publication, publication)
            self.assertIs(base.installer.__globals__["installer_environment"], base.installer_environment)
            self.assertIs(base.build.__globals__["review"], review_adapter)
            self.assertIsNot(base.installer_environment, original_environment)
        self.assertIs(base.installer, sealed_installer)
        self.assertIs(base.retained_signed_artifact, retained)
        self.assertIs(base.retained_signed_artifact_reinspect, reinspect)
        self.assertIs(base.publication, publication)
        self.assertIs(base.installer_environment, original_environment)
        self.assertIs(base.review, original_review)

    def test_build_delegation_does_not_override_parent_execution_subject_hooks(self):
        tree = ast.parse(inspect.getsource(MODULE.build))
        calls = [
            node
            for node in ast.walk(tree)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr == "build"
        ]
        self.assertEqual(len(calls), 1)
        keywords = {keyword.arg for keyword in calls[0].keywords if keyword.arg is not None}
        self.assertIn("control_authority", keywords)
        self.assertNotIn("run_installer", keywords)
        self.assertNotIn("inspect_signed_artifact", keywords)
        self.assertNotIn("reinspect_signed_artifact", keywords)

    def test_main_publication_is_bound_to_final_control_context(self):
        tree = ast.parse(inspect.getsource(MODULE.main))
        calls = [
            node
            for node in ast.walk(tree)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr == "publication"
        ]
        self.assertEqual(len(calls), 1)
        keywords = {keyword.arg for keyword in calls[0].keywords if keyword.arg is not None}
        self.assertEqual(keywords, {"authority_repo", "control"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
