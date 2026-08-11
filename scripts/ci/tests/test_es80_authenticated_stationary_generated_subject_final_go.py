#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
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
DIGEST = "ab" * 32
LOCK = "cd" * 32
BLOB = "4" * 40
STANDARD = "5" * 64
ACCESSIBILITY = "6" * 64


class FakeBase:
    AUTH_WORKFLOW_NAME = "Capture Authenticated Stationary Final GO"
    AUTH_WORKFLOW_PATH = ".github/workflows/capture-authenticated-stationary-final-go.yml"

    class GoError(RuntimeError):
        pass

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


class GeneratedSubjectFinalGoTests(unittest.TestCase):
    def visual(self):
        return {
            "runID": 123,
            "artifactID": 456,
            "screenshots": {
                "unprovisioned-dark-standard": {"sha256": STANDARD},
                "unprovisioned-dark-accessibility-xxxl": {"sha256": ACCESSIBILITY},
            },
        }

    def review_get(self, *, generated=DIGEST, owner="jonathangana131-lab", association="OWNER"):
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
                "submitted_at": "2026-08-11T04:30:00Z",
                "node_id": "PRR_v3",
                "body": body,
            }

        return get

    def test_one_v3_owner_review_binds_pixels_lock_and_generated_subject(self):
        result = MODULE.review_v3(
            2612,
            77,
            SOURCE,
            self.visual(),
            self.review_get(),
            base=FakeBase,
        )
        self.assertEqual(result["tuyaDependencyLockSHA256"], LOCK)
        self.assertEqual(result[MODULE.GENERATED_KEY], DIGEST)
        self.assertEqual(result["authority"], MODULE.REVIEW_AUTHORITY)

    def test_v3_review_rejects_noncanonical_or_nonowner_generated_authority(self):
        with self.assertRaises(MODULE.GeneratedSubjectGoError):
            MODULE.review_v3(
                2612,
                77,
                SOURCE,
                self.visual(),
                self.review_get(generated=DIGEST.upper()),
                base=FakeBase,
            )
        with self.assertRaises(MODULE.GeneratedSubjectGoError):
            MODULE.review_v3(
                2612,
                77,
                SOURCE,
                self.visual(),
                self.review_get(owner="attacker", association="CONTRIBUTOR"),
                base=FakeBase,
            )

    def test_environment_extension_adds_only_reviewed_digest(self):
        original = lambda device, device_digest, accepted_lock: {
            "PATH": "/usr/bin:/bin",
            "BASH_ENV": "/dev/null",
            "GIT_NO_REPLACE_OBJECTS": "1",
            "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256": device_digest,
            "NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256": accepted_lock,
        }
        fake = SimpleNamespace(installer_environment=original)
        extended = MODULE._environment_adapter(fake, DIGEST)
        result = extended(Path("/private/device"), "7" * 64, LOCK)
        self.assertEqual(result[MODULE.GENERATED_ENV], DIGEST)
        self.assertEqual(result["GIT_NO_REPLACE_OBJECTS"], "1")
        self.assertEqual(result["BASH_ENV"], "/dev/null")
        self.assertEqual(set(result) - set(original(None, "7" * 64, LOCK)), {MODULE.GENERATED_ENV})

    def test_parent_extension_preserves_current_sealed_installer_function_and_restores_globals(self):
        base = MODULE._load_base_module()
        original_installer = base.installer
        original_environment = base.installer_environment
        original_review = base.review

        def adapter(*args, **kwargs):
            del args, kwargs
            return {"authority": MODULE.REVIEW_AUTHORITY}

        with MODULE._parent_extensions(
            base,
            accepted_generated_digest=DIGEST,
            review_adapter=adapter,
        ):
            self.assertIs(base.installer, original_installer, "child must not replace/copy the sealed parent installer")
            self.assertIs(base.review, adapter)
            self.assertIsNot(base.installer_environment, original_environment)
            self.assertIs(base.installer.__globals__["installer_environment"], base.installer_environment)
            self.assertIs(base.build.__globals__["review"], adapter)

        self.assertIs(base.installer, original_installer)
        self.assertIs(base.installer_environment, original_environment)
        self.assertIs(base.review, original_review)

    def test_candidate_authority_requires_exact_generated_enforcement_and_reviewed_graph(self):
        with tempfile.TemporaryDirectory(prefix="nembra-generated-final-go-") as temporary:
            root = Path(temporary)
            contents = {
                "Scripts/bootstrap_capture_tuya_sdk.sh": MODULE.GENERATED_ENV + "\ncapture_cocoapods_build_subject.py\n",
                "Scripts/capture_cocoapods_build_subject.py": "nembra-cocoapods-generated-build-subject-v1\n",
                "Scripts/capture_tuya_private_input_provenance.py": "provenance\n",
                "Scripts/capture_tuya_private_input_build_guard.py": "accepted_generated_subject_sha256\nrequire_accepted_generated_subject\n",
                "scripts/field/install_one_time_capture.command": "bootstrap_capture_tuya_sdk.sh\ncapture_tuya_private_input_build_guard.py\n",
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
                if args[0] == "rev-parse" and args[1].startswith("HEAD:"):
                    return BLOB
                if args[:3] == ("hash-object", "--no-filters", "--"):
                    return BLOB
                raise AssertionError(args)

            fake_base = SimpleNamespace(canon=FakeBase.canon, git=fake_git)
            result = MODULE.candidate_generated_authority(
                root,
                SOURCE,
                DIGEST,
                base=fake_base,
                derive_subject=lambda _: DIGEST,
            )
            self.assertEqual(result[MODULE.GENERATED_KEY], DIGEST)
            with self.assertRaises(MODULE.GeneratedSubjectGoError):
                MODULE.candidate_generated_authority(
                    root,
                    SOURCE,
                    DIGEST,
                    base=fake_base,
                    derive_subject=lambda _: "ef" * 32,
                )

    def test_control_plane_requires_live_parent_sha_and_both_terminal_green_runs(self):
        with tempfile.TemporaryDirectory(prefix="nembra-generated-control-") as temporary:
            root = Path(temporary)

            def fake_git(repo, *args):
                self.assertEqual(repo, root)
                if args == ("rev-parse", "HEAD"):
                    return SOURCE
                if args == ("status", "--porcelain=v1", "--untracked-files=all"):
                    return ""
                if args[0] == "rev-parse" and args[1].startswith("HEAD:"):
                    return BLOB
                raise AssertionError(args)

            fake_base = SimpleNamespace(
                canon=FakeBase.canon,
                pos=FakeBase.pos,
                git=fake_git,
                AUTH_WORKFLOW_NAME=FakeBase.AUTH_WORKFLOW_NAME,
                AUTH_WORKFLOW_PATH=FakeBase.AUTH_WORKFLOW_PATH,
            )

            def make_get(*, child_base=PARENT, child_conclusion="success"):
                def get(path):
                    if path == "/pulls/2724":
                        return b"{}", {
                            "state": "open",
                            "draft": False,
                            "merged_at": None,
                            "head": {"sha": SOURCE, "ref": "control/generated", "repo": {"full_name": MODULE.REPO}},
                            "base": {"sha": child_base, "ref": MODULE.PARENT_BRANCH},
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
                            "name": FakeBase.AUTH_WORKFLOW_NAME,
                            "path": FakeBase.AUTH_WORKFLOW_PATH,
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
                            "conclusion": child_conclusion,
                            "event": "pull_request",
                            "head_branch": "control/generated",
                            "pull_requests": [{"number": 2724}],
                        }
                    raise AssertionError(path)

                return get

            result = MODULE.generated_control_plane(
                root,
                2724,
                20,
                parent_pr=2638,
                parent_run_id=10,
                get=make_get(),
                base=fake_base,
            )
            self.assertEqual(result["parentSourceCommitSHA"], PARENT)

            with self.assertRaises(MODULE.GeneratedSubjectGoError):
                MODULE.generated_control_plane(
                    root,
                    2724,
                    20,
                    parent_pr=2638,
                    parent_run_id=10,
                    get=make_get(child_base="9" * 40),
                    base=fake_base,
                )
            with self.assertRaises(MODULE.GeneratedSubjectGoError):
                MODULE.generated_control_plane(
                    root,
                    2724,
                    20,
                    parent_pr=2638,
                    parent_run_id=10,
                    get=make_get(child_conclusion="failure"),
                    base=fake_base,
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
