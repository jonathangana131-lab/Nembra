#!/usr/bin/env python3
"""Expected-red contract for trusted Capture authority on a persistent self-hosted Mac.

The repository documents ``xcode-27`` as the self-hosted runner. A predecessor
job and an authority-producing job that both target that runner class do not,
by job separation alone, prove an OS/process isolation boundary. Candidate code
can deliberately escape the Actions runner's ordinary descendant cleanup, so a
surviving same-UID process from prevalidation must not be able to precede the
authority build on the same persistent runner class.

This validation intentionally does not prescribe the final infrastructure. A
green repair may move candidate prevalidation off the authority runner class,
move all candidate execution behind authority production, or establish a
mechanically proven disposable/isolated authority runner boundary.
"""

from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
TRUSTED_WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
RUNNER_DOC = ROOT / "docs/CI_EXACT_HEAD_SCHEDULER.md"


def job_block(workflow: str, job_name: str) -> str:
    marker = f"  {job_name}:\n"
    start = workflow.find(marker)
    if start < 0:
        raise AssertionError(f"missing job {job_name!r}")
    next_job = re.search(r"^  [A-Za-z0-9_-]+:\s*$", workflow[start + len(marker) :], re.MULTILINE)
    if next_job is None:
        return workflow[start:]
    return workflow[start : start + len(marker) + next_job.start()]


def runner_label(block: str) -> str:
    match = re.search(r"^    runs-on:\s*([^\n#]+)", block, re.MULTILINE)
    if match is None:
        raise AssertionError("job has no scalar runs-on label")
    return match.group(1).strip().strip("'\"")


class TrustedXcodeSelfHostedProcessCustodyTests(unittest.TestCase):
    def test_candidate_prevalidation_does_not_precede_authority_on_same_persistent_runner_class(self) -> None:
        workflow = TRUSTED_WORKFLOW.read_text(encoding="utf-8")
        runner_doc = RUNNER_DOC.read_text(encoding="utf-8")

        self.assertIn("prevalidate-candidate:", workflow)
        self.assertIn("capture-simulator-qa:", workflow)
        self.assertRegex(runner_doc, r"self-hosted [`']?xcode-27[`']? runner")

        prevalidate = job_block(workflow, "prevalidate-candidate")
        authority = job_block(workflow, "capture-simulator-qa")
        prevalidate_runner = runner_label(prevalidate)
        authority_runner = runner_label(authority)

        self.assertIn("needs: [resolve, prevalidate-candidate]", authority)
        self.assertNotEqual(
            prevalidate_runner,
            authority_runner,
            "candidate-controlled prevalidation precedes authority on the same documented "
            "self-hosted runner class; a separate Actions job is not itself a process/host "
            "isolation proof for a persistent same-UID child",
        )


if __name__ == "__main__":
    unittest.main()
