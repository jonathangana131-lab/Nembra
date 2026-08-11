#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("private_review_final_go_current", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current private-review Final-GO module")
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


def blob_oid(payload: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload).hexdigest()


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


def authority_values():
    return {
        MODULE.PRIVATE_REVIEW_COMMITMENT_KEY: PRIVATE,
        MODULE.PRIVATE_REVIEW_HELPER_KEY: "a1" * 32,
        MODULE.PROVENANCE_HELPER_KEY: "b2" * 32,
        MODULE.GENERATED_HELPER_KEY: "c3" * 32,
    }


def review_get(*, owner=MODULE.OWNER, association="OWNER", overrides=None, extra=None):
    body = {
        "schemaVersion": 5,
        "authority": MODULE.REVIEW_AUTHORITY,
        "sourceCommitSHA": SOURCE,
        "visualRunID": 123,
        "visualArtifactID": 456,
        "standardScreenshotSHA256": STANDARD,
        "accessibilityScreenshotSHA256": ACCESSIBILITY,
        "tuyaDependencyLockSHA256": LOCK,
        MODULE.generated.GENERATED_KEY: GENERATED,
        **authority_values(),
        "verdict": "accepted",
    }
    if overrides:
        body.update(overrides)
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
            "submitted_at": "2026-08-11T09:30:00Z",
            "node_id": "PRR_v5",
            "body": json.dumps(body, separators=(",", ":")),
        }

    return get


