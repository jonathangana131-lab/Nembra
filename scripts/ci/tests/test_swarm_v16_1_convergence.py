#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
import swarm_control as sc

NOW = dt.datetime(2026, 8, 13, 9, 30, tzinfo=dt.timezone.utc)


class PolicyActivationTests(unittest.TestCase):
    def test_seed_carries_v16_1_policy_without_schema_reset(self):
        graph = sc.seed_nembra_graph(NOW)
        self.assertEqual(graph['schemaVersion'], 16)
        self.assertEqual(graph['modes']['v16_1']['policyVersion'], '16.1')
        self.assertTrue(graph['modes']['v16_1']['oneBuilderBranchPerBlocker'])
        self.assertEqual(graph['modes']['v16_1']['maxTournamentCandidates'], 2)

    def test_store_lazily_upgrades_old_v16_graph(self):
        store = sc.MemoryStore()
        legacy = sc.mission_graph.seed_nembra_graph(NOW) if hasattr(sc, 'mission_graph') else None
        if legacy is None:
            from swarmcp import mission_graph
            legacy = mission_graph.seed_nembra_graph(NOW)
        store.create(sc.V16_GRAPH_PATH, legacy, message='seed old v16')
        service = sc.MissionGraphStore(store)
        graph, _ = service.ensure()
        self.assertEqual(graph['modes']['v16_1']['policyVersion'], '16.1')
        self.assertGreaterEqual(graph['revision'], 1)


class BuilderConvergenceTests(unittest.TestCase):
    def setUp(self):
        self.graph = sc.seed_nembra_graph(NOW)
        sc.add_blocker(
            self.graph,
            blocker_id='signed-build-origin',
            mission_id='capture-stationary',
            objective_id='capture-signed-build',
            symptom='signed build origin is not accepted',
            severity='P0',
            exit_condition='signed candidate is accepted from exact source',
            legitimate_new=False,
            now=NOW,
        )

    def test_force_duplicate_flag_cannot_create_second_builder_branch(self):
        sc.add_work_item(
            self.graph,
            work_item_id='primary',
            mission_id='capture-stationary',
            objective_id='capture-signed-build',
            blocker_id='signed-build-origin',
            title='Close signed build origin',
            outcome='accepted signed build origin',
            branch='mission/capture-signed-build',
            now=NOW,
        )
        _, decision = sc.add_work_item(
            self.graph,
            work_item_id='successor',
            mission_id='capture-stationary',
            objective_id='capture-signed-build',
            blocker_id='signed-build-origin',
            title='Try another signed build recovery',
            outcome='alternate signed build origin repair',
            branch='recovery/signed-build-origin-2',
            allow_duplicate=True,
            now=NOW,
        )
        self.assertTrue(decision.duplicate)
        self.assertEqual(decision.action, 'JOIN_EXISTING')
        self.assertNotIn('successor', self.graph['workItems'])
        self.assertEqual(self.graph['metrics']['branchForksPrevented'], 1)

    def test_tournament_is_hard_capped_at_two(self):
        sc.authorize_tournament(self.graph, 'origin-tournament', 'signed-build-origin', 2, NOW)
        for index in range(2):
            sc.add_work_item(
                self.graph,
                work_item_id=f'candidate-{index}',
                mission_id='capture-stationary',
                objective_id='capture-signed-build',
                blocker_id='signed-build-origin',
                title=f'Origin candidate {index}',
                outcome=f'bounded architecture {index}',
                branch=f'experimental/origin-{index}',
                tournament_id='origin-tournament',
                allow_duplicate=True,
                now=NOW,
            )
        _, decision = sc.add_work_item(
            self.graph,
            work_item_id='candidate-2',
            mission_id='capture-stationary',
            objective_id='capture-signed-build',
            blocker_id='signed-build-origin',
            title='Origin candidate 2',
            outcome='third bounded architecture',
            branch='experimental/origin-2',
            tournament_id='origin-tournament',
            allow_duplicate=True,
            now=NOW,
        )
        self.assertTrue(decision.duplicate)
        self.assertNotIn('candidate-2', self.graph['workItems'])

    def test_third_low_progress_branch_is_rejected(self):
        sc.record_blocker_attempt(self.graph, 'signed-build-origin', worker='sol-20260813-a', approach='a', result='red', branch='validation/a', meaningful_progress=False, now=NOW)
        sc.record_blocker_attempt(self.graph, 'signed-build-origin', worker='sol-20260813-b', approach='b', result='red', branch='validation/b', meaningful_progress=False, now=NOW)
        with self.assertRaises(sc.ConflictError):
            sc.record_blocker_attempt(self.graph, 'signed-build-origin', worker='sol-20260813-c', approach='c', result='red', branch='validation/c', meaningful_progress=False, now=NOW)
        self.assertTrue(self.graph['modes']['frozenBranchFamilies'])


