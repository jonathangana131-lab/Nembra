from __future__ import annotations
import datetime as dt, uuid
from dataclasses import dataclass, asdict
from typing import Mapping, Sequence
from .model import *
from .model import _worker, _id, _str, _branch
from .store import *

def claim_is_live(c,now):
    c=validate_claim(c); return c['status']=='ACTIVE' and now<parse_time(c['lastHeartbeatAt'])+dt.timedelta(seconds=c['leaseSeconds'])
def claim_expiry(c): c=validate_claim(c); return parse_time(c['lastHeartbeatAt'])+dt.timedelta(seconds=c['leaseSeconds'])
def new_claim(lane,slot,worker,now,branch='',pr=None,source_sha=None,generation=1,takeover_from=None):
    lane=validate_lane(lane); _worker(worker); slots={x['name']:x for x in lane['slots']}
    if slot not in slots: raise ValidationError('unknown lane slot')
    s=slots[slot]; x={'schemaVersion':1,'kind':'claim','laneId':lane['laneId'],'slot':slot,'role':s['role'],'workerId':worker,'leaseId':uuid.uuid4().hex,'generation':generation,'status':'ACTIVE','claimedAt':format_time(now),'lastHeartbeatAt':format_time(now),'leaseSeconds':s['leaseSeconds'],'branch':_branch(branch),'pr':pr}
    if source_sha is not None: x['sourceSHA']=source_sha
    if takeover_from is not None: x['takeoverFromWorkerId']=takeover_from
    return validate_claim(x)
def claim_slot(store,lane,slot,worker,now,branch='',pr=None,source_sha=None):
    lane=validate_lane(lane)
    if lane['state'] in TERMINAL_LANE_STATES|{'BLOCKED','BLOCKED_EXTERNAL'}: raise ValidationError('lane not claimable')
    c=new_claim(lane,slot,worker,now,branch,pr,source_sha); return store.create(claim_path(lane['laneId'],slot),c,f"swarm: claim {lane['laneId']}/{slot}")
def heartbeat(store,lane,slot,worker,lease_id,generation,now):
    p=claim_path(lane,slot); cur=store.get(p); c=validate_claim(cur.value)
    if (c['workerId'],c['leaseId'],c['generation'])!=(worker,lease_id,generation) or not claim_is_live(c,now): raise LeaseLostError('claim ownership changed or expired')
    c['lastHeartbeatAt']=format_time(now); return store.update(p,c,cur.version,f'swarm: heartbeat {lane}/{slot}')
def release_claim(store,lane,slot,worker,lease_id,generation,now):
    p=claim_path(lane,slot); cur=store.get(p); c=validate_claim(cur.value)
    if (c['workerId'],c['leaseId'],c['generation'])!=(worker,lease_id,generation): raise LeaseLostError('claim ownership changed')
    c['status']='RELEASED'; c['lastHeartbeatAt']=c['releasedAt']=format_time(now); return store.update(p,c,cur.version,f'swarm: release {lane}/{slot}')
def takeover_claim(store,lane,slot,worker,now,branch='',pr=None,source_sha=None):
    lane=validate_lane(lane); p=claim_path(lane['laneId'],slot); cur=store.get(p); old=validate_claim(cur.value)
    if claim_is_live(old,now): raise ConflictError('claim still live')
    c=new_claim(lane,slot,worker,now,branch or old.get('branch',''),pr if pr is not None else old.get('pr'),source_sha or old.get('sourceSHA'),old['generation']+1,old['workerId'])
    return store.update(p,c,cur.version,f"swarm: takeover {lane['laneId']}/{slot}")
def register_worker(store,worker,now,status='ACTIVE',branch=''):
    x=validate_worker({'schemaVersion':1,'kind':'worker','workerId':worker,'model':'GPT-5.6 Sol','status':status,'branch':branch,'startedAt':format_time(now),'lastSeenAt':format_time(now)}); p=worker_path(worker)
    try:return store.create(p,x,f'swarm: register {worker}')
    except ConflictError:
        cur=store.get(p); x['startedAt']=validate_worker(cur.value)['startedAt']; return store.update(p,x,cur.version,f'swarm: refresh {worker}')
