#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import swarm_control as sc

NOW = dt.datetime(2026, 8, 11, 5, 48, tzinfo=dt.timezone.utc)


def worker(suffix: str) -> str:
    return f"sol-20260811-{suffix}"


class StaleLaneAndConfigTests(unittest.TestCase):
    def test_claim_re_reads_authoritative_terminal_lane_after_stale_ready_snapshot(self):
        store = sc.MemoryStore()
        stale = sc.sample_lane("stale-done", state="READY")
        current = dict(stale)
        current["state"] = "DONE"
        current = sc.validate_lane(current)
        store.create(sc.lane_path(current["laneId"]), current)
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, stale, "primary", worker("stal1"), NOW)

    def test_claim_re_reads_authoritative_blocked_lane_after_stale_ready_snapshot(self):
        store = sc.MemoryStore()
        stale = sc.sample_lane("stale-block", state="READY")
        current = dict(stale)
        current["state"] = "BLOCKED"
        current = sc.validate_lane(current)
        store.create(sc.lane_path(current["laneId"]), current)
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, stale, "primary", worker("stal2"), NOW)

    def test_authoritative_lane_replaces_stale_scope_and_phase(self):
        store = sc.MemoryStore()
        stale = sc.sample_lane("stale-phase", state="READY")
        current = dict(stale)
        current["state"] = "INTEGRATION_READY"
        current = sc.validate_lane(current)
        store.create(sc.lane_path(current["laneId"]), current)
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, stale, "primary", worker("stal3"), NOW)
        integration = sc.claim_slot(store, stale, "integration", worker("stal4"), NOW)
        self.assertEqual(integration.value["role"], "integration")

    def test_validate_config_materializes_default_state_branch(self):
        config = sc.default_config()
        config.pop("stateBranch")
        validated = sc.validate_config(config)
        self.assertEqual(validated["stateBranch"], sc.DEFAULT_STATE_BRANCH)


if __name__ == "__main__":
    unittest.main(verbosity=2)
