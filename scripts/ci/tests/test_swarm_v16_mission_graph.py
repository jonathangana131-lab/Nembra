#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
import sys
import threading
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc

NOW=dt.datetime(2026,8,12,8,0,tzinfo=dt.timezone.utc)
def worker(i:int)->str: return f'sol-20260812-v16{i:02d}'

class SchemaTests(unittest.TestCase):
    def test_seed_valid(self):
        graph=sc.seed_nembra_graph(NOW); self.assertEqual(graph['schemaVersion'],16); self.assertIn('capture-stationary',graph['missions']); self.assertIn('dashboard',graph['objectives']); self.assertIn('capture-auth-observation',graph['objectives'])
    def test_genome_dimensions_are_explicit(self):
        graph=sc.seed_nembra_graph(NOW)
        for objective in graph['objectives'].values(): self.assertEqual(set(objective['featureGenome']),set(sc.GENOME_DIMENSIONS))
    def test_definition_of_done_is_required(self):
        graph=sc.seed_nembra_graph(NOW); graph['objectives']['dashboard'].pop('finishConditions')
        with self.assertRaises(sc.ValidationError): sc.validate_graph(graph)
    def test_dependency_cycle_fails_closed(self):
        graph=sc.seed_nembra_graph(NOW); graph['objectives']['capture-standalone-build']['dependencies']=['capture-apple-auth']
        with self.assertRaises(sc.ValidationError): sc.validate_graph(graph)
    def test_capture_contract_forbids_commands(self):
        graph=sc.seed_nembra_graph(NOW)
        for oid in graph['missions']['capture-stationary']['objectiveIds']: self.assertIn('scooter commands',graph['objectives'][oid]['forbiddenAreas'])

class DuplicateTests(unittest.TestCase):
    def setUp(self):
        self.graph=sc.seed_nembra_graph(NOW); sc.add_blocker(self.graph,blocker_id='auth-sdk-signature',mission_id='capture-stationary',objective_id='capture-tuya-auth',symptom='Tuya SDK signature mismatch',severity='P0',exit_condition='compiler and auth acceptance green',legitimate_new=False,now=NOW)
    def test_same_blocker_suppressed(self):
        sc.add_work_item(self.graph,work_item_id='auth-1',mission_id='capture-stationary',objective_id='capture-tuya-auth',blocker_id='auth-sdk-signature',title='Repair Tuya SDK signature',outcome='close official auth compiler blocker',branch='mission/capture-stationary',now=NOW)
        _,decision=sc.add_work_item(self.graph,work_item_id='auth-2',mission_id='capture-stationary',objective_id='capture-tuya-auth',blocker_id='auth-sdk-signature',title='Fix Tuya auth SDK signature mismatch',outcome='make official auth compiler green',branch='agent/duplicate',now=NOW)
        self.assertTrue(decision.duplicate); self.assertNotIn('auth-2',self.graph['workItems']); self.assertGreaterEqual(self.graph['metrics']['duplicateTasksPrevented']+self.graph['metrics']['branchForksPrevented'],1)
    def test_semantic_ax5_duplicate_suppressed(self):
        sc.add_work_item(self.graph,work_item_id='dash-a',mission_id='nembra-shipping',objective_id='dashboard',title='Keep retained dashboard currentness untruncated at AX5',outcome='make retained dashboard state readable under accessibility text sizing',now=NOW)
        _,decision=sc.add_work_item(self.graph,work_item_id='dash-b',mission_id='nembra-shipping',objective_id='dashboard',title='Fix AX5 retained Dashboard truncation',outcome='retained state remains readable with accessibility text sizes',now=NOW)
        self.assertTrue(decision.duplicate)
    def test_done_work_does_not_hide_regression(self):
        sc.add_work_item(self.graph,work_item_id='dash-a',mission_id='nembra-shipping',objective_id='dashboard',title='Fix dashboard AX5',outcome='accept AX5',now=NOW); self.graph['workItems']['dash-a']['status']='DONE'
        _,decision=sc.add_work_item(self.graph,work_item_id='dash-regression',mission_id='nembra-shipping',objective_id='dashboard',title='Fix dashboard AX5 regression',outcome='restore AX5 acceptance',now=NOW); self.assertFalse(decision.duplicate)
    def test_tournament_is_bounded_intentional_duplication(self):
        sc.authorize_tournament(self.graph,'auth-tournament','auth-sdk-signature',2,NOW)
        for i in range(2): sc.add_work_item(self.graph,work_item_id=f'candidate-{i}',mission_id='capture-stationary',objective_id='capture-tuya-auth',blocker_id='auth-sdk-signature',title='Auth architecture alternative',outcome=f'independent candidate {i}',branch=f'experimental/auth-{i}',tournament_id='auth-tournament',allow_duplicate=True,now=NOW)
        sc.select_tournament_winner(self.graph,'auth-tournament','candidate-1',{'correctness':'best','integrationCost':'lowest'},NOW); self.assertEqual(self.graph['workItems']['candidate-0']['status'],'SUPERSEDED'); self.assertEqual(self.graph['branches']['experimental/auth-0']['state'],'SUPERSEDED'); self.assertEqual(self.graph['workItems']['candidate-1']['branchState'],'SELECTED')
    def test_unauthorized_tournament_rejected(self):
        with self.assertRaises(sc.ValidationError): sc.add_work_item(self.graph,work_item_id='bad',mission_id='capture-stationary',objective_id='capture-tuya-auth',blocker_id='auth-sdk-signature',title='Alt',outcome='alt',tournament_id='missing',allow_duplicate=True,now=NOW)

