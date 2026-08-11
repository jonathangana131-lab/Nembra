from __future__ import annotations
import argparse, json, os, sys
from .model import *
from .model import _dict
from .store import *
from .engine import *
def store(args): return GitHubContentsStore(args.repo,args.token or os.getenv('GITHUB_TOKEN',''),args.state_branch)
def snapshot(s):
    vals=lambda p:[x.value for _,x in s.list(p)]
    return vals('.swarm/runtime/lanes'),vals('.swarm/runtime/claims'),vals('.swarm/runtime/workers'),vals('.swarm/runtime/events'),vals('.swarm/runtime/resources')
def remote(p):p.add_argument('--repo',required=True);p.add_argument('--state-branch',default=DEFAULT_STATE_BRANCH);p.add_argument('--token')
def parser():
    p=argparse.ArgumentParser(description='Nembra Swarm Control Plane');sub=p.add_subparsers(dest='cmd',required=True)
    q=sub.add_parser('simulate');q.add_argument('--workers',type=int,default=30)
    for name in ('remote-validate','register','claim','takeover','heartbeat','release','event','recommend','board'):
        q=sub.add_parser(name);remote(q)
        if name=='register':q.add_argument('--worker',required=True);q.add_argument('--branch',default='')
        if name in {'claim','takeover'}:q.add_argument('--lane',required=True);q.add_argument('--slot',required=True);q.add_argument('--worker',required=True);q.add_argument('--branch',default='');q.add_argument('--pr',type=int);q.add_argument('--source-sha')
        if name in {'heartbeat','release'}:q.add_argument('--lane',required=True);q.add_argument('--slot',required=True);q.add_argument('--worker',required=True);q.add_argument('--lease-id',required=True);q.add_argument('--generation',type=int,required=True)
        if name=='event':q.add_argument('--type',choices=sorted(EVENT_TYPES),required=True);q.add_argument('--worker',required=True);q.add_argument('--lane');q.add_argument('--message',required=True);q.add_argument('--data')
        if name=='recommend':q.add_argument('--red-main',action='store_true');q.add_argument('--limit',type=int,default=20)
        if name=='board':q.add_argument('--red-main',action='store_true')
    return p
def main(argv=None):
    try:
        a=parser().parse_args(argv)
        if a.cmd=='simulate':r=run_adversarial_simulation(a.workers);print(pretty_json(r),end='');return 0 if r['passed'] else 1
        s=store(a)
        if a.cmd=='remote-validate':
            l,c,w,e,r=snapshot(s);errs=validate_state_snapshot(l,c,w,e,r,utc_now());print('\n'.join('ERROR: '+x for x in errs) if errs else f'validated lanes={len(l)} claims={len(c)} workers={len(w)} events={len(e)} resources={len(r)}');return 1 if errs else 0
        if a.cmd=='register':x=register_worker(s,a.worker,utc_now(),branch=a.branch)
        elif a.cmd=='claim':x=claim_slot(s,validate_lane(s.get(lane_path(a.lane)).value),a.slot,a.worker,utc_now(),a.branch,a.pr,a.source_sha)
        elif a.cmd=='takeover':x=takeover_claim(s,validate_lane(s.get(lane_path(a.lane)).value),a.slot,a.worker,utc_now(),a.branch,a.pr,a.source_sha)
        elif a.cmd=='heartbeat':x=heartbeat(s,a.lane,a.slot,a.worker,a.lease_id,a.generation,utc_now())
        elif a.cmd=='release':x=release_claim(s,a.lane,a.slot,a.worker,a.lease_id,a.generation,utc_now())
        elif a.cmd=='event':x=publish_event(s,a.type,a.worker,a.message,utc_now(),a.lane,_dict(json.loads(a.data),'data') if a.data else None)
        elif a.cmd=='recommend':
            l,c,_,_,r=snapshot(s);print(pretty_json([asdict(x) for x in recommend_slots(l,c,r,default_config(),utc_now(),a.red_main)[:a.limit]]),end='');return 0
        elif a.cmd=='board':
            l,c,w,e,r=snapshot(s);print(render_dashboard(l,c,w,r,e,utc_now(),a.red_main),end='');return 0
        else:raise ValidationError('unknown command')
        print(pretty_json(x.value),end='');return 0
    except (SwarmError,ValueError,json.JSONDecodeError) as e:print(f'swarm-control error: {e}',file=sys.stderr);return 2
