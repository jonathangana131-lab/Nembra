#!/usr/bin/env python3
from __future__ import annotations

# Activation is idempotent, but an already-ACTIVE graph still needs fresh live
# PR topology. Active refreshes are deliberately non-destructive: they update
# observed PR/head metadata while preserving native V16 coordination state.
import argparse
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc
from swarm_v16_dogfood import ingest_live, self_integration_proof


# validate_data_only intentionally limits ordinary maps to 128 keys. Live PR
# classification is migration evidence, not the scheduling source of truth, so
# persist a bounded deterministic witness set instead of weakening that global
# defensive limit as repository PR count grows.
MAX_PERSISTED_PR_CLASSIFICATIONS=128
LIVE_WORK_PREFIX='live-pr-'


def compact_pr_classifications(candidate: dict, summary: dict) -> None:
    migration=candidate.setdefault('migration',{})
    classified=migration.get('classifiedPRs',{})
    if not isinstance(classified,dict):
        raise sc.ValidationError('migration.classifiedPRs must be an object')
    total=len(classified)
    migration['classifiedPRTotal']=total
    migration['classifiedPRsTruncated']=total>MAX_PERSISTED_PR_CLASSIFICATIONS
    if total<=MAX_PERSISTED_PR_CLASSIFICATIONS:
        return

    # Canonical selections and duplicate-suppression witnesses are the
    # classifications that activation must never discard. Fill the remainder
    # with newest PR numbers so recovery gets the freshest bounded snapshot.
    required=[]
    for field in ('selectedCanonicalPRs','duplicatesSuppressed'):
        for number in summary.get(field,[]):
            key=str(number)
            if key in classified and key not in required:
                required.append(key)
    newest=sorted(classified,key=lambda key:int(key),reverse=True)
    retained=(required+[key for key in newest if key not in required])[:MAX_PERSISTED_PR_CLASSIFICATIONS]
    migration['classifiedPRs']={key:classified[key] for key in retained}


def _copy_json(value):
    return json.loads(json.dumps(value))


def refresh_active_topology(existing: dict, candidate: dict, summary: dict, *, main_sha: str='') -> dict:
    """Refresh observed GitHub topology without resetting V16 coordination truth.

    The candidate is a fresh legacy/open-PR ingestion. Only migration inventory
    and selected live-PR observation metadata may move here. Work status, owner,
    reviewer, evidence, integration world, branch state, agents, memory,
    blockers, feature genomes and merge-train state stay owned by the ACTIVE
    graph. A selected PR disappearing from the open snapshot is recorded for
    reconciliation rather than being auto-closed or archived. A selected PR
    whose freshly migrated mission/objective/blocker parent is not yet present
    in the ACTIVE graph is likewise deferred for explicit topology migration;
    refresh never invents or partially copies scheduling authority.
    """
    migration=existing.get('migration',{})
    if migration.get('phase')!='ACTIVE' or not migration.get('legacyImported'):
        raise sc.ValidationError('live topology refresh requires one ACTIVE imported V16 graph')

    fresh_migration=candidate.get('migration',{})
    for field in ('classifiedPRs','classifiedPRTotal','classifiedPRsTruncated','legacyLaneIds'):
        if field in fresh_migration:
            migration[field]=_copy_json(fresh_migration[field])
    migration['liveRefreshMainSHA']=main_sha
    migration['liveRefreshAt']=candidate.get('updatedAt','')
    migration['liveRefreshSelectedCanonicalPRs']=list(summary.get('selectedCanonicalPRs',[]))
    migration['liveRefreshDuplicatesSuppressed']=list(summary.get('duplicatesSuppressed',[]))
    migration['destructiveActionsAllowed']=False

    fresh_live={wid:item for wid,item in candidate.get('workItems',{}).items() if wid.startswith(LIVE_WORK_PREFIX)}
    current_live={wid:item for wid,item in existing.get('workItems',{}).items() if wid.startswith(LIVE_WORK_PREFIX)}
    added=[]
    refreshed=[]
    deferred=[]
    head_updates=[]
    branch_mismatches=[]

    for wid,fresh in fresh_live.items():
        if wid not in current_live:
            missing_parents=[]
            mission_id=str(fresh.get('missionId') or '')
            objective_id=str(fresh.get('objectiveId') or '')
            blocker_id=str(fresh.get('blockerId') or '')
            if mission_id not in existing.get('missions',{}):
                missing_parents.append(f'mission:{mission_id}')
            if objective_id not in existing.get('objectives',{}):
                missing_parents.append(f'objective:{objective_id}')
            if blocker_id and blocker_id not in existing.get('blockers',{}):
                missing_parents.append(f'blocker:{blocker_id}')
            if missing_parents:
                deferred.append({'workItemId':wid,'missingParents':missing_parents})
                continue
            existing['workItems'][wid]=_copy_json(fresh)
            branch=fresh.get('branch','')
            if branch and branch in candidate.get('branches',{}) and branch not in existing.get('branches',{}):
                existing['branches'][branch]=_copy_json(candidate['branches'][branch])
            added.append(wid)
            continue

        current=current_live[wid]
        old_source=dict(current.get('source') or {})
        fresh_source=_copy_json(fresh.get('source') or {})
        old_head=str(old_source.get('headSHA') or '')
        new_head=str(fresh_source.get('headSHA') or '')
        if old_head!=new_head:
            head_updates.append({'workItemId':wid,'from':old_head,'to':new_head})

        # Scheduling fields are intentionally absent from this update set.
        for field in ('title','outcome','primaryScope','allowedAdjacentScope','forbiddenAreas','similarityKey'):
            current[field]=_copy_json(fresh[field])
        current['source']=fresh_source
        current['updatedAt']=candidate.get('updatedAt',fresh.get('updatedAt',current['updatedAt']))

        fresh_branch=str(fresh.get('branch') or '')
        current_branch=str(current.get('branch') or '')
        if fresh_branch and current_branch and fresh_branch!=current_branch:
            branch_mismatches.append({'workItemId':wid,'scheduledBranch':current_branch,'observedBranch':fresh_branch})
        elif fresh_branch and not current_branch:
            current['branch']=fresh_branch
            current_branch=fresh_branch

        if current_branch and current_branch in existing.get('branches',{}):
            branch_record=existing['branches'][current_branch]
            branch_record['source']=_copy_json(fresh_source)
            branch_record['pr']=fresh_source.get('pr')
        elif fresh_branch and fresh_branch in candidate.get('branches',{}):
            existing['branches'][fresh_branch]=_copy_json(candidate['branches'][fresh_branch])
        refreshed.append(wid)

    missing=sorted(wid for wid in current_live if wid not in fresh_live)
    migration['livePRsMissingFromLatestOpenSnapshot']=missing
    migration['livePRBranchMismatches']=branch_mismatches
    migration['livePRHeadUpdates']=head_updates
    migration['livePRWorkItemsAdded']=added
    migration['livePRWorkItemsDeferred']=deferred
    return {
        'refreshedWorkItems':sorted(refreshed),
        'addedWorkItems':sorted(added),
        'deferredWorkItems':deferred,
        'missingOpenWorkItems':missing,
        'headUpdates':head_updates,
        'branchMismatches':branch_mismatches,
    }


