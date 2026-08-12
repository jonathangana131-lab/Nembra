#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc

NOW=dt.datetime(2026,8,12,10,0,tzinfo=dt.timezone.utc)


def classification(pr: int) -> dict:
    return {
        'pr':pr,
        'title':f'PR {pr}',
        'classification':'requires-review',
        'lane':'',
        'reason':'migration inventory',
    }


class MigrationIndexBoundTests(unittest.TestCase):
    def graph_with_classifications(self, count: int) -> dict:
        graph=sc.seed_nembra_graph(NOW)
        graph['migration']['classifiedPRs']={str(pr):classification(pr) for pr in range(1,count+1)}
        return graph

    def test_live_scale_334_pr_inventory_is_valid(self):
        graph=sc.validate_graph(self.graph_with_classifications(334))
        self.assertEqual(len(graph['migration']['classifiedPRs']),334)

    def test_producer_maximum_400_pr_inventory_is_valid(self):
        graph=sc.validate_graph(self.graph_with_classifications(400))
        self.assertEqual(len(graph['migration']['classifiedPRs']),400)

    def test_migration_index_over_producer_maximum_fails_closed(self):
        with self.assertRaisesRegex(sc.ValidationError,r'\$\.migration\.classifiedPRs too many keys'):
            sc.validate_graph(self.graph_with_classifications(401))

    def test_unrelated_dictionary_keeps_default_128_key_limit(self):
        with self.assertRaisesRegex(sc.ValidationError,r'\$\.ordinary too many keys'):
            sc.validate_data_only({'ordinary':{str(i):i for i in range(129)}})

    def test_large_migration_index_does_not_bypass_forbidden_control_fields(self):
        graph=self.graph_with_classifications(334)
        graph['migration']['classifiedPRs']['1']['script']='do not execute'
        with self.assertRaisesRegex(sc.ValidationError,'executable control field forbidden'):
            sc.validate_graph(graph)


if __name__=='__main__': unittest.main()