def publish_event(store,event_type,worker,message,now,lane_id=None,data=None):
    if event_type not in EVENT_TYPES: raise ValidationError('unknown event type')
    x={'schemaVersion':1,'kind':'event','eventId':f"{now:%H%M%S}-{uuid.uuid4().hex[:16]}",'type':event_type,'workerId':worker,'message':_str(message,'message',MAX_EVENT_MESSAGE),'createdAt':format_time(now)}
    if lane_id is not None:x['laneId']=_id(lane_id,'laneId')
    if data:x['data']=dict(data)
    x=validate_event(x); return store.create(event_path(x),x,f'swarm: event {event_type.lower()}')
def publish_handoff(store,handoff,now):
    x=validate_handoff(handoff); return store.create(handoff_path(x['laneId'],now),x,f"swarm: handoff {x['laneId']}")
def _resource_claim(resource,worker,lane,now):
    if resource not in RESOURCE_CLASSES: raise ValidationError('unknown resource')
    return validate_claim({'schemaVersion':1,'kind':'resource-claim','laneId':_id(lane,'laneId'),'slot':resource.lower(),'role':'resource','workerId':_worker(worker),'leaseId':uuid.uuid4().hex,'generation':1,'status':'ACTIVE','claimedAt':format_time(now),'lastHeartbeatAt':format_time(now),'leaseSeconds':DEFAULT_RESOURCE_LEASE_SECONDS,'branch':'','pr':None,'resource':resource})
def acquire_resources(store,resources,worker,lane,now,resource_order):
    req=list(dict.fromkeys(resources)); idx={r:i for i,r in enumerate(resource_order)}
    if any(r not in RESOURCE_CLASSES or r not in idx for r in req): raise ValidationError('resource missing from deterministic order')
    req.sort(key=idx.__getitem__); acquired=[]
    try:
        for r in req:
            p=resource_path(r); c=_resource_claim(r,worker,lane,now)
            try:s=store.create(p,c,f'swarm: acquire {r}')
            except ConflictError:
                cur=store.get(p); old=validate_claim(cur.value)
                if claim_is_live(old,now):raise
                c['generation']=old['generation']+1;c['takeoverFromWorkerId']=old['workerId'];s=store.update(p,c,cur.version,f'swarm: takeover resource {r}')
            acquired.append((r,s))
        return [s for _,s in acquired]
    except Exception:
        for r,s in reversed(acquired):
            try:
                cur=store.get(resource_path(r)); c=validate_claim(cur.value)
                if c['workerId']==worker and c['leaseId']==s.value['leaseId']:
                    c['status']='RELEASED';c['releasedAt']=format_time(now);store.update(resource_path(r),c,cur.version,f'swarm: rollback {r}')
            except SwarmError:pass
        raise
def active_blockers(lane): return [dict(b) for b in validate_lane(lane).get('blockers',[]) if b.get('state')=='ACTIVE']
def detect_dependency_cycles(lanes):
    m={validate_lane(x)['laneId']:validate_lane(x) for x in lanes}; color={k:0 for k in m}; stack=[]; cycles=[]
    def visit(n):
        color[n]=1;stack.append(n)
        for d in m[n].get('dependencies',[]):
            if d not in m:continue
            if color[d]==0:visit(d)
            elif color[d]==1:
                c=stack[stack.index(d):]+[d]
                if c not in cycles:cycles.append(c)
        stack.pop();color[n]=2
    for n in m:
        if color[n]==0:visit(n)
    return cycles
def dependency_ready(lane,m):
    lane=validate_lane(lane)
    for d in lane['dependencies']:
        if d not in m:return False,f'missing dependency {d}'
        if validate_lane(m[d])['state']!='DONE':return False,f"dependency {d} is {m[d]['state']}"
    return True,'dependencies satisfied'
def physical_slot_runnable(lane,slot):
    lane=validate_lane(lane); p=lane['physical']
    if not p.get('required',False) or slot.get('role')!='physical-evidence':return True,'no physical authority required'
    if p.get('state')!='PHYSICAL_GO':return False,f"physical state is {p.get('state')}; scheduler cannot promote GO"
    return True,'existing reviewed PHYSICAL_GO present'
