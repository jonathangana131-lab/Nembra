#!/usr/bin/env python3
"""Portable regressions for component-anchored, held-descriptor lease admission."""
from __future__ import annotations

import importlib.util
import inspect
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_component_walk", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseComponentWalkTests(unittest.TestCase):
    def test_intermediate_symlink_swap_is_rejected_after_plan(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-walk-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            legitimate = repo / "LocalSecrets/TuyaSDK/Build"
            legitimate.mkdir(parents=True)
            planned = helper._lease_paths((legitimate,), repo)
            self.assertIn((legitimate, False), planned)

            sdk = repo / "LocalSecrets/TuyaSDK"
            sdk.rename(repo / "LocalSecrets/TuyaSDK.original")
            attacker = outer / "attacker/TuyaSDK"
            attacker_build = attacker / "Build"
            attacker_build.mkdir(parents=True)
            sdk.symlink_to(attacker, target_is_directory=True)

            plain = os.open(legitimate, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                self.assertEqual(os.fstat(plain).st_ino, attacker_build.stat().st_ino)
            finally:
                os.close(plain)

            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._open_pinned_path(legitimate, True)

    def test_real_directory_and_regular_file_still_open(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-walk-control-") as raw:
            root = Path(raw)
            directory = root / "a/b/c"
            directory.mkdir(parents=True)
            file = directory / "private.fixture"
            file.write_bytes(b"fixture\n")
            for path, is_directory in ((directory, True), (file, False)):
                descriptor = helper._open_pinned_path(path, is_directory)
                try:
                    self.assertEqual(
                        helper._descriptor_signature(descriptor),
                        helper._path_signature(path),
                    )
                finally:
                    os.close(descriptor)

    def test_real_directory_replacement_is_rejected_against_planned_identity(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-real-swap-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            legitimate = repo / "LocalSecrets/TuyaSDK/Build"
            legitimate.mkdir(parents=True)
            planned = helper._lease_paths((legitimate,), repo, include_signatures=True)
            expected = next(
                signature
                for path, _host_only, signature in planned
                if path == legitimate
            )

            sdk = repo / "LocalSecrets/TuyaSDK"
            sdk.rename(repo / "LocalSecrets/TuyaSDK.original")
            replacement = repo / "LocalSecrets/TuyaSDK/Build"
            replacement.mkdir(parents=True)
            self.assertFalse(sdk.is_symlink())
            self.assertFalse(replacement.is_symlink())
            self.assertNotEqual(expected, helper._path_signature(replacement))

            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._open_pinned_path(legitimate, True, expected)

    def test_descriptor_plan_rejects_mixed_generation_descendant(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-mixed-generation-") as raw:
            outer = Path(raw)
            outer.chmod(0o711)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)
            (subject / "accepted.bin").write_bytes(b"accepted\n")

            sdk = repo / "LocalSecrets/TuyaSDK"
            accepted_sdk = repo / "LocalSecrets/TuyaSDK.accepted"
            attacker_sdk = outer / "attacker/TuyaSDK"
            attacker_build = attacker_sdk / "Build"
            attacker_build.mkdir(parents=True)
            (attacker_build / "substituted.bin").write_bytes(b"substituted\n")

            real_subject_entries = helper._subject_entries
            swapped = False

            def swap_after_ancestry(path: Path, *, include_signatures: bool = False):
                nonlocal swapped
                if Path(path) == subject and not swapped:
                    sdk.rename(accepted_sdk)
                    attacker_sdk.rename(sdk)
                    swapped = True
                return real_subject_entries(path, include_signatures=include_signatures)

            with mock.patch.object(
                helper,
                "_subject_entries",
                side_effect=swap_after_ancestry,
            ):
                with self.assertRaisesRegex(
                    helper.SelectedXcodeBuildOrchestratorError,
                    "held ancestry disagrees|no longer reachable|pathname changed",
                ):
                    helper._lease_paths(
                        (subject,), repo, include_descriptors=True
                    )
            self.assertTrue(swapped)

    def test_actual_grant_rejects_mixed_generation_before_acl_mutation(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-mixed-grant-") as raw:
            outer = Path(raw)
            outer.chmod(0o711)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)
            (subject / "accepted.bin").write_bytes(b"accepted\n")

            sdk = repo / "LocalSecrets/TuyaSDK"
            accepted_sdk = repo / "LocalSecrets/TuyaSDK.accepted"
            attacker_sdk = outer / "attacker/TuyaSDK"
            attacker_build = attacker_sdk / "Build"
            attacker_build.mkdir(parents=True)
            (attacker_build / "substituted.bin").write_bytes(b"substituted\n")
            real_subject_entries = helper._subject_entries
            swapped = False

            def swap_after_ancestry(path: Path, *, include_signatures: bool = False):
                nonlocal swapped
                if Path(path) == subject and not swapped:
                    sdk.rename(accepted_sdk)
                    attacker_sdk.rename(sdk)
                    swapped = True
                return real_subject_entries(path, include_signatures=include_signatures)

            def unexpected_acl(_descriptor: int) -> str:
                raise AssertionError("mixed-generation descriptor reached ACL inspection")

            lease = helper._PrivateReadLease((subject,), repo)
            with (
                mock.patch.object(
                    helper,
                    "_subject_entries",
                    side_effect=swap_after_ancestry,
                ),
                mock.patch.object(helper, "_acl_listing", side_effect=unexpected_acl),
            ):
                with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                    lease.grant("nembramixedgeneration")
            self.assertTrue(swapped)
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")

    def test_descriptor_bound_symlink_policy_rejects_pathname_generation_swap(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-held-symlink-race-") as raw:
            outer = Path(raw)
            outer.chmod(0o711)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)

            external = outer / "outside-subject"
            external.mkdir()
            (external / "outside.fixture").write_text("outside\n", encoding="utf-8")
            (subject / "escape").symlink_to(external, target_is_directory=True)
            accepted_hold = repo / "LocalSecrets/TuyaSDK/Build.accepted-hold"

            replacement = outer / "replacement-build"
            replacement.mkdir()
            (replacement / "escape").symlink_to(".", target_is_directory=True)

            original_subject_entries = helper._subject_entries
            raced = False

            def classify_replacement_then_restore(
                path: Path,
                *,
                include_signatures: bool = False,
            ):
                nonlocal raced
                candidate = Path(path)
                if candidate != subject or raced:
                    return original_subject_entries(
                        candidate,
                        include_signatures=include_signatures,
                    )
                subject.rename(accepted_hold)
                replacement.rename(subject)
                try:
                    entries = original_subject_entries(
                        subject,
                        include_signatures=include_signatures,
                    )
                finally:
                    subject.rename(replacement)
                    accepted_hold.rename(subject)
                raced = True
                return entries

            def unexpected_acl(_descriptor: int) -> str:
                raise AssertionError("untrusted held symlink reached ACL inspection")

            lease = helper._PrivateReadLease((subject,), repo)
            with (
                mock.patch.object(
                    helper,
                    "_subject_entries",
                    side_effect=classify_replacement_then_restore,
                ),
                mock.patch.object(helper, "_acl_listing", side_effect=unexpected_acl),
            ):
                with self.assertRaisesRegex(
                    helper.SelectedXcodeBuildOrchestratorError,
                    "symlink escaped|symlink target",
                ):
                    lease.grant("nembraheldsymlink")
            self.assertTrue(raced)
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")

    def test_descriptor_bound_symlink_policy_accepts_internal_framework_chain(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-held-symlink-control-") as raw:
            repo = Path(raw) / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            headers = subject / "Thing.framework/Versions/A/Headers"
            headers.mkdir(parents=True)
            (headers / "Thing.h").write_text("// fixture\n", encoding="utf-8")
            (subject / "Thing.framework/Versions/Current").symlink_to(
                "A",
                target_is_directory=True,
            )
            (subject / "Thing.framework/Headers").symlink_to(
                "Versions/Current/Headers",
                target_is_directory=True,
            )

            plan = helper._lease_paths((subject,), repo, include_descriptors=True)
            try:
                paths = {entry[0] for entry in plan}
                self.assertIn(headers, paths)
                self.assertIn(headers / "Thing.h", paths)
                self.assertNotIn(subject / "Thing.framework/Versions/Current", paths)
                self.assertNotIn(subject / "Thing.framework/Headers", paths)
            finally:
                for _path, _host_only, _signature, descriptor in reversed(plan):
                    os.close(int(descriptor))

    def test_post_validation_retarget_is_rejected_before_acl_mutation(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-post-validate-retarget-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            inside = subject / "inside"
            inside.mkdir(parents=True)
            (inside / "inside.fixture").write_text("inside\n", encoding="utf-8")
            external = outer / "outside-subject"
            external.mkdir()
            (external / "outside.fixture").write_text("outside\n", encoding="utf-8")
            link = subject / "escape"
            link.symlink_to("inside", target_is_directory=True)

            real_validator = helper._validate_subject_symlinks_from_descriptor
            retargeted = False

            def validate_safe_then_retarget(admitted_subject: Path, descriptor: int):
                nonlocal retargeted
                generations = real_validator(admitted_subject, descriptor)
                if not retargeted:
                    link.unlink()
                    link.symlink_to(external, target_is_directory=True)
                    retargeted = True
                return generations

            def unexpected_acl(_descriptor: int) -> str:
                raise AssertionError("post-validation retarget reached ACL inspection")

            lease = helper._PrivateReadLease((subject,), repo)
            with (
                mock.patch.object(
                    helper,
                    "_validate_subject_symlinks_from_descriptor",
                    side_effect=validate_safe_then_retarget,
                ),
                mock.patch.object(helper, "_acl_listing", side_effect=unexpected_acl),
            ):
                with self.assertRaisesRegex(
                    helper.SelectedXcodeBuildOrchestratorError,
                    "namespace generation changed|symlink escaped|symlink target",
                ):
                    lease.grant("nembrapostvalidate")
            self.assertTrue(retargeted)
            self.assertFalse(lease._opened)
            self.assertFalse(lease._namespace_witnesses)
            self.assertEqual(lease._principal, "")

    def test_build_window_symlink_retarget_restore_invalidates_after_cleanup(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-build-window-retarget-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            inside = subject / "inside"
            inside.mkdir(parents=True)
            (inside / "inside.fixture").write_text("inside\n", encoding="utf-8")
            external = outer / "outside-subject"
            external.mkdir()
            link = subject / "escape"
            link.symlink_to("inside", target_is_directory=True)

            acl_state: dict[int, str] = {}

            def fake_acl_listing(descriptor: int) -> str:
                return acl_state.get(descriptor, "")

            def fake_chmod_acl(descriptor: int, operation: str, acl: str) -> None:
                if operation == "+a":
                    acl_state[descriptor] = f"0: {acl}"
                elif operation == "-a":
                    acl_state[descriptor] = ""
                else:
                    raise AssertionError(f"unexpected ACL operation: {operation}")

            lease = helper._PrivateReadLease((subject,), repo)
            with (
                mock.patch.object(helper, "_acl_listing", side_effect=fake_acl_listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=fake_chmod_acl),
            ):
                lease.grant("nembralifetime")
                self.assertTrue(lease._opened)
                self.assertTrue(lease._namespace_witnesses)

                # Retarget and restore the exact pathname before revoke. A
                # final pathname reread would see the safe text again; the
                # held parent-directory generation must still remember it.
                time.sleep(0.01)
                link.unlink()
                link.symlink_to(external, target_is_directory=True)
                link.unlink()
                link.symlink_to("inside", target_is_directory=True)

                with self.assertRaisesRegex(
                    helper.SelectedXcodeBuildOrchestratorError,
                    "namespace changed during guarded build",
                ):
                    lease.revoke()

            self.assertTrue(all(value == "" for value in acl_state.values()))
            self.assertFalse(lease._opened)
            self.assertFalse(lease._namespace_witnesses)
            self.assertEqual(lease._principal, "")
            self.assertEqual(link.readlink(), Path("inside"))

    def test_held_descriptor_prevents_inode_reuse_after_admission(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-held-inode-") as raw:
            repo = Path(raw) / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)
            plan = helper._lease_paths((subject,), repo, include_descriptors=True)
            try:
                entry = next(item for item in plan if item[0] == subject)
                accepted_signature = entry[2]
                accepted_descriptor = int(entry[3])
                self.assertEqual(
                    helper._descriptor_signature(accepted_descriptor),
                    accepted_signature,
                )

                retired = repo / "LocalSecrets/TuyaSDK/Build.retired"
                subject.rename(retired)
                retired.rmdir()
                for _ in range(2000):
                    subject.mkdir()
                    self.assertNotEqual(
                        helper._path_signature(subject), accepted_signature
                    )
                    subject.rmdir()
            finally:
                for _path, _host_only, _signature, descriptor in reversed(plan):
                    os.close(int(descriptor))

    def test_source_production_grant_consumes_held_descriptor_plan(self) -> None:
        helper = load()
        opener = inspect.getsource(helper._open_pinned_path)
        lease_paths = inspect.getsource(helper._lease_paths)
        verifier = inspect.getsource(helper._verify_descriptor_plan)
        symlink_validator = inspect.getsource(helper._validate_subject_symlinks_from_descriptor)
        symlink_target = inspect.getsource(helper._validate_held_symlink_target)
        namespace_validator = inspect.getsource(helper._validated_namespace_witnesses)
        namespace_verifier = inspect.getsource(helper._verify_namespace_generation_witnesses)
        grant = inspect.getsource(helper._PrivateReadLease.grant)
        revoke = inspect.getsource(helper._PrivateReadLease.revoke)
        self.assertIn("dir_fd=current", opener)
        self.assertIn("O_NOFOLLOW", opener)
        self.assertIn("include_descriptors", lease_paths)
        self.assertIn("_verify_descriptor_plan", lease_paths)
        self.assertIn("_validate_subject_symlinks_from_descriptor", lease_paths)
        self.assertIn("_open_pinned_child", verifier)
        self.assertIn("os.listdir(directory_descriptor)", symlink_validator)
        self.assertIn("os.readlink(name, dir_fd=directory_descriptor)", symlink_validator)
        self.assertIn("os.readlink(component, dir_fd=current)", symlink_target)
        self.assertNotIn(".resolve(strict=True)", symlink_validator)
        self.assertNotIn(".resolve(strict=True)", symlink_target)
        self.assertIn("include_descriptors=True", grant)
        self.assertIn("accepted_signature, descriptor", grant)
        self.assertNotIn("include_signatures=True", grant)
        self.assertIn("_validated_namespace_witnesses", namespace_validator)
        self.assertIn("_verify_namespace_generation_witnesses", namespace_validator)
        self.assertIn("namespace_witnesses_out", lease_paths)
        self.assertIn("_validated_namespace_witnesses", lease_paths)
        self.assertIn("_validated_namespace_witnesses", grant)
        self.assertIn("_verify_namespace_generation_witnesses", namespace_verifier)
        self.assertIn("_verify_namespace_generation_witnesses", revoke)
        self.assertLess(
            revoke.index("_verify_namespace_generation_witnesses"),
            revoke.index("_chmod_acl"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