def activate(repo: str, token: str, state_branch: str, *, main_sha: str = '') -> dict:
    state_store=sc.GitHubContentsStore(repo,token,state_branch)
    service=sc.v16_graph_service(state_store)
    current,_=service.ensure(sc.seed_nembra_graph())
    if current.get('migration',{}).get('phase')=='ACTIVE' and current.get('migration',{}).get('legacyImported'):
        candidate,summary=ingest_live(repo,token,state_branch)
        compact_pr_classifications(candidate,summary)

        def refresh(existing: dict):
            return refresh_active_topology(existing,candidate,summary,main_sha=main_sha)

        graph,result=service.mutate(
            refresh,
            message=f'swarm v16: refresh live topology from main {main_sha[:12] or "unknown"}',
        )
        return {
            'activated':False,
            'idempotent':True,
            'refreshed':True,
            'reason':'V16 already ACTIVE; refreshed live PR topology non-destructively',
            'revision':graph['revision'],
            'migration':sc.migration_summary(graph),
            'health':sc.health_report(graph,workers=30),
            'status':sc.user_status(graph,workers=30),
            'topologyRefresh':result,
        }

    candidate,summary=ingest_live(repo,token,state_branch)
    summary['selfIntegrationProof']=self_integration_proof(candidate)
    compact_pr_classifications(candidate,summary)
    sc.migration_phase(candidate,'READY_TO_ACTIVATE')
    candidate['migration']['activationMainSHA']=main_sha
    candidate['migration']['destructiveActionsAllowed']=False

    def replace(existing: dict):
        # Preserve graph identity/creation time and let MissionGraphStore assign
        # the next revision atomically. No legacy V15 files are modified.
        created=existing.get('createdAt',candidate['createdAt'])
        revision=existing.get('revision',0)
        existing.clear(); existing.update(_copy_json(candidate))
        existing['createdAt']=created
        existing['revision']=revision
        sc.migration_phase(existing,'ACTIVE')
        existing['migration']['activationMainSHA']=main_sha
        existing['migration']['destructiveActionsAllowed']=False
        return {'summary':summary,'cleanupPlan':sc.branch_cleanup_plan(existing)}

    graph,result=service.mutate(replace,message=f'swarm v16: activate Mission Graph from main {main_sha[:12] or "unknown"}')
    return {'activated':True,'idempotent':False,'refreshed':False,'revision':graph['revision'],'migration':sc.migration_summary(graph),'health':sc.health_report(graph,workers=30),'status':sc.user_status(graph,workers=30),'dogfood':result['summary'],'cleanupPlan':result['cleanupPlan']}


def main(argv=None) -> int:
    parser=argparse.ArgumentParser(description='Activate or non-destructively refresh Nembra Swarm V16 on swarm-state')
    parser.add_argument('--repo',default=os.getenv('GITHUB_REPOSITORY',''))
    parser.add_argument('--token',default=os.getenv('GITHUB_TOKEN',''))
    parser.add_argument('--state-branch',default='swarm-state')
    parser.add_argument('--main-sha',default=os.getenv('GITHUB_SHA',''))
    parser.add_argument('--output')
    args=parser.parse_args(argv)
    if not args.repo or not args.token: parser.error('--repo and --token/GITHUB_TOKEN are required')
    result=activate(args.repo,args.token,args.state_branch,main_sha=args.main_sha)
    text=json.dumps(result,indent=2,sort_keys=True)+'\n'
    if args.output: Path(args.output).write_text(text,encoding='utf-8')
    print(text,end='')
    if result.get('activated'):
        dogfood=result.get('dogfood',{})
        if not dogfood.get('selectedCanonicalPRs') or not dogfood.get('duplicatesSuppressed'): return 3
    return 0

if __name__=='__main__': raise SystemExit(main())