from __future__ import annotations
import argparse, json, os, sys
from .model import *
from .model import _dict
from .store import *
from .engine import *
from .policy import claim_slot, takeover_claim, recommend_slots
from .resources import heartbeat_resource, release_resource

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
    names=('remote-validate','register','claim','takeover','heartbeat','release','event','recommend','board','resource-acquire','resource-heartbeat','resource-release')
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
    return p
def main(argv=None):
    try:
        a=parser().parse_args(argv)
        if a.cmd=='simulate':r=run_adversarial_simulation(a.workers);print(pretty_json(r),end='');return 0 if r['passed'] else 1
        config=trusted_config(a)
        s=store(a,config)
        if a.cmd=='remote-validate':
            l,c,w,e,r=snapshot(s);errs=validate_state_snapshot(l,c,w,e,r,utc_now());print('\n'.join('ERROR: '+x for x in errs) if errs else f'validated lanes={len(l)} claims={len(c)} workers={len(w)} events={len(e)} resources={len(r)}');return 1 if errs else 0
        if a.cmd=='register':x=register_worker(s,a.worker,utc_now(),branch=a.branch)
        elif a.cmd=='claim':x=claim_slot(s,validate_lane(s.get(lane_path(a.lane)).value),a.slot,a.worker,utc_now(),a.branch,a.pr,a.source_sha,config=config)
        elif a.cmd=='takeover':x=takeover_claim(s,validate_lane(s.get(lane_path(a.lane)).value),a.slot,a.worker,utc_now(),a.branch,a.pr,a.source_sha,config=config)
        elif a.cmd=='heartbeat':x=heartbeat(s,a.lane,a.slot,a.worker,a.lease_id,a.generation,utc_now())
        elif a.cmd=='release':x=release_claim(s,a.lane,a.slot,a.worker,a.lease_id,a.generation,utc_now())
        elif a.cmd=='event':x=publish_event(s,a.type,a.worker,a.message,utc_now(),a.lane,_dict(json.loads(a.data),'data') if a.data else None)
        elif a.cmd=='recommend':
            l,c,_,_,r=snapshot(s);print(pretty_json([asdict(x) for x in recommend_slots(l,c,r,config,utc_now(),a.red_main)[:a.limit]]),end='');return 0
        elif a.cmd=='board':
            l,c,w,e,r=snapshot(s);print(render_dashboard(l,c,w,r,e,utc_now(),a.red_main),end='');return 0
        elif a.cmd=='resource-acquire':
            values=acquire_resources(s,a.resource,a.worker,a.lane,utc_now(),config['resourceOrder']);print(pretty_json([value.value for value in values]),end='');return 0
        elif a.cmd=='resource-heartbeat':x=heartbeat_resource(s,a.resource,a.worker,a.lease_id,a.generation,utc_now())
        elif a.cmd=='resource-release':x=release_resource(s,a.resource,a.worker,a.lease_id,a.generation,utc_now())
        else:raise ValidationError('unknown command')
        print(pretty_json(x.value),end='');return 0
    except (SwarmError,ValueError,json.JSONDecodeError) as e:print(f'swarm-control error: {e}',file=sys.stderr);return 2
