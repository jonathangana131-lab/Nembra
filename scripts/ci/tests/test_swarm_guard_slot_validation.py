#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import swarm_control as sc
import swarmcp.enforcement as enforcement

NOW = dt.datetime(2026, 8, 11, 6, 10, tzinfo=dt.timezone.utc)


def worker(suffix: str) -> str:
    return f"sol-20260811-{suffix}"


class GuardAndSlotValidationTests(unittest.TestCase):
    def test_slow_claim_renews_guard_immediately_before_target_write(self):
        store = sc.MemoryStore()
        lane = sc.sample_lane("slow-guard")
        after_lease = NOW + dt.timedelta(seconds=enforcement._policy.SCHEDULER_GUARD_LEASE_SECONDS + 1)
        with mock.patch.object(enforcement, "utc_now", return_value=after_lease):
            claim = enforcement.claim_slot(store, lane, "primary", worker("grd01"), NOW)
        self.assertEqual(claim.value["workerId"], worker("grd01"))

    def test_claim_aborts_if_guard_was_taken_over_before_target_write(self):
        store = sc.MemoryStore()
        lane = sc.sample_lane("stolen-guard")
        original_policy = enforcement._policy._enforce_claim_policy

        def policy_then_takeover(*args, **kwargs):
            result = original_policy(*args, **kwargs)
            enforcement._policy._acquire_scheduler_guard(
                store,
                worker("grd03"),
                NOW + dt.timedelta(seconds=enforcement._policy.SCHEDULER_GUARD_LEASE_SECONDS + 1),
            )
            return result

        with mock.patch.object(enforcement._policy, "_enforce_claim_policy", side_effect=policy_then_takeover):
            with self.assertRaises(sc.LeaseLostError):
                enforcement.claim_slot(store, lane, "primary", worker("grd02"), NOW)
        with self.assertRaises(sc.NotFoundError):
            store.get(sc.claim_path(lane["laneId"], "primary"))

    def test_slot_resources_reject_unhashable_items_as_validation_error(self):
        lane = sc.sample_lane("bad-slot-resource")
        lane["slots"][0]["resources"] = [{"bad": "resource"}]
        with self.assertRaises(sc.ValidationError):
            sc.validate_lane(lane)

    def test_slot_resources_reject_non_array_collection(self):
        lane = sc.sample_lane("bad-resource-shape")
        lane["slots"][0]["resources"] = {"XCODE_BUILD": True}
        with self.assertRaises(sc.ValidationError):
            sc.validate_lane(lane)


if __name__ == "__main__":
    unittest.main(verbosity=2)