def scope_violations(lane,files):
    lane=validate_lane(lane); areas=lane.get('allowedWriteAreas',[])+lane.get('adjacentWriteAreas',[]); exact=set(areas); pref=[a.rstrip('/')+'/' for a in areas]
    return [p for p in [safe_relpath(x,'changed file') for x in files] if p not in exact and not any(p.startswith(a) for a in pref)]
def primary_claim_counts(lanes,claims,now):
    lm={validate_lane(x)['laneId']:validate_lane(x) for x in lanes}; total=0; by_epic={}
    for raw in claims:
        c=validate_claim(raw)
        if not claim_is_live(c,now) or c['laneId'] not in lm:continue
        lane=lm[c['laneId']]; slots={s['name']:s for s in lane['slots']}
        if slots.get(c['slot'],{}).get('role')=='implementation':
            total+=1
            epic=lane.get('epic','')
            by_epic[epic]=by_epic.get(epic,0)+1
    return total,by_epic
def primary_claims(lanes,claims,now): return primary_claim_counts(lanes,claims,now)[0]
@dataclass(frozen=True)
class Recommendation:
    lane_id:str;slot:str;role:str;priority_key:tuple;reason:str
def recommend_slots(lanes,claims,resources,config,now,red_main=False):
    config=validate_config(config); ls=[validate_lane(x) for x in lanes]
    if detect_dependency_cycles(ls): raise ValidationError('dependency cycle detected')
    lm={x['laneId']:x for x in ls}; live={(c['laneId'],c['slot']):c for raw in claims for c in [validate_claim(raw)] if claim_is_live(c,now)}
    busy={raw.get('resource') for raw in resources if raw.get('resource') in RESOURCE_CLASSES and claim_is_live(validate_claim(raw),now)}
    prim,prim_by_epic=primary_claim_counts(ls,claims,now); w=config['wipLimits']; review=sum(x['state'] in {'REVIEW','NEEDS_CHANGES'} for x in ls); integ=sum(x['state']=='INTEGRATION_READY' for x in ls)
    fan={x['laneId']:0 for x in ls}
    for x in ls:
        for d in x['dependencies']:
            if d in fan:fan[d]+=1
    out=[]
    for lane in ls:
        if lane['state'] not in RUNNABLE_LANE_STATES or active_blockers(lane):continue
        ready,dep=dependency_ready(lane,lm)
        if not ready:continue
        tags=set(lane.get('tags',[]))
        for s in lane['slots']:
            if (lane['laneId'],s['name']) in live:continue
            ok,phys=physical_slot_runnable(lane,s)
            if not ok or any(r in busy for r in s.get('resources',[])):continue
            role=s['role']
            if role=='implementation' and (prim>=w['maxPrimaryLanes'] or prim_by_epic.get(lane.get('epic',''),0)>=w['maxPrimaryPerEpic']):continue
            pressure=(3 if review>=w['reviewBacklogThreshold'] and role not in {'review','adversarial-review'} else 0)+(3 if integ>=w['integrationBacklogThreshold'] and role!='integration' else 0)
            red=0 if red_main and ('red-main-repair' in tags or role=='repair') else (20 if red_main else 0)
            state={'INTEGRATION_READY':0 if role=='integration' else 5,'REVIEW':0 if role in {'review','adversarial-review'} else 5,'NEEDS_CHANGES':1 if role=='implementation' else 4,'VERIFYING':1 if role in {'tests','xcode-evidence','performance','accessibility'} else 4}.get(lane['state'],2)
            key=(red,pressure,lane['priority'],state,-fan[lane['laneId']],0 if 'epic-closer' in tags else 1,ROLE_ORDER.get(role,15)); reason=f'{dep}; {phys}; fanout={fan[lane["laneId"]]}; review={review}; integration={integ}'
            out.append(Recommendation(lane['laneId'],s['name'],role,key,reason))
    return sorted(out,key=lambda x:(x.priority_key,x.lane_id,x.slot))
def verify_review_independence(lane,primary,reviewer):
    lane=validate_lane(lane);primary=validate_claim(primary);_worker(reviewer)
    if lane.get('acceptance',{}).get('independentReview',False) and primary['workerId']==reviewer:raise ValidationError('independent review requires different workerId')
