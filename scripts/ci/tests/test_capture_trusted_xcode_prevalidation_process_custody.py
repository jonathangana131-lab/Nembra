#!/usr/bin/env python3
"""Source contract for trusted Capture prevalidation process isolation.

Repository-controlled validation must execute in a predecessor xcode-27 job. The authority-producing
job then starts on its own runner only after that job succeeds, so a process spawned by candidate
validation cannot survive inside the authority job's process namespace.

Exact repository-owner commands are serialized across the whole workflow run. This is required
because prevalidation and authority both consume the scarce xcode-27 runner: if only the authority
job is concurrent, repeated commands can run fresh prevalidation jobs while repeatedly replacing a
pending authority job, preventing terminal software acceptance indefinitely.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github" / "workflows" / "capture-xcode27-trusted-command.yml"
SERIALIZATION_EPOCH = "v14-field-command-v1"


class TrustedXcodePrevalidationProcessCustodyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_candidate_prevalidation_is_a_distinct_predecessor_job(self) -> None:
        workflow = self.workflow
        prevalidation = workflow.index("  prevalidate-candidate:\n")
        authority = workflow.index("  capture-simulator-qa:\n")
        self.assertLess(prevalidation, authority)

        prevalidation_block = workflow[prevalidation:authority]
        self.assertIn("runs-on: xcode-27", prevalidation_block)
        for step in (
            "Validate project structure",
            "Validate core package",
            "Validate Capture package",
            "Validate signed field evidence tooling",
            "Validate signed field candidate producer source",
            "Validate offline field authorization signer",
        ):
            with self.subTest(step=step):
                self.assertIn(f"- name: {step}", prevalidation_block)

    def test_authority_job_waits_for_prevalidation_and_does_not_repeat_candidate_validation(self) -> None:
        workflow = self.workflow
        authority = workflow.index("  capture-simulator-qa:\n")
        authority_block = workflow[authority:]
        self.assertRegex(
            authority_block,
            re.compile(r"needs:\s*\[resolve, prevalidate-candidate\]"),
        )
        self.assertIn("runs-on: xcode-27", authority_block)
        self.assertIn("- name: Build, test, and capture Simulator states", authority_block)

        for step in (
            "Validate project structure",
            "Validate core package",
            "Validate Capture package",
            "Validate signed field evidence tooling",
            "Validate signed field candidate producer source",
            "Validate offline field authorization signer",
        ):
            with self.subTest(step=step):
                self.assertNotIn(f"- name: {step}", authority_block)

    def test_prevalidation_and_authority_each_reject_head_movement(self) -> None:
        workflow = self.workflow
        prevalidation = workflow.index("  prevalidate-candidate:\n")
        authority = workflow.index("  capture-simulator-qa:\n")
        prevalidation_block = workflow[prevalidation:authority]
        authority_block = workflow[authority:]

        self.assertIn("Reject stale or detached Capture head before prevalidation", prevalidation_block)
        self.assertIn("Reject head movement after isolated prevalidation", prevalidation_block)
        self.assertIn("Reject stale or detached Capture head before scarce Mac work", authority_block)
        self.assertIn("Reject head movement before trusted acceptance completes", authority_block)

    def test_exact_owner_commands_serialize_the_entire_workflow_before_prevalidation(self) -> None:
        workflow = self.workflow
        jobs = workflow.index("jobs:\n")
        top_level = workflow[:jobs]

        self.assertIn("concurrency:\n", top_level)
        self.assertIn(SERIALIZATION_EPOCH, top_level)
        self.assertIn("github.event.issue.number", top_level)
        self.assertIn("github.event.comment.body == '/capture-xcode27'", top_level)
        self.assertIn("github.actor == github.repository_owner", top_level)
        self.assertIn("'owner-command' || github.run_id", top_level)
        self.assertIn("cancel-in-progress: false", top_level)

        # Non-authorizing issue comments must remain unique and therefore cannot replace one
        # pending exact owner command in the workflow-level concurrency group.
        self.assertIn("github.run_id", top_level)

    def test_authority_job_uses_new_epoch_group_not_legacy_pending_replacement_group(self) -> None:
        authority = self.workflow.index("  capture-simulator-qa:\n")
        authority_block = self.workflow[authority:]
        self.assertIn(f"nembra-capture-xcode27-authority-{SERIALIZATION_EPOCH}", authority_block)
        self.assertNotIn(
            "group: nembra-capture-xcode27-${{ needs.resolve.outputs.pr_number }}-${{ needs.resolve.outputs.head_sha }}",
            authority_block,
        )


if __name__ == "__main__":
    unittest.main()