class ClaimRaceTests(unittest.TestCase):
    def setUp(self):
        self.graph=sc.seed_nembra_graph(NOW); sc.add_work_item(self.graph,work_item_id='target',mission_id='nembra-shipping',objective_id='dashboard',title='Dashboard closure',outcome='finish dashboard shipping repair',branch='mission/dashboard',now=NOW); self.item=self.graph['workItems']['target']
    def test_30_simultaneous_claims_one_winner(self):
        store=sc.MemoryStore(); barrier=threading.Barrier(30); wins=[]; lock=threading.Lock()
        def run(i):
            barrier.wait()
            try: sc.claim_work_item(store,self.item,worker(i),NOW)
            except sc.ConflictError: return
            with lock: wins.append(i)
        threads=[threading.Thread(target=run,args=(i,)) for i in range(30)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertEqual(len(wins),1)
    def test_stale_owner_takeover_preserves_branch(self):
        store=sc.MemoryStore(); first=sc.claim_work_item(store,self.item,worker(0),NOW).value; later=NOW+dt.timedelta(seconds=first['leaseSeconds']+1); second=sc.takeover_work_claim(store,self.item,worker(1),later).value; self.assertEqual(second['generation'],2); self.assertEqual(second['salvageBranch'],'mission/dashboard')
    def test_old_owner_rejected_after_takeover(self):
        store=sc.MemoryStore(); first=sc.claim_work_item(store,self.item,worker(0),NOW).value; later=NOW+dt.timedelta(seconds=first['leaseSeconds']+1); sc.takeover_work_claim(store,self.item,worker(1),later)
        with self.assertRaises(sc.ConflictError): sc.heartbeat_work_claim(store,'target',worker(0),first['leaseId'],1,later)
    def test_live_claim_blocks_takeover(self):
        store=sc.MemoryStore(); sc.claim_work_item(store,self.item,worker(0),NOW)
        with self.assertRaises(sc.ConflictError): sc.takeover_work_claim(store,self.item,worker(1),NOW+dt.timedelta(seconds=10))

class ConvergenceTests(unittest.TestCase):
    def setUp(self):
        self.graph=sc.seed_nembra_graph(NOW); sc.add_blocker(self.graph,blocker_id='capture-principal-retirement',mission_id='capture-stationary',objective_id='capture-signed-build',symptom='ephemeral build principal retirement not mechanically proven',severity='P0',exit_condition='successful promotion fails closed unless principal absence is proven',legitimate_new=False,now=NOW)
    def test_blocker_owner_is_exclusive(self):
        sc.claim_blocker(self.graph,'capture-principal-retirement',worker(1),worker(2),NOW); self.assertEqual(self.graph['blockers']['capture-principal-retirement']['owner'],worker(1))
        with self.assertRaises(sc.ConflictError): sc.claim_blocker(self.graph,'capture-principal-retirement',worker(3),now=NOW)
    def test_convergence_and_rabbit_hole(self):
        sc.record_blocker_attempt(self.graph,'capture-principal-retirement',worker=worker(0),approach='successor 0',result='same blocker',branch='validation/0',meaningful_progress=False,now=NOW)
        sc.record_blocker_attempt(self.graph,'capture-principal-retirement',worker=worker(1),approach='successor 1',result='same blocker',branch='validation/1',meaningful_progress=False,now=NOW)
        sc.record_blocker_attempt(self.graph,'capture-principal-retirement',worker=worker(2),approach='reinspect existing branch',result='same blocker',branch='validation/1',meaningful_progress=False,now=NOW)
        self.assertTrue(self.graph['modes']['convergenceFamilies']); self.assertTrue(sc.rabbit_hole_review_required(self.graph,'capture-principal-retirement')[0])
        with self.assertRaises(sc.ConflictError): sc.record_blocker_attempt(self.graph,'capture-principal-retirement',worker=worker(3),approach='third branch',result='same blocker',branch='validation/2',meaningful_progress=False,now=NOW)
    def test_fake_green_cannot_resolve_blocker(self):
        with self.assertRaises(sc.ValidationError): sc.resolve_blocker(self.graph,'capture-principal-retirement',evidence_ids=[],resolution='green',now=NOW)
    def test_evidence_closes_blocker(self):
        sc.resolve_blocker(self.graph,'capture-principal-retirement',evidence_ids=['review-1'],resolution='principal absence proven',now=NOW); self.assertEqual(self.graph['blockers']['capture-principal-retirement']['state'],'RESOLVED'); self.assertEqual(self.graph['metrics']['closedBlockers'],1)

class SchedulerTests(unittest.TestCase):
    def test_capture_release_work_outranks_polish(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_work_item(graph,work_item_id='polish',mission_id='nembra-shipping',objective_id='premium-ui',title='Polish',outcome='small polish',now=NOW); sc.add_work_item(graph,work_item_id='capture',mission_id='capture-stationary',objective_id='capture-standalone-build',title='Capture blocker',outcome='standalone build accepted',now=NOW); self.assertEqual(sc.recommend_mission_packets(graph,limit=2,now=NOW)[0].work_item_id,'capture')
    def test_dependency_blocks_downstream(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_work_item(graph,work_item_id='apple',mission_id='capture-stationary',objective_id='capture-apple-auth',title='Apple auth',outcome='auth accepted',now=NOW); self.assertEqual(sc.recommend_mission_packets(graph,limit=2,now=NOW),[])
    def test_dynamic_role_allocation(self):
        graph=sc.seed_nembra_graph(NOW); allocation=sc.role_allocation(graph,30); self.assertEqual(sum(allocation.values()),30); self.assertGreaterEqual(allocation['builder'],17)
        for i in range(8): sc.add_work_item(graph,work_item_id=f'int-{i}',mission_id='nembra-shipping',objective_id='dashboard',title=f'integration {i}',outcome=f'integrate shard {i}',role='integrator',allow_duplicate=True,now=NOW); graph['workItems'][f'int-{i}']['status']='INTEGRATING'
        self.assertGreaterEqual(sc.role_allocation(graph,30)['integrator'],8)
    def test_mission_packet_carries_scope_and_memory(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_work_item(graph,work_item_id='dash',mission_id='nembra-shipping',objective_id='dashboard',title='Dashboard',outcome='close dashboard',primary_scope=['Dashboard SwiftUI'],allowed_adjacent_scope=['Dashboard tests'],forbidden_areas=['BLE'],now=NOW); packet=sc.recommend_mission_packets(graph,limit=1,now=NOW)[0].packet; self.assertEqual(packet['PRIMARY_SCOPE'],['Dashboard SwiftUI']); self.assertEqual(packet['FORBIDDEN_AREAS'],['BLE']); self.assertIn('DO_NOT_REDISCOVER',packet); self.assertEqual(packet['CONVERGENCE_POLICY'],'16.1')
    def test_surge_concentrates_priority(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_work_item(graph,work_item_id='dash',mission_id='nembra-shipping',objective_id='dashboard',title='Dashboard',outcome='close dashboard',now=NOW); sc.add_work_item(graph,work_item_id='cap',mission_id='capture-stationary',objective_id='capture-standalone-build',title='Capture',outcome='close capture',now=NOW); sc.enter_surge(graph,'capture-stationary',NOW); self.assertEqual(sc.recommend_mission_packets(graph,limit=2,now=NOW)[0].mission_id,'capture-stationary')

class MergeAndEvidenceTests(unittest.TestCase):
    def test_merge_train_repairs_failure_and_promotes_success(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_work_item(graph,work_item_id='dash',mission_id='nembra-shipping',objective_id='dashboard',title='Dashboard closure',outcome='shipping dashboard accepted',branch='mission/dashboard',now=NOW); graph['workItems']['dash']['status']='REVIEW'; sc.enqueue_merge(graph,work_item_ids=['dash'],candidate_id='train-1',required_suites=['dashboard'],now=NOW); sc.start_merge_candidate(graph,'train-1',NOW); sc.finish_merge_candidate(graph,'train-1',results={'dashboard':False},integrated=False,now=NOW); self.assertEqual(graph['workItems']['dash']['status'],'INTEGRATING')
        sc.enqueue_merge(graph,work_item_ids=['dash'],candidate_id='train-2',required_suites=['dashboard'],now=NOW); sc.start_merge_candidate(graph,'train-2',NOW); sc.finish_merge_candidate(graph,'train-2',results={'dashboard':True},integrated=True,now=NOW); self.assertEqual(graph['workItems']['dash']['integrationWorld'],'MAIN'); self.assertEqual(graph['branches']['mission/dashboard']['state'],'INTEGRATED')
    def test_only_one_merge_is_active(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_work_item(graph,work_item_id='dash',mission_id='nembra-shipping',objective_id='dashboard',title='Dashboard',outcome='accepted',now=NOW); graph['workItems']['dash']['status']='REVIEW'; sc.enqueue_merge(graph,work_item_ids=['dash'],candidate_id='train',required_suites=['ui'],now=NOW); sc.start_merge_candidate(graph,'train',NOW)
        with self.assertRaises(sc.ConflictError): sc.start_merge_candidate(graph,'train',NOW)
    def test_test_impact_does_not_run_unrelated_capture_suite(self):
        suites=sc.test_impact(['NembraApp/Features/Dashboard/DashboardView.swift']); self.assertIn('dashboard-ui',suites); self.assertIn('accessibility',suites); self.assertNotIn('capture-truth',suites)
    def test_evidence_binding_reuse_and_invalidation(self):
        graph=sc.seed_nembra_graph(NOW); sd,dd,ed=sc.evidence_binding({'Dashboard.swift':'1'},{'core':'2'},{'xcode':'27'}); sc.add_evidence(graph,evidence_id='e1',objective_id='dashboard',evidence_type='ui',status='PASS',truth_class='SIMULATED',source_digest=sd,dependency_digest=dd,environment_digest=ed,affected_paths=['NembraApp/Features/Dashboard'],now=NOW); self.assertTrue(sc.reusable_evidence(graph,'e1',source_digest=sd,dependency_digest=dd,environment_digest=ed)); self.assertEqual(sc.invalidate_evidence_for_paths(graph,['NembraApp/Features/Dashboard/DashboardView.swift'],'source moved',NOW),['e1']); self.assertFalse(sc.reusable_evidence(graph,'e1',source_digest=sd,dependency_digest=dd,environment_digest=ed))
    def test_command_truth_requires_explicit_physical_authority(self):
        graph=sc.seed_nembra_graph(NOW)
        with self.assertRaises(sc.ValidationError): sc.add_evidence(graph,evidence_id='bad',objective_id='capture-auth-observation',evidence_type='command',status='PASS',truth_class='COMMAND_VERIFIED',source_digest='a',dependency_digest='b',environment_digest='c',affected_paths=[],details={},now=NOW)
    def test_authenticated_is_not_physical_truth(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_evidence(graph,evidence_id='auth',objective_id='capture-auth-observation',evidence_type='tuya',status='PASS',truth_class='AUTHENTICATED',source_digest='a',dependency_digest='b',environment_digest='c',affected_paths=['Capture'],details={'readOnly':True},now=NOW); self.assertNotEqual(graph['objectives']['capture-auth-observation']['featureGenome']['physicalTruth']['state'],'ACCEPTED')

class MigrationHealthGoTests(unittest.TestCase):
    def legacy(self): return {'schemaVersion':1,'kind':'lane','laneId':'capture-signed-install-custody','epic':'capture','title':'Capture signed-app install custody','objective':'close intended-device install custody','priority':1,'state':'NEEDS_CHANGES','dependencies':[],'blockers':[{'id':'principal-retirement','state':'ACTIVE','scope':'lane','reason':'retirement unchecked','pr':3142,'headSHA':'abc'},{'id':'uid-validation','state':'RESOLVED','scope':'validation','reason':'accepted proof','pr':3131,'headSHA':'def'}],'allowedWriteAreas':['scripts/field/install_one_time_capture.command'],'adjacentWriteAreas':['scripts/ci/tests'],'slots':[],'physical':{'required':True,'state':'PHYSICAL_NO_GO'},'tags':['capture','p0']}
    def test_legacy_migration_preserves_physical_no_go(self):
        graph=sc.seed_nembra_graph(NOW); sc.migrate_legacy_lane(graph,self.legacy(),NOW); objective=graph['objectives']['legacy-capture-signed-install-custody']; self.assertEqual(graph['blockers']['principal-retirement']['state'],'OPEN'); self.assertEqual(graph['blockers']['uid-validation']['state'],'RESOLVED'); self.assertEqual(objective['featureGenome']['physicalTruth']['state'],'BLOCKED')
    def test_validation_pr_never_becomes_product_candidate(self):
        pr={'number':3146,'title':'[Capture P0][VALIDATION] Freeze selected Xcode','body':'SWARM_LANE: capture-build-authority\nVALIDATION ONLY / DO NOT MERGE AS PRODUCT'}; result=sc.classify_pr(pr); self.assertEqual(result['classification'],'validation'); self.assertFalse(result['destructiveActionAllowed'])
    def test_security_product_can_be_candidate_but_not_auto_destructive(self):
        pr={'number':3142,'title':'[Capture P0][SECURITY] Compose dedicated-UID APFS freeze','body':'SWARM_LANE: capture-signed-install-custody\nEXACT CURRENT HEAD: `abc1234`'}; result=sc.classify_pr(pr); self.assertEqual(result['classification'],'canonical-candidate'); self.assertFalse(result['destructiveActionAllowed'])
    def test_go_hands_off_then_requests_next(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_work_item(graph,work_item_id='first',mission_id='nembra-shipping',objective_id='dashboard',title='First',outcome='coherent mission',now=NOW); result=sc.go_cycle(graph,worker(0),completed_work_item_id='first',evidence_ids=['e1'],now=NOW); self.assertEqual(graph['workItems']['first']['status'],'REVIEW'); self.assertIn(result['status'],{'WORK','IDLE'})
    def test_go_cannot_finish_without_evidence(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_work_item(graph,work_item_id='first',mission_id='nembra-shipping',objective_id='dashboard',title='First',outcome='mission',now=NOW)
        with self.assertRaises(sc.ValidationError): sc.go_cycle(graph,worker(0),completed_work_item_id='first',evidence_ids=[],now=NOW)
    def test_complexity_and_momentum_penalize_churn(self):
        review=sc.complexity_review(production_loc=4000,test_loc=20000,workflow_count=40,branch_count=30,validation_count=40,duplicate_checks=12,integration_overhead=15); self.assertTrue(review['reviewRequired']); self.assertGreaterEqual(len(review['flags']),4); self.assertLess(sc.momentum_score(meaningful_code=1,blockers_removed=0,dependencies_unlocked=0,acceptance_gained=0,integration_gained=0,user_visible_improvement=0,regressions=0,duplicate_work=5),0)
    def test_user_status_is_plain_product_language(self):
        graph=sc.seed_nembra_graph(NOW); sc.add_work_item(graph,work_item_id='dash',mission_id='nembra-shipping',objective_id='dashboard',title='Dashboard',outcome='finish',now=NOW); text=sc.user_status(graph,workers=30,now=NOW); self.assertIn('NEMBRA SWARM',text); self.assertIn('Dashboard',text); self.assertIn('Milestones destroyed',text)

class StoreAndSimulationTests(unittest.TestCase):
    def test_cas_graph_store(self):
        store=sc.MemoryStore(); service=sc.MissionGraphStore(store); graph,_=service.ensure(sc.seed_nembra_graph(NOW)); self.assertEqual(graph['revision'],0); updated,_=service.mutate(lambda g:g['metrics'].update({'meaningfulProgressEvents':4}),now=NOW); self.assertEqual(updated['revision'],1); self.assertEqual(updated['metrics']['meaningfulProgressEvents'],4)
    def test_full_30_worker_adversarial_simulation(self):
        result=sc.run_v16_adversarial_simulation(30,NOW); self.assertTrue(result['passed'],json.dumps(result,indent=2)); self.assertGreaterEqual(len(result['checks']),14)

if __name__=='__main__': unittest.main()
