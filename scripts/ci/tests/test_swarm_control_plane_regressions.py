#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import swarm_control as sc
from swarmcp import cli

NOW = dt.datetime(2026, 8, 11, 5, 20, tzinfo=dt.timezone.utc)


def worker(suffix: str) -> str:
    return f"sol-20260811-{suffix}"


def lane(lane_id: str, epic: str = "swarm", state: str = "READY"):
    value = sc.sample_lane(lane_id, state=state)
    value["epic"] = epic
    return sc.validate_lane(value)


def persist_lane(store, value):
    return store.create(sc.lane_path(value["laneId"]), value)


class ReviewFindingRegressionTests(unittest.TestCase):
    def test_trusted_config_loader_uses_persisted_config_not_defaults(self):
        store = sc.MemoryStore()
        config = sc.default_config()
        config["wipLimits"]["maxPrimaryLanes"] = 1
        store.create(cli.CONFIG_PATH, config)
        loaded = cli.trusted_config_from_store(store)
        self.assertEqual(loaded["wipLimits"]["maxPrimaryLanes"], 1)

    def test_independent_reviewer_is_rejected_at_claim_time(self):
        store = sc.MemoryStore()
        value = lane("review-claim")
        sc.claim_slot(store, value, "primary", worker("impl1"), NOW)
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, value, "review", worker("impl1"), NOW)

    def test_different_reviewer_can_claim_review_slot(self):
        store = sc.MemoryStore()
        value = lane("review-ok")
        sc.claim_slot(store, value, "primary", worker("impl2"), NOW)
        review = sc.claim_slot(store, value, "review", worker("review2"), NOW)
        self.assertEqual(review.value["workerId"], worker("review2"))

    def test_project_wip_is_enforced_atomically_at_claim_time(self):
        store = sc.MemoryStore()
        first = lane("wip-a", epic="a")
        second = lane("wip-b", epic="b")
        persist_lane(store, first)
        persist_lane(store, second)
        config = sc.default_config()
        config["wipLimits"]["maxPrimaryLanes"] = 1
        config["wipLimits"]["maxPrimaryPerEpic"] = 1
        sc.claim_slot(store, first, "primary", worker("wipa"), NOW, config=config)
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, second, "primary", worker("wipb"), NOW, config=config)

    def test_per_epic_wip_is_enforced_atomically_at_claim_time(self):
        store = sc.MemoryStore()
        first = lane("epic-a", epic="capture")
        second = lane("epic-b", epic="capture")
        persist_lane(store, first)
        persist_lane(store, second)
        config = sc.default_config()
        config["wipLimits"]["maxPrimaryLanes"] = 10
        config["wipLimits"]["maxPrimaryPerEpic"] = 1
        sc.claim_slot(store, first, "primary", worker("epica"), NOW, config=config)
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, second, "primary", worker("epicb"), NOW, config=config)

    def test_recommendations_reserve_remaining_project_capacity(self):
        config = sc.default_config()
        config["wipLimits"]["maxPrimaryLanes"] = 1
        config["wipLimits"]["maxPrimaryPerEpic"] = 1
        lanes = [lane("reserve-a", epic="a"), lane("reserve-b", epic="b")]
        recommendations = sc.recommend_slots(lanes, [], [], config, NOW)
        primaries = [item for item in recommendations if item.role == "implementation"]
        self.assertEqual(len(primaries), 1)

    def test_project_blocker_propagates_to_sibling_recommendation_and_claim(self):
        store = sc.MemoryStore()
        freeze = lane("project-freeze", epic="ops")
        freeze["blockers"] = [{"id": "freeze", "state": "ACTIVE", "scope": "project"}]
        freeze = sc.validate_lane(freeze)
        target = lane("project-target", epic="capture")
        persist_lane(store, freeze)
        persist_lane(store, target)
        recommendations = sc.recommend_slots([freeze, target], [], [], sc.default_config(), NOW)
        self.assertFalse(any(item.lane_id == "project-target" for item in recommendations))
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, target, "primary", worker("proj1"), NOW)

    def test_epic_blocker_propagates_only_to_same_epic(self):
        freeze = lane("epic-freeze", epic="capture")
        freeze["blockers"] = [{"id": "capture-freeze", "state": "ACTIVE", "scope": "epic"}]
        freeze = sc.validate_lane(freeze)
        sibling = lane("capture-sibling", epic="capture")
        other = lane("other-epic", epic="rides")
        recommendations = sc.recommend_slots([freeze, sibling, other], [], [], sc.default_config(), NOW)
        self.assertFalse(any(item.lane_id == "capture-sibling" for item in recommendations))
        self.assertTrue(any(item.lane_id == "other-epic" for item in recommendations))

    def test_takeover_cannot_resurrect_terminal_lane(self):
        store = sc.MemoryStore()
        value = lane("terminal-takeover")
        claim = sc.claim_slot(store, value, "primary", worker("term1"), NOW).value
        sc.release_claim(store, value["laneId"], "primary", worker("term1"), claim["leaseId"], claim["generation"], NOW)
        terminal = dict(value)
        terminal["state"] = "DONE"
        terminal = sc.validate_lane(terminal)
        with self.assertRaises(sc.ValidationError):
            sc.takeover_claim(store, terminal, "primary", worker("term2"), NOW)


if __name__ == "__main__":
    unittest.main(verbosity=2)
