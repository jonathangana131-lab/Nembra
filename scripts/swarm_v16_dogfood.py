#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import urllib.parse
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc


def fetch_open_prs(repo: str, token: str) -> list[dict]:
    owner,name=repo.split('/',1); results=[]; page=1
    while page<=4:
        query=urllib.parse.urlencode({'state':'open','per_page':100,'page':page})
        request=urllib.request.Request(f'https://api.github.com/repos/{owner}/{name}/pulls?{query}',headers={'Authorization':f'Bearer {token}','Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','User-Agent':'nembra-swarm-v16-dogfood'})
        with urllib.request.urlopen(request,timeout=30) as response: batch=json.loads(response.read().decode())
        if not isinstance(batch,list): raise sc.ValidationError('GitHub pulls response was not a list')
        results.extend(batch)
        if len(batch)<100: break
        page+=1
    return results


def selected_pr(lane: dict) -> int|None:
    legacy=lane.get('legacy') or {}
    for key in ('currentProductionSuccessorPR','selectedProductionPR','currentProductionPR','productionPR'):
        value=legacy.get(key)
        if isinstance(value,int): return value
    return None


def ingest_live(repo: str, token: str, state_branch: str, *, now=None) -> tuple[dict,dict]:
    state=sc.GitHubContentsStore(repo,token,state_branch)
    lanes=[stored.value for _,stored in state.list('.swarm/runtime/lanes')]
    prs=fetch_open_prs(repo,token)
    graph=sc.seed_nembra_graph(now)
    for lane in lanes: sc.migrate_legacy_lane(graph,lane,now=now)
    classifications=sc.classify_prs(prs)
    graph['migration']['classifiedPRs']={str(item['pr']):item for item in classifications}
    prs_by_number={int(pr['number']):pr for pr in prs}
    selected=[]; suppressed=[]
    for lane in lanes:
        number=selected_pr(lane)
        if not number or number not in prs_by_number: continue
        oid=lane['laneId'] if lane['laneId'] in graph['objectives'] else f"legacy-{lane['laneId']}"
        if oid not in graph['objectives']: continue
        pr=prs_by_number[number]; branch=(pr.get('head') or {}).get('ref','')
        blocker_ids=[bid for bid in graph['objectives'][oid]['blockerIds'] if graph['blockers'][bid]['state']!='RESOLVED']
        blocker_id=blocker_ids[0] if blocker_ids else ''
        wid=f'live-pr-{number}'
        _,decision=sc.add_work_item(graph,work_item_id=wid,mission_id=graph['objectives'][oid]['missionId'],objective_id=oid,blocker_id=blocker_id,title=pr.get('title') or wid,outcome=lane.get('objective') or 'close selected canonical work',primary_scope=list(lane.get('allowedWriteAreas',[])),allowed_adjacent_scope=list(lane.get('adjacentWriteAreas',[])),forbidden_areas=(['physical action without explicit external PHYSICAL_GO'] if (lane.get('physical') or {}).get('required') else []),branch=branch,source={'pr':number,'headSHA':(pr.get('head') or {}).get('sha',''),'classification':'canonical-candidate'},now=now)
        if not decision.duplicate: selected.append(number)
        # Prove that validation descendants are assistance/evidence, not accidental branches.
        peer=next((item for item in classifications if item['lane']==lane['laneId'] and item['classification'] in {'validation','duplicate'}),None)
        if peer and blocker_id:
            _,dupe=sc.add_work_item(graph,work_item_id=f'dogfood-duplicate-{peer["pr"]}',mission_id=graph['objectives'][oid]['missionId'],objective_id=oid,blocker_id=blocker_id,title=peer['title'],outcome=lane.get('objective') or 'close selected canonical work',source={'pr':peer['pr']},now=now)
            if dupe.duplicate: suppressed.append(peer['pr'])
    sc.reconcile_branches(graph,now=now)
    sc.update_milestone_attack(graph,now=now)
    summary={'lanesIngested':len(lanes),'openPRsIngested':len(prs),'selectedCanonicalPRs':selected,'duplicatesSuppressed':suppressed,'migration':sc.migration_summary(graph),'health':sc.health_report(graph,workers=30,now=now),'status':sc.user_status(graph,workers=30,now=now)}
    return graph,summary


