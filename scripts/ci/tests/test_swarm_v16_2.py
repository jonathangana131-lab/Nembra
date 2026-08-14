#!/usr/bin/env python3
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))
import swarm_control as sc


def managed_body(*, protocol="16.2", lane="capture-tuya-readonly-preflight", slot="slot-a", worker="sol-test", intent="validation", parent="#4000"):
    lines = [
        f"SWARM_PROTOCOL: {protocol}",
        "SWARM_SCHEMA: 2",
        f"SWARM_LANE: {lane}",
        f"SWARM_SLOT: {slot}",
        f"SWARM_WORKER: {worker}",
        f"SWARM_BRANCH_INTENT: {intent}",
    ]
    if parent:
        lines.append(f"SWARM_PARENT_PR: {parent}")
    return "\n".join(lines)


class IntegrationPressureTests(unittest.TestCase):
    def make_graph(self):
        graph = sc.seed_nembra_graph()
        sc.add_blocker(
            graph,
            blocker_id="v162-integration-blocker",
            mission_id="nembra-shipping",
            objective_id="dashboard",
            symptom="accepted dashboard work is waiting outside main",
            severity="P1",
            exit_condition="dashboard work is composed into canonical main-ready candidate",
            legitimate_new=False,
        )
        sc.add_work_item(
            graph,
            work_item_id="v162-dashboard-child",
            mission_id="nembra-shipping",
            objective_id="dashboard",
            blocker_id="v162-integration-blocker",
            title="Integrate accepted dashboard child",
            outcome="canonical dashboard contains accepted child",
            branch="review/dashboard-child",
        )
        item = graph["workItems"]["v162-dashboard-child"]
        item["status"] = "INTEGRATING"
        item["integrationWorld"] = "NEXT"
        item["branchState"] = "SELECTED"
        return graph

    def test_policy_activates_in_place(self):
        graph = sc.seed_nembra_graph()
        self.assertEqual(graph["schemaVersion"], 16)
        self.assertEqual(graph["modes"]["v16_2"]["policyVersion"], "16.2")
        self.assertTrue(graph["modes"]["v16_2"]["canonicalAbsorptionRequired"])

    def test_integrating_work_outranks_capacity_mining(self):
        graph = self.make_graph()
        packets = sc.recommend_mission_packets(graph, limit=10)
        self.assertTrue(packets)
        self.assertEqual(packets[0].packet["MODE"], "MERGE_PRESSURE")
        self.assertEqual(packets[0].work_item_id, "v162-dashboard-child")
        self.assertFalse(packets[0].packet["MAY_CREATE_SUCCESSOR_PR"])

    def test_absorption_plan_points_child_at_canonical(self):
        graph = self.make_graph()
        plans = sc.canonical_absorption_plan(graph)
        plan = next(p for p in plans if p["objectiveId"] == "dashboard")
        self.assertEqual(plan["canonicalBranch"], "mission/dashboard")
        self.assertEqual(plan["action"], "ABSORB_INTO_CANONICAL")
        self.assertIn("v162-dashboard-child", plan["childWorkItemIds"])

    def test_merge_pressure_shifts_workers_to_integration(self):
        graph = self.make_graph()
        allocation = sc.role_allocation(graph, 30)
        self.assertGreater(allocation["integrator"], allocation["builder"])
        report = sc.merge_pressure_report(graph)
        self.assertTrue(report["active"])
        self.assertEqual(report["integratingCount"], 1)

    def test_go_cycle_records_merge_pressure_and_does_not_stop(self):
        graph = self.make_graph()
        result = sc.go_cycle(graph, "sol-v162-worker")
        self.assertFalse(result["stopAuthorized"])
        self.assertTrue(result["mergePressure"]["active"])
        self.assertIn(result["status"], {"WORK", "ASSIST"})
        self.assertIn("dashboard", graph["modes"]["mergePressureObjectives"])


class PRAbsorptionGuardTests(unittest.TestCase):
    def pr(self, number, body, *, created="2026-08-14T08:10:00Z", state="open"):
        return {"number": number, "body": body, "created_at": created, "state": state}

    def test_new_pr_must_use_16_2(self):
        pr = self.pr(5001, managed_body(protocol="16.1", intent="canonical", parent=""))
        decision = sc.evaluate_pr_admission(pr, [pr])
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.action, "UPGRADE_METADATA")

    def test_old_v16_1_pr_remains_compatible(self):
        pr = self.pr(5002, managed_body(protocol="16.1", intent="canonical", parent=""), created="2026-08-13T20:00:00Z")
        decision = sc.evaluate_pr_admission(pr, [pr])
        self.assertTrue(decision.allowed)

    def test_review_child_requires_parent(self):
        pr = self.pr(5003, managed_body(intent="review", parent=""))
        decision = sc.evaluate_pr_admission(pr, [pr])
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.action, "JOIN_PARENT")

    def test_child_must_attach_to_open_canonical(self):
        canonical = self.pr(5000, managed_body(slot="canonical", worker="captain", intent="canonical", parent=""))
        child = self.pr(5004, managed_body(slot="review-a", intent="review", parent="#4999"))
        decision = sc.evaluate_pr_admission(child, [canonical, child])
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.action, "JOIN_CANONICAL")
        self.assertEqual(decision.join_pr, 5000)

    def test_third_child_is_rejected_until_absorption(self):
        canonical = self.pr(5100, managed_body(slot="canonical", worker="captain", intent="canonical", parent=""))
        one = self.pr(5101, managed_body(slot="validation-a", worker="a", intent="validation", parent="#5100"))
        two = self.pr(5102, managed_body(slot="review-a", worker="b", intent="review", parent="#5100"))
        three = self.pr(5103, managed_body(slot="validation-b", worker="c", intent="validation", parent="#5100"))
        decision = sc.evaluate_pr_admission(three, [canonical, one, two, three])
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.action, "ABSORB_FIRST")
        self.assertEqual(decision.join_pr, 5100)

    def test_only_one_integration_child_per_parent(self):
        canonical = self.pr(5200, managed_body(slot="canonical", worker="captain", intent="canonical", parent=""))
        one = self.pr(5201, managed_body(slot="integration-a", worker="a", intent="integration", parent="#5200"))
        two = self.pr(5202, managed_body(slot="integration-b", worker="b", intent="integration", parent="#5200"))
        decision = sc.evaluate_pr_admission(two, [canonical, one, two])
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.action, "JOIN_EXISTING")
        self.assertEqual(decision.join_pr, 5201)


if __name__ == "__main__":
    unittest.main()
