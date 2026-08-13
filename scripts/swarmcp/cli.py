from __future__ import annotations
import argparse, json, os, sys
from .model import *
from .model import _dict
from .store import *
from .engine import *
from .mission_graph import *
from .v16_ops import *
from .migration_v16 import *
from .v16_1_persistence import go_cycle, recommend_mission_packets
from .resources import release_resource
from .enforcement import (
    acquire_resources_for_claim,
    claim_slot,
    heartbeat_resource_for_claim,
    safe_recommend_slots,
    takeover_claim,
    validate_config,
    validate_lane,
    validate_state_snapshot,
)

CONFIG_PATH='.swarm/config.json'

def _token(args): return args.token or os.getenv('GITHUB_TOKEN','')
def trusted_config_from_store(config_store): return validate_config(config_store.get(CONFIG_PATH).value)
def trusted_config(args): return trusted_config_from_store(GitHubContentsStore(args.repo,_token(args),args.config_ref))
def store(args,config): return GitHubContentsStore(args.repo,_token(args),args.state_branch or config['stateBranch'])
def snapshot(s):
    vals=lambda p:[x.value for _,x in s.list(p)]
    return vals('.swarm/runtime/lanes'),vals('.swarm/runtime/claims'),vals('.swarm/runtime/workers'),vals('.swarm/runtime/events'),vals('.swarm/runtime/resources')
def remote(p):
    p.add_argument('--repo',required=True);p.add_argument('--state-branch');p.add_argument('--config-ref',default='main');p.add_argument('--token')

def parser():
    p=argparse.ArgumentParser(description='Nembra Swarm Control Plane');sub=p.add_subparsers(dest='cmd',required=True)
    q=sub.add_parser('simulate');q.add_argument('--workers',type=int,default=30)
    q=sub.add_parser('v16-simulate');q.add_argument('--workers',type=int,default=30)
    names=('remote-validate','register','claim','takeover','heartbeat','release','event','recommend','board','resource-acquire','resource-heartbeat','resource-release','v16-init','v16-status','v16-recommend','v16-go','v16-surge','v16-migrate','v16-captain','v16-cleanup-plan','v16-claim','v16-takeover','v16-work-heartbeat','v16-work-release')
    for name in names:
        q=sub.add_parser(name);remote(q)
        if name=='register':q.add_argument('--worker',required=True);q.add_argument('--branch',default='')
        if name in {'claim','takeover'}:q.add_argument('--lane',required=True);q.add_argument('--slot',required=True);q.add_argument('--worker',required=True);q.add_argument('--branch',default='');q.add_argument('--pr',type=int);q.add_argument('--source-sha')
        if name in {'heartbeat','release'}:q.add_argument('--lane',required=True);q.add_argument('--slot',required=True);q.add_argument('--worker',required=True);q.add_argument('--lease-id',required=True);q.add_argument('--generation',type=int,required=True)
        if name=='event':q.add_argument('--type',choices=sorted(EVENT_TYPES),required=True);q.add_argument('--worker',required=True);q.add_argument('--lane');q.add_argument('--message',required=True);q.add_argument('--data')
        if name=='recommend':q.add_argument('--red-main',action='store_true');q.add_argument('--limit',type=int,default=20)
        if name=='board':q.add_argument('--red-main',action='store_true')
        if name=='resource-acquire':q.add_argument('--resource',action='append',choices=sorted(RESOURCE_CLASSES),required=True);q.add_argument('--worker',required=True);q.add_argument('--lane',required=True)
        if name in {'resource-heartbeat','resource-release'}:q.add_argument('--resource',choices=sorted(RESOURCE_CLASSES),required=True);q.add_argument('--worker',required=True);q.add_argument('--lease-id',required=True);q.add_argument('--generation',type=int,required=True)
        if name=='v16-recommend':q.add_argument('--worker',action='append',default=[]);q.add_argument('--limit',type=int,default=30)
        if name=='v16-go':q.add_argument('--worker',required=True);q.add_argument('--completed');q.add_argument('--evidence',action='append',default=[])
        if name=='v16-surge':q.add_argument('--mission');q.add_argument('--stop-reason')
        if name=='v16-captain':q.add_argument('--mission',required=True);q.add_argument('--worker',required=True);q.add_argument('--replace-reason')
        if name in {'v16-claim','v16-takeover'}:q.add_argument('--work-item',required=True);q.add_argument('--worker',required=True)
        if name in {'v16-work-heartbeat','v16-work-release'}:q.add_argument('--work-item',required=True);q.add_argument('--worker',required=True);q.add_argument('--lease-id',required=True);q.add_argument('--generation',type=int,required=True)
    return p

def _v16_service(s): return v16_graph_service(s)
def _v16_load(s): return _v16_service(s).ensure(seed_nembra_graph(utc_now()))[0]