def parse_pr_metadata(body):
    if not isinstance(body,str):raise ValidationError('PR body must be text')
    out={}
    import re
    for line in body.splitlines():
        m=re.fullmatch(r'(SWARM_SCHEMA|SWARM_LANE|SWARM_SLOT|SWARM_WORKER|SWARM_CLAIM_GENERATION):\s*(\S+)\s*',line)
        if m:out[m.group(1)]=m.group(2)
    return out
def validate_pr_metadata(body):
    f=parse_pr_metadata(body); need=('SWARM_SCHEMA','SWARM_LANE','SWARM_SLOT','SWARM_WORKER','SWARM_CLAIM_GENERATION'); missing=[x for x in need if x not in f]
    if missing:raise ValidationError('missing PR swarm metadata: '+', '.join(missing))
    try:schema=int(f['SWARM_SCHEMA']);gen=int(f['SWARM_CLAIM_GENERATION'])
    except ValueError as e:raise ValidationError('schema/generation must be integers') from e
    if schema not in SUPPORTED_SCHEMA_VERSIONS or gen<1:raise ValidationError('unsupported metadata version')
    return {'schemaVersion':schema,'laneId':_id(f['SWARM_LANE'],'lane'),'slot':_id(f['SWARM_SLOT'],'slot'),'workerId':_worker(f['SWARM_WORKER']),'generation':gen}
def validate_state_snapshot(lanes,claims,workers,events,resources,now):
    errors=[]; good=[]
    for i,x in enumerate(lanes):
        try:good.append(validate_lane(x))
        except ValidationError as e:errors.append(f'lane[{i}]: {e}')
    for name,seq,fn in [('worker',workers,validate_worker),('event',events,validate_event)]:
        for i,x in enumerate(seq):
            try:fn(x)
            except ValidationError as e:errors.append(f'{name}[{i}]: {e}')
    lm={x['laneId']:x for x in good}; seen=set()
    for i,raw in enumerate(claims):
        try:
            c=validate_claim(raw)
            if c['laneId'] not in lm:raise ValidationError('claim references unknown lane')
            if c['slot'] not in {s['name'] for s in lm[c['laneId']]['slots']}:raise ValidationError('claim references unknown slot')
            if claim_is_live(c,now):
                k=(c['laneId'],c['slot'])
                if k in seen:raise ValidationError('duplicate active owner')
                seen.add(k)
        except ValidationError as e:errors.append(f'claim[{i}]: {e}')
    rseen=set()
    for i,raw in enumerate(resources):
        try:
            c=validate_claim(raw);r=raw.get('resource')
            if r not in RESOURCE_CLASSES:raise ValidationError('unknown resource')
            if claim_is_live(c,now) and r in rseen:raise ValidationError('duplicate resource owner')
            if claim_is_live(c,now):rseen.add(r)
        except ValidationError as e:errors.append(f'resource[{i}]: {e}')
    for c in detect_dependency_cycles(good):errors.append('dependency cycle: '+' -> '.join(c))
    return errors
