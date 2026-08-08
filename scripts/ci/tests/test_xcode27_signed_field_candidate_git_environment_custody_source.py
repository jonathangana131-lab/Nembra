#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateGitEnvironmentCustodySourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = PRODUCER.read_text(encoding="utf-8")

    def test_git_authority_runs_through_one_isolated_wrapper(self) -> None:
        self.assertRegex(
            self.source,
            re.compile(r"(?ms)^run_git\(\)\s*\{.*?\benv\s+-i\b.*?\b(?:/usr/bin/)?git\b.*?^\}"),
        )
        raw_git_invocations = [
            line for line in self.source.splitlines()
            if re.search(r"(^|[;&|$(]\s*)git\s", line)
            and not line.lstrip().startswith("#")
        ]
        self.assertEqual(raw_git_invocations, [])

    def test_isolated_git_neutralizes_config_and_replace_objects(self) -> None:
        start = self.source.find("run_git()")
        self.assertNotEqual(start, -1)
        end = self.source.find("\n}", start)
        self.assertNotEqual(end, -1)
        wrapper = self.source[start : end + 2]
        for marker in (
            "GIT_CONFIG_NOSYSTEM=1",
            "GIT_CONFIG_GLOBAL=/dev/null",
            "GIT_NO_REPLACE_OBJECTS=1",
        ):
            self.assertIn(marker, wrapper)
        self.assertRegex(wrapper, re.compile(r"PATH=/usr/bin:/bin:/usr/sbin:/sbin"))

    def test_git_isolation_exists_before_first_repository_authority_query(self) -> None:
        wrapper = self.source.find("run_git()")
        first_status = self.source.find(" status --porcelain")
        first_revision = self.source.find(" rev-parse")
        first_authority_query = min(index for index in (first_status, first_revision) if index != -1)
        self.assertGreaterEqual(wrapper, 0)
        self.assertLess(wrapper, first_authority_query)


if __name__ == "__main__":
    unittest.main()
