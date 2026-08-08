#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateSourceTreeBlobCustodySourceTests(unittest.TestCase):
    """Pin built checkout bytes to SOURCE_SHA blobs, independent of Git clean/smudge semantics."""

    def setUp(self) -> None:
        self.source = PRODUCER.read_text(encoding="utf-8")

    def test_detached_worktree_is_raw_blob_audited_before_archive(self) -> None:
        worktree_add = self.source.find("worktree add --detach")
        archive_call = self.source.find('if ! run_xcodebuild \\\n  -project Nembra.xcodeproj')
        self.assertGreaterEqual(worktree_add, 0, "Expected detached SOURCE_SHA worktree production")
        self.assertGreater(archive_call, worktree_add, "Expected archive after detached worktree creation")
        prearchive = self.source[worktree_add:archive_call]

        self.assertRegex(
            prearchive,
            re.compile(r"ls-tree[^\n]*SOURCE_SHA|SOURCE_SHA[^\n]*ls-tree"),
            "A clean Git status is not raw-byte evidence; the producer must enumerate exact SOURCE_SHA tree subjects before Xcode consumes the checkout.",
        )
        self.assertTrue(
            "hash-object --no-filters" in prearchive
            or "hash-object -w --stdin" in prearchive
            or "b\"blob \"" in prearchive
            or "b'blob '" in prearchive,
            "Tracked filesystem bytes must be compared with exact Git blob identity without invoking checkout clean/smudge filters.",
        )

    def test_exact_blob_audit_runs_again_after_archive_export(self) -> None:
        marker = re.search(r"(?:verify|audit)[A-Za-z0-9_]*source[A-Za-z0-9_]*(?:tree|blob)[A-Za-z0-9_]*\(\)", self.source, re.IGNORECASE)
        self.assertIsNotNone(
            marker,
            "Expected one named exact-source tree/blob audit so the same raw-byte proof can gate both pre-build and post-build state.",
        )
        function_name = marker.group(0).split("(", 1)[0]
        self.assertGreaterEqual(
            self.source.count(function_name),
            3,
            "Exact raw-byte source audit must be defined and invoked both before archive and after archive/export; Git status alone can be masked by repository-local filters.",
        )

    def test_status_is_not_the_only_source_integrity_authority(self) -> None:
        self.assertIn("git status", self.source)
        self.assertTrue(
            "--no-filters" in self.source or "ls-tree" in self.source,
            "The release candidate must not treat `git status` as sufficient proof that Xcode built the exact SOURCE_SHA file bytes.",
        )


if __name__ == "__main__":
    unittest.main()
