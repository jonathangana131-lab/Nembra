#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateDescriptorSubjectCustodySourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = SCRIPT.read_text(encoding="utf-8")

    def test_each_executable_tool_descriptor_is_exact_source_bound_after_open(self) -> None:
        start = self.source.index('exec 7< "$PRIVATE_RUNNER_SNAPSHOT"')
        end = self.source.index('rm -f "$PRIVATE_RUNNER_SNAPSHOT" "$INSPECTOR_SNAPSHOT"', start)
        binding = self.source[start:end]

        # Path hashing before these opens is not enough: a same-user replacement can occur between
        # hash verification and shell redirection. Every descriptor that will execute or inspect
        # private release evidence must itself be checked against the accepted SOURCE_SHA blob.
        for descriptor in (7, 8, 9):
            self.assertIn(
                f"/dev/fd/{descriptor}",
                binding,
                f"FD {descriptor} must be verified as the exact admitted Git subject after it is opened and before the mutable pathname is removed.",
            )

        self.assertGreaterEqual(
            binding.count("PRIVATE_RUNNER_BLOB_SHA"),
            2,
            "Both independently opened private-runner descriptors (preflight FD 7 and evidence FD 9) require exact post-open blob binding.",
        )
        self.assertIn(
            "INSPECTOR_BLOB_SHA",
            binding,
            "The canonical-inspector descriptor must be checked against its exact SOURCE_SHA blob after FD 8 is opened.",
        )

    def test_descriptor_verification_preserves_execution_read_position(self) -> None:
        start = self.source.index('exec 7< "$PRIVATE_RUNNER_SNAPSHOT"')
        end = self.source.index('rm -f "$PRIVATE_RUNNER_SNAPSHOT" "$INSPECTOR_SNAPSHOT"', start)
        binding = self.source[start:end].lower()

        self.assertTrue(
            "pread" in binding or "lseek" in binding or "seek(" in binding,
            "Exact descriptor verification must not leave FD 7/8/9 consumed at EOF before Python executes the admitted subjects.",
        )


if __name__ == "__main__":
    unittest.main()
