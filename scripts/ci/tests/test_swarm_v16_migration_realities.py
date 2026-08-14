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

if __name__=='__main__': unittest.main()
