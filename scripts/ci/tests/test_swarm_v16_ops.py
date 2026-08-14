#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
from pathlib import Path
import sys
import threading
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc

NOW=dt.datetime(2026,8,12,9,0,tzinfo=dt.timezone.utc)
def worker(i:int)->str: return f'sol-20260812-ops{i:02d}'

class CaptainAndKitTests(unittest.TestCase):
    def test_captain_assignment_covers_mission(self):
        graph=sc.seed_nembra_graph(NOW); sc.assign_captain(graph,'capture-stationary',worker(0),now=NOW)
        self.assertEqual(graph['missions']['capture-stationary']['captain'],worker(0))
        self.assertTrue(all(graph['objectives'][oid]['captain']==worker(0) for oid in graph['missions']['capture-stationary']['objectiveIds']))
    def test_captain_recovery_is_not_deadlock(self):
        graph=sc.seed_nembra_graph(NOW); sc.assign_captain(graph,'capture-stationary',worker(0),now=NOW); sc.replace_failed_captain(graph,'capture-stationary',worker(1),reason='heartbeat stale',now=NOW); self.assertEqual(graph['missions']['capture-stationary']['captain'],worker(1))
    def test_every_test_kit_primitive_exists(self):
        expected={'SourceCustody','BuildIdentity','SignedBuildIdentity','SimulatorIdentity','DeviceIdentity','PrivateInputCustody','InstallationCustody','AccessibilityAcceptance','VisualEvidence','PerformanceEvidence','TelemetryTruth','PhysicalTruth','IntegrationTruth'}; self.assertEqual(set(sc.NEMBRA_TEST_KIT),expected)
    def test_authenticated_telemetry_does_not_accept_physical_truth(self):
        graph=sc.seed_nembra_graph(NOW); sc.record_test_kit_evidence(graph,primitive='TelemetryTruth',evidence_id='telemetry-auth',objective_id='capture-auth-observation',status='PASS',source_digest='s',dependency_digest='d',environment_digest='e',affected_paths=['Capture'],details={'readOnly':True},now=NOW); self.assertNotEqual(graph['objectives']['capture-auth-observation']['featureGenome']['physicalTruth']['state'],'ACCEPTED')
    def test_physical_truth_requires_explicit_authority(self):
        graph=sc.seed_nembra_graph(NOW)
        with self.assertRaises(sc.ValidationError): sc.record_test_kit_evidence(graph,primitive='PhysicalTruth',evidence_id='physical',objective_id='capture-auth-observation',status='PASS',source_digest='s',dependency_digest='d',environment_digest='e',affected_paths=['Capture'],details={},now=NOW)
        sc.record_test_kit_evidence(graph,primitive='PhysicalTruth',evidence_id='physical-ok',objective_id='capture-auth-observation',status='PASS',source_digest='s',dependency_digest='d',environment_digest='e',affected_paths=['Capture'],details={'physicalAuthorityExplicit':True},now=NOW); self.assertEqual(graph['objectives']['capture-auth-observation']['featureGenome']['physicalTruth']['state'],'ACCEPTED')
    def test_accessibility_primitive_updates_only_accessibility(self):
        graph=sc.seed_nembra_graph(NOW); sc.record_test_kit_evidence(graph,primitive='AccessibilityAcceptance',evidence_id='ax',objective_id='dashboard',status='PASS',source_digest='s',dependency_digest='d',environment_digest='e',affected_paths=['Dashboard'],now=NOW); self.assertEqual(graph['objectives']['dashboard']['featureGenome']['accessibility']['state'],'ACCEPTED'); self.assertEqual(graph['objectives']['dashboard']['featureGenome']['functionality']['state'],'NOT_STARTED')