def render_dashboard(lanes,claims,workers,resources,events,now,red_main=False):
    ls=[validate_lane(x) for x in lanes];cs=[validate_claim(x) for x in claims];ws=[validate_worker(x) for x in workers];es=[validate_event(x) for x in events]
    count={}
    for x in ls:count[x['state']]=count.get(x['state'],0)+1
    live=[x for x in cs if claim_is_live(x,now)];stale=[x for x in cs if x['status']=='ACTIVE' and not claim_is_live(x,now)];active=[x for x in ws if (now-parse_time(x['lastSeenAt'])).total_seconds()<=7200]
    rs=[]
    for raw in resources:
        c=validate_claim(raw); r=raw.get('resource')
        if r in RESOURCE_CLASSES: rs.append((r,c,claim_is_live(c,now)))
    lines=['# Nembra Swarm Dashboard','', '> Generated cache only. Authority lives in lane/claim/resource/event records and live GitHub product state.','',f'Generated: `{format_time(now)}`',f"Main: `{'RED' if red_main else 'not declared red by control snapshot'}`",'','## Summary','',f"- Ready lanes: **{count.get('READY',0)}**",f'- Active claims: **{len(live)}**',f"- Waiting review: **{count.get('REVIEW',0)+count.get('NEEDS_CHANGES',0)}**",f"- Waiting integration: **{count.get('INTEGRATION_READY',0)}**",f"- Blocked lanes: **{count.get('BLOCKED',0)+count.get('BLOCKED_EXTERNAL',0)}**",f'- Active workers: **{len(active)}**',f'- Stale claims: **{len(stale)}**','','## Active lanes','']
    for x in sorted(ls,key=lambda q:(q['priority'],q['laneId'])):
        if x['state'] not in TERMINAL_LANE_STATES:lines.append(f"- `{x['laneId']}` — **{x['state']}** — {x['title']}")
    lines+=['','## Scarce resources','']
    if rs:
        for r,c,is_live in sorted(rs,key=lambda x:x[0]): lines.append(f"- `{r}` — **{'LEASED' if is_live else 'STALE/RELEASED'}** — `{c['workerId']}` / `{c['laneId']}`")
    else: lines.append('- No resource leases recorded.')
    lines+=['','## Recent important events',''];imp=[x for x in es if x['type'] in {'BLOCKER','DECISION','HANDOFF','SUPERSEDED','EVIDENCE_RESULT','EXTERNAL_BLOCKER','INTEGRATION_RESULT','TAKEOVER'}]
    for x in sorted(imp,key=lambda q:q['createdAt'],reverse=True)[:12]:lines.append(f"- `{x['createdAt']}` **{x['type']}**: {x['message']}")
    if not imp:lines.append('- No important events recorded.')
    return '\n'.join(lines)+'\n'
def run_adversarial_simulation(worker_count=30):
    if not 2<=worker_count<=200:raise ValidationError('workers must be 2..200')
    now=dt.datetime(2026,8,11,5,0,tzinfo=dt.timezone.utc);lane=sample_lane();store=MemoryStore();wins=[];collisions=0
    for i in range(worker_count):
        w=f'sol-20260811-w{i:04x}'
        try:claim_slot(store,lane,'primary',w,now);wins.append(w)
        except ConflictError:collisions+=1
    first=store.get(claim_path(lane['laneId'],'primary')).value; expired=claim_expiry(first)+dt.timedelta(seconds=1);takes=[]
    for w in ('sol-20260811-takea','sol-20260811-takeb'):
        try:takes.append(takeover_claim(store,lane,'primary',w,expired).value['workerId'])
        except ConflictError:pass
    old=False
    try:heartbeat(store,lane['laneId'],'primary',first['workerId'],first['leaseId'],first['generation'],expired+dt.timedelta(seconds=1))
    except LeaseLostError:old=True
    up=sample_lane('upstream',state='BLOCKED_EXTERNAL');down=sample_lane('downstream',deps=['upstream']);hidden=not any(r.lane_id=='downstream' for r in recommend_slots([up,down],[],[],default_config(),now));up['state']='DONE';returned=any(r.lane_id=='downstream' for r in recommend_slots([up,down],[],[],default_config(),now))
    phys=sample_lane('physical',physical=True);slot={'name':'physical','role':'physical-evidence','exclusive':True,'leaseSeconds':1800,'resources':['PHYSICAL_SCOOTER']};phys['slots'].append(slot);phys=validate_lane(phys);nogo=not physical_slot_runnable(phys,slot)[0]
    board=render_dashboard([lane],[store.get(claim_path(lane['laneId'],'primary')).value],[],[],[],expired)
    checks={'simultaneousExclusiveClaimExactlyOne':len(wins)==1 and collisions==worker_count-1,'singleAtomicTakeoverWinner':len(takes)==1,'oldPrimaryCannotHeartbeatAfterTakeover':old,'blockedDependencyLeavesReadyQueue':hidden,'recoveredDependencyReturnsToReadyQueue':returned,'physicalNoGoNeverAutoPromoted':nogo,'generatedBoardDeterministic':board==render_dashboard([lane],[store.get(claim_path(lane['laneId'],'primary')).value],[],[],[],expired)}
    return {'schemaVersion':1,'workers':worker_count,'claimWinner':wins[0] if wins else None,'claimCollisionsPrevented':collisions,'takeoverWinner':takes[0] if takes else None,'checks':checks,'passed':all(checks.values())}
