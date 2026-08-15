#!/usr/bin/env python3
"""Regress descriptor-bound private read-lease symlink classification."""
from __future__ import annotations

import importlib.util
import inspect
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_held_symlink_policy", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseHeldSymlinkPolicyTests(unittest.TestCase):
    def test_pathname_generation_swap_cannot_classify_held_external_symlink(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-held-symlink-policy-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)

            external = outer / "outside-subject"
            external.mkdir()
            (external / "outside.fixture").write_text("outside\n", encoding="utf-8")
            (subject / "escape").symlink_to(external, target_is_directory=True)

            replacement = outer / "replacement-build"
            replacement.mkdir()
            (replacement / "escape").symlink_to(".", target_is_directory=True)
            accepted_hold = repo / "LocalSecrets/TuyaSDK/Build.accepted-hold"

            original_subject_entries = helper._subject_entries
            raced = False

            def classify_replacement_then_restore(path: Path, *, include_signatures: bool = False):
                nonlocal raced
                candidate = Path(path)
                if candidate != subject or raced:
                    return original_subject_entries(candidate, include_signatures=include_signatures)
                subject.rename(accepted_hold)
                replacement.rename(subject)
                try:
                    result = original_subject_entries(subject, include_signatures=include_signatures)
                finally:
                    subject.rename(replacement)
                    accepted_hold.rename(subject)
                raced = True
                return result

            lease = helper._PrivateReadLease((subject,), repo)
            with mock.patch.object(
                helper,
                "_subject_entries",
                side_effect=classify_replacement_then_restore,
            ):
                with self.assertRaisesRegex(
                    helper.SelectedXcodeBuildOrchestratorError,
                    "symlink escaped its held subject",
                ):
                    lease.grant("nembrasymlinkpolicy")

            self.assertFalse(raced)
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")

    def test_internal_relative_symlink_is_topology_not_acl_subject(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-held-symlink-internal-") as raw:
            repo = Path(raw) / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            target = subject / "Framework/Versions/A/private.fixture"
            target.parent.mkdir(parents=True)
            target.write_bytes(b"fixture\n")
            current = subject / "Framework/Versions/Current"
            current.symlink_to("A", target_is_directory=True)

            plan = helper._lease_paths((subject,), repo, include_descriptors=True)
            try:
                planned_paths = {Path(entry[0]) for entry in plan}
                self.assertIn(subject, planned_paths)
                self.assertIn(target, planned_paths)
                self.assertNotIn(current, planned_paths)
            finally:
                for _path, _host_only, _signature, descriptor in reversed(plan):
                    os.close(int(descriptor))

    def test_relative_escape_fails_closed(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-held-symlink-relative-escape-") as raw:
            repo = Path(raw) / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)
            (subject / "escape").symlink_to("../../../../outside")
            with self.assertRaisesRegex(
                helper.SelectedXcodeBuildOrchestratorError,
                "symlink escaped its held subject",
            ):
                helper._lease_paths((subject,), repo, include_descriptors=True)

    def test_source_descriptor_mode_owns_symlink_classification(self) -> None:
        helper = load()
        policy = inspect.getsource(helper._subject_entries_from_descriptor)
        readlink = inspect.getsource(helper._held_readlink)
        plan = inspect.getsource(helper._lease_paths)
        self.assertIn("os.listdir(directory_descriptor)", policy)
        self.assertIn("_held_readlink", policy)
        self.assertIn("dir_fd=parent_descriptor", readlink)
        self.assertIn("_subject_entries_from_descriptor", plan)
        self.assertIn("include_descriptors", plan)


if __name__ == "__main__":
    unittest.main(verbosity=2)
