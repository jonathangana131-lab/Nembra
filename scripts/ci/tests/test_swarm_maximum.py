#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import swarm_control as sc
from swarmcp import maximum as mx

NOW = dt.datetime(2026, 8, 11, 8, 5, tzinfo=dt.timezone.utc)
WORKER = "sol-20260811-maxtst"


def write_json(root: Path, relative: str, value: dict):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def config():
    value = sc.default_config()
    value["rolloutMode"] = "enforcement"
    value["enforcement"] = {
        "legacyCutoffUTC": "2026-08-11T08:03:20Z",
        "requireValidatedState": True,
        "trustedBaseValidator": True,
        "hardFailControlledScope": True,
        "hardFailPostCutoffMissingMetadata": True,
    }
    value["legacyPRCompatibility"] = "created-before-v16-cutoff-only"
    return value


def worker_record():
    return {
        "schemaVersion": 1,
        "kind": "worker",
        "workerId": WORKER,
        "model": "GPT-5.6 Sol",
        "status": "ACTIVE",
        "branch": "agent/alpha",
        "startedAt": sc.format_time(NOW),
        "lastSeenAt": sc.format_time(NOW),
    }


def event(created_at: str, body: str, number: int = 9001):
    return {
        "pull_request": {
            "number": number,
            "created_at": created_at,
            "body": body,
            "head": {"ref": "agent/alpha"},
        }
    }


class MaximumControlPlaneTests(unittest.TestCase):
    def make_root(self, lane=None, claim=None, resource=None):
        td = tempfile.TemporaryDirectory()
        root = Path(td.name)
        write_json(root, ".swarm/config.json", config())
        if lane is not None:
            write_json(root, sc.lane_path(lane["laneId"]), lane)
        if claim is not None:
            write_json(root, sc.claim_path(claim["laneId"], claim["slot"]), claim)
        if resource is not None:
            write_json(root, sc.resource_path(resource["resource"]), resource)
        write_json(root, f".swarm/runtime/workers/{WORKER}.json", worker_record())
        return td, root

    def test_state_digest_ignores_generated_cache(self):
        lane = sc.sample_lane("done", state="DONE")
        td, root = self.make_root(lane=lane)
        try:
            first = mx.state_digest(root)
            write_json(root, ".swarm/runtime/generated/noise.json", {"cache": 1})
            self.assertEqual(mx.state_digest(root), first)
        finally:
            td.cleanup()

    def test_render_writes_matching_validation_fence(self):
        lane = sc.sample_lane("done", state="DONE")
        td, root = self.make_root(lane=lane)
        try:
            result = mx.render_projection(root, NOW)
            self.assertEqual(result["validation"]["stateDigest"], mx.state_digest(root))
            self.assertEqual(mx.verify_projection(root)["status"], "PASS")
        finally:
            td.cleanup()

    def test_fence_rejects_state_change_after_validation(self):
        lane = sc.sample_lane("done", state="DONE")
        td, root = self.make_root(lane=lane)
        try:
            mx.render_projection(root, NOW)
            lane["title"] = "changed after fence"
            write_json(root, sc.lane_path("done"), lane)
            with self.assertRaises(sc.ValidationError):
                mx.verify_projection(root)
        finally:
            td.cleanup()

    def test_post_cutoff_pr_without_metadata_hard_fails(self):
        lane = sc.sample_lane("done", state="DONE")
        td, root = self.make_root(lane=lane)
        try:
            mx.render_projection(root, NOW)
            ev = write_json(root, "event.json", event("2026-08-11T08:04:00Z", "no swarm metadata"))
            changed = root / "changed.txt"; changed.write_text("README.md\n", encoding="utf-8")
            with self.assertRaises(sc.ValidationError):
                mx.enforce_pr(root, ev, changed, NOW)
        finally:
            td.cleanup()

    def test_pre_cutoff_legacy_pr_is_grandfathered(self):
        lane = sc.sample_lane("done", state="DONE")
        td, root = self.make_root(lane=lane)
        try:
            mx.render_projection(root, NOW)
            ev = write_json(root, "event.json", event("2026-08-11T08:00:00Z", "legacy body"))
            changed = root / "changed.txt"; changed.write_text("README.md\n", encoding="utf-8")
            self.assertEqual(mx.enforce_pr(root, ev, changed, NOW)["status"], "LEGACY_GRANDFATHERED")
        finally:
            td.cleanup()

    def test_controlled_pr_requires_live_owner_generation_branch_and_scope(self):
        lane = sc.sample_lane("alpha")
        claim = sc.new_claim(lane, "primary", WORKER, NOW, branch="agent/alpha")
        td, root = self.make_root(lane=lane, claim=claim)
        try:
            mx.render_projection(root, NOW)
            body = "\n".join([
                "SWARM_SCHEMA: 1",
                "SWARM_LANE: alpha",
                "SWARM_SLOT: primary",
                f"SWARM_WORKER: {WORKER}",
                "SWARM_CLAIM_GENERATION: 1",
            ])
            ev = write_json(root, "event.json", event("2026-08-11T08:04:00Z", body))
            changed = root / "changed.txt"; changed.write_text("work/alpha/file.swift\n", encoding="utf-8")
            self.assertEqual(mx.enforce_pr(root, ev, changed, NOW)["status"], "PASS")
            changed.write_text("unrelated/escape.swift\n", encoding="utf-8")
            with self.assertRaises(sc.ValidationError):
                mx.enforce_pr(root, ev, changed, NOW)
        finally:
            td.cleanup()

    def test_controlled_pr_requires_declared_resource_lease(self):
        lane = sc.sample_lane("alpha")
        lane["slots"][0]["resources"] = ["HIGH_CONTENTION_FILE"]
        lane = sc.validate_lane(lane)
        claim = sc.new_claim(lane, "primary", WORKER, NOW, branch="agent/alpha")
        td, root = self.make_root(lane=lane, claim=claim)
        try:
            mx.render_projection(root, NOW)
            body = "\n".join([
                "SWARM_SCHEMA: 1",
                "SWARM_LANE: alpha",
                "SWARM_SLOT: primary",
                f"SWARM_WORKER: {WORKER}",
                "SWARM_CLAIM_GENERATION: 1",
            ])
            ev = write_json(root, "event.json", event("2026-08-11T08:04:00Z", body))
            changed = root / "changed.txt"; changed.write_text("work/alpha/file.swift\n", encoding="utf-8")
            with self.assertRaises(sc.ValidationError):
                mx.enforce_pr(root, ev, changed, NOW)
        finally:
            td.cleanup()

    def test_stop_proof_is_mechanical_not_green_status_prose(self):
        done = sc.sample_lane("done", state="DONE")
        td, root = self.make_root(lane=done)
        try:
            self.assertEqual(mx.stop_proof(root, NOW)["status"], "PASS")
        finally:
            td.cleanup()
        ready = sc.sample_lane("ready", state="READY")
        td, root = self.make_root(lane=ready)
        try:
            with self.assertRaises(sc.ValidationError):
                mx.stop_proof(root, NOW)
        finally:
            td.cleanup()


if __name__ == "__main__":
    unittest.main()