class PrivateReviewFinalGoCurrentTests(unittest.TestCase):
    def test_parent_loader_uses_accepted_git_blob_and_ignores_hidden_worktree_replacement(self):
        child_source = SCRIPT.read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory(prefix="nembra-private-parent-current-") as temporary:
            root = Path(temporary).resolve(strict=True)
            child = root / MODULE.CHILD_AUTHORITY_PATHS[0]
            parent = root / MODULE.GENERATED_MODULE_PATH
            sentinel = root / "attacker-parent-executed"
            parent.parent.mkdir(parents=True, exist_ok=True)
            parent.write_text(
                "#!/usr/bin/env python3\n"
                "def _current_generated_subject(_root, _source, _base):\n"
                "    return 'a' * 64\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", MODULE.GENERATED_MODULE_PATH], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted generated parent"], check=True)
            accepted_blob = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", f"HEAD:{MODULE.GENERATED_MODULE_PATH}"], text=True
            ).strip()

            patched_child = child_source.replace(
                f'PARENT_GENERATED_MODULE_GIT_BLOB = "{MODULE.PARENT_GENERATED_MODULE_GIT_BLOB}"',
                f'PARENT_GENERATED_MODULE_GIT_BLOB = "{accepted_blob}"',
                1,
            )
            child.parent.mkdir(parents=True, exist_ok=True)
            child.write_text(patched_child, encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", MODULE.CHILD_AUTHORITY_PATHS[0]], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted private child"], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "update-index", "--assume-unchanged", MODULE.GENERATED_MODULE_PATH],
                check=True,
            )
            parent.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n"
                "def _current_generated_subject(_root, _source, _base):\n"
                "    return 'b' * 64\n",
                encoding="utf-8",
            )
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"], text=True
                ),
                "",
            )
            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location("private_review_current_fixture", child)
                if spec is None or spec.loader is None:
                    self.fail("could not load private-review fixture")
                fixture = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(fixture)
            finally:
                sys.dont_write_bytecode = previous
            self.assertFalse(sentinel.exists(), "mutable generated-parent worktree bytes executed")
            self.assertEqual(fixture.generated.__nembra_accepted_control_blob__, accepted_blob)

    def test_v5_owner_review_binds_pixels_generated_private_hmac_and_all_helper_sources(self):
        result = MODULE.review_v5(2612, 77, SOURCE, visual(), review_get(), base=TinyBase)
        self.assertEqual(result["authority"], MODULE.REVIEW_AUTHORITY)
        self.assertEqual(result[MODULE.generated.GENERATED_KEY], GENERATED)
        self.assertEqual(result[MODULE.PRIVATE_REVIEW_COMMITMENT_KEY], PRIVATE)
        for key, value in authority_values().items():
            self.assertEqual(result[key], value)

    def test_v5_review_rejects_noncanonical_nonowner_and_extra_authority(self):
        with self.assertRaises(MODULE.PrivateReviewGoError):
            MODULE.review_v5(
                2612, 77, SOURCE, visual(), review_get(overrides={MODULE.PRIVATE_REVIEW_HELPER_KEY: ("a1" * 32).upper()}), base=TinyBase
            )
        with self.assertRaises(MODULE.PrivateReviewGoError):
            MODULE.review_v5(2612, 77, SOURCE, visual(), review_get(owner="attacker", association="CONTRIBUTOR"), base=TinyBase)
        with self.assertRaises(MODULE.PrivateReviewGoError):
            MODULE.review_v5(2612, 77, SOURCE, visual(), review_get(extra={"secondPrivateAuthority": PRIVATE}), base=TinyBase)

    def test_private_environment_layers_all_current_authority_and_rejects_collision(self):
        values = {MODULE.generated.GENERATED_KEY: GENERATED, **authority_values()}

        class Base:
            @staticmethod
            def installer_environment(device, device_digest, accepted_lock_sha256):
                del device, device_digest
                return {"LOCK": accepted_lock_sha256}

        adapter = MODULE._private_environment_adapter(MODULE.generated._environment_adapter, values)
        extended = adapter(Base, GENERATED)
        environment = extended(Path("/tmp/device"), "aa" * 32, LOCK)
        self.assertEqual(environment[MODULE.generated.GENERATED_ENV], GENERATED)
        self.assertEqual(environment[MODULE.PRIVATE_REVIEW_ENV], PRIVATE)
        self.assertEqual(environment[MODULE.PRIVATE_REVIEW_HELPER_ENV], values[MODULE.PRIVATE_REVIEW_HELPER_KEY])
        self.assertEqual(environment[MODULE.PROVENANCE_HELPER_ENV], values[MODULE.PROVENANCE_HELPER_KEY])
        self.assertEqual(environment[MODULE.GENERATED_HELPER_ENV], values[MODULE.GENERATED_HELPER_KEY])
        self.assertEqual(environment["LOCK"], LOCK)

        class CollisionBase:
            @staticmethod
            def installer_environment(device, device_digest, accepted_lock_sha256):
                del device, device_digest, accepted_lock_sha256
                return {MODULE.PROVENANCE_HELPER_ENV: "attacker"}

        collision = adapter(CollisionBase, GENERATED)
        with self.assertRaises(MODULE.PrivateReviewGoError):
            collision(Path("/tmp/device"), "aa" * 32, LOCK)

    def test_candidate_private_authority_binds_exact_git_helper_bytes_to_review(self):
        payloads = {
            MODULE.PRIVATE_REVIEW_HELPER_PATH: (MODULE.PRIVATE_REVIEW_DOMAIN + "\n").encode(),
            MODULE.PROVENANCE_HELPER_PATH: b"provenance helper\n",
            MODULE.generated.GENERATED_HELPER_PATH: b"generated helper\n",
            "Scripts/bootstrap_capture_tuya_sdk.sh": (
                MODULE.PRIVATE_REVIEW_ENV + "\n" + MODULE.PRIVATE_REVIEW_HELPER_ENV + "\n" +
                MODULE.PROVENANCE_HELPER_ENV + "\n" + MODULE.GENERATED_HELPER_ENV + "\nrun_accepted_python_helper() {\n"
            ).encode(),
            "Scripts/capture_tuya_private_input_build_guard.py": (
                MODULE.PRIVATE_REVIEW_HELPER_ENV + "\n" + MODULE.PROVENANCE_HELPER_ENV + "\n" +
                MODULE.GENERATED_HELPER_ENV + "\n_load_accepted_helper_module\n"
            ).encode(),
        }
        review = {
            MODULE.generated.GENERATED_KEY: GENERATED,
            MODULE.PRIVATE_REVIEW_COMMITMENT_KEY: PRIVATE,
            MODULE.PRIVATE_REVIEW_HELPER_KEY: hashlib.sha256(payloads[MODULE.PRIVATE_REVIEW_HELPER_PATH]).hexdigest(),
            MODULE.PROVENANCE_HELPER_KEY: hashlib.sha256(payloads[MODULE.PROVENANCE_HELPER_PATH]).hexdigest(),
            MODULE.GENERATED_HELPER_KEY: hashlib.sha256(payloads[MODULE.generated.GENERATED_HELPER_PATH]).hexdigest(),
        }
        oids = {path: blob_oid(payload) for path, payload in payloads.items()}

        with tempfile.TemporaryDirectory(prefix="nembra-current-private-candidate-") as temporary:
            root = Path(temporary).resolve(strict=True)

            def fake_git(repo, *args):
                self.assertEqual(repo, root)
                if args == ("rev-parse", "HEAD"):
                    return SOURCE
                if args == ("status", "--porcelain=v1", "--untracked-files=all"):
                    return ""
                if args[0] == "rev-parse" and args[1].startswith(f"{SOURCE}:"):
                    return oids[args[1].split(":", 1)[1]]
                raise AssertionError(args)

            def fake_git_bytes(repo, *args):
                self.assertEqual(repo, root)
                if args[0] == "show" and args[1].startswith(f"{SOURCE}:"):
                    return payloads[args[1].split(":", 1)[1]]
                raise AssertionError(args)

            base = SimpleNamespace(canon=TinyBase.canon, git=fake_git, git_bytes=fake_git_bytes)
            original = MODULE.generated.candidate_generated_authority
            MODULE.generated.candidate_generated_authority = lambda *args, **kwargs: {
                MODULE.generated.GENERATED_KEY: GENERATED,
                "authority": "fixture-generated",
            }
            try:
                result = MODULE.candidate_private_authority(
                    root, SOURCE, review, base=base, derive_subject=lambda *_args: GENERATED
                )
                self.assertEqual(result[MODULE.PRIVATE_REVIEW_COMMITMENT_KEY], PRIVATE)
                self.assertEqual(result[MODULE.PRIVATE_REVIEW_HELPER_KEY], review[MODULE.PRIVATE_REVIEW_HELPER_KEY])
                bad = dict(review)
                bad[MODULE.PROVENANCE_HELPER_KEY] = "0" * 64
                with self.assertRaises(MODULE.PrivateReviewGoError):
                    MODULE.candidate_private_authority(root, SOURCE, bad, base=base, derive_subject=lambda *_args: GENERATED)
            finally:
                MODULE.generated.candidate_generated_authority = original

    def test_extension_preserves_parent_sealed_installer_and_restores_parent_functions(self):
        base = MODULE.generated._load_base_module()
        installer_before = base.installer
        review_before = MODULE.generated.review_v3
        environment_before = MODULE.generated._environment_adapter
        control_before = MODULE.generated.generated_control_plane
        review = {MODULE.generated.GENERATED_KEY: GENERATED, **authority_values()}
        with MODULE._generated_extensions(review=review):
            self.assertIs(base.installer, installer_before)
            self.assertIsNot(MODULE.generated.review_v3, review_before)
            self.assertIsNot(MODULE.generated._environment_adapter, environment_before)
            self.assertIs(MODULE.generated.generated_control_plane, MODULE.private_control_plane)
        self.assertIs(base.installer, installer_before)
        self.assertIs(MODULE.generated.review_v3, review_before)
        self.assertIs(MODULE.generated._environment_adapter, environment_before)
        self.assertIs(MODULE.generated.generated_control_plane, control_before)

    def test_private_control_plane_is_exact_child_of_current_2775_and_pins_parent_modules(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-control-current-") as temporary:
            root = Path(temporary).resolve(strict=True)
            for relative in MODULE.CHILD_AUTHORITY_PATHS:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(relative + "\n", encoding="utf-8")

            def expected_blob(relative):
                return MODULE.PARENT_GENERATED_MODULE_GIT_BLOB if relative == MODULE.GENERATED_MODULE_PATH else BLOB

            def fake_git(repo, *args):
                self.assertEqual(repo, root)
                if args == ("rev-parse", "HEAD"):
                    return SOURCE
                if args == ("status", "--porcelain=v1", "--untracked-files=all"):
                    return ""
                if args[0] == "rev-parse" and ":" in args[1]:
                    return expected_blob(args[1].split(":", 1)[1])
                if args[:2] == ("ls-files", "-v"):
                    return "H " + args[-1]
                if args[:2] == ("ls-files", "-t"):
                    return "H " + args[-1]
                if args[:3] == ("hash-object", "--no-filters", "--"):
                    return expected_blob(args[-1])
                raise AssertionError(args)

            base = SimpleNamespace(canon=TinyBase.canon, pos=TinyBase.pos, git=fake_git)

            def get(path):
                if path == "/pulls/4000":
                    return b"{}", {"state": "open", "draft": False, "merged_at": None,
                        "head": {"sha": SOURCE, "ref": "recovery/current-r4", "repo": {"full_name": MODULE.REPO}},
                        "base": {"sha": PARENT, "ref": MODULE.PARENT_BRANCH}}
                if path == "/pulls/2775":
                    return b"{}", {"state": "open", "draft": False, "merged_at": None,
                        "head": {"sha": PARENT, "ref": MODULE.PARENT_BRANCH, "repo": {"full_name": MODULE.REPO}},
                        "base": {"ref": MODULE.generated.PARENT_BRANCH}}
                if path == "/branches/main":
                    return b"{}", {"commit": {"sha": MAIN}}
                if path == f"/compare/{MAIN}...{PARENT}":
                    return b"{}", {"status": "ahead", "merge_base_commit": {"sha": MAIN}}
                if path == f"/compare/{PARENT}...{SOURCE}":
                    return b"{}", {"status": "ahead", "merge_base_commit": {"sha": PARENT}}
                if path == "/actions/runs/10":
                    return b"{}", {"name": MODULE.generated.WORKFLOW_NAME, "path": MODULE.generated.WORKFLOW_PATH,
                        "head_sha": PARENT, "status": "completed", "conclusion": "success", "event": "pull_request",
                        "head_branch": MODULE.PARENT_BRANCH, "pull_requests": [{"number": 2775}]}
                if path == "/actions/runs/20":
                    return b"{}", {"name": MODULE.WORKFLOW_NAME, "path": MODULE.WORKFLOW_PATH,
                        "head_sha": SOURCE, "status": "completed", "conclusion": "success", "event": "pull_request",
                        "head_branch": "recovery/current-r4", "pull_requests": [{"number": 4000}]}
                raise AssertionError(path)

            record = MODULE.private_control_plane(root, 4000, 20, parent_pr=2775, parent_run_id=10, get=get, base=base)
            self.assertEqual(record["privateReviewExtensionAuthority"], MODULE.PRIVATE_CONTROL_EXTENSION)
            self.assertEqual(record["parentSourceCommitSHA"], PARENT)
            self.assertEqual(record["gitBlobs"][MODULE.GENERATED_MODULE_PATH], MODULE.PARENT_GENERATED_MODULE_GIT_BLOB)


if __name__ == "__main__":
    unittest.main(verbosity=2)
