#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc
from swarm_v16_activate import (
    MAX_PERSISTED_PR_CLASSIFICATIONS,
    compact_pr_classifications,
    refresh_active_topology,
)


def add_live_work(graph: dict, *, number: int, head: str, branch: str='repair/capture') -> None:
    sc.add_work_item(
        graph,
        work_item_id=f'live-pr-{number}',
        mission_id='capture-stationary',
        objective_id='capture-signed-build',
        title=f'Capture selected PR {number}',
        outcome='close the selected signed-build blocker',
        primary_scope=['scripts/ci/capture.py'],
        allowed_adjacent_scope=['scripts/ci/tests'],
        forbidden_areas=['physical action without explicit external PHYSICAL_GO'],
        branch=branch,
        source={
            'pr':number,
            'headSHA':head,
            'classification':'canonical-candidate',
            'selectionAuthority':'legacy-selected-production',
        },
        allow_duplicate=True,
    )


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

    def test_active_refresh_updates_head_without_resetting_coordination_state(self):
        current=sc.seed_nembra_graph()
        current['migration']['phase']='ACTIVE'
        current['migration']['legacyImported']=True
        current['migration']['destructiveActionsAllowed']=False
        add_live_work(current,number=3142,head='a'*40)
        item=current['workItems']['live-pr-3142']
        item.update({
            'status':'ACTIVE',
            'owner':'sol-20260812-owner',
            'reviewer':'sol-20260812-reviewer',
            'evidenceIds':['accepted-evidence'],
            'integrationWorld':'NEXT',
            'branchState':'SELECTED',
        })
        current['agents']['sol-20260812-owner']={'domains':{},'acceptedOutcomes':1,'integratedOutcomes':0,'regressions':0}
        current['memory'].append({'type':'TEST_MEMORY','message':'preserve me'})
        preserved_agents=dict(current['agents'])
        preserved_memory=list(current['memory'])

        candidate=sc.seed_nembra_graph()
        candidate['migration']['legacyImported']=True
        candidate['migration']['classifiedPRs']={'3142':{'pr':3142,'classification':'canonical-candidate'}}
        add_live_work(candidate,number=3142,head='b'*40)
        compact_pr_classifications(candidate,{'selectedCanonicalPRs':[3142],'duplicatesSuppressed':[]})

        result=refresh_active_topology(
            current,
            candidate,
            {'selectedCanonicalPRs':[3142],'duplicatesSuppressed':[]},
            main_sha='c'*40,
        )

        refreshed=current['workItems']['live-pr-3142']
        self.assertEqual(refreshed['source']['headSHA'],'b'*40)
        self.assertEqual(refreshed['status'],'ACTIVE')
        self.assertEqual(refreshed['owner'],'sol-20260812-owner')
        self.assertEqual(refreshed['reviewer'],'sol-20260812-reviewer')
        self.assertEqual(refreshed['evidenceIds'],['accepted-evidence'])
        self.assertEqual(refreshed['integrationWorld'],'NEXT')
        self.assertEqual(refreshed['branchState'],'SELECTED')
        self.assertEqual(current['agents'],preserved_agents)
        self.assertEqual(current['memory'],preserved_memory)
        self.assertEqual(current['migration']['phase'],'ACTIVE')
        self.assertFalse(current['migration']['destructiveActionsAllowed'])
        self.assertEqual(current['migration']['liveRefreshMainSHA'],'c'*40)
        self.assertEqual(result['headUpdates'],[{'workItemId':'live-pr-3142','from':'a'*40,'to':'b'*40}])
        sc.validate_graph(current)

    def test_active_refresh_records_missing_open_pr_without_archiving_it(self):
        current=sc.seed_nembra_graph()
        current['migration']['phase']='ACTIVE'
        current['migration']['legacyImported']=True
        add_live_work(current,number=3142,head='a'*40)
        current['workItems']['live-pr-3142']['status']='ACTIVE'
        current['workItems']['live-pr-3142']['owner']='sol-20260812-owner'

        candidate=sc.seed_nembra_graph()
        candidate['migration']['legacyImported']=True
        compact_pr_classifications(candidate,{'selectedCanonicalPRs':[],'duplicatesSuppressed':[]})

        result=refresh_active_topology(
            current,
            candidate,
            {'selectedCanonicalPRs':[],'duplicatesSuppressed':[]},
            main_sha='d'*40,
        )

        item=current['workItems']['live-pr-3142']
        self.assertEqual(item['status'],'ACTIVE')
        self.assertEqual(item['owner'],'sol-20260812-owner')
        self.assertEqual(current['migration']['livePRsMissingFromLatestOpenSnapshot'],['live-pr-3142'])
        self.assertEqual(result['missingOpenWorkItems'],['live-pr-3142'])
        self.assertNotIn('live-pr-3142',result['addedWorkItems'])
        sc.validate_graph(current)

    def test_active_refresh_does_not_retarget_a_scheduled_branch_implicitly(self):
        current=sc.seed_nembra_graph()
        current['migration']['phase']='ACTIVE'
        current['migration']['legacyImported']=True
        add_live_work(current,number=3142,head='a'*40,branch='repair/original')
        current['workItems']['live-pr-3142']['status']='ACTIVE'

        candidate=sc.seed_nembra_graph()
        candidate['migration']['legacyImported']=True
        add_live_work(candidate,number=3142,head='b'*40,branch='repair/renamed')
        compact_pr_classifications(candidate,{'selectedCanonicalPRs':[3142],'duplicatesSuppressed':[]})

        result=refresh_active_topology(
            current,
            candidate,
            {'selectedCanonicalPRs':[3142],'duplicatesSuppressed':[]},
        )

        self.assertEqual(current['workItems']['live-pr-3142']['branch'],'repair/original')
        self.assertEqual(result['branchMismatches'],[
            {
                'workItemId':'live-pr-3142',
                'scheduledBranch':'repair/original',
                'observedBranch':'repair/renamed',
            }
        ])
        sc.validate_graph(current)

    def test_active_refresh_defers_new_work_when_scheduling_parents_are_unknown(self):
        current=sc.seed_nembra_graph()
        current['migration']['phase']='ACTIVE'
        current['migration']['legacyImported']=True

        candidate=sc.seed_nembra_graph()
        candidate['migration']['legacyImported']=True
        add_live_work(candidate,number=3999,head='e'*40,branch='repair/new-legacy-lane')
        candidate['workItems']['live-pr-3999']['objectiveId']='legacy-new-objective'
        candidate['workItems']['live-pr-3999']['blockerId']='legacy-new-blocker'
        compact_pr_classifications(candidate,{'selectedCanonicalPRs':[3999],'duplicatesSuppressed':[]})

        result=refresh_active_topology(
            current,
            candidate,
            {'selectedCanonicalPRs':[3999],'duplicatesSuppressed':[]},
        )

        self.assertNotIn('live-pr-3999',current['workItems'])
        self.assertEqual(result['deferredWorkItems'],[
            {
                'workItemId':'live-pr-3999',
                'missingParents':['objective:legacy-new-objective','blocker:legacy-new-blocker'],
            }
        ])
        self.assertEqual(current['migration']['livePRWorkItemsDeferred'],result['deferredWorkItems'])
        sc.validate_graph(current)


if __name__=='__main__': unittest.main()