class CanonicalAndSpecializationTests(unittest.TestCase):
    def test_explicit_legacy_selection_beats_branch_name(self):
        graph=sc.seed_nembra_graph(NOW); graph['branches']['aaa-experiment']={'branch':'aaa-experiment','missionId':'nembra-shipping','objectiveId':'dashboard','state':'SELECTED','world':'FRONTIER','selectedAt':sc.format_v16_time(NOW),'integratedAt':'','pr':1,'source':{'acceptedEvidenceCount':9}}
        graph['branches']['zzz-canonical']={'branch':'zzz-canonical','missionId':'nembra-shipping','objectiveId':'dashboard','state':'SELECTED','world':'FRONTIER','selectedAt':sc.format_v16_time(NOW),'integratedAt':'','pr':2,'source':{'selectionAuthority':'legacy-selected-production'}}
        result=sc.reconcile_canonical_branches(graph,now=NOW); self.assertIn('aaa-experiment',result['superseded']); self.assertEqual(graph['branches']['zzz-canonical']['state'],'SELECTED')
    def test_cleanup_is_non_destructive_until_activation(self):
        graph=sc.seed_nembra_graph(NOW); graph['branches']['old']={'branch':'old','missionId':'nembra-shipping','objectiveId':'dashboard','state':'ARCHIVED','world':'EXPERIMENTAL','selectedAt':'','integratedAt':'','pr':1,'source':{}}; plan=sc.branch_cleanup_plan(graph); self.assertFalse(plan[0]['remoteDeleteAllowed']); sc.migration_phase(graph,'ACTIVE',now=NOW); graph['migration']['destructiveActionsAllowed']=True; self.assertTrue(sc.branch_cleanup_plan(graph)[0]['remoteDeleteAllowed'])
    def test_specialization_prefers_accepted_outcomes(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_work_item(graph,work_item_id='dash',mission_id='nembra-shipping',objective_id='dashboard',title='Dashboard',outcome='ship dashboard',now=NOW); sc.update_agent_outcome(graph,worker(1),domain='SwiftUI',accepted=True,integrated=True); assigned=sc.assign_specialized_workers(graph,['dash'],[worker(0),worker(1)]); self.assertEqual(assigned['dash'],worker(1))
    def test_surge_allocation_uses_all_30_workers(self):
        allocation=sc.surge_role_allocation(30); self.assertEqual(sum(allocation.values()),30); self.assertEqual(allocation['captain'],1); self.assertGreaterEqual(allocation['implementation'],9); self.assertGreaterEqual(allocation['review/testing'],5)
    def test_red_team_physical_objective_tests_authority(self):
        graph=sc.seed_nembra_graph(NOW); plan=sc.red_team_acceptance_plan(graph,'capture-auth-observation'); self.assertIn('authenticated is not physical mapping',plan['truth']); self.assertIn('no command authority without physical evidence',plan['truth'])

class ContentionTests(unittest.TestCase):
    def test_30_structural_writers_converge_with_cas(self):
        store=sc.MemoryStore(); service=sc.v16_graph_service(store); service.ensure(sc.seed_nembra_graph(NOW)); barrier=threading.Barrier(30); failures=[]
        def run(i:int):
            try:
                barrier.wait()
                service.mutate(lambda g:g['agents'].update({worker(i):{'domains':{},'acceptedOutcomes':0,'integratedOutcomes':0,'regressions':0}}),now=NOW,message=f'writer {i}')
            except Exception as exc:
                failures.append(repr(exc))
        threads=[threading.Thread(target=run,args=(i,)) for i in range(30)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertEqual(failures,[])
        graph,_=service.load(); self.assertEqual(len([k for k in graph['agents'] if k.startswith('sol-20260812-ops')]),30); self.assertEqual(graph['revision'],30)
    def test_migration_phase_fails_closed_for_destructive_actions(self):
        graph=sc.seed_nembra_graph(NOW); graph['migration']['destructiveActionsAllowed']=True; sc.migration_phase(graph,'DOGFOOD',now=NOW); self.assertFalse(graph['migration']['destructiveActionsAllowed'])

if __name__=='__main__': unittest.main()
