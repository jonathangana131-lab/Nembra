#!/usr/bin/env python3
"""Adversarial contract for the Final-GO source -> detached-record handoff.

These tests do not pretend watcher teardown can freeze a caller-owned checkout.
They prove the narrower production contract instead: all source-dependent work
and JSON detachment happen while exact #3042 candidate custody is still active,
no live candidate pathname can escape in the returned authority value, and a
mutation that happens only during custody teardown cannot rewrite the already-
detached result.

No Bluetooth, Tuya, signing, install, device, telemetry, or physical operation is
performed.
"""
from __future__ import annotations

import contextlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import types
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_sealed_record_handoff_subject", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Final-GO sealed-record successor")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class FakeBase:
    @staticmethod
    def canon(value, label):
        del label
        if not isinstance(value, str):
            raise ValueError("source is not text")
        return value.lower()


class FinalGoSealedRecordHandoffTests(unittest.TestCase):
    SOURCE = "a" * 40

    def test_exact_parent_is_pinned_to_current_3042_blob(self) -> None:
        self.assertEqual(MODULE.DIRECT_PARENT_SOURCE, "cb36f9265f08708c8e47564f62f4857aeae7af0f")
        self.assertEqual(
            MODULE.DIRECT_PARENT_MODULE_GIT_BLOB,
            "baef9de23a680bedf16f9f7b367f45f7710ac0c6",
        )
        repo = SCRIPT.resolve().parents[2]
        entry = MODULE._parent._direct_parent._tree_entries(
            repo, MODULE.DIRECT_PARENT_SOURCE
        )[MODULE.DIRECT_PARENT_MODULE_PATH]
        self.assertEqual(entry[1], MODULE.DIRECT_PARENT_MODULE_GIT_BLOB)

    def test_detachment_breaks_parent_container_aliases(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-detach-alias-") as temporary:
            root = Path(temporary).resolve()
            original = {
                "sourceCommitSHA": self.SOURCE,
                "nested": {"items": [1, 2, 3]},
            }
            detached = MODULE._detach_authority_record(original, root, self.SOURCE)
            original["nested"]["items"].append(4)
            self.assertEqual(detached["nested"]["items"], [1, 2, 3])
            self.assertNotEqual(id(detached), id(original))
            self.assertEqual(
                MODULE._detached_record_sha256(detached),
                MODULE._detached_record_sha256(
                    {"nested": {"items": [1, 2, 3]}, "sourceCommitSHA": self.SOURCE}
                ),
            )

    def test_detachment_rejects_live_candidate_path_reference(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-detach-path-") as temporary:
            root = Path(temporary).resolve()
            record = {
                "sourceCommitSHA": self.SOURCE,
                "debugPath": str(root / "A.swift"),
            }
            with self.assertRaisesRegex(
                MODULE.FinalGoRecordHandoffError,
                "live candidate pathname",
            ):
                MODULE._detach_authority_record(record, root, self.SOURCE)

    def test_detachment_rejects_mixed_source_authority(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-detach-source-") as temporary:
            root = Path(temporary).resolve()
            record = {
                "sourceCommitSHA": self.SOURCE,
                "nested": {"sourceCommitSHA": "b" * 40},
            }
            with self.assertRaisesRegex(
                MODULE.FinalGoRecordHandoffError,
                "source authority outside",
            ):
                MODULE._detach_authority_record(record, root, self.SOURCE)

    def test_detachment_requires_json_only_authority(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-detach-json-") as temporary:
            root = Path(temporary).resolve()
            record = {
                "sourceCommitSHA": self.SOURCE,
                "escapedHandle": object(),
            }
            with self.assertRaisesRegex(
                MODULE.FinalGoRecordHandoffError,
                "not a detached JSON authority value",
            ):
                MODULE._detach_authority_record(record, root, self.SOURCE)

    def test_detachment_requires_at_least_one_exact_source_binding(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-detach-binding-") as temporary:
            root = Path(temporary).resolve()
            with self.assertRaisesRegex(
                MODULE.FinalGoRecordHandoffError,
                "no sourceCommitSHA binding",
            ):
                MODULE._detach_authority_record({"authority": "fixture"}, root, self.SOURCE)

    def test_build_seals_before_custody_release_and_never_reopens_candidate(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-release-handoff-") as temporary:
            root = Path(temporary).resolve()
            tracked = root / "A.swift"
            tracked.write_text("accepted\n", encoding="utf-8")
            state = {"custody": False, "sealed": False, "released": False}

            original_custody = MODULE._parent._candidate_git_custody
            original_vnode = MODULE._parent._direct_parent._current_vnode_authority
            original_build = MODULE._parent._direct_parent._parent.build
            original_detach = MODULE._detach_authority_record

            @contextlib.contextmanager
            def fake_custody(base, candidate_repo, source):
                del base
                self.assertEqual(candidate_repo, root)
                self.assertEqual(source, self.SOURCE)
                state["custody"] = True
                try:
                    yield
                finally:
                    # This is the release-boundary schedule: the source changes
                    # only after the build result has been evaluated and sealed.
                    self.assertTrue(state["sealed"], "authority did not detach before release")
                    tracked.write_text("attacker-after-seal\n", encoding="utf-8")
                    state["custody"] = False
                    state["released"] = True

            @contextlib.contextmanager
            def fake_vnode():
                yield

            def fake_parent_build(**kwargs):
                self.assertTrue(state["custody"])
                self.assertFalse(state["released"])
                self.assertEqual(Path(kwargs["candidate_repo"]), root)
                self.assertEqual(kwargs["source"], self.SOURCE)
                return {
                    "authority": "fixture-final-go",
                    "sourceCommitSHA": self.SOURCE,
                    "nested": {
                        "sourceCommitSHA": self.SOURCE,
                        "capturedPayload": tracked.read_text(encoding="utf-8"),
                    },
                }

            def observed_detach(record, candidate_repo, source):
                self.assertTrue(state["custody"])
                self.assertFalse(state["released"])
                detached = original_detach(record, candidate_repo, source)
                state["sealed"] = True
                return detached

            MODULE._parent._candidate_git_custody = fake_custody
            MODULE._parent._direct_parent._current_vnode_authority = fake_vnode
            MODULE._parent._direct_parent._parent.build = fake_parent_build
            MODULE._detach_authority_record = observed_detach
            try:
                result = MODULE.build(
                    candidate_repo=root,
                    source=self.SOURCE,
                    base_module=FakeBase(),
                )
            finally:
                MODULE._detach_authority_record = original_detach
                MODULE._parent._direct_parent._parent.build = original_build
                MODULE._parent._direct_parent._current_vnode_authority = original_vnode
                MODULE._parent._candidate_git_custody = original_custody

            self.assertTrue(state["released"])
            self.assertEqual(tracked.read_text(encoding="utf-8"), "attacker-after-seal\n")
            self.assertEqual(result["nested"]["capturedPayload"], "accepted\n")
            self.assertEqual(result["sourceCommitSHA"], self.SOURCE)
            self.assertNotIn(str(root), repr(result))

            # Once build() returns, the checkout is intentionally not part of
            # this record's authority. Later mutations cannot change the sealed
            # JSON value or its diagnostic digest.
            digest = MODULE._detached_record_sha256(result)
            tracked.write_text("another-post-handoff-change\n", encoding="utf-8")
            self.assertEqual(MODULE._detached_record_sha256(result), digest)
            self.assertEqual(result["nested"]["capturedPayload"], "accepted\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
