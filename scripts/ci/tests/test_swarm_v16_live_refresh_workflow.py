#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
LIVE_REFRESH = ROOT / ".github/workflows/swarm-v16-live-topology-refresh.yml"


class LiveRefreshWorkflowTests(unittest.TestCase):
    def test_running_refresh_is_never_cancelled_by_new_pr_churn(self) -> None:
        text = LIVE_REFRESH.read_text(encoding="utf-8")
        self.assertIn("group: swarm-v16-live-topology-refresh", text)
        self.assertIn("cancel-in-progress: false", text)
        self.assertNotIn("cancel-in-progress: true", text)

    def test_write_capable_refresh_executes_only_trusted_default_branch_code(self) -> None:
        text = LIVE_REFRESH.read_text(encoding="utf-8")
        self.assertIn("pull_request_target:", text)
        self.assertIn("ref: ${{ github.event.repository.default_branch }}", text)
        self.assertIn("persist-credentials: false", text)
        self.assertNotIn("ref: ${{ github.event.pull_request.head.sha }}", text)
        self.assertNotIn("ref: ${{ github.head_ref }}", text)


if __name__ == "__main__":
    unittest.main()
