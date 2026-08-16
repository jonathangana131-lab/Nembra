#!/usr/bin/env python3
"""One-shot authoring materializer for the #3438 held-symlink authority repair.

This file is temporary authoring scaffolding. The final product branch must delete it
and retain only the production helper, permanent regression, and exact-head workflow.
"""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"
TEST = REPO / "scripts/ci/tests/test_capture_private_read_lease_symlink_authority_transition.py"


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    return source.replace(old, new, 1)


def patch_helper() -> None:
    source = HELPER.read_text(encoding="utf-8")

    helper_anchor = """        os.close(diagnostic)\n\ndef _descriptor_path(descriptor: int) -> str:\n"""
    helper_insert = """        os.close(diagnostic)\n\n\ndef _validate_lease_subject_symlinks(\n    subjects: Sequence[Path],\n    plan: Sequence[tuple[Path, bool, tuple[int, int, int], int]],\n) -> None:\n    \"\"\"Re-attest held subject symlink policy at an ACL authority transition.\n\n    The descriptor plan pins every ACL-bearing real object, while symlink objects\n    remain deliberately unprivileged. Rewalking each canonical subject through its\n    already-held descriptor closes the validation-to-grant gap without treating a\n    pathname snapshot as authority or granting ACLs to symlinks themselves.\n    \"\"\"\n    by_path = {Path(path): entry for entry in plan for path in (entry[0],)}\n    for raw_subject in subjects:\n        subject = _absolute_lexical(Path(raw_subject))\n        held_subject = by_path.get(subject)\n        if held_subject is None or len(held_subject) != 4:\n            raise SelectedXcodeBuildOrchestratorError(\n                \"private read-lease held subject descriptor is unavailable at authority transition\"\n            )\n        _path, host_only, accepted_signature, descriptor = held_subject\n        if host_only:\n            raise SelectedXcodeBuildOrchestratorError(\n                \"private read-lease subject was misclassified as host-only authority\"\n            )\n        if _descriptor_signature(int(descriptor)) != accepted_signature:\n            raise SelectedXcodeBuildOrchestratorError(\n                \"private read-lease held subject changed before authority transition\"\n            )\n        _validate_subject_symlinks_from_descriptor(subject, int(descriptor))\n\n\ndef _descriptor_path(descriptor: int) -> str:\n"""
    source = replace_once(source, helper_anchor, helper_insert, "held-symlink helper insertion")

    pre_acl_anchor = """            self._opened = [\n                {\n                    \"descriptor\": descriptor,\n                    \"path\": path,\n                    \"before\": \"\",\n                    \"acl\": \"\",\n                    \"added\": False,\n                    \"accepted_signature\": accepted_signature,\n                    \"is_directory\": stat.S_ISDIR(accepted_signature[2]),\n                }\n                for path, _host_only, accepted_signature, descriptor in pinned_plan\n            ]\n\n            for record, (path, host_only, accepted_signature, descriptor) in zip(\n"""
    pre_acl_replacement = """            self._opened = [\n                {\n                    \"descriptor\": descriptor,\n                    \"path\": path,\n                    \"before\": \"\",\n                    \"acl\": \"\",\n                    \"added\": False,\n                    \"accepted_signature\": accepted_signature,\n                    \"is_directory\": stat.S_ISDIR(accepted_signature[2]),\n                }\n                for path, _host_only, accepted_signature, descriptor in pinned_plan\n            ]\n\n            # _lease_paths performs descriptor-bound symlink classification while\n            # planning. Re-attest immediately before the first ACL mutation so a\n            # retarget injected after planning cannot cross into authority.\n            _validate_lease_subject_symlinks(self._subjects, pinned_plan)\n\n            for record, (path, host_only, accepted_signature, descriptor) in zip(\n"""
    source = replace_once(source, pre_acl_anchor, pre_acl_replacement, "pre-ACL authority fence")

    post_acl_anchor = """                diagnostic = _open_pinned_path(\n                    path, is_directory, accepted_signature\n                )\n                os.close(diagnostic)\n        except Exception as error:\n"""
    post_acl_replacement = """                diagnostic = _open_pinned_path(\n                    path, is_directory, accepted_signature\n                )\n                os.close(diagnostic)\n\n            # ACL application itself spans multiple syscalls. Re-attest the held\n            # symlink graph after the final ACL is proven and before grant returns.\n            # Any persistent retarget in that interval enters the existing exact\n            # rollback path instead of becoming build authority.\n            _validate_lease_subject_symlinks(self._subjects, pinned_plan)\n        except Exception as error:\n"""
    source = replace_once(source, post_acl_anchor, post_acl_replacement, "post-ACL authority fence")

    HELPER.write_text(source, encoding="utf-8")


