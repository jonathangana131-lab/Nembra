#!/usr/bin/env python3
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
import swarm_control as sc


class RolloutTests(unittest.TestCase):
    def test_new_pr_requires_v16_1_contract(self):
        pr = {
            'number': 1,
            'state': 'open',
            'body': '',
            'created_at': '2026-08-13T20:00:00Z',
        }
        decision = sc.evaluate_pr_admission(pr, [pr])
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.action, 'UPGRADE_METADATA')

    def test_existing_pr_keeps_compatibility(self):
        pr = {
            'number': 2,
            'state': 'open',
            'body': '',
            'created_at': '2026-08-12T20:00:00Z',
        }
        decision = sc.evaluate_pr_admission(pr, [pr])
        self.assertTrue(decision.allowed)
        self.assertEqual(decision.action, 'ALLOW_UNMANAGED')


class WorkerPersistenceTests(unittest.TestCase):
    def test_empty_exclusive_queue_becomes_assist_not_idle(self):
        graph = sc.seed_nembra_graph()
        result = sc.go_cycle(graph, 'sol-20260813-persist-a')
        self.assertEqual(result['status'], 'ASSIST')
        self.assertFalse(result['stopAuthorized'])
        self.assertIsNotNone(result['next'])
        payload = result['next']['packet']
        self.assertTrue(payload['NON_EXCLUSIVE_ASSIST'])
        self.assertFalse(payload['MAY_CREATE_BRANCH'])
        self.assertFalse(payload['MAY_CREATE_SUCCESSOR_PR'])

    def test_thirty_workers_are_routed_when_exclusive_work_is_sparse(self):
        graph = sc.seed_nembra_graph()
        workers = [f'sol-20260813-burst-{i}' for i in range(30)]
        packets = sc.recommend_mission_packets(graph, worker_ids=workers, limit=30)
        self.assertEqual(len(packets), 30)
        self.assertTrue(all(packet.packet['STOP_AUTHORIZED'] is False for packet in packets))
        self.assertTrue(all(packet.packet.get('MODE') for packet in packets))

    def test_claim_conflict_has_fallbacks_instead_of_stop(self):
        graph = sc.seed_nembra_graph()
        sc.add_blocker(
            graph,
            blocker_id='burst-routing-blocker',
            mission_id='nembra-shipping',
            objective_id='dashboard',
            symptom='dashboard candidate needs closure',
            severity='P1',
            exit_condition='dashboard candidate accepted',
            legitimate_new=False,
        )
        sc.add_work_item(
            graph,
            work_item_id='burst-routing-primary',
            mission_id='nembra-shipping',
            objective_id='dashboard',
            blocker_id='burst-routing-blocker',
            title='Close dashboard candidate',
            outcome='accepted dashboard candidate',
            branch='mission/dashboard',
        )
        result = sc.go_cycle(graph, 'sol-20260813-persist-b')
        self.assertEqual(result['status'], 'WORK')
        self.assertFalse(result['stopAuthorized'])
        self.assertGreater(len(result['fallbacks']), 0)
        self.assertIn('do not stop', result['onClaimConflict'])

    def test_stop_requires_genuine_internal_exhaustion(self):
        graph = sc.seed_nembra_graph()
        for objective in graph['objectives'].values():
            objective['status'] = 'DONE'
        result = sc.go_cycle(graph, 'sol-20260813-persist-stop')
        self.assertEqual(result['status'], 'STOP')
        self.assertTrue(result['stopAuthorized'])
        self.assertIsNone(result['next'])


if __name__ == '__main__':
    unittest.main()
