#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import importlib.util

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("private_review_final_go", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load private-review Final-GO module")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SOURCE = "1" * 40
PARENT = "2" * 40
MAIN = "3" * 40
BLOB = "4" * 40
GENERATED = "ab" * 32
PRIVATE = "ef" * 32
LOCK = "cd" * 32
STANDARD = "5" * 64
ACCESSIBILITY = "6" * 64


class TinyBase:
    AUTH_WORKFLOW_NAME = "Capture Authenticated Stationary Final GO"
    AUTH_WORKFLOW_PATH = ".github/workflows/capture-authenticated-stationary-final-go.yml"
    VISUAL = "Capture Standalone Visual Evidence"

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


def visual():
    return {
        "runID": 123,
        "artifactID": 456,
        "screenshots": {
            "unprovisioned-dark-standard": {"sha256": STANDARD},
            "unprovisioned-dark-accessibility-xxxl": {"sha256": ACCESSIBILITY},
        },
    }


def review_get(*, private=PRIVATE, generated=GENERATED, owner=MODULE.OWNER, association="OWNER", extra=None):
    body = {
        "schemaVersion": 4,
        "authority": MODULE.REVIEW_AUTHORITY,
        "sourceCommitSHA": SOURCE,
        "visualRunID": 123,
        "visualArtifactID": 456,
        "standardScreenshotSHA256": STANDARD,
        "accessibilityScreenshotSHA256": ACCESSIBILITY,
        "tuyaDependencyLockSHA256": LOCK,
        MODULE.generated.GENERATED_KEY: generated,
        MODULE.PRIVATE_KEY: private,
        "verdict": "accepted",
    }
    if extra:
        body.update(extra)

    def get(path):
        if path != "/pulls/2612/reviews/77":
            raise AssertionError(path)
        return b"{}", {
            "id": 77,
            "state": "APPROVED",
            "commit_id": SOURCE,
            "user": {"login": owner},
            "author_association": association,
            "submitted_at": "2026-08-11T05:00:00Z",
            "node_id": "PRR_v4",
            "body": json.dumps(body, separators=(",", ":")),
        }

    return get


class PrivateReviewFinalGoTests(unittest.TestCase):
    def test_single_v4_owner_review_binds_pixels_lock_generated_and_private(self):
        result = MODULE.review_v4(2612, 77, SOURCE, visual(), review_get(), base=TinyBase)
        self.assertEqual(result["authority"], MODULE.REVIEW_AUTHORITY)
        self.assertEqual(result["tuyaDependencyLockSHA256"], LOCK)
        self.assertEqual(result[MODULE.generated.GENERATED_KEY], GENERATED)
        self.assertEqual(result[MODULE.PRIVATE_KEY], PRIVATE)

    def test_v4_review_rejects_noncanonical_private_mixed_or_extra_authority(self):
        with self.assertRaises(MODULE.PrivateReviewGoError):
            MODULE.review_v4(
                2612, 77, SOURCE, visual(), review_get(private=PRIVATE.upper()), base=TinyBase
            )
        with self.assertRaises(MODULE.PrivateReviewGoError):
            MODULE.review_v4(
                2612,
                77,
                SOURCE,
                visual(),
                review_get(owner="attacker", association="CONTRIBUTOR"),
                base=TinyBase,
            )
        with self.assertRaises(MODULE.PrivateReviewGoError):
            MODULE.review_v4(
                2612, 77, SOURCE, visual(), review_get(extra={"secondPrivateAuthority": PRIVATE}), base=TinyBase
            )

    def test_private_environment_layers_on_generated_parent_and_rejects_collision(self):
        class Base:
            @staticmethod
            def installer_environment(device, device_digest, accepted_lock_sha256):
                del device, device_digest
                return {"LOCK": accepted_lock_sha256}

        adapter = MODULE._private_environment_adapter(
            MODULE.generated._environment_adapter,
            PRIVATE,
        )
        extended = adapter(Base, GENERATED)
        environment = extended(Path("/tmp/device"), "aa" * 32, LOCK)
        self.assertEqual(environment[MODULE.generated.GENERATED_ENV], GENERATED)
        self.assertEqual(environment[MODULE.PRIVATE_ENV], PRIVATE)
        self.assertEqual(environment["LOCK"], LOCK)

        class CollisionBase:
            @staticmethod
            def installer_environment(device, device_digest, accepted_lock_sha256):
                del device, device_digest, accepted_lock_sha256
                return {MODULE.PRIVATE_ENV: "attacker"}

        collision = adapter(CollisionBase, GENERATED)
        with self.assertRaises(MODULE.PrivateReviewGoError):
            collision(Path("/tmp/device"), "aa" * 32, LOCK)

    def test_extension_never_replaces_parent_sealed_installer_and_restores_parent_functions(self):
        base = MODULE.generated._load_base_module()
        installer_before = base.installer
        review_before = MODULE.generated.review_v3
        environment_before = MODULE.generated._environment_adapter
        control_before = MODULE.generated.generated_control_plane
        with MODULE._generated_extensions(accepted_private_commitment=PRIVATE):
            self.assertIs(base.installer, installer_before)
            self.assertIsNot(MODULE.generated.review_v3, review_before)
            self.assertIsNot(MODULE.generated._environment_adapter, environment_before)
            self.assertIs(MODULE.generated.generated_control_plane, MODULE.private_control_plane)
        self.assertIs(base.installer, installer_before)
        self.assertIs(MODULE.generated.review_v3, review_before)
        self.assertIs(MODULE.generated._environment_adapter, environment_before)
        self.assertIs(MODULE.generated.generated_control_plane, control_before)

    def test_candidate_private_authority_requires_selected_2779_source_contract(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-review-candidate-") as temporary:
            root = Path(temporary)
            contents = {
                "Scripts/bootstrap_capture_tuya_sdk.sh": (
                    MODULE.generated.GENERATED_ENV
                    + "\ncapture_cocoapods_generated_build_subject.py\n"
                    + MODULE.PRIVATE_ENV
                    + "\ncapture_tuya_private_input_review.py\n"
                ),
                MODULE.generated.GENERATED_HELPER_PATH: MODULE.generated.GENERATED_SCHEMA + "\n",
                "Scripts/capture_tuya_private_input_provenance.py": "provenance\n",
                "Scripts/capture_tuya_private_input_build_guard.py": (
                    "capture_cocoapods_generated_build_subject.py\n"
                    "_verify_accepted_generated_build_subject\n"
                    "require_accepted_generated_subject=True\n"
                    "capture_tuya_private_input_review.py\n"
                    "_verify_accepted_private_input_subject\n"
                    "require_accepted_private_subject=True\n"
                ),
                "scripts/field/install_one_time_capture.command": (
                    "bootstrap_capture_tuya_sdk.sh\ncapture_tuya_private_input_build_guard.py\n"
                ),
                MODULE.PRIVATE_HELPER_PATH: MODULE.PRIVATE_HELPER_DOMAIN + "\n",
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
            candidate = MODULE.candidate_private_authority(
                root,
                SOURCE,
                GENERATED,
                PRIVATE,
                base=base,
                derive_subject=lambda _root: GENERATED,
            )
            self.assertEqual(candidate[MODULE.PRIVATE_KEY], PRIVATE)
            self.assertEqual(
                candidate["generatedBuildSubjectCandidate"][MODULE.generated.GENERATED_KEY], GENERATED
            )
            self.assertEqual(candidate["gitBlobs"][MODULE.PRIVATE_HELPER_PATH], BLOB)

            (root / MODULE.PRIVATE_HELPER_PATH).write_text("wrong domain\n", encoding="utf-8")
            with self.assertRaises(MODULE.PrivateReviewGoError):
                MODULE.candidate_private_authority(
                    root,
                    SOURCE,
                    GENERATED,
                    PRIVATE,
                    base=base,
                    derive_subject=lambda _root: GENERATED,
                )

    def test_private_control_plane_pins_exact_generated_parent_execution_modules(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-control-r4-") as temporary:
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
                if args[0] == "rev-parse" and (
                    args[1].startswith(f"{SOURCE}:") or args[1].startswith(f"{PARENT}:")
                ):
                    return BLOB
                if args[:2] == ("ls-files", "-v"):
                    return "H " + args[-1]
                if args[:2] == ("ls-files", "-t"):
                    return "H " + args[-1]
                if args[:3] == ("hash-object", "--no-filters", "--"):
                    return BLOB
                raise AssertionError(args)

            base = SimpleNamespace(canon=TinyBase.canon, pos=TinyBase.pos, git=fake_git)

            def get(path):
                if path == "/pulls/4000":
                    return b"{}", {
                        "state": "open",
                        "draft": False,
                        "merged_at": None,
                        "head": {"sha": SOURCE, "ref": "control/private-r4", "repo": {"full_name": MODULE.REPO}},
                        "base": {"sha": PARENT, "ref": MODULE.PARENT_BRANCH},
                    }
                if path == "/pulls/2775":
                    return b"{}", {
                        "state": "open",
                        "draft": False,
                        "merged_at": None,
                        "head": {"sha": PARENT, "ref": MODULE.PARENT_BRANCH, "repo": {"full_name": MODULE.REPO}},
                        "base": {"ref": MODULE.generated.PARENT_BRANCH},
                    }
                if path == "/branches/main":
                    return b"{}", {"commit": {"sha": MAIN}}
                if path == f"/compare/{MAIN}...{PARENT}":
                    return b"{}", {"status": "ahead", "merge_base_commit": {"sha": MAIN}}
                if path == f"/compare/{PARENT}...{SOURCE}":
                    return b"{}", {"status": "ahead", "merge_base_commit": {"sha": PARENT}}
                if path == "/actions/runs/10":
                    return b"{}", {
                        "name": MODULE.generated.WORKFLOW_NAME,
                        "path": MODULE.generated.WORKFLOW_PATH,
                        "head_sha": PARENT,
                        "status": "completed",
                        "conclusion": "success",
                        "event": "pull_request",
                        "head_branch": MODULE.PARENT_BRANCH,
                        "pull_requests": [{"number": 2775}],
                    }
                if path == "/actions/runs/20":
                    return b"{}", {
                        "name": MODULE.WORKFLOW_NAME,
                        "path": MODULE.WORKFLOW_PATH,
                        "head_sha": SOURCE,
                        "status": "completed",
                        "conclusion": "success",
                        "event": "pull_request",
                        "head_branch": "control/private-r4",
                        "pull_requests": [{"number": 4000}],
                    }
                raise AssertionError(path)

            record = MODULE.private_control_plane(
                root,
                4000,
                20,
                parent_pr=2775,
                parent_run_id=10,
                get=get,
                base=base,
            )
            self.assertEqual(record["extensionAuthority"], MODULE.generated.CONTROL_EXTENSION)
            self.assertEqual(
                record["privateReviewExtensionAuthority"], MODULE.PRIVATE_CONTROL_EXTENSION
            )
            self.assertEqual(record["parentSourceCommitSHA"], PARENT)
            for relative in MODULE.PARENT_PINNED_PATHS:
                self.assertEqual(record["gitBlobs"][relative], BLOB)


if __name__ == "__main__":
    unittest.main(verbosity=2)
