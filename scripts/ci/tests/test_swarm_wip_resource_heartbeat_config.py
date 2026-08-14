#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import swarm_control as sc

NOW = dt.datetime(2026, 8, 11, 6, 27, tzinfo=dt.timezone.utc)


def worker(suffix: str) -> str:
    return f"sol-20260811-{suffix}"


def repair_lane(lane_id: str, epic: str):
    lane = sc.sample_lane(lane_id)
    lane["epic"] = epic
    lane["slots"] = [
        {
            "name": "repair",
            "role": "repair",
            "exclusive": True,
            "leaseSeconds": 1800,
            "resources": [],
        }
    ]
    return sc.validate_lane(lane)


class WIPResourceHeartbeatConfigTests(unittest.TestCase):
    def test_repair_recommendations_reserve_primary_wip_capacity(self):
        config = sc.default_config()
        config["wipLimits"]["maxPrimaryLanes"] = 1
        config["wipLimits"]["maxPrimaryPerEpic"] = 1
        lanes = [repair_lane("repair-a", "ops-a"), repair_lane("repair-b", "ops-b")]
        recommendations = sc.safe_recommend_slots(lanes, [], [], config, NOW, red_main=True)
        repairs = [item for item in recommendations if item.role == "repair"]
        self.assertEqual(len(repairs), 1)

    def test_repair_claims_are_enforced_by_project_wip_limit(self):
        store = sc.MemoryStore()
        first = repair_lane("repair-claim-a", "ops-a")
        second = repair_lane("repair-claim-b", "ops-b")
        store.create(sc.lane_path(first["laneId"]), first)
        store.create(sc.lane_path(second["laneId"]), second)
        config = sc.default_config()
        config["wipLimits"]["maxPrimaryLanes"] = 1
        config["wipLimits"]["maxPrimaryPerEpic"] = 1
        sc.claim_slot(store, first, "repair", worker("rwp01"), NOW, config=config)
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, second, "repair", worker("rwp02"), NOW, config=config)

    def test_live_repair_consumes_capacity_before_normal_implementation(self):
        store = sc.MemoryStore()
        repair = repair_lane("repair-live", "ops")
        normal = sc.sample_lane("normal-after-repair")
        normal["epic"] = "feature"
        normal = sc.validate_lane(normal)
        store.create(sc.lane_path(repair["laneId"]), repair)
        store.create(sc.lane_path(normal["laneId"]), normal)
        config = sc.default_config()
        config["wipLimits"]["maxPrimaryLanes"] = 1
        config["wipLimits"]["maxPrimaryPerEpic"] = 1
        sc.claim_slot(store, repair, "repair", worker("rwp03"), NOW, config=config)
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, normal, "primary", worker("rwp04"), NOW, config=config)

    def test_resource_heartbeat_fails_after_owning_slot_is_released(self):
        store = sc.MemoryStore()
        lane = sc.sample_lane("resource-owner-release")
        lane["slots"][0]["resources"] = ["XCODE_BUILD"]
        lane = sc.validate_lane(lane)
        store.create(sc.lane_path(lane["laneId"]), lane)
        owner = worker("rhs01")
        claim = sc.claim_slot(store, lane, "primary", owner, NOW).value
        resource = sc.acquire_resources_for_claim(
            store,
            ["XCODE_BUILD"],
            owner,
            lane["laneId"],
            NOW,
            sc.default_config()["resourceOrder"],
        )[0].value
        sc.release_claim(
            store,
            lane["laneId"],
            "primary",
            owner,
            claim["leaseId"],
            claim["generation"],
            NOW,
        )
        with self.assertRaises(sc.LeaseLostError):
            sc.heartbeat_resource_for_claim(
                store,
                "XCODE_BUILD",
                owner,
                resource["leaseId"],
                resource["generation"],
                NOW + dt.timedelta(seconds=30),
            )

    def test_resource_heartbeat_fails_after_owning_slot_is_taken_over(self):
        store = sc.MemoryStore()
        lane = sc.sample_lane("resource-owner-takeover")
        lane["slots"][0]["resources"] = ["XCODE_BUILD"]
        lane = sc.validate_lane(lane)
        store.create(sc.lane_path(lane["laneId"]), lane)
        old_owner = worker("rhs02")
        claim = sc.claim_slot(store, lane, "primary", old_owner, NOW).value
        resource = sc.acquire_resources_for_claim(
            store,
            ["XCODE_BUILD"],
            old_owner,
            lane["laneId"],
            NOW,
            sc.default_config()["resourceOrder"],
        )[0].value
        sc.release_claim(
            store,
            lane["laneId"],
            "primary",
            old_owner,
            claim["leaseId"],
            claim["generation"],
            NOW,
        )
        sc.takeover_claim(store, lane, "primary", worker("rhs03"), NOW)
        with self.assertRaises(sc.LeaseLostError):
            sc.heartbeat_resource_for_claim(
                store,
                "XCODE_BUILD",
                old_owner,
                resource["leaseId"],
                resource["generation"],
                NOW + dt.timedelta(seconds=30),
            )

    def test_boolean_project_wip_is_rejected(self):
        config = sc.default_config()
        config["wipLimits"]["maxPrimaryLanes"] = True
        with self.assertRaises(sc.ValidationError):
            sc.validate_config(config)

    def test_boolean_backlog_threshold_is_rejected(self):
        config = sc.default_config()
        config["wipLimits"]["reviewBacklogThreshold"] = False
        with self.assertRaises(sc.ValidationError):
            sc.validate_config(config)


if __name__ == "__main__":
    unittest.main(verbosity=2)
