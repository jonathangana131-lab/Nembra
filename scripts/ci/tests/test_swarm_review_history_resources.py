#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import swarm_control as sc

NOW = dt.datetime(2026, 8, 11, 5, 58, tzinfo=dt.timezone.utc)


def worker(suffix: str) -> str:
    return f"sol-20260811-{suffix}"


class ReviewHistoryAndResourceAuthorizationTests(unittest.TestCase):
    def test_takeover_preserves_all_prior_implementers_for_review_independence(self):
        store = sc.MemoryStore()
        lane = sc.sample_lane("history-review")
        first = sc.claim_slot(store, lane, "primary", worker("hist1"), NOW).value
        sc.release_claim(store, lane["laneId"], "primary", worker("hist1"), first["leaseId"], first["generation"], NOW)
        second = sc.takeover_claim(store, lane, "primary", worker("hist2"), NOW).value
        sc.release_claim(store, lane["laneId"], "primary", worker("hist2"), second["leaseId"], second["generation"], NOW)
        third = sc.takeover_claim(store, lane, "primary", worker("hist3"), NOW).value
        self.assertEqual(third["priorWorkerIds"], [worker("hist1"), worker("hist2")])

        review_lane = dict(lane)
        review_lane["state"] = "REVIEW"
        review_lane = sc.validate_lane(review_lane)
        for previous in (worker("hist1"), worker("hist2"), worker("hist3")):
            with self.assertRaises(sc.ValidationError):
                sc.claim_slot(store, review_lane, "review", previous, NOW)
        accepted = sc.claim_slot(store, review_lane, "review", worker("hist4"), NOW)
        self.assertEqual(accepted.value["workerId"], worker("hist4"))

    def test_malformed_tag_fails_validation_before_scheduler_set(self):
        lane = sc.sample_lane("bad-tags")
        lane["tags"] = [{"not": "hashable"}]
        with self.assertRaises(sc.ValidationError):
            sc.validate_lane(lane)

    def test_resource_acquire_requires_existing_lane_and_live_declaring_owner(self):
        store = sc.MemoryStore()
        order = sc.default_config()["resourceOrder"]
        with self.assertRaises(sc.ValidationError):
            sc.acquire_resources_for_claim(store, ["XCODE_BUILD"], worker("res01"), "missing-lane", NOW, order)

        lane = sc.sample_lane("owned-resource")
        lane["slots"][0]["resources"] = ["XCODE_BUILD"]
        lane = sc.validate_lane(lane)
        store.create(sc.lane_path(lane["laneId"]), lane)
        sc.claim_slot(store, lane, "primary", worker("res01"), NOW)

        with self.assertRaises(sc.ValidationError):
            sc.acquire_resources_for_claim(store, ["XCODE_BUILD"], worker("res02"), lane["laneId"], NOW, order)
        acquired = sc.acquire_resources_for_claim(store, ["XCODE_BUILD"], worker("res01"), lane["laneId"], NOW, order)
        self.assertEqual(acquired[0].value["workerId"], worker("res01"))

    def test_resource_not_declared_by_owned_slot_is_rejected(self):
        store = sc.MemoryStore()
        order = sc.default_config()["resourceOrder"]
        lane = sc.sample_lane("wrong-resource")
        store.create(sc.lane_path(lane["laneId"]), lane)
        sc.claim_slot(store, lane, "primary", worker("res03"), NOW)
        with self.assertRaises(sc.ValidationError):
            sc.acquire_resources_for_claim(store, ["IOS_SIMULATOR"], worker("res03"), lane["laneId"], NOW, order)

    def test_orphan_resource_does_not_suppress_safe_recommendations(self):
        lane = sc.sample_lane("orphan-resource")
        for slot in lane["slots"]:
            if slot["name"] == "tests":
                slot["resources"] = ["XCODE_BUILD"]
        lane = sc.validate_lane(lane)
        orphan = sc._resource_claim("XCODE_BUILD", worker("res04"), lane["laneId"], NOW)
        recommendations = sc.safe_recommend_slots([lane], [], [orphan], sc.default_config(), NOW)
        self.assertTrue(any(item.slot == "tests" for item in recommendations))

    def test_snapshot_reports_live_orphan_resource_lease(self):
        lane = sc.sample_lane("orphan-snapshot")
        orphan = sc._resource_claim("XCODE_BUILD", worker("res05"), lane["laneId"], NOW)
        errors = sc.validate_state_snapshot([lane], [], [], [], [orphan], NOW)
        self.assertTrue(any("no matching live owning slot claim" in error for error in errors))


if __name__ == "__main__":
    unittest.main(verbosity=2)