def main(argv=None):
    try:
        a=parser().parse_args(argv)
        if a.cmd=='simulate':r=run_adversarial_simulation(a.workers);print(pretty_json(r),end='');return 0 if r['passed'] else 1
        if a.cmd=='v16-simulate':r=run_v16_adversarial_simulation(a.workers,utc_now());print(pretty_json(r),end='');return 0 if r['passed'] else 1
        config=trusted_config(a);s=store(a,config)
        if a.cmd=='remote-validate':
            l,c,w,e,r=snapshot(s);errs=validate_state_snapshot(l,c,w,e,r,utc_now());print('\n'.join('ERROR: '+x for x in errs) if errs else f'validated lanes={len(l)} claims={len(c)} workers={len(w)} events={len(e)} resources={len(r)}');return 1 if errs else 0
        if a.cmd=='v16-init':
            graph,_=_v16_service(s).ensure(seed_nembra_graph(utc_now()));print(pretty_json({'graphId':graph['graphId'],'revision':graph['revision'],'missions':list(graph['missions']),'objectives':len(graph['objectives']),'physicalAutoPromotion':False}),end='');return 0
        if a.cmd=='v16-status':print(user_status(_v16_load(s),workers=30,now=utc_now()),end='\n');return 0
        if a.cmd=='v16-recommend':
            graph=_v16_load(s);print(pretty_json([asdict(x) for x in recommend_mission_packets(graph,worker_ids=a.worker,limit=a.limit,now=utc_now())]),end='');return 0
        if a.cmd=='v16-go':
            service=_v16_service(s)
            def mutate(graph): return go_cycle(graph,a.worker,completed_work_item_id=a.completed or '',evidence_ids=a.evidence,now=utc_now())
            _,result=service.mutate(mutate,message=f'swarm v16: go handoff {a.worker}');print(pretty_json(result),end='');return 0
        if a.cmd=='v16-surge':
            if not a.mission and not a.stop_reason: raise ValidationError('v16-surge requires --mission or --stop-reason')
            service=_v16_service(s)
            def mutate(graph):
                if a.stop_reason:return stop_surge(graph,reason=a.stop_reason,now=utc_now())
                return enter_surge(graph,a.mission,now=utc_now())
            graph,_=service.mutate(mutate,message='swarm v16: change surge mode');allocation=surge_role_allocation(30) if graph['modes']['surgeMissionId'] else role_allocation(graph,30);print(pretty_json({'surgeMissionId':graph['modes']['surgeMissionId'],'allocation':allocation}),end='');return 0
        if a.cmd=='v16-migrate':
            lanes,_,_,_,_=snapshot(s);service=_v16_service(s)
            def migrate(graph):
                migration_phase(graph,'IMPORTING',now=utc_now())
                for lane in lanes:migrate_legacy_lane(graph,lane,now=utc_now())
                migration_phase(graph,'DOGFOOD',now=utc_now())
                return migration_summary(graph)
            graph,result=service.mutate(migrate,message='swarm v16: migrate legacy lanes');print(pretty_json({'migration':result,'health':health_report(graph,workers=30,now=utc_now())}),end='');return 0
        if a.cmd=='v16-captain':
            service=_v16_service(s)
            def mutate(graph):
                if a.replace_reason:return replace_failed_captain(graph,a.mission,a.worker,reason=a.replace_reason,now=utc_now())
                return assign_captain(graph,a.mission,a.worker,now=utc_now())
            graph,_=service.mutate(mutate,message=f'swarm v16: captain {a.mission}');print(pretty_json({'mission':a.mission,'captain':graph['missions'][a.mission]['captain']}),end='');return 0
        if a.cmd=='v16-cleanup-plan':print(pretty_json(branch_cleanup_plan(_v16_load(s))),end='');return 0
        if a.cmd in {'v16-claim','v16-takeover'}:
            graph=_v16_load(s);item=graph['workItems'].get(a.work_item)
            if not item:raise ValidationError('unknown V16 work item')
            x=claim_work_item(s,item,a.worker,utc_now()) if a.cmd=='v16-claim' else takeover_work_claim(s,item,a.worker,utc_now())
            print(pretty_json(x.value),end='');return 0
        if a.cmd=='v16-work-heartbeat':x=heartbeat_work_claim(s,a.work_item,a.worker,a.lease_id,a.generation,utc_now());print(pretty_json(x.value),end='');return 0
        if a.cmd=='v16-work-release':x=release_work_claim(s,a.work_item,a.worker,a.lease_id,a.generation,utc_now());print(pretty_json(x.value),end='');return 0
        if a.cmd=='register':x=register_worker(s,a.worker,utc_now(),branch=a.branch)
        elif a.cmd=='claim':x=claim_slot(s,validate_lane(s.get(lane_path(a.lane)).value),a.slot,a.worker,utc_now(),a.branch,a.pr,a.source_sha,config=config)
        elif a.cmd=='takeover':x=takeover_claim(s,validate_lane(s.get(lane_path(a.lane)).value),a.slot,a.worker,utc_now(),a.branch,a.pr,a.source_sha,config=config)
        elif a.cmd=='heartbeat':x=heartbeat(s,a.lane,a.slot,a.worker,a.lease_id,a.generation,utc_now())
        elif a.cmd=='release':x=release_claim(s,a.lane,a.slot,a.worker,a.lease_id,a.generation,utc_now())
        elif a.cmd=='event':x=publish_event(s,a.type,a.worker,a.message,utc_now(),a.lane,_dict(json.loads(a.data),'data') if a.data else None)
        elif a.cmd=='recommend':
            l,c,_,_,r=snapshot(s);print(pretty_json([asdict(x) for x in safe_recommend_slots(l,c,r,config,utc_now(),a.red_main)[:a.limit]]),end='');return 0
        elif a.cmd=='board':
            l,c,w,e,r=snapshot(s);print(render_dashboard(l,c,w,r,e,utc_now(),a.red_main),end='');return 0
        elif a.cmd=='resource-acquire':
            values=acquire_resources_for_claim(s,a.resource,a.worker,a.lane,utc_now(),config['resourceOrder']);print(pretty_json([value.value for value in values]),end='');return 0
        elif a.cmd=='resource-heartbeat':x=heartbeat_resource_for_claim(s,a.resource,a.worker,a.lease_id,a.generation,utc_now())
        elif a.cmd=='resource-release':x=release_resource(s,a.resource,a.worker,a.lease_id,a.generation,utc_now())
        else:raise ValidationError('unknown command')
        print(pretty_json(x.value),end='');return 0
    except (SwarmError,ValueError,json.JSONDecodeError) as e:print(f'swarm-control error: {e}',file=sys.stderr);return 2
