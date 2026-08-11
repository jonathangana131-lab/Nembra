#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import importlib.util
from pathlib import Path
import sys
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "capture_pr_queue_janitor.py"
spec = importlib.util.spec_from_file_location("capture_pr_queue_janitor", SCRIPT)
assert spec is not None and spec.loader is not None
janitor = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = janitor
spec.loader.exec_module(janitor)


class CapturePRQueueJanitorTests(unittest.TestCase):
    repository = "owner/repo"
    now = dt.datetime(2026, 8, 11, 3, 0, tzinfo=dt.timezone.utc)

    def workflow_run(self, **overrides):
        value = {
            "id": 42,
            "status": "queued",
            "event": "pull_request",
            "path": ".github/workflows/capture-field-build-provenance.yml",
            "head_branch": "agent/final-capture",
            "head_sha": "a" * 40,
            "created_at": "2026-08-11T02:30:00Z",
        }
        value.update(overrides)
        return value

    def pr(self, sha="a" * 40, *, repo="owner/repo"):
        return {
            "state": "open",
            "head": {
                "ref": "agent/final-capture",
                "sha": sha,
                "repo": {"full_name": repo},
            },
        }

    def classify(self, workflow_run=None, prs=None, **overrides):
        kwargs = {
            "repository": self.repository,
            "now": self.now,
            "minimum_age_seconds": 120,
            "protected_heads": set(),
        }
        kwargs.update(overrides)
        return janitor.classify_run(
            workflow_run or self.workflow_run(),
            [self.pr()] if prs is None else prs,
            **kwargs,
        )

    def test_only_three_direct_capture_workflows_are_allowlisted(self):
        self.assertEqual(
            set(janitor.WORKFLOWS),
            {
                "capture-main-selective-graft-diagnostic.yml",
                "capture-field-build-provenance.yml",
                "capture-standalone-visual-evidence.yml",
            },
        )

    def test_current_exact_open_pr_head_is_never_cancelled(self):
        self.assertFalse(self.classify(prs=[self.pr()]).cancel)

    def test_old_sha_on_same_open_branch_is_cancelled(self):
        decision = self.classify(prs=[self.pr("b" * 40)])
        self.assertTrue(decision.cancel)
        self.assertIn("stale", decision.reason)

    def test_closed_or_abandoned_branch_run_is_cancelled(self):
        self.assertTrue(self.classify(prs=[]).cancel)

    def test_synchronize_event_protection_wins_over_stale_api_view(self):
        protected = {("agent/final-capture", "a" * 40)}
        decision = self.classify(
            prs=[self.pr("b" * 40)], protected_heads=protected
        )
        self.assertFalse(decision.cancel)
        self.assertIn("synchronize-event", decision.reason)

    def test_api_consistency_grace_preserves_fresh_run(self):
        workflow_run = self.workflow_run(created_at="2026-08-11T02:59:30Z")
        self.assertFalse(
            self.classify(
                workflow_run=workflow_run, prs=[self.pr("b" * 40)]
            ).cancel
        )

    def test_non_pull_request_and_non_allowlisted_workflows_are_preserved(self):
        self.assertFalse(
            self.classify(
                workflow_run=self.workflow_run(event="workflow_dispatch"), prs=[]
            ).cancel
        )
        self.assertFalse(
            self.classify(
                workflow_run=self.workflow_run(
                    path=".github/workflows/xcode27-pr-command.yml"
                ),
                prs=[],
            ).cancel
        )

    def test_ambiguous_pr_subject_preserves_run(self):
        malformed = self.pr()
        malformed["head"]["sha"] = None
        self.assertFalse(self.classify(prs=[malformed]).cancel)
        self.assertFalse(self.classify(prs=[self.pr(repo="fork/repo")]).cancel)

    def test_invalid_run_identity_preserves_run(self):
        self.assertFalse(
            self.classify(workflow_run=self.workflow_run(head_sha="123"), prs=[]).cancel
        )
        self.assertFalse(
            self.classify(workflow_run=self.workflow_run(head_branch=""), prs=[]).cancel
        )
        self.assertFalse(
            self.classify(
                workflow_run=self.workflow_run(created_at="not-time"), prs=[]
            ).cancel
        )

    def test_protected_head_parser_requires_branch_and_40hex(self):
        self.assertEqual(
            janitor.parse_protected_head("agent/final-capture=" + "c" * 40),
            ("agent/final-capture", "c" * 40),
        )
        with self.assertRaises(Exception):
            janitor.parse_protected_head("missing-sha")
        with self.assertRaises(Exception):
            janitor.parse_protected_head("agent/final-capture=BAD")


if __name__ == "__main__":
    unittest.main()
