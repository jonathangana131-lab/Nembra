#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc

NOW=dt.datetime(2026,8,12,9,0,tzinfo=dt.timezone.utc)

class LegacyPriorityRealityTests(unittest.TestCase):
    def lane(self, priority):
        return {'schemaVersion':1,'kind':'lane','laneId':f'legacy-priority-{str(priority).lower()}','epic':'product','title':'Legacy mixed priority','objective':'preserve useful legacy state','priority':priority,'state':'READY','dependencies':[],'blockers':[],'allowedWriteAreas':['NembraApp'],'adjacentWriteAreas':['Tests'],'slots':[],'physical':{'required':False,'state':'SOURCE_READY'},'tags':[]}
    def test_severity_priorities_normalize(self):
        self.assertEqual(sc.normalize_legacy_priority('P0'),0); self.assertEqual(sc.normalize_legacy_priority('P2'),2); self.assertEqual(sc.normalize_legacy_priority('P3'),3)
    def test_numeric_and_named_priorities_normalize(self):
        self.assertEqual(sc.normalize_legacy_priority(4),4); self.assertEqual(sc.normalize_legacy_priority('5'),5); self.assertEqual(sc.normalize_legacy_priority('high'),2)
    def test_live_style_p2_lane_migrates(self):
        graph=sc.seed_nembra_graph(NOW); sc.migrate_legacy_lane(graph,self.lane('P2'),now=NOW); self.assertEqual(graph['objectives']['legacy-legacy-priority-p2']['priority'],2)
    def test_unsupported_priority_fails_closed(self):
        with self.assertRaises(sc.ValidationError): sc.normalize_legacy_priority('whatever')

class LargeRegistryRealityTests(unittest.TestCase):
    def test_live_scale_classified_pr_registry_validates(self):
        graph=sc.seed_nembra_graph(NOW)
        graph['migration']['classifiedPRs']={
            str(number):{'pr':number,'classification':'requires-review'}
            for number in range(1,335)
        }
        validated=sc.validate_graph(graph)
        self.assertEqual(len(validated['migration']['classifiedPRs']),334)

    def test_v16_registry_ceiling_remains_bounded(self):
        graph=sc.seed_nembra_graph(NOW)
        graph['migration']['classifiedPRs']={str(number):number for number in range(sc.MAX_V16_REGISTRY_KEYS+1)}
        with self.assertRaises(sc.ValidationError):
            sc.validate_graph(graph)

    def test_non_v16_objects_keep_default_object_ceiling(self):
        payload={f'key-{number}':number for number in range(sc.MAX_DATA_OBJECT_KEYS+1)}
        with self.assertRaises(sc.ValidationError):
            sc.validate_data_only(payload)

if __name__=='__main__': unittest.main()
