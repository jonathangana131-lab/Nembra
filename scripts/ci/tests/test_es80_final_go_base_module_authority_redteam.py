#!/usr/bin/env python3
"""Exploit-positive classifier for #3613 base-module review authority.

Terminal SUCCESS means the attacked recovery still lets a caller replace the
independent GitHub OWNER-review transport by supplying a synthetic `base_module`
whose `api` method returns attacker-selected review bytes.

Validation only. This file performs no install, Bluetooth, Tuya/DP, telemetry,
command, or physical operation and must not be merged as product behavior.
"""
from __future__ import annotations

import contextlib
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location(
    "nembra_final_go_base_module_authority_redteam", MODULE_PATH
)
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

SOURCE = "a" * 40
DIGEST = "9" * 64
PR = 3613
REVIEW_ID = 8801
REVIEW_NODE_ID = "PRR_base_module_redteam"


def review_response() -> dict[str, object]:
    body = json.dumps(
        {
            "schemaVersion": 1,
            "authority": module.MANIFEST_REVIEW_AUTHORITY,
            "sourceCommitSHA": SOURCE,
            module.MANIFEST_DIGEST_KEY: DIGEST,
            "verdict": "ACCEPT",
        },
        sort_keys=True,
    )
    return {
        "id": REVIEW_ID,
        "node_id": REVIEW_NODE_ID,
        "state": "APPROVED",
        "commit_id": SOURCE,
        "user": {"login": module.OWNER},
        "author_association": "OWNER",
        "submitted_at": "2026-08-18T11:05:00Z",
        "body": body,
    }


class ForgedBase:
    """Caller-owned object accepted by the attacked public `base_module=` seam."""

    def __init__(self) -> None:
        self.git = lambda *_args, **_kwargs: "git"
        self.git_bytes = lambda *_args, **_kwargs: b"git-bytes"
        self.api_calls: list[str] = []

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
        self.api_calls.append(path)
        return b"{}", copy.deepcopy(review_response())


@contextlib.contextmanager
def noop_custody(*_args, **_kwargs):
    yield


class BaseModuleAuthorityRedTeamTests(unittest.TestCase):
    def setUp(self):
        self.original_semantic_build = module._SEMANTIC_BUILD
        self.original_candidate_custody = module._PREDECESSOR_CANDIDATE_GIT_CUSTODY
        self.original_vnode = module._CURRENT_VNODE_AUTHORITY
        self.original_adapter = module._SEMANTIC_MODULE._private_environment_adapter
        module._PREDECESSOR_CANDIDATE_GIT_CUSTODY = noop_custody
        module._CURRENT_VNODE_AUTHORITY = noop_custody

    def tearDown(self):
        module._SEMANTIC_BUILD = self.original_semantic_build
        module._PREDECESSOR_CANDIDATE_GIT_CUSTODY = self.original_candidate_custody
        module._CURRENT_VNODE_AUTHORITY = self.original_vnode
        module._SEMANTIC_MODULE._private_environment_adapter = self.original_adapter
        self.assertIsNone(module._ACTIVE_MANIFEST_REVIEW.get())
        self.assertFalse(module._CANDIDATE_RETIRED.get())

    @staticmethod
    def sealed_record() -> dict[str, object]:
        return {
            "privateFieldInstall": {"status": "complete"},
            "retainedSignedFieldArtifact": {"status": "retained"},
            "physicalResultCollected": False,
        }

    def test_caller_supplied_base_module_can_mint_manifest_review_authority(self):
        forged_base = ForgedBase()
        semantic_subjects: list[str] = []

        def semantic_build(**_kwargs):
            subject = module._ACTIVE_MANIFEST_REVIEW.get()
            self.assertIsNotNone(subject)
            semantic_subjects.append(subject[module.MANIFEST_DIGEST_KEY])
            return self.sealed_record()

        module._SEMANTIC_BUILD = semantic_build
        with tempfile.TemporaryDirectory(prefix="nembra-base-module-redteam-") as temporary:
            result = module.build(
                candidate_repo=Path(temporary),
                source=SOURCE,
                pr=PR,
                generated_manifest_review_id=REVIEW_ID,
                base_module=forged_base,
            )

        expected_path = f"/pulls/{PR}/reviews/{REVIEW_ID}"
        self.assertEqual(forged_base.api_calls, [expected_path, expected_path])
        self.assertEqual(semantic_subjects, [DIGEST])
        self.assertEqual(
            result[module.MANIFEST_RECORD_KEY][module.MANIFEST_DIGEST_KEY], DIGEST
        )
        self.assertEqual(result[module.MANIFEST_RECORD_KEY]["reviewNodeID"], REVIEW_NODE_ID)
        self.assertFalse(result["physicalResultCollected"])


if __name__ == "__main__":
    unittest.main()
