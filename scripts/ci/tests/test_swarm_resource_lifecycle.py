#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import swarm_control as sc

NOW = dt.datetime(2026, 8, 11, 5, 25, tzinfo=dt.timezone.utc)
WORKER = "sol-20260811-res01"
OTHER = "sol-20260811-res02"


class ResourceLifecycleTests(unittest.TestCase):
    def test_acquire_heartbeat_release_resource(self):
        store = sc.MemoryStore()
        acquired = sc.acquire_resources(
            store,
            ["XCODE_BUILD"],
            WORKER,
            "alpha",
            NOW,
            sc.default_config()["resourceOrder"],
        )[0].value
        later = NOW + dt.timedelta(seconds=30)
        heartbeat = sc.heartbeat_resource(
            store,
            "XCODE_BUILD",
            WORKER,
            acquired["leaseId"],
            acquired["generation"],
            later,
        ).value
        self.assertEqual(heartbeat["lastHeartbeatAt"], sc.format_time(later))
        released = sc.release_resource(
            store,
            "XCODE_BUILD",
            WORKER,
            acquired["leaseId"],
            acquired["generation"],
            later,
        ).value
        self.assertEqual(released["status"], "RELEASED")

    def test_other_worker_cannot_heartbeat_or_release_resource(self):
        store = sc.MemoryStore()
        acquired = sc.acquire_resources(
            store,
            ["IOS_SIMULATOR"],
            WORKER,
            "alpha",
            NOW,
            sc.default_config()["resourceOrder"],
        )[0].value
        with self.assertRaises(sc.LeaseLostError):
            sc.heartbeat_resource(store,"IOS_SIMULATOR",OTHER,acquired["leaseId"],acquired["generation"],NOW)
        with self.assertRaises(sc.LeaseLostError):
            sc.release_resource(store,"IOS_SIMULATOR",OTHER,acquired["leaseId"],acquired["generation"],NOW)

    def test_expired_resource_cannot_heartbeat(self):
        store = sc.MemoryStore()
        acquired = sc.acquire_resources(
            store,
            ["IOS_DEVICE"],
            WORKER,
            "alpha",
            NOW,
            sc.default_config()["resourceOrder"],
        )[0].value
        expired = sc.claim_expiry(acquired) + dt.timedelta(seconds=1)
        with self.assertRaises(sc.LeaseLostError):
            sc.heartbeat_resource(store,"IOS_DEVICE",WORKER,acquired["leaseId"],acquired["generation"],expired)

    def test_released_resource_can_be_acquired_by_next_worker(self):
        store = sc.MemoryStore()
        first = sc.acquire_resources(store,["XCODE_BUILD"],WORKER,"alpha",NOW,sc.default_config()["resourceOrder"])[0].value
        sc.release_resource(store,"XCODE_BUILD",WORKER,first["leaseId"],first["generation"],NOW)
        second = sc.acquire_resources(store,["XCODE_BUILD"],OTHER,"beta",NOW,sc.default_config()["resourceOrder"])[0].value
        self.assertEqual(second["workerId"], OTHER)
        self.assertEqual(second["generation"], first["generation"] + 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
