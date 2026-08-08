#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateDescriptorSubjectCustodySourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = SCRIPT.read_text(encoding="utf-8")

    def descriptor_binding_block(self) -> str:
        start = self.source.index('exec 7< "$PRIVATE_RUNNER_SNAPSHOT"')
        end = self.source.index('rm -f "$PRIVATE_RUNNER_SNAPSHOT" "$INSPECTOR_SNAPSHOT"', start)
        return self.source[start:end]

    def test_each_executable_tool_descriptor_is_exact_source_bound_after_open(self) -> None:
        binding = self.descriptor_binding_block()
        for descriptor in (7, 8, 9):
            self.assertIn(f"/dev/fd/{descriptor}", binding)
        self.assertGreaterEqual(binding.count("PRIVATE_RUNNER_BLOB_SHA"), 2)
        self.assertIn("INSPECTOR_BLOB_SHA", binding)

    def test_accepted_git_blob_sizes_are_bound_before_mutable_path_open(self) -> None:
        open_boundary = self.source.index('exec 7< "$PRIVATE_RUNNER_SNAPSHOT"')
        prefix = self.source[:open_boundary]
        self.assertIn('git -C "$ROOT" cat-file -s "$PRIVATE_RUNNER_BLOB_SHA"', prefix)
        self.assertIn('git -C "$ROOT" cat-file -s "$INSPECTOR_BLOB_SHA"', prefix)
        self.assertIn("PRIVATE_RUNNER_BLOB_BYTES", prefix)
        self.assertIn("INSPECTOR_BLOB_BYTES", prefix)

    def test_descriptor_verification_requires_regular_exact_size_stable_subject(self) -> None:
        binding = self.descriptor_binding_block()
        self.assertIn("import stat", binding)
        self.assertIn("os.fstat(fd)", binding)
        self.assertIn("stat.S_ISREG", binding)
        self.assertIn("expected_size", binding)
        self.assertIn("st_size", binding)
        self.assertIn("st_mtime_ns", binding)
        self.assertIn("st_ctime_ns", binding)
        self.assertGreaterEqual(binding.count("os.fstat(fd)"), 2)
        self.assertIn("descriptor subject changed during verification", binding)

    def test_descriptor_hash_is_streamed_and_preserves_execution_read_position(self) -> None:
        binding = self.descriptor_binding_block()
        self.assertIn("os.pread", binding)
        self.assertIn("digest.update(header)", binding)
        self.assertIn("digest.update(chunk)", binding)
        self.assertNotIn("chunks = []", binding)
        self.assertNotIn('b"".join(chunks)', binding)
        self.assertIn("before = os.lseek(fd, 0, os.SEEK_CUR)", binding)
        self.assertIn("os.lseek(fd, 0, os.SEEK_CUR) != before", binding)

    def test_each_descriptor_verification_receives_exact_accepted_size(self) -> None:
        binding = self.descriptor_binding_block()
        self.assertIn(
            'verify_open_git_blob_descriptor "/dev/fd/7" 7 "$PRIVATE_RUNNER_BLOB_SHA" "$PRIVATE_RUNNER_BLOB_BYTES"',
            binding,
        )
        self.assertIn(
            'verify_open_git_blob_descriptor "/dev/fd/8" 8 "$INSPECTOR_BLOB_SHA" "$INSPECTOR_BLOB_BYTES"',
            binding,
        )
        self.assertIn(
            'verify_open_git_blob_descriptor "/dev/fd/9" 9 "$PRIVATE_RUNNER_BLOB_SHA" "$PRIVATE_RUNNER_BLOB_BYTES"',
            binding,
        )


if __name__ == "__main__":
    unittest.main()
