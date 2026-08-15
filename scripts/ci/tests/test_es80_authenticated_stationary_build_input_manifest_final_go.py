#!/usr/bin/env python3
"""Focused control acceptance for reviewed generated/private build-input authority."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/ci/es80_authenticated_stationary_build_input_manifest_final_go.py"

SPEC = importlib.util.spec_from_file_location("nembra_build_input_manifest_final_go", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load build-input manifest Final-GO control")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SOURCE = "a" * 40
LOCK = "b" * 64
MANIFEST = "c" * 64
STANDARD = "d" * 64
ACCESSIBILITY = "e" * 64


def semantic_namespace() -> dict[str, object]:
    def canon(value, _label):
        if not isinstance(value, str) or len(value) != 40:
            raise ValueError("bad canon")
        return value.lower()

    def pos(value, _label):
        if not isinstance(value, int) or value <= 0:
            raise ValueError("bad positive")
        return value

    def obj(raw, _label):
        return json.loads(raw)

    def sha(raw):
        return hashlib.sha256(raw).hexdigest()

    def review(*_args, **_kwargs):
        raise AssertionError("original review should be patched")

    def installer_environment(_device, _device_digest, accepted_lock_sha256):
        return {"BASE": "accepted", "LOCK": accepted_lock_sha256}

    namespace: dict[str, object] = {
        "canon": canon,
        "pos": pos,
        "obj": obj,
        "sha": sha,
        "review": review,
        "installer_environment": installer_environment,
    }
    exec(
        "def semantic_build():\n    return None\n",
        namespace,
    )
    return namespace


def visual() -> dict[str, object]:
    return {
        "runID": 70,
        "artifactID": 80,
        "screenshots": {
            "unprovisioned-dark-standard": {"sha256": STANDARD},
            "unprovisioned-dark-accessibility-xxxl": {"sha256": ACCESSIBILITY},
        },
    }


def review_body(manifest: str = MANIFEST) -> str:
    return json.dumps(
        {
            "schemaVersion": 4,
            "authority": MODULE.REVIEW_AUTHORITY,
            "sourceCommitSHA": SOURCE,
            "visualRunID": 70,
            "visualArtifactID": 80,
            "standardScreenshotSHA256": STANDARD,
            "accessibilityScreenshotSHA256": ACCESSIBILITY,
            "tuyaDependencyLockSHA256": LOCK,
            MODULE.REVIEW_KEY: manifest,
            "verdict": "accepted",
        },
        sort_keys=True,
    )


def get_review(path: str, *, manifest: str = MANIFEST, owner: str = MODULE.OWNER):
    if path != "/pulls/9/reviews/11":
        raise AssertionError(path)
    record = {
        "id": 11,
        "node_id": "review-node",
        "state": "APPROVED",
        "commit_id": SOURCE,
        "body": review_body(manifest),
        "submitted_at": "2026-08-14T23:00:00Z",
        "author_association": "OWNER",
        "user": {"login": owner},
    }
    return json.dumps(record).encode(), record


class BuildInputManifestFinalGoTests(unittest.TestCase):
    def test_exact_parent_and_manifest_helper_git_blobs_are_pinned(self) -> None:
        parent = MODULE._accepted_git_blob(
            ROOT,
            MODULE.PARENT_SOURCE,
            MODULE.PARENT_PATH,
            MODULE.PARENT_BLOB,
        )
        helper = MODULE._accepted_git_blob(
            ROOT,
            "HEAD",
            MODULE.MANIFEST_HELPER_PATH,
            MODULE.MANIFEST_HELPER_BLOB,
        )
        self.assertEqual(MODULE._canonical_blob_oid(parent, MODULE.PARENT_BLOB), MODULE.PARENT_BLOB)
        self.assertEqual(
            MODULE._canonical_blob_oid(helper, MODULE.MANIFEST_HELPER_BLOB),
            MODULE.MANIFEST_HELPER_BLOB,
        )

    def test_review_v4_requires_owner_exact_source_pixels_lock_and_manifest(self) -> None:
        semantic = semantic_namespace()
        accepted = MODULE.review_v4(9, 11, SOURCE, visual(), get_review, semantic=semantic)
        self.assertEqual(accepted["tuyaDependencyLockSHA256"], LOCK)
        self.assertEqual(accepted[MODULE.REVIEW_KEY], MANIFEST)
        self.assertEqual(accepted["authority"], MODULE.REVIEW_AUTHORITY)

        with self.assertRaises(MODULE.BuildInputManifestFinalGoError):
            MODULE.review_v4(
                9,
                11,
                SOURCE,
                visual(),
                lambda path: get_review(path, owner="not-owner"),
                semantic=semantic,
            )
        with self.assertRaises(MODULE.BuildInputManifestFinalGoError):
            MODULE.review_v4(
                9,
                11,
                SOURCE,
                visual(),
                lambda path: get_review(path, manifest="BAD"),
                semantic=semantic,
            )

    def test_semantic_adapter_verifies_manifest_before_adding_closed_environment_key(self) -> None:
        semantic = semantic_namespace()
        original_review = semantic["review"]
        original_environment = semantic["installer_environment"]
        parent = types.SimpleNamespace(_SEMANTIC_BUILD=semantic["semantic_build"])
        with tempfile.TemporaryDirectory(prefix="nembra-manifest-control-") as temporary:
            candidate = Path(temporary)
            with mock.patch.object(MODULE, "derive_generated_manifest_sha256", return_value=MANIFEST):
                with MODULE._semantic_manifest_authority(
                    parent,
                    candidate_repo=candidate,
                    source=SOURCE,
                ) as state:
                    reviewed = semantic["review"](9, 11, SOURCE, visual(), get_review)
                    environment = semantic["installer_environment"](
                        Path("/private/device"),
                        "f" * 64,
                        LOCK,
                    )
                    self.assertEqual(reviewed[MODULE.REVIEW_KEY], MANIFEST)
                    self.assertEqual(state["digest"], MANIFEST)
                    self.assertEqual(environment[MODULE.ENV_KEY], MANIFEST)
                    self.assertEqual(environment["BASE"], "accepted")
            self.assertIs(semantic["review"], original_review)
            self.assertIs(semantic["installer_environment"], original_environment)

    def test_environment_fails_closed_before_review_or_when_parent_preowns_key(self) -> None:
        semantic = semantic_namespace()
        parent = types.SimpleNamespace(_SEMANTIC_BUILD=semantic["semantic_build"])
        with tempfile.TemporaryDirectory(prefix="nembra-manifest-env-order-") as temporary:
            with MODULE._semantic_manifest_authority(
                parent,
                candidate_repo=Path(temporary),
                source=SOURCE,
            ):
                with self.assertRaisesRegex(
                    MODULE.BuildInputManifestFinalGoError,
                    "before owner-reviewed",
                ):
                    semantic["installer_environment"](Path("/device"), "f" * 64, LOCK)

        semantic = semantic_namespace()
        semantic["installer_environment"] = lambda *_args: {MODULE.ENV_KEY: "preowned"}
        exec("def semantic_build_two():\n    return None\n", semantic)
        parent = types.SimpleNamespace(_SEMANTIC_BUILD=semantic["semantic_build_two"])
        with tempfile.TemporaryDirectory(prefix="nembra-manifest-env-preowned-") as temporary:
            with mock.patch.object(MODULE, "derive_generated_manifest_sha256", return_value=MANIFEST):
                with MODULE._semantic_manifest_authority(
                    parent,
                    candidate_repo=Path(temporary),
                    source=SOURCE,
                ):
                    semantic["review"](9, 11, SOURCE, visual(), get_review)
                    with self.assertRaisesRegex(
                        MODULE.BuildInputManifestFinalGoError,
                        "already owns",
                    ):
                        semantic["installer_environment"](Path("/device"), "f" * 64, LOCK)

    def test_build_preserves_parent_record_and_cannot_create_physical_authority(self) -> None:
        semantic = semantic_namespace()
        captured: dict[str, object] = {}

        def parent_build(*, candidate_repo, source, **_kwargs):
            reviewed = semantic["review"](9, 11, source, visual(), get_review)
            environment = semantic["installer_environment"](Path("/device"), "f" * 64, LOCK)
            captured["environment"] = environment
            # Re-review as the semantic production build does after private install.
            post_review = semantic["review"](9, 11, source, visual(), get_review)
            self.assertEqual(reviewed, post_review)
            return {
                "authority": "accepted-parent-authority",
                "visualReview": reviewed,
                "privateFieldInstall": {"result": "success"},
                "retainedSignedFieldArtifact": {"retained": True},
                "physicalResultCollected": False,
            }

        parent = types.SimpleNamespace(
            _SEMANTIC_BUILD=semantic["semantic_build"],
            build=parent_build,
        )
        with tempfile.TemporaryDirectory(prefix="nembra-manifest-build-") as temporary:
            with mock.patch.object(MODULE, "derive_generated_manifest_sha256", return_value=MANIFEST):
                record = MODULE.build(
                    candidate_repo=Path(temporary),
                    source=SOURCE,
                    parent_module=parent,
                )
        self.assertEqual(record["authority"], "accepted-parent-authority")
        self.assertFalse(record["physicalResultCollected"])
        self.assertEqual(record["acceptedGeneratedBuildInputManifestSHA256"], MANIFEST)
        authority = record["generatedBuildInputManifestAuthority"]
        self.assertFalse(authority["installerConsumerIntegrated"])
        self.assertFalse(authority["physicalAuthorityCreated"])
        self.assertEqual(captured["environment"][MODULE.ENV_KEY], MANIFEST)


if __name__ == "__main__":
    unittest.main(verbosity=2)
