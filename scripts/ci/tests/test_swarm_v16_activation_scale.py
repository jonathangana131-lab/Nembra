#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc
from swarm_v16_activate import MAX_PERSISTED_PR_CLASSIFICATIONS, compact_pr_classifications


class ActivationScaleTests(unittest.TestCase):
    def test_live_pr_classifications_are_bounded_without_losing_authority_witnesses(self):
        graph=sc.seed_nembra_graph()
        graph['migration']['classifiedPRs']={
            str(number):{'pr':number,'classification':'validation','lane':'capture'}
            for number in range(3000,3334)
        }
        summary={'selectedCanonicalPRs':[3001,3135,3320],'duplicatesSuppressed':[3002,3146,3321]}

        compact_pr_classifications(graph,summary)

        migration=graph['migration']
        self.assertEqual(migration['classifiedPRTotal'],334)
        self.assertTrue(migration['classifiedPRsTruncated'])
        self.assertEqual(len(migration['classifiedPRs']),MAX_PERSISTED_PR_CLASSIFICATIONS)
        for number in summary['selectedCanonicalPRs']+summary['duplicatesSuppressed']:
            self.assertIn(str(number),migration['classifiedPRs'])
        sc.validate_graph(graph)

    def test_global_data_only_map_limit_remains_strict(self):
        with self.assertRaises(sc.ValidationError):
            sc.validate_data_only({str(index):index for index in range(129)})

    def test_small_classification_set_is_preserved_exactly(self):
        graph=sc.seed_nembra_graph()
        original={'1':{'pr':1},'2':{'pr':2}}
        graph['migration']['classifiedPRs']=dict(original)

        compact_pr_classifications(graph,{'selectedCanonicalPRs':[1],'duplicatesSuppressed':[]})

        self.assertEqual(graph['migration']['classifiedPRs'],original)
        self.assertEqual(graph['migration']['classifiedPRTotal'],2)
        self.assertFalse(graph['migration']['classifiedPRsTruncated'])


if __name__=='__main__': unittest.main()
