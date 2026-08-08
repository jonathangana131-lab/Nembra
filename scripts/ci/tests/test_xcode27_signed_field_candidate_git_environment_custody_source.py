#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateGitEnvironmentCustodySourceTests(unittest.TestCase):
    """Pin Git as an exact release-authority process, not an ambient semantic surface."""

    def setUp(self) -> None:
        self.source = PRODUCER.read_text(encoding="utf-8")

    def _wrapper(self) -> str:
        start = self.source.find("run_git()")
        self.assertNotEqual(start, -1, "Expected one isolated run_git wrapper")
        end = self.source.find("\n}", start)
        self.assertNotEqual(end, -1, "Expected run_git wrapper terminator")
        return self.source[start : end + 2]

    def test_git_authority_runs_through_one_isolated_wrapper(self) -> None:
        wrapper = self._wrapper()
        self.assertIn("/usr/bin/env -i", wrapper)
        self.assertIn("/usr/bin/git", wrapper)

        without_wrapper = self.source.replace(wrapper, "")
        raw_git_invocations = [
            line.strip()
            for line in without_wrapper.splitlines()
            if re.search(r"(^|[;&|$(]\s*)(?:/usr/bin/)?git(?:\s|$)", line)
            and not line.lstrip().startswith("#")
        ]
        self.assertEqual(
            raw_git_invocations,
            [],
            "Every producer Git command participating in field-build authority must use run_git; bare and absolute Git bypasses are forbidden: "
            + " | ".join(raw_git_invocations),
        )

    def test_isolated_git_explicitly_neutralizes_config_and_replace_objects(self) -> None:
        wrapper = self._wrapper()
        for marker in (
            "GIT_CONFIG_NOSYSTEM=1",
            "GIT_CONFIG_GLOBAL=/dev/null",
            "GIT_NO_REPLACE_OBJECTS=1",
        ):
            self.assertIn(marker, wrapper)
        self.assertIn("PATH=/usr/bin:/bin:/usr/sbin:/sbin", wrapper)

    def test_git_isolation_is_established_before_first_repository_authority_query(self) -> None:
        wrapper = self.source.find("run_git()")
        first_status = self.source.find(" status --porcelain")
        first_revision = self.source.find(" rev-parse")
        first_authority_query = min(index for index in (first_status, first_revision) if index != -1)
        self.assertGreaterEqual(wrapper, 0)
        self.assertLess(wrapper, first_authority_query)

    def test_every_expected_release_git_operation_uses_wrapper(self) -> None:
        for fragment in (
            'run_git status --porcelain=v1 --untracked-files=all',
            'run_git rev-parse --verify HEAD^{commit}',
            'run_git check-ignore -q -- "$RELATIVE_ARTIFACTS_DIR"',
            'run_git show "$SOURCE_SHA:$PRIVATE_RUNNER_RELATIVE_PATH"',
            'run_git show "$SOURCE_SHA:$INSPECTOR_RELATIVE_PATH"',
            'run_git rev-parse "$SOURCE_SHA:$PRIVATE_RUNNER_RELATIVE_PATH"',
            'run_git rev-parse "$SOURCE_SHA:$INSPECTOR_RELATIVE_PATH"',
            'run_git -C "$ROOT" cat-file -s "$PRIVATE_RUNNER_BLOB_SHA"',
            'run_git -C "$ROOT" cat-file -s "$INSPECTOR_BLOB_SHA"',
            'run_git hash-object "$PRIVATE_RUNNER_SNAPSHOT"',
            'run_git hash-object "$INSPECTOR_SNAPSHOT"',
            'run_git worktree add --detach "$SOURCE_ROOT" "$SOURCE_SHA"',
            'run_git worktree remove --force "$SOURCE_ROOT"',
        ):
            self.assertIn(fragment, self.source)


if __name__ == "__main__":
    unittest.main()
