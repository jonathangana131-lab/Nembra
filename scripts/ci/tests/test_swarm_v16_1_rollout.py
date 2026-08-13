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


if __name__ == '__main__':
    unittest.main()
