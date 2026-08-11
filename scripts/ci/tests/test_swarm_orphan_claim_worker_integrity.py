#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import swarm_control as sc


NOW = dt.datetime(2026, 8, 11, 8, 0, tzinfo=dt.timezone.utc)
WORKER = "sol-20260811-orphan1"


def registered_worker(worker_id: str = WORKER):
    return sc.validate_worker(
        {
            "schemaVersion": 1,
            "kind": "worker",
            "workerId": worker_id,
            "model": "GPT-5.6 Sol",
            "status": "ACTIVE",
            "branch": "",
            "startedAt": sc.format_time(NOW),
            "lastSeenAt": sc.format_time(NOW),
        }
    )


class OrphanClaimWorkerIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.lane = sc.sample_lane("orphan-integrity")

    def test_live_claim_without_registered_worker_fails_snapshot(self):
        claim = sc.new_claim(self.lane, "primary", WORKER, now=NOW)
        errors = sc.validate_state_snapshot([self.lane], [claim], [], [], [], now=NOW)
        self.assertTrue(
            any("live claim references unregistered worker" in error for error in errors),
            errors,
        )

    def test_registered_worker_satisfies_live_claim_binding(self):
        claim = sc.new_claim(self.lane, "primary", WORKER, now=NOW)
        errors = sc.validate_state_snapshot(
            [self.lane], [claim], [registered_worker()], [], [], now=NOW
        )
        self.assertFalse(
            any("unregistered worker" in error for error in errors),
            errors,
        )

    def test_released_historical_claim_does_not_require_live_worker_record(self):
        store = sc.MemoryStore()
        claim = sc.claim_slot(store, self.lane, "primary", WORKER, now=NOW).value
        released = sc.release_claim(
            store,
            self.lane["laneId"],
            "primary",
            WORKER,
            claim["leaseId"],
            claim["generation"],
            now=NOW,
        ).value
        errors = sc.validate_state_snapshot([self.lane], [released], [], [], [], now=NOW)
        self.assertFalse(
            any("unregistered worker" in error for error in errors),
            errors,
        )

    def test_expired_claim_does_not_pin_worker_registry_forever(self):
        claim = sc.new_claim(self.lane, "primary", WORKER, now=NOW)
        after_expiry = sc.claim_expiry(claim) + dt.timedelta(seconds=1)
        errors = sc.validate_state_snapshot(
            [self.lane], [claim], [], [], [], now=after_expiry
        )
        self.assertFalse(
            any("unregistered worker" in error for error in errors),
            errors,
        )

    def test_invalid_worker_record_cannot_satisfy_live_claim_binding(self):
        claim = sc.new_claim(self.lane, "primary", WORKER, now=NOW)
        invalid_worker = registered_worker()
        invalid_worker["workerId"] = "worker-one"
        errors = sc.validate_state_snapshot(
            [self.lane], [claim], [invalid_worker], [], [], now=NOW
        )
        self.assertTrue(any(error.startswith("worker[0]:") for error in errors), errors)
        self.assertTrue(
            any("live claim references unregistered worker" in error for error in errors),
            errors,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
