from __future__ import annotations
import datetime as dt, hashlib, json, re, uuid
from pathlib import PurePosixPath
from typing import Any, Mapping

SCHEMA_VERSION=1
SUPPORTED_SCHEMA_VERSIONS={1}
DEFAULT_STATE_BRANCH='swarm-state'
DEFAULT_LEASE_SECONDS=2700
DEFAULT_REVIEW_LEASE_SECONDS=1800
DEFAULT_RESOURCE_LEASE_SECONDS=1800
MAX_EVENT_MESSAGE=4000
MAX_TEXT_FIELD=8000
MAX_LIST_ITEMS=256
MAX_DATA_ONLY_OBJECT_KEYS=128
# V16 live migration intentionally inspects at most four GitHub PR pages of
# 100 entries each. Preserve the default object bound everywhere else while
# allowing that complete, data-only classification index to survive validation.
DATA_ONLY_OBJECT_KEY_LIMITS={'$.migration.classifiedPRs':400}
ID_RE=re.compile(r'^[a-z0-9][a-z0-9._-]{0,63}$')
WORKER_RE=re.compile(r'^sol-[0-9]{8}-[a-z0-9]{4,16}$')
SHA40_RE=re.compile(r'^[0-9a-f]{40}$')
BRANCH_RE=re.compile(r'^[A-Za-z0-9._/-]{1,200}$')
LANE_STATES={'PROPOSED','READY','CLAIMED','IMPLEMENTING','BLOCKED','REVIEW','NEEDS_CHANGES','INTEGRATION_READY','MERGED','VERIFYING','DONE','SUPERSEDED','CANCELLED','BLOCKED_EXTERNAL','STALE_CLAIM'}
TERMINAL_LANE_STATES={'DONE','SUPERSEDED','CANCELLED'}
RUNNABLE_LANE_STATES={'READY','CLAIMED','IMPLEMENTING','REVIEW','NEEDS_CHANGES','INTEGRATION_READY','VERIFYING'}
LANE_MODES={'exclusive','tournament'}
PHYSICAL_STATES={'SOURCE_READY','SIMULATOR_READY','DEVICE_READY','PHYSICAL_NO_GO','PHYSICAL_GO','PHYSICAL_EVIDENCE_ACCEPTED'}
EVENT_TYPES={'FINDING','BLOCKER','QUESTION','ANSWER','DECISION','DEPENDENCY_DISCOVERED','REVIEW_REQUEST','REVIEW_RESULT','HANDOFF','SCOPE_CHANGE','SUPERSEDED','EVIDENCE_RESULT','EXTERNAL_BLOCKER','INTEGRATION_RESULT','CLAIMED','HEARTBEAT','RELEASED','TAKEOVER','RESOURCE_ACQUIRED','RESOURCE_RELEASED','SCHEMA_MIGRATION','RECOVERY_RESULT'}
CLAIM_STATUSES={'ACTIVE','RELEASED','STALE'}
RESOURCE_CLASSES={'XCODE_BUILD','IOS_SIMULATOR','IOS_DEVICE','PHYSICAL_SCOOTER','BLUETOOTH_CAPTURE','SIGNING','RELEASE_INTEGRATION','PROJECT_STATE_WRITER','HIGH_CONTENTION_FILE'}
ROLE_ORDER={'repair':0,'integration':1,'adversarial-review':2,'review':3,'tests':4,'xcode-evidence':5,'accessibility':6,'performance':7,'implementation':8,'physical-evidence':9,'recovery':10}
EXTRA_ROLES={'architecture-review','ci-sheriff','scheduler-reconciler','release'}
FORBIDDEN_KEYS={'command','commands','shell','script','scripts','python','swift','applescript','exec','execute','executable','localpath','filesystempath','workingdirectory'}

class SwarmError(RuntimeError): pass
class ValidationError(SwarmError): pass
class ConflictError(SwarmError): pass
class NotFoundError(SwarmError): pass
class LeaseLostError(SwarmError): pass
class GitHubAPIError(SwarmError):
    def __init__(self,method:str,path:str,status:int,body:str):
        self.method,self.path,self.status,self.body=method,path,status,body
        super().__init__(f'GitHub API {method} {path} failed: HTTP {status}: {body[:500]}')

