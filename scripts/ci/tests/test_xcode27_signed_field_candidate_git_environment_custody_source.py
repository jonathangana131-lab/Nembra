#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateGitEnvironmentCustodySourceTests(unittest.TestCase):
    """Pin Git as an exact release-authority process, not an ambient semantic surface."""

    def setUp(self) -> None:
        self.source = PRODUCER.read_text(encoding="utf-8")

    def test_git_authority_runs_through_one_isolated_wrapper(self) -> None:
        self.assertRegex(
            self.source,
            re.compile(r"(?ms)^run_git\(\)\s*\{.*?\benv\s+-i\b.*?\b(?:/usr/bin/)?git\b.*?^\}"),
            "SOURCE_SHA, exact tool blobs, status, ignore policy, and detached-worktree authority must not inherit caller Git environment semantics.",
        )

        raw_git_invocations = [
            line
            for line in self.source.splitlines()
            if re.search(r"(^|[;&|$(]\s*)git\s", line)
            and not line.lstrip().startswith("#")
        ]
        self.assertEqual(
            raw_git_invocations,
            [],
            "Every producer Git command that participates in field-build authority must use the isolated run_git wrapper: "
            + " | ".join(raw_git_invocations),
        )

    def test_isolated_git_explicitly_neutralizes_config_and_replace_objects(self) -> None:
        start = self.source.find("run_git()")
        self.assertNotEqual(start, -1, "Expected one isolated run_git wrapper")
        end = self.source.find("\n}", start)
        self.assertNotEqual(end, -1, "Expected run_git wrapper terminator")
        wrapper = self.source[start : end + 2]

        for marker in (
            "GIT_CONFIG_NOSYSTEM=1",
            "GIT_CONFIG_GLOBAL=/dev/null",
            "GIT_NO_REPLACE_OBJECTS=1",
        ):
            self.assertIn(
                marker,
                wrapper,
                f"Isolated Git must explicitly pin {marker} so config/replacement refs cannot reinterpret exact SOURCE_SHA evidence.",
            )

        self.assertRegex(
            wrapper,
            re.compile(r"PATH=/usr/bin:/bin:/usr/sbin:/sbin"),
            "The Git subprocess must receive only the closed system executable search path.",
        )

    def test_git_isolation_is_established_before_first_repository_authority_query(self) -> None:
        wrapper = self.source.find("run_git()")
        first_status = self.source.find(" status --porcelain")
        first_revision = self.source.find(" rev-parse")
        first_authority_query = min(index for index in (first_status, first_revision) if index != -1)
        self.assertGreaterEqual(wrapper, 0)
        self.assertLess(
            wrapper,
            first_authority_query,
            "Git semantic isolation must exist before dirty-tree or SOURCE_SHA authority is derived.",
        )


if __name__ == "__main__":
    unittest.main()
