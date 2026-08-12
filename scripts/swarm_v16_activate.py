#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc
from swarm_v16_dogfood import ingest_live, self_integration_proof


def activate(repo: str, token: str, state_branch: str, *, main_sha: str = '') -> dict:
    state_store=sc.GitHubContentsStore(repo,token,state_branch)
    service=sc.v16_graph_service(state_store)
    current,_=service.ensure(sc.seed_nembra_graph())
    if current.get('migration',{}).get('phase')=='ACTIVE' and current.get('migration',{}).get('legacyImported'):
        return {'activated':False,'idempotent':True,'reason':'V16 already ACTIVE','revision':current['revision'],'health':sc.health_report(current,workers=30)}

    candidate,summary=ingest_live(repo,token,state_branch)
    summary['selfIntegrationProof']=self_integration_proof(candidate)
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