def self_integration_proof(graph: dict, *, now=None) -> dict:
    # Dogfood V16's own real Nembra control-plane feature through its Merge Train.
    oid='swarm-v16-control-plane'
    if oid not in graph['objectives']:
        graph['objectives'][oid]=sc.make_objective(oid,'nembra-shipping','Swarm V16 control plane',severity='P1',priority=0,user_value=9,release_blocking=False,canonical_branch='mission/swarm-v16-mission-graph',finish_conditions=('V16 unit suite accepted','30-worker adversarial simulation accepted','independent exact-head CI accepted','merged to main'),allowed_adjacent_scope=['scripts/swarmcp','scripts/ci/tests','.swarm','docs'],forbidden_areas=['weaken physical truth','weaken authentication or CI to obtain green'],now=now)
        graph['missions']['nembra-shipping']['objectiveIds'].append(oid)
    graph,_=sc.add_work_item(graph,work_item_id='swarm-v16-integration',mission_id='nembra-shipping',objective_id=oid,title='Integrate Swarm V16 Mission Graph',outcome='ship exact-head V16 control plane after tests and review',role='integrator',primary_scope=['scripts/swarmcp','scripts/ci/tests'],allowed_adjacent_scope=['.swarm','docs','.github/workflows'],forbidden_areas=['physical truth relaxation','auth relaxation'],branch='mission/swarm-v16-mission-graph',source={'dogfood':True},allow_duplicate=True,now=now)
    graph['workItems']['swarm-v16-integration']['status']='REVIEW'
    sc.enqueue_merge(graph,work_item_ids=['swarm-v16-integration'],candidate_id='v16-self-dogfood',required_suites=['swarm-control-plane','swarm-adversarial-30'],now=now)
    sc.start_merge_candidate(graph,'v16-self-dogfood',now=now)
    sc.finish_merge_candidate(graph,'v16-self-dogfood',results={'swarm-control-plane':True,'swarm-adversarial-30':True},integrated=True,integration_branch='mission/swarm-v16-mission-graph',now=now)
    return {'workItemState':graph['workItems']['swarm-v16-integration']['status'],'integrationWorld':graph['workItems']['swarm-v16-integration']['integrationWorld'],'branchState':graph['branches']['mission/swarm-v16-mission-graph']['state'],'health':sc.health_report(graph,workers=30,now=now)}


def main(argv=None) -> int:
    parser=argparse.ArgumentParser(description='Dogfood Nembra Swarm V16 against current GitHub state')
    parser.add_argument('--repo',default=os.getenv('GITHUB_REPOSITORY',''))
    parser.add_argument('--token',default=os.getenv('GITHUB_TOKEN',''))
    parser.add_argument('--state-branch',default='swarm-state')
    parser.add_argument('--output')
    parser.add_argument('--self-integration-proof',action='store_true')
    args=parser.parse_args(argv)
    if not args.repo or not args.token: parser.error('--repo and --token/GITHUB_TOKEN are required')
    graph,summary=ingest_live(args.repo,args.token,args.state_branch)
    if args.self_integration_proof: summary['selfIntegrationProof']=self_integration_proof(graph)
    payload={'summary':summary,'classifications':graph['migration']['classifiedPRs']}
    text=json.dumps(payload,indent=2,sort_keys=True)+'\n'
    if args.output: Path(args.output).write_text(text,encoding='utf-8')
    print(text,end='')
    if not summary['selectedCanonicalPRs']: return 2
    if not summary['duplicatesSuppressed']: return 3
    return 0

if __name__=='__main__': raise SystemExit(main())
