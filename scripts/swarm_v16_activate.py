#!/usr/bin/env python3
from __future__ import annotations

# This entrypoint is intentionally idempotent: once the workflow is registered
# on main, any accepted V16-path push may safely re-run activation/recovery.
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


def activate(repo: str, token: str, state_branch: str, *, main_sha: str = '') -> dict:
    state_store=sc.GitHubContentsStore(repo,token,state_branch)
    service=sc.v16_graph_service(state_store)
    current,_=service.ensure(sc.seed_nembra_graph())
    if current.get('migration',{}).get('phase')=='ACTIVE' and current.get('migration',{}).get('legacyImported'):
        return {'activated':False,'idempotent':True,'reason':'V16 already ACTIVE','revision':current['revision'],'health':sc.health_report(current,workers=30)}

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
        existing.clear(); existing.update(json.loads(json.dumps(candidate)))
        existing['createdAt']=created
        existing['revision']=revision
        sc.migration_phase(existing,'ACTIVE')
        existing['migration']['activationMainSHA']=main_sha
        existing['migration']['destructiveActionsAllowed']=False
        return {'summary':summary,'cleanupPlan':sc.branch_cleanup_plan(existing)}

    graph,result=service.mutate(replace,message=f'swarm v16: activate Mission Graph from main {main_sha[:12] or "unknown"}')
    return {'activated':True,'idempotent':False,'revision':graph['revision'],'migration':sc.migration_summary(graph),'health':sc.health_report(graph,workers=30),'status':sc.user_status(graph,workers=30),'dogfood':result['summary'],'cleanupPlan':result['cleanupPlan']}


def main(argv=None) -> int:
    parser=argparse.ArgumentParser(description='Activate Nembra Swarm V16 on swarm-state after accepted main integration')
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