def write_regression() -> None:
    TEST.write_text('''#!/usr/bin/env python3
"""Permanent regressions for held-symlink policy at ACL authority transitions."""
from __future__ import annotations

import importlib.util
import inspect
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_symlink_authority_transition", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture():
    return tempfile.TemporaryDirectory(
        prefix="nembra-symlink-authority-transition-",
        dir=REPO,
    )


class CapturePrivateReadLeaseSymlinkAuthorityTransitionTests(unittest.TestCase):
    def _make_tree(self, raw: str):
        outer = Path(raw)
        repo = outer / "repo"
        subject = repo / "LocalSecrets/TuyaSDK/Build"
        inside = subject / "inside"
        inside.mkdir(parents=True)
        (inside / "inside.fixture").write_text("inside\\n", encoding="utf-8")
        external = outer / "outside-subject"
        external.mkdir()
        (external / "outside.fixture").write_text("outside\\n", encoding="utf-8")
        link = subject / "escape"
        link.symlink_to("inside", target_is_directory=True)
        return repo, subject, external, link

    @staticmethod
    def _acl_transport():
        state: dict[int, str] = {}

        def listing(descriptor: int) -> str:
            return state.get(descriptor, "")

        def chmod(descriptor: int, operation: str, acl: str) -> None:
            if operation == "+a":
                state[descriptor] = f"0: {acl}"
            elif operation == "-a":
                state[descriptor] = ""
            else:
                raise AssertionError(f"unexpected ACL operation: {operation}")

        return state, listing, chmod

    def test_retarget_after_planner_validation_is_rejected_before_acl(self) -> None:
        helper = load()
        with fixture() as raw:
            repo, subject, external, link = self._make_tree(raw)
            original = helper._validate_subject_symlinks_from_descriptor
            calls = 0

            def validate_then_retarget(admitted_subject: Path, descriptor: int) -> None:
                nonlocal calls
                calls += 1
                original(admitted_subject, descriptor)
                if calls == 1:
                    link.unlink()
                    link.symlink_to(external, target_is_directory=True)

            state, listing, chmod = self._acl_transport()
            lease = helper._PrivateReadLease((subject,), repo)
            with (
                mock.patch.object(
                    helper,
                    "_validate_subject_symlinks_from_descriptor",
                    side_effect=validate_then_retarget,
                ),
                mock.patch.object(helper, "_acl_listing", side_effect=listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=chmod),
            ):
                with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                    lease.grant("nembrasymlinkfence")

            self.assertGreaterEqual(calls, 2)
            self.assertFalse(any(state.values()), "no ACL may survive rejected authority admission")
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")
            self.assertEqual(link.resolve(strict=True), external.resolve(strict=True))

    def test_retarget_during_acl_application_fails_closed_and_rolls_back(self) -> None:
        helper = load()
        with fixture() as raw:
            repo, subject, external, link = self._make_tree(raw)
            state, listing, base_chmod = self._acl_transport()
            retargeted = False

            def chmod_then_retarget(descriptor: int, operation: str, acl: str) -> None:
                nonlocal retargeted
                base_chmod(descriptor, operation, acl)
                if operation == "+a" and not retargeted:
                    link.unlink()
                    link.symlink_to(external, target_is_directory=True)
                    retargeted = True

            lease = helper._PrivateReadLease((subject,), repo)
            with (
                mock.patch.object(helper, "_acl_listing", side_effect=listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=chmod_then_retarget),
            ):
                with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                    lease.grant("nembrasymlinkfence")

            self.assertTrue(retargeted)
            self.assertTrue(state, "the fixture must reach ACL materialization")
            self.assertFalse(any(state.values()), "exact rollback must remove every synthetic ACL")
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")
            self.assertEqual(link.resolve(strict=True), external.resolve(strict=True))

    def test_grant_source_revalidates_symlinks_before_and_after_acl_loop(self) -> None:
        helper = load()
        grant = inspect.getsource(helper._PrivateReadLease.grant)
        marker = "_validate_lease_subject_symlinks(self._subjects, pinned_plan)"
        self.assertEqual(grant.count(marker), 2)
        first = grant.index(marker)
        loop = grant.index("for record, (path, host_only, accepted_signature, descriptor) in zip")
        second = grant.rindex(marker)
        rollback = grant.index("except Exception as error:")
        self.assertLess(first, loop)
        self.assertLess(loop, second)
        self.assertLess(second, rollback)


if __name__ == "__main__":
    unittest.main(verbosity=2)
''', encoding="utf-8")


def main() -> int:
    if TEST.exists():
        raise SystemExit(f"permanent regression already exists: {TEST.relative_to(REPO)}")
    patch_helper()
    write_regression()
    print("materialized held-symlink authority transition repair")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
