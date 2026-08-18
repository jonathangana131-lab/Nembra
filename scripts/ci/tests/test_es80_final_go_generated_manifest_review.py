#!/usr/bin/env python3
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
SPEC = importlib.util.spec_from_file_location("nembra_final_go_manifest_successor", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

SOURCE = "a" * 40
DIGEST_A = "1" * 64
DIGEST_B = "2" * 64
REVIEW_ID = 7001
REVIEW_NODE_ID = "PRR_manifest_v1"
PR = 3606


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
        raise AssertionError(f"unexpected API fallback: {path}")


def review_payload(digest=DIGEST_A, *, source=SOURCE, extra=None):
    payload = {
        "schemaVersion": 1,
        "authority": module.MANIFEST_REVIEW_AUTHORITY,
        "sourceCommitSHA": source,
        module.MANIFEST_DIGEST_KEY: digest,
        "verdict": "ACCEPT",
    }
    if extra is not None:
        payload["extra"] = extra
    return payload


def review_response(
    digest=DIGEST_A,
    *,
    source=SOURCE,
    state="COMMENTED",
    login=module.OWNER,
    association="OWNER",
    node_id=REVIEW_NODE_ID,
    extra=None,
    body=None,
):
    return {
        "id": REVIEW_ID,
        "node_id": node_id,
        "state": state,
        "commit_id": source,
        "user": {"login": login},
        "author_association": association,
        "submitted_at": "2026-08-18T03:35:00Z",
        "body": body
        if body is not None
        else json.dumps(review_payload(digest, source=source, extra=extra), sort_keys=True),
    }


@contextlib.contextmanager
def noop_custody(*_args, **_kwargs):
    yield


class ReviewAuthorityTests(unittest.TestCase):
    def setUp(self):
        self.base = FakeBase()

    def get_for(self, response):
        def get(path):
            self.assertEqual(path, f"/pulls/{PR}/reviews/{REVIEW_ID}")
            return b"{}", copy.deepcopy(response)

        return get

    def test_exact_owner_review_binds_source_digest_and_review_identity(self):
        for state in ("COMMENTED", "APPROVED"):
            with self.subTest(state=state):
                response = review_response(state=state)
                subject = module.generated_manifest_review(
                    PR,
                    REVIEW_ID,
                    SOURCE,
                    self.get_for(response),
                    base=self.base,
                )
                self.assertEqual(subject["sourceCommitSHA"], SOURCE)
                self.assertEqual(subject[module.MANIFEST_DIGEST_KEY], DIGEST_A)
                self.assertEqual(subject["reviewID"], REVIEW_ID)
                self.assertEqual(subject["reviewNodeID"], REVIEW_NODE_ID)
                self.assertEqual(
                    subject["reviewBodySHA256"],
                    hashlib.sha256(response["body"].encode("utf-8")).hexdigest(),
                )
                self.assertEqual(subject["reviewer"], module.OWNER)
                self.assertEqual(subject["state"], state)
                self.assertEqual(subject["verdict"], "accepted")

    def test_rejected_dismissed_nonowner_or_missing_node_review_never_promotes(self):
        for response in (
            review_response(state="CHANGES_REQUESTED"),
            review_response(state="DISMISSED"),
            review_response(login="someone-else"),
            review_response(association="COLLABORATOR"),
            review_response(node_id=""),
        ):
            with self.subTest(response=response):
                with self.assertRaises(module.PrivateReviewGoError):
                    module.generated_manifest_review(
                        PR, REVIEW_ID, SOURCE, self.get_for(response), base=self.base
                    )

    def test_wrong_commit_malformed_digest_and_schema_extension_fail_closed(self):
        wrong_source = "b" * 40
        cases = (
            review_response(source=wrong_source),
            review_response(digest="A" * 64),
            review_response(extra="caller-authored-extension"),
        )
        for response in cases:
            with self.subTest(response=response):
                with self.assertRaises(module.PrivateReviewGoError):
                    module.generated_manifest_review(
                        PR, REVIEW_ID, SOURCE, self.get_for(response), base=self.base
                    )


class EnvironmentAuthorityTests(unittest.TestCase):
    def test_reviewed_digest_overwrites_hostile_ambient_value(self):
        environment = {
            "PATH": "/usr/bin:/bin",
            module.MANIFEST_ENV: DIGEST_B,
            "UNCHANGED": "yes",
        }
        subject = {module.MANIFEST_DIGEST_KEY: DIGEST_A}
        result = module._inject_manifest_environment(environment, subject)
        self.assertEqual(result[module.MANIFEST_ENV], DIGEST_A)
        self.assertEqual(result["UNCHANGED"], "yes")
        self.assertEqual(environment[module.MANIFEST_ENV], DIGEST_B)

    def test_noncanonical_reviewed_digest_never_enters_installer_environment(self):
        with self.assertRaises(module.PrivateReviewGoError):
            module._inject_manifest_environment(
                {module.MANIFEST_ENV: DIGEST_B},
                {module.MANIFEST_DIGEST_KEY: "not-a-digest"},
            )

    def test_inherited_two_stage_adapter_is_extended_only_at_final_environment(self):
        semantic = module._SEMANTIC_MODULE
        inherited_review = {
            semantic.PRIVATE_REVIEW_COMMITMENT_KEY: DIGEST_A,
            semantic.PRIVATE_REVIEW_HELPER_KEY: DIGEST_A,
            semantic.PROVENANCE_HELPER_KEY: DIGEST_A,
            semantic.GENERATED_HELPER_KEY: DIGEST_A,
        }

        def generated_parent_adapter(base, accepted_generated_digest):
            self.assertEqual(accepted_generated_digest, DIGEST_A)

            def generated_environment(device, device_digest, accepted_lock_sha256):
                return {
                    module.MANIFEST_ENV: DIGEST_B,
                    "DEVICE": str(device),
                    "LOCK": accepted_lock_sha256,
                }

            return generated_environment

        token = module._ACTIVE_MANIFEST_REVIEW.set(
            {module.MANIFEST_DIGEST_KEY: DIGEST_A}
        )
        try:
            adapter = module._manifest_environment_adapter(
                generated_parent_adapter, inherited_review
            )
            environment_builder = adapter(object(), DIGEST_A)
            result = environment_builder(Path("/tmp/device"), DIGEST_A, DIGEST_B)
        finally:
            module._ACTIVE_MANIFEST_REVIEW.reset(token)

        self.assertEqual(result[module.MANIFEST_ENV], DIGEST_A)
        self.assertEqual(result["DEVICE"], "/tmp/device")
        self.assertEqual(result["LOCK"], DIGEST_B)
        self.assertEqual(result[semantic.PRIVATE_REVIEW_ENV], DIGEST_A)
        self.assertEqual(result[semantic.PRIVATE_REVIEW_HELPER_ENV], DIGEST_A)
        self.assertEqual(result[semantic.PROVENANCE_HELPER_ENV], DIGEST_A)
        self.assertEqual(result[semantic.GENERATED_HELPER_ENV], DIGEST_A)


class BuildCompositionTests(unittest.TestCase):
    def setUp(self):
        self.base = FakeBase()
        self.original_semantic_build = module._SEMANTIC_BUILD
        self.original_candidate_custody = module._PREDECESSOR_CANDIDATE_GIT_CUSTODY
        self.original_vnode = module._CURRENT_VNODE_AUTHORITY
        self.original_semantic_adapter = module._SEMANTIC_MODULE._private_environment_adapter
        self.original_base_loader = module.generated._load_base_module
        module._PREDECESSOR_CANDIDATE_GIT_CUSTODY = noop_custody
        module._CURRENT_VNODE_AUTHORITY = noop_custody
        module.generated._load_base_module = lambda: self.base

    def tearDown(self):
        module._SEMANTIC_BUILD = self.original_semantic_build
        module._PREDECESSOR_CANDIDATE_GIT_CUSTODY = self.original_candidate_custody
        module._CURRENT_VNODE_AUTHORITY = self.original_vnode
        module._SEMANTIC_MODULE._private_environment_adapter = self.original_semantic_adapter
        module.generated._load_base_module = self.original_base_loader
        self.assertIsNone(module._ACTIVE_MANIFEST_REVIEW.get())

    @staticmethod
    def sealed_record():
        return {
            "privateFieldInstall": {"status": "complete"},
            "retainedSignedFieldArtifact": {"status": "retained"},
            "physicalResultCollected": False,
        }

    def run_build(self, get, semantic_build):
        module._SEMANTIC_BUILD = semantic_build
        original_api = self.base.api
        self.base.api = get
        try:
            with tempfile.TemporaryDirectory(prefix="nembra-manifest-final-go-") as temporary:
                return module.build(
                    candidate_repo=Path(temporary),
                    source=SOURCE,
                    pr=PR,
                    generated_manifest_review_id=REVIEW_ID,
                )
        finally:
            self.base.api = original_api

    def test_stable_review_is_retained_before_candidate_retirement(self):
        calls = []
        response = review_response()
        record = self.sealed_record()

        def get(path):
            calls.append(path)
            return b"{}", copy.deepcopy(response)

        result = self.run_build(get, lambda **_kwargs: record)
        self.assertIs(result, record)
        self.assertEqual(calls, [f"/pulls/{PR}/reviews/{REVIEW_ID}"] * 2)
        subject = record[module.MANIFEST_RECORD_KEY]
        self.assertEqual(subject["authority"], module.MANIFEST_RECORD_AUTHORITY)
        self.assertEqual(subject["sourceCommitSHA"], SOURCE)
        self.assertEqual(subject[module.MANIFEST_DIGEST_KEY], DIGEST_A)
        self.assertEqual(subject["reviewNodeID"], REVIEW_NODE_ID)
        self.assertEqual(
            subject["reviewBodySHA256"],
            hashlib.sha256(response["body"].encode("utf-8")).hexdigest(),
        )
        self.assertEqual(subject["reviewer"], module.OWNER)
        self.assertEqual(subject["state"], "COMMENTED")
        self.assertFalse(record["physicalResultCollected"])
        self.assertIs(
            module._SEMANTIC_MODULE._private_environment_adapter,
            self.original_semantic_adapter,
        )

    def test_review_digest_drift_after_private_side_effect_fails_closed(self):
        responses = [review_response(DIGEST_A), review_response(DIGEST_B)]

        def get(path):
            return b"{}", responses.pop(0)

        with self.assertRaisesRegex(
            module.PrivateReviewGoError,
            "review changed during Final-GO composition",
        ):
            self.run_build(get, lambda **_kwargs: self.sealed_record())
        self.assertIs(
            module._SEMANTIC_MODULE._private_environment_adapter,
            self.original_semantic_adapter,
        )

    def test_semantically_equivalent_review_body_rewrite_after_side_effect_fails_closed(self):
        canonical = review_response()
        reformatted = review_response(
            body=json.dumps(review_payload(), indent=2, sort_keys=True)
        )
        self.assertEqual(json.loads(canonical["body"]), json.loads(reformatted["body"]))
        responses = [canonical, reformatted]

        def get(path):
            return b"{}", responses.pop(0)

        with self.assertRaisesRegex(
            module.PrivateReviewGoError,
            "review changed during Final-GO composition",
        ):
            self.run_build(get, lambda **_kwargs: self.sealed_record())

    def test_review_dismissal_after_private_side_effect_fails_closed(self):
        responses = [review_response(), review_response(state="DISMISSED")]

        def get(path):
            return b"{}", responses.pop(0)

        with self.assertRaises(module.PrivateReviewGoError):
            self.run_build(get, lambda **_kwargs: self.sealed_record())
        self.assertFalse(module._CANDIDATE_RETIRED.get())

    def test_caller_cannot_replace_production_review_transport(self):
        side_effect = []

        def semantic_build(**_kwargs):
            side_effect.append("ran")
            return self.sealed_record()

        module._SEMANTIC_BUILD = semantic_build
        with tempfile.TemporaryDirectory(prefix="nembra-manifest-final-go-") as temporary:
            with self.assertRaisesRegex(
                module.PrivateReviewGoError,
                "caller-supplied Final-GO review authority is forbidden",
            ):
                module.build(
                    candidate_repo=Path(temporary),
                    source=SOURCE,
                    pr=PR,
                    generated_manifest_review_id=REVIEW_ID,
                    get=lambda _path: (b"{}", copy.deepcopy(review_response(DIGEST_B))),
                )
        self.assertEqual(side_effect, [])

    def test_caller_cannot_replace_production_base_authority(self):
        forged_base = FakeBase()
        forged_base.api = lambda _path: (b"{}", copy.deepcopy(review_response(DIGEST_B)))
        side_effect = []

        def semantic_build(**_kwargs):
            side_effect.append("ran")
            return self.sealed_record()

        module._SEMANTIC_BUILD = semantic_build
        with tempfile.TemporaryDirectory(prefix="nembra-manifest-final-go-") as temporary:
            with self.assertRaisesRegex(
                module.PrivateReviewGoError,
                "caller-supplied Final-GO review authority is forbidden",
            ):
                module.build(
                    candidate_repo=Path(temporary),
                    source=SOURCE,
                    pr=PR,
                    generated_manifest_review_id=REVIEW_ID,
                    base_module=forged_base,
                )
        self.assertEqual(side_effect, [])

    def test_lock_wait_review_drift_fails_before_semantic_side_effect(self):
        current = {"review": review_response(DIGEST_A)}
        api_calls = []
        semantic_side_effect = threading.Event()
        entered_lock = threading.Event()
        release_lock = threading.Event()
        failures = []

        def api(path):
            api_calls.append(path)
            return b"{}", copy.deepcopy(current["review"])

        self.base.api = api

        class GateLock:
            def __enter__(inner_self):
                entered_lock.set()
                if not release_lock.wait(5):
                    raise AssertionError("test gate was not released")
                return inner_self

            def __exit__(inner_self, exc_type, exc, tb):
                return False

        original_lock = module._MANIFEST_EXTENSION_LOCK
        module._MANIFEST_EXTENSION_LOCK = GateLock()
        try:
            with tempfile.TemporaryDirectory(prefix="nembra-manifest-final-go-") as temporary:
                candidate = Path(temporary)

                def semantic_build(**_kwargs):
                    semantic_side_effect.set()
                    return self.sealed_record()

                module._SEMANTIC_BUILD = semantic_build

                def worker():
                    try:
                        module.build(
                            candidate_repo=candidate,
                            source=SOURCE,
                            pr=PR,
                            generated_manifest_review_id=REVIEW_ID,
                        )
                    except Exception as error:
                        failures.append(error)

                thread = threading.Thread(target=worker, daemon=True)
                thread.start()
                self.assertTrue(entered_lock.wait(5), "composition never reached lock")
                current["review"] = review_response(DIGEST_A, state="DISMISSED")
                release_lock.set()
                thread.join(5)
                self.assertFalse(thread.is_alive(), "composition worker did not finish")
        finally:
            release_lock.set()
            module._MANIFEST_EXTENSION_LOCK = original_lock

        self.assertFalse(semantic_side_effect.is_set())
        self.assertEqual(len(api_calls), 1)
        self.assertEqual(len(failures), 1)
        self.assertIsInstance(failures[0], module.PrivateReviewGoError)

    def test_semantic_failure_restores_adapter_context_and_candidate_dispatch(self):
        def get(path):
            return b"{}", review_response()

        def fail(**_kwargs):
            raise RuntimeError("synthetic semantic failure")

        original_git = self.base.git
        original_git_bytes = self.base.git_bytes
        with self.assertRaisesRegex(RuntimeError, "synthetic semantic failure"):
            self.run_build(get, fail)
        self.assertIs(
            module._SEMANTIC_MODULE._private_environment_adapter,
            self.original_semantic_adapter,
        )
        self.assertIs(self.base.git, original_git)
        self.assertIs(self.base.git_bytes, original_git_bytes)
        self.assertFalse(module._CANDIDATE_RETIRED.get())


if __name__ == "__main__":
    unittest.main(verbosity=2)