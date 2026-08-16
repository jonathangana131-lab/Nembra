#!/usr/bin/env python3
"""One-shot authoring materializer for held-directory generation continuity."""
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
    before_anchor = '''    def walk(directory_descriptor: int, relative_parts: tuple[str, ...]) -> None:\n        try:\n            names = sorted(os.listdir(directory_descriptor))\n'''
    before_replacement = '''    def walk(directory_descriptor: int, relative_parts: tuple[str, ...]) -> None:\n        before_metadata = os.fstat(directory_descriptor)\n        before_generation = (\n            before_metadata.st_dev,\n            before_metadata.st_ino,\n            stat.S_IFMT(before_metadata.st_mode),\n            before_metadata.st_mtime_ns,\n            before_metadata.st_ctime_ns,\n        )\n        try:\n            names = sorted(os.listdir(directory_descriptor))\n'''
    source = replace_once(source, before_anchor, before_replacement, "directory generation admission")

    after_anchor = '''            try:\n                walk(child, entry_parts)\n            finally:\n                os.close(child)\n\n    walk(subject_descriptor, ())\n'''
    after_replacement = '''            try:\n                walk(child, entry_parts)\n            finally:\n                os.close(child)\n\n        after_metadata = os.fstat(directory_descriptor)\n        after_generation = (\n            after_metadata.st_dev,\n            after_metadata.st_ino,\n            stat.S_IFMT(after_metadata.st_mode),\n            after_metadata.st_mtime_ns,\n            after_metadata.st_ctime_ns,\n        )\n        if after_generation != before_generation:\n            raise SelectedXcodeBuildOrchestratorError(\n                \"private read-lease held directory generation changed during symlink validation\"\n            )\n\n    walk(subject_descriptor, ())\n'''
    source = replace_once(source, after_anchor, after_replacement, "directory generation completion")
    HELPER.write_text(source, encoding="utf-8")


def patch_test() -> None:
    source = TEST.read_text(encoding="utf-8")
    anchor = '''    def test_grant_source_revalidates_symlinks_before_and_after_acl_loop(self) -> None:\n'''
    insertion = '''    def test_retarget_inside_readlink_is_rejected_by_directory_generation(self) -> None:\n        helper = load()\n        with fixture() as raw:\n            repo, subject, external, link = self._make_tree(raw)\n            original_readlink = helper.os.readlink\n            retargets = 0\n\n            def safe_readlink_then_external(path, *, dir_fd=None):\n                nonlocal retargets\n                # Simulate a concurrent field mutation that presents the safe target\n                # only for the descriptor-relative readlink, then restores the\n                # external target before the validator can return.\n                if link.is_symlink():\n                    link.unlink()\n                link.symlink_to(\"inside\", target_is_directory=True)\n                value = original_readlink(path, dir_fd=dir_fd)\n                link.unlink()\n                link.symlink_to(external, target_is_directory=True)\n                retargets += 1\n                return value\n\n            state, listing, chmod = self._acl_transport()\n            lease = helper._PrivateReadLease((subject,), repo)\n            with (\n                mock.patch.object(helper.os, \"readlink\", side_effect=safe_readlink_then_external),\n                mock.patch.object(helper, \"_acl_listing\", side_effect=listing),\n                mock.patch.object(helper, \"_chmod_acl\", side_effect=chmod),\n            ):\n                with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):\n                    lease.grant(\"nembrasymlinkgeneration\")\n\n            self.assertGreaterEqual(retargets, 1)\n            self.assertFalse(any(state.values()))\n            self.assertFalse(lease._opened)\n            self.assertEqual(lease._principal, \"\")\n            self.assertEqual(link.resolve(strict=True), external.resolve(strict=True))\n\n    def test_grant_source_revalidates_symlinks_before_and_after_acl_loop(self) -> None:\n'''
    source = replace_once(source, anchor, insertion, "generation race regression")

    source_anchor = '''        helper = load()\n        grant = inspect.getsource(helper._PrivateReadLease.grant)\n        marker = \"_validate_lease_subject_symlinks(self._subjects, pinned_plan)\"\n'''
    source_replacement = '''        helper = load()\n        grant = inspect.getsource(helper._PrivateReadLease.grant)\n        validator = inspect.getsource(helper._validate_subject_symlinks_from_descriptor)\n        self.assertIn(\"st_mtime_ns\", validator)\n        self.assertIn(\"st_ctime_ns\", validator)\n        self.assertIn(\"after_generation != before_generation\", validator)\n        marker = \"_validate_lease_subject_symlinks(self._subjects, pinned_plan)\"\n'''
    source = replace_once(source, source_anchor, source_replacement, "generation source contract")
    TEST.write_text(source, encoding="utf-8")


def main() -> int:
    patch_helper()
    patch_test()
    print("materialized held-symlink directory generation continuity")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