def utc_now(): return dt.datetime.now(dt.timezone.utc)
def format_time(v:dt.datetime):
    if v.tzinfo is None: v=v.replace(tzinfo=dt.timezone.utc)
    return v.astimezone(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00','Z')
def parse_time(v:str):
    if not isinstance(v,str) or not v: raise ValidationError('timestamp must be non-empty text')
    try: x=dt.datetime.fromisoformat(v.replace('Z','+00:00'))
    except ValueError as e: raise ValidationError(f'invalid timestamp {v!r}') from e
    if x.tzinfo is None: raise ValidationError('timestamp must include timezone')
    return x.astimezone(dt.timezone.utc)
def canonical_json(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def pretty_json(v): return json.dumps(v,sort_keys=True,indent=2,ensure_ascii=False)+'\n'
def digest_json(v): return hashlib.sha256(canonical_json(v).encode()).hexdigest()

def _dict(v,n):
    if not isinstance(v,dict): raise ValidationError(f'{n} must be object')
    return v
def _list(v,n):
    if not isinstance(v,list): raise ValidationError(f'{n} must be array')
    if len(v)>MAX_LIST_ITEMS: raise ValidationError(f'{n} too large')
    return v
def _str(v,n,max_len=MAX_TEXT_FIELD,empty=False):
    if not isinstance(v,str) or (not empty and not v): raise ValidationError(f'{n} must be text')
    if len(v)>max_len: raise ValidationError(f'{n} too long')
    return v
def _id(v,n):
    v=_str(v,n,64)
    if not ID_RE.fullmatch(v): raise ValidationError(f'invalid {n}')
    return v
def _worker(v,n='workerId'):
    v=_str(v,n,64)
    if not WORKER_RE.fullmatch(v): raise ValidationError(f'invalid {n}')
    return v
def _branch(v,n='branch',empty=True):
    v=_str(v,n,200,empty)
    if v and (not BRANCH_RE.fullmatch(v) or '..' in v or v.startswith('/') or v.endswith('/')): raise ValidationError(f'invalid {n}')
    return v
def _sha(v,n):
    v=_str(v,n,40)
    if not SHA40_RE.fullmatch(v): raise ValidationError(f'{n} must be lowercase 40-hex')
    return v
def _schema(r):
    v=r.get('schemaVersion')
    if v not in SUPPORTED_SCHEMA_VERSIONS: raise ValidationError(f'unsupported schemaVersion {v!r}')
    return v

def validate_data_only(v,path='$'):
    if isinstance(v,dict):
        key_limit=DATA_ONLY_OBJECT_KEY_LIMITS.get(path,MAX_DATA_ONLY_OBJECT_KEYS)
        if len(v)>key_limit: raise ValidationError(f'{path} too many keys')
        for k,x in v.items():
            if not isinstance(k,str) or len(k)>128: raise ValidationError(f'{path} invalid key')
            if k.lower().replace('_','').replace('-','') in FORBIDDEN_KEYS: raise ValidationError(f'{path}.{k} executable control field forbidden')
            validate_data_only(x,f'{path}.{k}')
    elif isinstance(v,list):
        if len(v)>MAX_LIST_ITEMS: raise ValidationError(f'{path} too many items')
        for i,x in enumerate(v): validate_data_only(x,f'{path}[{i}]')
    elif isinstance(v,str):
        if len(v)>MAX_TEXT_FIELD or '\x00' in v: raise ValidationError(f'{path} invalid text')
    elif v is None or isinstance(v,(bool,int,float)): pass
    else: raise ValidationError(f'{path} unsupported type')

def safe_relpath(v,n='path'):
    v=_str(v,n,300); p=PurePosixPath(v)
    if p.is_absolute() or '..' in p.parts or v.startswith('~') or '\\' in v: raise ValidationError(f'{n} must be repository-relative POSIX path')
    return str(p)

def validate_slot(s):
    s=dict(_dict(s,'slot')); _id(s.get('name'),'slot.name'); role=_id(s.get('role'),'slot.role')
    if role not in (set(ROLE_ORDER)|EXTRA_ROLES): raise ValidationError(f'unsupported role {role}')
    if not isinstance(s.get('exclusive',True),bool): raise ValidationError('slot.exclusive must be bool')
    lease=s.get('leaseSeconds',DEFAULT_REVIEW_LEASE_SECONDS if 'review' in role else DEFAULT_LEASE_SECONDS)
    if not isinstance(lease,int) or not 300<=lease<=21600: raise ValidationError('invalid slot leaseSeconds')
    s['leaseSeconds']=lease
    for r in s.get('resources',[]):
        if r not in RESOURCE_CLASSES: raise ValidationError(f'unknown resource {r}')
    if role=='implementation' and s['name']!='primary' and not s['name'].startswith('candidate-'): raise ValidationError('implementation slot must be primary or candidate-*')
    return s

def validate_lane(r):
    lane=dict(_dict(r,'lane')); validate_data_only(lane); _schema(lane)
    if lane.get('kind')!='lane': raise ValidationError('lane.kind must be lane')
    _id(lane.get('laneId'),'laneId'); lane['epic']=_id(lane.get('epic','general'),'epic'); _str(lane.get('title'),'title',300); _str(lane.get('objective'),'objective',3000)
    if lane.get('state') not in LANE_STATES: raise ValidationError('invalid lane state')
    mode=lane.get('mode','exclusive')
    if mode not in LANE_MODES: raise ValidationError('invalid lane mode')
    p=lane.get('priority',3)
    if not isinstance(p,int) or not 0<=p<=9: raise ValidationError('priority must be 0..9')
    lane['priority']=p
    lane['dependencies']=[_id(x,'dependency') for x in _list(lane.get('dependencies',[]),'dependencies')]
    for b in _list(lane.get('blockers',[]),'blockers'):
        _dict(b,'blocker'); _id(b.get('id'),'blocker.id')
        if b.get('state') not in {'ACTIVE','RESOLVED'}: raise ValidationError('invalid blocker state')
        if b.get('scope','lane') not in {'lane','epic','project','resource'}: raise ValidationError('invalid blocker scope')
    slots=[validate_slot(x) for x in _list(lane.get('slots',[]),'slots')]
    names=[x['name'] for x in slots]
    if len(names)!=len(set(names)): raise ValidationError('duplicate slot names')
    impl=[x for x in slots if x['role']=='implementation']
    if mode=='exclusive' and len(impl)>1: raise ValidationError('exclusive lane has multiple primaries')
    if mode=='tournament' and (not 2<=len(impl)<=3 or not lane.get('tournament',{}).get('authorized',False)): raise ValidationError('tournament must be authorized with 2..3 candidates')
    lane['slots']=slots
    for f in ('allowedWriteAreas','adjacentWriteAreas'): lane[f]=[safe_relpath(x,f) for x in _list(lane.get(f,[]),f)]
    acc=_dict(lane.get('acceptance',{}),'acceptance')
    if not isinstance(acc.get('independentReview',False),bool): raise ValidationError('independentReview must be bool')
    phys=_dict(lane.get('physical',{'required':False,'state':'PHYSICAL_NO_GO'}),'physical')
    if not isinstance(phys.get('required',False),bool) or phys.get('state','PHYSICAL_NO_GO') not in PHYSICAL_STATES: raise ValidationError('invalid physical state')
    lane['physical']=phys
    if lane.get('sourceSHA') is not None: _sha(lane['sourceSHA'],'sourceSHA')
    return lane

def validate_worker(r):
    x=dict(_dict(r,'worker')); validate_data_only(x); _schema(x)
    if x.get('kind')!='worker': raise ValidationError('worker.kind must be worker')
    _worker(x.get('workerId'))
    if x.get('model')!='GPT-5.6 Sol': raise ValidationError('wrong model')
    _str(x.get('status'),'status',32); _branch(x.get('branch','')); parse_time(x.get('startedAt')); parse_time(x.get('lastSeenAt')); return x

def validate_claim(r):
    x=dict(_dict(r,'claim')); validate_data_only(x); _schema(x)
    if x.get('kind') not in {'claim','resource-claim','reconciler-claim'}: raise ValidationError('invalid claim kind')
    _id(x.get('laneId'),'claim.laneId'); _id(x.get('slot'),'claim.slot'); _worker(x.get('workerId')); _id(x.get('role'),'claim.role'); _str(x.get('leaseId'),'leaseId',64)
    if not isinstance(x.get('generation'),int) or x['generation']<1: raise ValidationError('invalid generation')
    if x.get('status') not in CLAIM_STATUSES: raise ValidationError('invalid claim status')
    a,b=parse_time(x.get('claimedAt')),parse_time(x.get('lastHeartbeatAt'))
    if b<a: raise ValidationError('heartbeat predates claim')
    if not isinstance(x.get('leaseSeconds'),int) or not 300<=x['leaseSeconds']<=21600: raise ValidationError('invalid leaseSeconds')
    _branch(x.get('branch',''))
    if x.get('pr') is not None and (not isinstance(x['pr'],int) or x['pr']<=0): raise ValidationError('invalid pr')
    if x.get('sourceSHA') is not None: _sha(x['sourceSHA'],'sourceSHA')
    return x

def validate_event(r):
    x=dict(_dict(r,'event')); validate_data_only(x); _schema(x)
    if x.get('kind')!='event' or x.get('type') not in EVENT_TYPES: raise ValidationError('invalid event')
    _str(x.get('eventId'),'eventId',100); _worker(x.get('workerId')); _str(x.get('message'),'message',MAX_EVENT_MESSAGE); parse_time(x.get('createdAt'))
    if x.get('laneId') is not None: _id(x['laneId'],'laneId')
    return x

def validate_handoff(r):
    x=dict(_dict(r,'handoff')); validate_data_only(x); _schema(x)
    if x.get('kind')!='handoff': raise ValidationError('invalid handoff')
    _id(x.get('laneId'),'laneId'); _worker(x.get('workerId')); _branch(x.get('branch','')); _sha(x.get('headSHA'),'headSHA'); parse_time(x.get('createdAt')); return x

def validate_config(r):
    x=dict(_dict(r,'config')); validate_data_only(x); _schema(x)
    if x.get('kind')!='swarm-config': raise ValidationError('invalid config kind')
    x['stateBranch']=_branch(x.get('stateBranch',DEFAULT_STATE_BRANCH),'stateBranch',False)
    if x.get('rolloutMode','shadow') not in {'shadow','coordination','enforcement'}: raise ValidationError('invalid rolloutMode')
    w=_dict(x.get('wipLimits',{}),'wipLimits')
    for k in ('maxPrimaryLanes','maxPrimaryPerEpic','reviewBacklogThreshold','integrationBacklogThreshold'):
        if not isinstance(w.get(k),int) or not 0<=w[k]<=100: raise ValidationError(f'invalid wip {k}')
    order=_list(x.get('resourceOrder',[]),'resourceOrder')
    if len(order)!=len(RESOURCE_CLASSES) or len(order)!=len(set(order)) or set(order)!=RESOURCE_CLASSES: raise ValidationError('resourceOrder must contain every supported resource exactly once')
    return x

def default_config():
    return {'schemaVersion':1,'kind':'swarm-config','stateBranch':'swarm-state','rolloutMode':'shadow','wipLimits':{'maxPrimaryLanes':8,'maxPrimaryPerEpic':3,'reviewBacklogThreshold':5,'integrationBacklogThreshold':4},'resourceOrder':['PROJECT_STATE_WRITER','HIGH_CONTENTION_FILE','XCODE_BUILD','IOS_SIMULATOR','IOS_DEVICE','SIGNING','RELEASE_INTEGRATION','BLUETOOTH_CAPTURE','PHYSICAL_SCOOTER'],'physicalSafety':{'schedulerMayPromotePhysicalGo':False,'simulatorEvidenceIsPhysicalEvidence':False,'unknownTelemetryMayBeFabricated':False},'legacyPRCompatibility':'shadow-warn'}
def sample_lane(lane_id='alpha',priority=1,state='READY',deps=(),physical=False):
    return validate_lane({'schemaVersion':1,'kind':'lane','laneId':lane_id,'epic':'swarm','title':f'Lane {lane_id}','objective':'Advance one non-conflicting unit of work.','priority':priority,'state':state,'dependencies':list(deps),'blockers':[],'mode':'exclusive','allowedWriteAreas':[f'work/{lane_id}'],'adjacentWriteAreas':[f'tests/{lane_id}',f'docs/{lane_id}'],'slots':[{'name':'primary','role':'implementation','exclusive':True,'leaseSeconds':2700,'resources':[]},{'name':'tests','role':'tests','exclusive':True,'leaseSeconds':1800,'resources':[]},{'name':'review','role':'adversarial-review','exclusive':True,'leaseSeconds':1800,'resources':[]},{'name':'integration','role':'integration','exclusive':True,'leaseSeconds':1800,'resources':[]}],'acceptance':{'independentReview':True},'physical':{'required':physical,'state':'PHYSICAL_NO_GO' if physical else 'SOURCE_READY'},'tags':[]})
def claim_path(lane,slot): _id(lane,'lane'); _id(slot,'slot'); return f'.swarm/runtime/claims/{lane}/{slot}.json'
def lane_path(lane): _id(lane,'lane'); return f'.swarm/runtime/lanes/{lane}.json'
def worker_path(worker): _worker(worker); return f'.swarm/runtime/workers/{worker}.json'
def resource_path(r):
    if r not in RESOURCE_CLASSES: raise ValidationError('unknown resource')
    return f'.swarm/runtime/resources/{r.lower()}.json'
def event_path(e):
    d=parse_time(e['createdAt']); eid=_str(e['eventId'],'eventId',100)
    if not re.fullmatch(r'[0-9A-Za-z._-]+',eid): raise ValidationError('invalid eventId')
    return f".swarm/runtime/events/{d:%Y/%m/%d}/{eid}.json"
def handoff_path(lane,now): _id(lane,'lane'); return f".swarm/runtime/handoffs/{lane}/{now:%Y%m%dT%H%M%SZ}-{uuid.uuid4().hex[:12]}.json"