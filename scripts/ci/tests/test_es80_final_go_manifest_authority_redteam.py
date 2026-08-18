#!/usr/bin/env python3
"""Exploit-positive classifier for #3607 manifest review authority.

Terminal SUCCESS means the attacked product head still admits both defects:
1. an accepted review can go stale while waiting for the manifest extension lock
   yet still reach the semantic private-build side-effect boundary; and
2. a caller-supplied review transport can mint OWNER-shaped manifest authority.

Validation only. This file creates no install, Bluetooth, telemetry, command, or
physical authority and must not be merged as product behavior.
"""
from __future__ import annotations

import contextlib
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_manifest_redteam", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

SOURCE = "a" * 40
DIGEST_A = "1" * 64
DIGEST_B = "2" * 64
PR = 3607
REVIEW_ID = 7701
REVIEW_NODE_ID = "PRR_manifest_redteam"


class FakeBase:
    def __init__(self) -> None:
        self.git = lambda *_args, **_kwargs: "git"
        self.git_bytes = lambda *_args, **_kwargs: b"git-bytes"

    def pos(self, value, label):
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise module.PrivateReviewGoError(f"{label} invalid")
        return value

    def canon(self, value, label):
        if not isinstance(value, str) or len(value) not in {40, 64}:
            raise module.PrivateReviewGoError(f"{label} invalid")
        lowered = value.lower()
        if any(character not in "0123456789abcdef" for character in lowered):
            raise module.PrivateReviewGoError(f"{label} invalid")
        return lowered

    def obj(self, raw, label):
        try:
            value = json.loads(raw.decode("utf-8"))
        except Exception as error:
            raise module.PrivateReviewGoError(f"{label} invalid") from error
        if not isinstance(value, dict):
            raise module.PrivateReviewGoError(f"{label} invalid")
        return value

    @staticmethod
    def sha(raw):
        return hashlib.sha256(raw).hexdigest()

    def api(self, path):
        raise AssertionError(f"trusted API should not be reached by exploit classifier: {path}")


def review_response(*, digest=DIGEST_A, state="COMMENTED"):
    body = json.dumps(
        {
            "schemaVersion": 1,
            "authority": module.MANIFEST_REVIEW_AUTHORITY,
            "sourceCommitSHA": SOURCE,
            module.MANIFEST_DIGEST_KEY: digest,
            "verdict": "ACCEPT",
        },
        sort_keys=True,
    )
    return {
        "id": REVIEW_ID,
        "node_id": REVIEW_NODE_ID,
        "state": state,
        "commit_id": SOURCE,
        "user": {"login": module.OWNER},
        "author_association": "OWNER",
        "submitted_at": "2026-08-18T10:45:00Z",
        "body": body,
    }


@contextlib.contextmanager
def noop_custody(*_args, **_kwargs):
    yield


class FinalGoManifestAuthorityRedTeamTests(unittest.TestCase):
    def setUp(self):
        self.base = FakeBase()
        self.original_semantic_build = module._SEMANTIC_BUILD
        self.original_candidate_custody = module._PREDECESSOR_CANDIDATE_GIT_CUSTODY
        self.original_vnode = module._CURRENT_VNODE_AUTHORITY
        self.original_semantic_adapter = module._SEMANTIC_MODULE._private_environment_adapter
        module._PREDECESSOR_CANDIDATE_GIT_CUSTODY = noop_custody
        module._CURRENT_VNODE_AUTHORITY = noop_custody

    def tearDown(self):
        module._SEMANTIC_BUILD = self.original_semantic_build
        module._PREDECESSOR_CANDIDATE_GIT_CUSTODY = self.original_candidate_custody
        module._CURRENT_VNODE_AUTHORITY = self.original_vnode
        module._SEMANTIC_MODULE._private_environment_adapter = self.original_semantic_adapter
        self.assertIsNone(module._ACTIVE_MANIFEST_REVIEW.get())
        self.assertFalse(module._CANDIDATE_RETIRED.get())

    @staticmethod
    def sealed_record():
        return {
            "privateFieldInstall": {"status": "complete"},
            "retainedSignedFieldArtifact": {"status": "retained"},
            "physicalResultCollected": False,
        }

    def run_build(self, *, get, semantic_build):
        module._SEMANTIC_BUILD = semantic_build
        with tempfile.TemporaryDirectory(prefix="nembra-manifest-redteam-") as temporary:
            return module.build(
                candidate_repo=Path(temporary),
                source=SOURCE,
                pr=PR,
                generated_manifest_review_id=REVIEW_ID,
                get=get,
                base_module=self.base,
            )

    def test_stale_review_snapshot_reaches_semantic_side_effect_after_lock_wait(self):
        first_review_returned = threading.Event()
        allow_second_fetch = threading.Event()
        mutable = {"state": "COMMENTED", "digest": DIGEST_A}
        semantic_subjects = []
        outcome = {}

        def get(path):
            self.assertEqual(path, f"/pulls/{PR}/reviews/{REVIEW_ID}")
            response = review_response(digest=mutable["digest"], state=mutable["state"])
            if not first_review_returned.is_set():
                first_review_returned.set()
            else:
                allow_second_fetch.wait(timeout=5)
            return b"{}", copy.deepcopy(response)

        def semantic_build(**_kwargs):
            subject = module._ACTIVE_MANIFEST_REVIEW.get()
            self.assertIsNotNone(subject)
            semantic_subjects.append(subject[module.MANIFEST_DIGEST_KEY])
            return self.sealed_record()

        def worker():
            try:
                self.run_build(get=get, semantic_build=semantic_build)
            except BaseException as error:  # capture exact fail-closed result after side effect
                outcome["error"] = error
            else:
                outcome["result"] = "unexpected-success"

        module._MANIFEST_EXTENSION_LOCK.acquire()
        try:
            thread = threading.Thread(target=worker, name="manifest-stale-review-redteam")
            thread.start()
            self.assertTrue(first_review_returned.wait(timeout=5))
            # The review is now revoked while the build is blocked behind the lock.
            mutable["state"] = "DISMISSED"
            mutable["digest"] = DIGEST_B
        finally:
            module._MANIFEST_EXTENSION_LOCK.release()

        # Let the post-side-effect re-fetch observe revocation only after the stale
        # subject has already been admitted to the semantic build boundary.
        allow_second_fetch.set()
        thread.join(timeout=10)
        self.assertFalse(thread.is_alive(), "red-team worker deadlocked")
        self.assertEqual(semantic_subjects, [DIGEST_A])
        self.assertIsInstance(outcome.get("error"), module.PrivateReviewGoError)
        self.assertNotIn("result", outcome)

    def test_caller_supplied_review_transport_can_mint_manifest_authority(self):
        forged = review_response(digest=DIGEST_B, state="APPROVED")
        semantic_subjects = []

        def attacker_get(path):
            self.assertEqual(path, f"/pulls/{PR}/reviews/{REVIEW_ID}")
            return b"{}", copy.deepcopy(forged)

        def semantic_build(**_kwargs):
            subject = module._ACTIVE_MANIFEST_REVIEW.get()
            self.assertIsNotNone(subject)
            semantic_subjects.append(subject[module.MANIFEST_DIGEST_KEY])
            return self.sealed_record()

        result = self.run_build(get=attacker_get, semantic_build=semantic_build)
        self.assertEqual(semantic_subjects, [DIGEST_B])
        self.assertEqual(
            result[module.MANIFEST_RECORD_KEY][module.MANIFEST_DIGEST_KEY],
            DIGEST_B,
        )
        self.assertFalse(result["physicalResultCollected"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