class MissionPacketTests(unittest.TestCase):
    def test_packet_makes_successor_pr_forbidden_without_bypassing_dependencies(self):
        graph = sc.seed_nembra_graph(NOW)
        sc.add_blocker(graph, blocker_id='x', mission_id='capture-stationary', objective_id='capture-standalone-build', symptom='x blocker', severity='P0', exit_condition='x resolved', legitimate_new=False, now=NOW)
        sc.add_work_item(graph, work_item_id='x-work', mission_id='capture-stationary', objective_id='capture-standalone-build', blocker_id='x', title='Resolve x', outcome='x resolved', branch='mission/x', now=NOW)
        packet = sc.recommend_mission_packets(graph, worker_ids=['sol-20260813-one'], limit=1, now=NOW)[0].packet
        self.assertEqual(packet['CONVERGENCE_POLICY'], '16.1')
        self.assertFalse(packet['MAY_CREATE_SUCCESSOR_PR'])
        self.assertEqual(packet['JOIN_BRANCH'], 'mission/x')
        self.assertIn('do not invent a successor branch', packet['LOST_CLAIM_ACTION'])

    def test_dependency_gate_still_blocks_downstream_v16_1_packet(self):
        graph = sc.seed_nembra_graph(NOW)
        sc.add_work_item(graph, work_item_id='blocked-auth', mission_id='capture-stationary', objective_id='capture-tuya-auth', title='Auth work', outcome='auth accepted', now=NOW)
        self.assertEqual(sc.recommend_mission_packets(graph, limit=5, now=NOW), [])


class PRAdmissionTests(unittest.TestCase):
    def pr(self, number: int, *, lane='capture-build', slot='origin', intent='canonical', protocol='16.1', parent=''):
        body = f'SWARM_PROTOCOL: {protocol}\nSWARM_SCHEMA: 2\nSWARM_LANE: {lane}\nSWARM_SLOT: {slot}\nSWARM_WORKER: sol-20260813-{number}\nSWARM_BRANCH_INTENT: {intent}\n'
        if parent:
            body += f'SWARM_PARENT_PR: {parent}\n'
        return {'number': number, 'state': 'open', 'body': body, 'title': f'PR {number}'}

    def test_same_lane_slot_routes_to_existing_pr(self):
        existing = self.pr(10)
        proposed = self.pr(11, intent='validation', parent='#10')
        decision = sc.evaluate_pr_admission(proposed, [existing, proposed])
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.action, 'JOIN_EXISTING')
        self.assertEqual(decision.join_pr, 10)

    def test_old_protocol_new_swarm_pr_is_rejected(self):
        proposed = self.pr(11, protocol='16')
        decision = sc.evaluate_pr_admission(proposed, [proposed])
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.action, 'UPGRADE_METADATA')

    def test_validation_requires_parent(self):
        proposed = self.pr(11, intent='validation')
        decision = sc.evaluate_pr_admission(proposed, [proposed])
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.action, 'JOIN_PARENT')

    def test_second_canonical_in_lane_is_rejected_even_with_new_slot(self):
        existing = self.pr(10, slot='origin-a', intent='canonical')
        proposed = self.pr(11, slot='origin-b', intent='canonical')
        decision = sc.evaluate_pr_admission(proposed, [existing, proposed])
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.action, 'JOIN_CANONICAL')


class FullSwarmSimulationTests(unittest.TestCase):
    def test_v16_1_30_worker_simulation(self):
        result = sc.run_v16_1_adversarial_simulation(30, NOW)
        self.assertTrue(result['passed'], json.dumps(result, indent=2, sort_keys=True))
        self.assertGreaterEqual(len(result['checks']), 6)


if __name__ == '__main__':
    unittest.main()
