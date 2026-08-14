#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import swarm_control as sc

NOW = dt.datetime(2026, 8, 11, 5, 42, tzinfo=dt.timezone.utc)


def worker(suffix: str) -> str:
    return f"sol-20260811-{suffix}"


def reconciliation_lane(state: str):
    return sc.validate_lane({
        "schemaVersion": 1,
        "kind": "lane",
        "laneId": "legacy-reconcile-test",
        "epic": "swarm-control-plane",
        "title": "Legacy reconciliation test",
        "objective": "Prove independent review works for non-primary reconciliation lanes.",
        "priority": 0,
        "state": state,
        "dependencies": [],
        "blockers": [],
        "mode": "exclusive",
        "allowedWriteAreas": [".swarm/runtime/lanes"],
        "adjacentWriteAreas": [],
        "slots": [
            {"name": "reconcile", "role": "scheduler-reconciler", "exclusive": True, "leaseSeconds": 1800, "resources": []},
            {"name": "review", "role": "adversarial-review", "exclusive": True, "leaseSeconds": 1800, "resources": []},
        ],
        "acceptance": {"independentReview": True},
        "physical": {"required": False, "state": "SOURCE_READY"},
        "tags": ["migration"],
    })


class ReviewSubjectTests(unittest.TestCase):
    def test_reconciliation_lane_can_receive_independent_review_without_primary_slot(self):
        store = sc.MemoryStore()
        ready = reconciliation_lane("READY")
        sc.claim_slot(store, ready, "reconcile", worker("rec01"), NOW)
        review = sc.claim_slot(store, reconciliation_lane("REVIEW"), "review", worker("rev01"), NOW)
        self.assertEqual(review.value["workerId"], worker("rev01"))

    def test_reconciliation_worker_cannot_review_own_lane(self):
        store = sc.MemoryStore()
        ready = reconciliation_lane("READY")
        sc.claim_slot(store, ready, "reconcile", worker("rec02"), NOW)
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, reconciliation_lane("REVIEW"), "review", worker("rec02"), NOW)

    def test_tournament_reviewer_must_differ_from_every_candidate(self):
        store = sc.MemoryStore()
        lane = sc.sample_lane("tournament-review")
        lane["mode"] = "tournament"
        lane["slots"] = [
            {"name": "candidate-a", "role": "implementation", "exclusive": True, "leaseSeconds": 1800, "resources": []},
            {"name": "candidate-b", "role": "implementation", "exclusive": True, "leaseSeconds": 1800, "resources": []},
            {"name": "review", "role": "adversarial-review", "exclusive": True, "leaseSeconds": 1800, "resources": []},
        ]
        lane["tournament"] = {"authorized": True}
        lane = sc.validate_lane(lane)
        sc.claim_slot(store, lane, "candidate-a", worker("cand1"), NOW)
        sc.claim_slot(store, lane, "candidate-b", worker("cand2"), NOW)
        review_lane = dict(lane)
        review_lane["state"] = "REVIEW"
        review_lane = sc.validate_lane(review_lane)
        with self.assertRaises(sc.ValidationError):
            sc.claim_slot(store, review_lane, "review", worker("cand2"), NOW)
        accepted = sc.claim_slot(store, review_lane, "review", worker("rev02"), NOW)
        self.assertEqual(accepted.value["workerId"], worker("rev02"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
