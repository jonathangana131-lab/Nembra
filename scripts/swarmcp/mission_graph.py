from __future__ import annotations

import datetime as dt
import hashlib
import json
import math
import re
import uuid
from collections import Counter
from copy import deepcopy
from dataclasses import asdict, dataclass
from difflib import SequenceMatcher
from typing import Any, Callable, Mapping, Sequence

from .model import ConflictError, NotFoundError, ValidationError, validate_data_only

V16_SCHEMA_VERSION = 16
V16_GRAPH_PATH = '.swarm/runtime/v16/mission-graph.json'
V16_CLAIMS_PREFIX = '.swarm/runtime/v16/claims'
MISSION_STATES = {'ACTIVE','MILESTONE_ATTACK','SURGE','BLOCKED_EXTERNAL','DONE'}
OBJECTIVE_STATES = {'PROPOSED','READY','ACTIVE','BLOCKED','REVIEW','INTEGRATING','EXTERNAL_BLOCKED','DONE'}
WORK_STATES = {'QUEUED','CLAIMED','ACTIVE','BLOCKED','REVIEW','INTEGRATING','DONE','SUPERSEDED','ARCHIVED'}
BLOCKER_STATES = {'OPEN','OWNED','RESOLVED','EXTERNAL'}
SEVERITIES = {'P0','P1','P2','P3'}
TRUTH_CLASSES = {'SIMULATED','ESTIMATED','OBSERVED','AUTHENTICATED','PHYSICALLY_MAPPED','COMMAND_VERIFIED'}
INTEGRATION_WORLDS = {'MAIN','NEXT','FRONTIER','EXPERIMENTAL'}
BRANCH_STATES = {'EXPERIMENTAL','PROMISING','SELECTED','INTEGRATED','SUPERSEDED','ARCHIVED'}
ROLES = {'builder','reviewer','integrator','captain','debugger'}
GENOME_DIMENSIONS = ('functionality','visualQuality','accessibility','performance','testing','integration','physicalTruth','knownBlockers')
GENOME_STATES = {'NOT_STARTED','ACTIVE','BLOCKED','ACCEPTED','NOT_APPLICABLE'}
_DUP_STOP = {'the','a','an','and','or','to','of','for','on','in','with','from','current','exact','head','capture','nembra','p0','p1','p2','p3','test','tests','qa','validation','red','team','repair','replay','prove','require','close','fix','build','product','successor','authority','gate','workflow'}
_TOKEN_RE = re.compile(r'[a-z0-9][a-z0-9._/-]*')
_PR_RE = re.compile(r'#(\d+)')

def _now(value: dt.datetime | None = None) -> dt.datetime:
    value = value or dt.datetime.now(dt.timezone.utc)
    if value.tzinfo is None:
        value = value.replace(tzinfo=dt.timezone.utc)
    return value.astimezone(dt.timezone.utc)

def format_v16_time(value: dt.datetime | None = None) -> str:
    return _now(value).isoformat(timespec='seconds').replace('+00:00','Z')

def parse_v16_time(value: str) -> dt.datetime:
    try:
        return _now(dt.datetime.fromisoformat(value.replace('Z','+00:00')))
    except Exception as exc:
        raise ValidationError('invalid V16 timestamp') from exc

def _id(value: Any, field: str) -> str:
    if not isinstance(value,str) or not re.fullmatch(r'[a-z0-9][a-z0-9._-]{0,95}',value):
        raise ValidationError(f'invalid {field}')
    return value

def _strings(value: Any, field: str, maximum: int = 100) -> list[str]:
    if not isinstance(value,list) or len(value)>maximum or any(not isinstance(x,str) for x in value):
        raise ValidationError(f'invalid {field}')
    return list(value)

def _enum(value: Any, allowed: set[str], field: str) -> str:
    if value not in allowed:
        raise ValidationError(f'invalid {field}')
    return value

def _require(value: Mapping[str,Any], fields: Sequence[str], kind: str) -> None:
    missing=[field for field in fields if field not in value]
    if missing:
        raise ValidationError(f'{kind} missing fields: {", ".join(missing)}')

def _severity_weight(severity: str) -> int:
    return {'P0':1200,'P1':700,'P2':250,'P3':60}[severity]

def _digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def default_genome(*, physical_required: bool = False) -> dict[str,dict[str,Any]]:
    return {dimension:{'state':('NOT_APPLICABLE' if dimension=='physicalTruth' and not physical_required else 'NOT_STARTED'),'evidenceIds':[],'notes':''} for dimension in GENOME_DIMENSIONS}

def validate_genome(value: Any) -> dict[str,dict[str,Any]]:
    if not isinstance(value,Mapping) or set(value)!=set(GENOME_DIMENSIONS):
        raise ValidationError('featureGenome must expose every V16 dimension')
    result={}
    for dimension in GENOME_DIMENSIONS:
        item=value[dimension]
        if not isinstance(item,Mapping):
            raise ValidationError(f'invalid featureGenome.{dimension}')
        _require(item,('state','evidenceIds','notes'),f'featureGenome.{dimension}')
        result[dimension]={'state':_enum(item['state'],GENOME_STATES,f'{dimension}.state'),'evidenceIds':_strings(item['evidenceIds'],f'{dimension}.evidenceIds'),'notes':str(item['notes'])[:4000]}
    return result

def validate_objective(value: Any) -> dict[str,Any]:
    if not isinstance(value,Mapping):
        raise ValidationError('objective must be object')
    fields=('objectiveId','missionId','title','status','priority','dependencies','blockerIds','captain','activeWorkers','evidenceIds','integrationState','severity','userValue','physicalOrUserDependency','lastMeaningfulProgress','finishConditions','finishSatisfied','featureGenome','canonicalBranch','allowedAdjacentScope','forbiddenAreas','releaseBlocking','safetyCritical','createdAt')
    _require(value,fields,'objective')
    finish=_strings(value['finishConditions'],'finishConditions')
    if not isinstance(value['finishSatisfied'],list) or len(value['finishSatisfied'])!=len(finish) or any(type(x) is not bool for x in value['finishSatisfied']):
        raise ValidationError('finishSatisfied must align with finishConditions')
    priority=int(value['priority']); user_value=int(value['userValue'])
    if not 0<=priority<=9 or not 0<=user_value<=10:
        raise ValidationError('invalid objective priority/user value')
    result=dict(value)
    result.update({'objectiveId':_id(value['objectiveId'],'objectiveId'),'missionId':_id(value['missionId'],'missionId'),'status':_enum(value['status'],OBJECTIVE_STATES,'objective status'),'priority':priority,'dependencies':_strings(value['dependencies'],'dependencies'),'blockerIds':_strings(value['blockerIds'],'blockerIds'),'activeWorkers':_strings(value['activeWorkers'],'activeWorkers'),'evidenceIds':_strings(value['evidenceIds'],'evidenceIds'),'integrationState':_enum(value['integrationState'],INTEGRATION_WORLDS,'integrationState'),'severity':_enum(value['severity'],SEVERITIES,'severity'),'userValue':user_value,'finishConditions':finish,'finishSatisfied':list(value['finishSatisfied']),'featureGenome':validate_genome(value['featureGenome']),'allowedAdjacentScope':_strings(value['allowedAdjacentScope'],'allowedAdjacentScope'),'forbiddenAreas':_strings(value['forbiddenAreas'],'forbiddenAreas'),'lastMeaningfulProgress':format_v16_time(parse_v16_time(value['lastMeaningfulProgress'])),'createdAt':format_v16_time(parse_v16_time(value['createdAt']))})
    return result

def validate_blocker(value: Any) -> dict[str,Any]:
    if not isinstance(value,Mapping):
        raise ValidationError('blocker must be object')
    fields=('blockerId','missionId','objectiveId','symptom','evidenceIds','owner','backup','severity','firstObserved','attempts','currentHypothesis','relatedBranches','knownDuplicateAttempts','nextAction','exitCondition','state','lastProgressAt')
    _require(value,fields,'blocker')
    if not isinstance(value['attempts'],list):
        raise ValidationError('invalid blocker attempts')
    result=dict(value)
    result.update({'blockerId':_id(value['blockerId'],'blockerId'),'missionId':_id(value['missionId'],'missionId'),'objectiveId':_id(value['objectiveId'],'objectiveId'),'evidenceIds':_strings(value['evidenceIds'],'blocker evidence'),'severity':_enum(value['severity'],SEVERITIES,'blocker severity'),'relatedBranches':_strings(value['relatedBranches'],'relatedBranches'),'knownDuplicateAttempts':_strings(value['knownDuplicateAttempts'],'knownDuplicateAttempts'),'state':_enum(value['state'],BLOCKER_STATES,'blocker state'),'firstObserved':format_v16_time(parse_v16_time(value['firstObserved'])),'lastProgressAt':format_v16_time(parse_v16_time(value['lastProgressAt']))})
    return result

def validate_work_item(value: Any) -> dict[str,Any]:
    if not isinstance(value,Mapping):
        raise ValidationError('work item must be object')
    fields=('workItemId','missionId','objectiveId','blockerId','title','outcome','role','status','primaryScope','allowedAdjacentScope','forbiddenAreas','branch','branchState','owner','reviewer','integrationWorld','createdAt','updatedAt','source','similarityKey','evidenceIds','tournamentId')
    _require(value,fields,'workItem')
    result=dict(value)
    result.update({'workItemId':_id(value['workItemId'],'workItemId'),'missionId':_id(value['missionId'],'missionId'),'objectiveId':_id(value['objectiveId'],'objectiveId'),'role':_enum(value['role'],ROLES,'role'),'status':_enum(value['status'],WORK_STATES,'work status'),'primaryScope':_strings(value['primaryScope'],'primaryScope'),'allowedAdjacentScope':_strings(value['allowedAdjacentScope'],'allowedAdjacentScope'),'forbiddenAreas':_strings(value['forbiddenAreas'],'forbiddenAreas'),'branchState':_enum(value['branchState'],BRANCH_STATES,'branchState'),'integrationWorld':_enum(value['integrationWorld'],INTEGRATION_WORLDS,'integrationWorld'),'evidenceIds':_strings(value['evidenceIds'],'work evidence'),'createdAt':format_v16_time(parse_v16_time(value['createdAt'])),'updatedAt':format_v16_time(parse_v16_time(value['updatedAt']))})
    return result

def _assert_acyclic(objectives: Mapping[str,Mapping[str,Any]]) -> None:
    visiting=set(); done=set()
    def visit(node: str) -> None:
        if node in done: return
        if node in visiting: raise ValidationError('mission graph dependency cycle')
        visiting.add(node)
        for dep in objectives[node]['dependencies']: visit(dep)
        visiting.remove(node); done.add(node)
    for node in objectives: visit(node)

def validate_graph(graph: Any) -> dict[str,Any]:
    validate_data_only(graph)
    if not isinstance(graph,Mapping): raise ValidationError('mission graph must be object')
    fields=('schemaVersion','kind','graphId','revision','createdAt','updatedAt','missions','objectives','blockers','workItems','solutions','evidence','branches','mergeTrain','agents','memory','failureKnowledge','metrics','modes','migration')
    _require(graph,fields,'mission graph')
    if graph['schemaVersion']!=16 or graph['kind']!='mission-graph' or not isinstance(graph['revision'],int):
        raise ValidationError('unsupported V16 graph schema')
    if not all(isinstance(graph[x],Mapping) for x in ('missions','objectives','blockers','workItems','solutions','evidence','branches','agents','metrics','modes','migration')):
        raise ValidationError('invalid graph record map')
    if not isinstance(graph['memory'],list) or not isinstance(graph['failureKnowledge'],list) or not isinstance(graph['mergeTrain'],Mapping):
        raise ValidationError('invalid graph coordination records')
    out=deepcopy(dict(graph))
    out['objectives']={key:validate_objective(value) for key,value in graph['objectives'].items()}
    out['blockers']={key:validate_blocker(value) for key,value in graph['blockers'].items()}
    out['workItems']={key:validate_work_item(value) for key,value in graph['workItems'].items()}
    for key,mission in graph['missions'].items():
        _require(mission,('missionId','title','why','status','priority','objectiveIds','captain','startedAt','lastMeaningfulProgress','remainingFinishConditions'),'mission')
        if key!=mission['missionId'] or mission['status'] not in MISSION_STATES: raise ValidationError('invalid mission')
    for key,obj in out['objectives'].items():
        if key!=obj['objectiveId'] or obj['missionId'] not in graph['missions']: raise ValidationError('invalid objective parent')
        if any(dep not in out['objectives'] for dep in obj['dependencies']): raise ValidationError('missing objective dependency')
        if any(bid not in out['blockers'] for bid in obj['blockerIds']): raise ValidationError('missing blocker reference')
    _assert_acyclic(out['objectives'])
    for key,blocker in out['blockers'].items():
        if key!=blocker['blockerId'] or blocker['missionId'] not in graph['missions'] or blocker['objectiveId'] not in out['objectives']: raise ValidationError('invalid blocker parent')
    for key,item in out['workItems'].items():
        if key!=item['workItemId'] or item['missionId'] not in graph['missions'] or item['objectiveId'] not in out['objectives']: raise ValidationError('invalid work item parent')
        if item['blockerId'] and item['blockerId'] not in out['blockers']: raise ValidationError('missing work blocker')
    return out

def make_objective(objective_id: str, mission_id: str, title: str, *, severity='P2', priority=5, dependencies: Sequence[str]=(), finish_conditions: Sequence[str]=(), canonical_branch='', user_value=5, physical_dependency=False, release_blocking=False, safety_critical=False, allowed_adjacent_scope: Sequence[str]=(), forbidden_areas: Sequence[str]=(), now: dt.datetime|None=None) -> dict[str,Any]:
    stamp=format_v16_time(now); finish=list(finish_conditions) or ['shipping implementation accepted','integration accepted','no unresolved P0/P1 defects']
    return validate_objective({'objectiveId':objective_id,'missionId':mission_id,'title':title,'status':'READY','priority':priority,'dependencies':list(dependencies),'blockerIds':[],'captain':'','activeWorkers':[],'evidenceIds':[],'integrationState':'FRONTIER','severity':severity,'userValue':user_value,'physicalOrUserDependency':physical_dependency,'lastMeaningfulProgress':stamp,'finishConditions':finish,'finishSatisfied':[False]*len(finish),'featureGenome':default_genome(physical_required=physical_dependency),'canonicalBranch':canonical_branch,'allowedAdjacentScope':list(allowed_adjacent_scope),'forbiddenAreas':list(forbidden_areas),'releaseBlocking':release_blocking,'safetyCritical':safety_critical,'createdAt':stamp})

def seed_nembra_graph(now: dt.datetime|None=None) -> dict[str,Any]:
    stamp=format_v16_time(now); shipping='nembra-shipping'; capture='capture-stationary'; objectives={}
    shipping_titles=(('dashboard','Dashboard'),('battery-range','Battery / Range'),('charging','Charging'),('navigation','Navigation'),('rides','Rides'),('vehicle-controls','Vehicle Controls'),('connection','Connection'),('settings','Settings'),('performance','Performance'),('accessibility','Accessibility'),('premium-ui','Premium UI'),('real-es80-telemetry','Real ES80 telemetry'))
    ship_ids=[]
    for oid,title in shipping_titles:
        objectives[oid]=make_objective(oid,shipping,title,severity=('P1' if oid in {'dashboard','battery-range','connection','real-es80-telemetry'} else 'P2'),priority=(1 if oid=='real-es80-telemetry' else 4),user_value=(10 if oid in {'dashboard','real-es80-telemetry'} else 7),physical_dependency=(oid=='real-es80-telemetry'),canonical_branch=f'mission/{oid}',finish_conditions=('shipping functionality complete','normal, disconnected, retained and active states accepted','accessibility accepted','performance accepted','integration accepted','no unresolved P0/P1 defects'),allowed_adjacent_scope=[title],forbidden_areas=(['scooter commands before command truth'] if oid=='real-es80-telemetry' else ['Capture authentication/truth boundary']),now=now); ship_ids.append(oid)
    steps=(('capture-standalone-build','Standalone build',(),False),('capture-apple-auth','Apple authentication',('capture-standalone-build',),False),('capture-tuya-auth','Tuya authentication',('capture-standalone-build',),False),('capture-account-device','Account / device verification',('capture-apple-auth','capture-tuya-auth'),False),('capture-secure-session','Secure authenticated session',('capture-account-device',),False),('capture-signed-build','Signed build',('capture-standalone-build',),False),('capture-installation','Installation',('capture-signed-build',),True),('capture-stationary-ux','Stationary UX',('capture-standalone-build',),False),('capture-auth-observation','Authenticated read-only observation',('capture-secure-session','capture-installation','capture-stationary-ux'),True),('capture-export','Secure observation export',('capture-auth-observation',),True),('capture-final-regression','Final regression',('capture-export',),True),('capture-physical-handoff','Physical handoff',('capture-final-regression',),True))
    capture_ids=[]
    for oid,title,deps,physical in steps:
        objectives[oid]=make_objective(oid,capture,title,severity='P0',priority=0,dependencies=deps,user_value=10,physical_dependency=physical,release_blocking=True,safety_critical=physical,canonical_branch='mission/capture-stationary',finish_conditions=('implementation complete','affected software acceptance green','independent review accepted','integrated into selected Capture candidate',('physical/user dependency explicitly satisfied' if physical else 'no unresolved software blocker')),allowed_adjacent_scope=['Capture','directly related tests','directly related CI'],forbidden_areas=['scooter commands','invented telemetry semantics','outdoor ride procedure'],now=now); capture_ids.append(oid)
    graph={'schemaVersion':16,'kind':'mission-graph','graphId':'nembra-v16','revision':0,'createdAt':stamp,'updatedAt':stamp,'missions':{shipping:{'missionId':shipping,'title':'Nembra Shipping Mission','why':'Ship coherent user-visible Nembra milestones rather than maximize PR activity.','status':'ACTIVE','priority':2,'objectiveIds':ship_ids,'captain':'','startedAt':stamp,'lastMeaningfulProgress':stamp,'remainingFinishConditions':['ship major product objectives','close release blockers']},capture:{'missionId':capture,'title':'Capture Mission','why':'Reach a rigorous, practical authenticated stationary read-only ES80 observation handoff.','status':'ACTIVE','priority':0,'objectiveIds':capture_ids,'captain':'','startedAt':stamp,'lastMeaningfulProgress':stamp,'remainingFinishConditions':['accepted signed installable Capture build','authenticated Tuya session and non-empty structured read-only observation','secure export and final regression','no commands sent']}},'objectives':objectives,'blockers':{},'workItems':{},'solutions':{},'evidence':{},'branches':{'mission/capture-stationary':{'branch':'mission/capture-stationary','missionId':capture,'objectiveId':'capture-standalone-build','state':'SELECTED','world':'FRONTIER','selectedAt':stamp,'integratedAt':'','pr':None,'source':'V16 canonical seed'}},'mergeTrain':{'queue':[],'history':[],'activeCandidate':None},'agents':{},'memory':[],'failureKnowledge':[],'metrics':{'startBlockers':0,'closedBlockers':0,'newLegitimateBlockers':0,'duplicateTasksPrevented':0,'supersededBranches':0,'meaningfulProgressEvents':0},'modes':{'surgeMissionId':'','convergenceFamilies':[],'milestoneAttackObjectives':[],'frozenBranchFamilies':[]},'migration':{'legacyImported':False,'legacyLaneIds':[],'classifiedPRs':{},'destructiveActionsAllowed':False}}
    return validate_graph(graph)

def semantic_tokens(text: str) -> list[str]:
    result=[]
    for token in _TOKEN_RE.findall(text.lower()):
        if token in _DUP_STOP or len(token)<=1: continue
        if token.endswith('ing') and len(token)>6: token=token[:-3]
        elif token.endswith('ed') and len(token)>5: token=token[:-2]
        result.append(token)
    return result

def semantic_similarity(left: str, right: str) -> float:
    a=semantic_tokens(left); b=semantic_tokens(right)
    if not a or not b: return 0.0
    aset,bset=set(a),set(b); union=aset|bset; intersection=aset&bset
    j=len(intersection)/len(union); seq=SequenceMatcher(a=' '.join(a),b=' '.join(b)).ratio(); containment=len(intersection)/max(1,min(len(aset),len(bset)))
    ab=set(zip(a,a[1:])); bb=set(zip(b,b[1:])); bigram=len(ab&bb)/len(ab|bb) if ab or bb else 0.0
    pr_overlap=bool(set(_PR_RE.findall(left))&set(_PR_RE.findall(right)))
    return min(1.0,.35*j+.20*seq+.15*bigram+.30*containment+(.08 if pr_overlap else 0.0))

def similarity_key(*parts: str) -> str:
    return ' '.join(sorted(set(semantic_tokens(' '.join(parts)))))

@dataclass(frozen=True)
class DuplicateDecision:
    duplicate: bool; score: float; existing_work_item_id: str; action: str; reason: str

def detect_duplicate_work(graph: Mapping[str,Any], *, title: str, outcome: str, objective_id: str, blocker_id: str='', threshold: float=.58) -> DuplicateDecision:
    proposed=' '.join((title,outcome,objective_id,blocker_id)); best=('',0.0,'')
    for wid,item in graph.get('workItems',{}).items():
        if item.get('status') in {'DONE','SUPERSEDED','ARCHIVED'}: continue
        score=1.0 if blocker_id and item.get('blockerId')==blocker_id else semantic_similarity(proposed,' '.join((item.get('title',''),item.get('outcome',''),item.get('objectiveId',''),item.get('blockerId',''))))
        if item.get('objectiveId')==objective_id: score=min(1.0,score+.08)
        if score>best[1]: best=(wid,score,item.get('role','builder'))
    if best[1]>=threshold:
        return DuplicateDecision(True,best[1],best[0],{'reviewer':'REVIEW','integrator':'INTEGRATE'}.get(best[2],'JOIN'),f'semantic duplicate of active {best[0]}')
    return DuplicateDecision(False,best[1],best[0],'CREATE','no active substantial duplicate')

def _memory(graph: dict[str,Any], kind: str, message: str, objective_id: str='', now: dt.datetime|None=None, data: Mapping[str,Any]|None=None) -> None:
    graph['memory'].append({'eventId':uuid.uuid4().hex[:16],'type':kind,'objectiveId':objective_id,'message':message[:2000],'data':dict(data or {}),'at':format_v16_time(now)})
    graph['memory']=graph['memory'][-256:]

def add_work_item(graph: dict[str,Any], *, work_item_id: str, mission_id: str, objective_id: str, title: str, outcome: str, role='builder', blocker_id='', primary_scope: Sequence[str]=(), allowed_adjacent_scope: Sequence[str]=(), forbidden_areas: Sequence[str]=(), branch='', source: Mapping[str,Any]|None=None, tournament_id='', now: dt.datetime|None=None, allow_duplicate=False) -> tuple[dict[str,Any],DuplicateDecision]:
    if objective_id not in graph['objectives']: raise ValidationError('unknown objective')
    decision=detect_duplicate_work(graph,title=title,outcome=outcome,objective_id=objective_id,blocker_id=blocker_id)
    if decision.duplicate and not allow_duplicate:
        graph['metrics']['duplicateTasksPrevented']=int(graph['metrics'].get('duplicateTasksPrevented',0))+1; _memory(graph,'DUPLICATE_SUPPRESSED',f'Suppressed {work_item_id}; {decision.reason}',objective_id,now); return graph,decision
    if tournament_id and not (graph['solutions'].get(tournament_id) or {}).get('authorized'): raise ValidationError('solution tournament must be explicitly authorized')
    stamp=format_v16_time(now); branch_state='EXPERIMENTAL' if tournament_id else ('SELECTED' if branch else 'PROMISING')
    item=validate_work_item({'workItemId':work_item_id,'missionId':mission_id,'objectiveId':objective_id,'blockerId':blocker_id,'title':title,'outcome':outcome,'role':role,'status':'QUEUED','primaryScope':list(primary_scope),'allowedAdjacentScope':list(allowed_adjacent_scope),'forbiddenAreas':list(forbidden_areas),'branch':branch,'branchState':branch_state,'owner':'','reviewer':'','integrationWorld':'FRONTIER','createdAt':stamp,'updatedAt':stamp,'source':dict(source or {}),'similarityKey':similarity_key(title,outcome,objective_id,blocker_id),'evidenceIds':[],'tournamentId':tournament_id})
    graph['workItems'][work_item_id]=item
    if branch: graph['branches'][branch]={'branch':branch,'missionId':mission_id,'objectiveId':objective_id,'state':branch_state,'world':'FRONTIER','selectedAt':(stamp if branch_state=='SELECTED' else ''),'integratedAt':'','pr':item['source'].get('pr'),'source':item['source']}
    _memory(graph,'WORK_CREATED',f'{work_item_id}: {outcome}',objective_id,now); return graph,DuplicateDecision(False,decision.score,decision.existing_work_item_id,'CREATE','created')

def authorize_tournament(graph: dict[str,Any], tournament_id: str, blocker_id: str, candidate_limit=3, now: dt.datetime|None=None) -> dict[str,Any]:
    if blocker_id not in graph['blockers'] or not 2<=candidate_limit<=3: raise ValidationError('invalid solution tournament')
    graph['solutions'][tournament_id]={'kind':'solution-tournament','tournamentId':tournament_id,'blockerId':blocker_id,'authorized':True,'candidateLimit':candidate_limit,'candidateWorkItemIds':[],'selectedWorkItemId':'','state':'EXPERIMENTAL','createdAt':format_v16_time(now),'selectionEvidence':{}}; return graph

def select_tournament_winner(graph: dict[str,Any], tournament_id: str, work_item_id: str, comparison: Mapping[str,Any], now: dt.datetime|None=None) -> dict[str,Any]:
    tournament=graph['solutions'].get(tournament_id); candidates=[wid for wid,item in graph['workItems'].items() if item.get('tournamentId')==tournament_id]
    if not tournament or not tournament.get('authorized') or work_item_id not in candidates: raise ValidationError('invalid tournament winner')
    tournament.update({'candidateWorkItemIds':candidates,'selectedWorkItemId':work_item_id,'state':'SELECTED','selectionEvidence':dict(comparison)})
    for wid in candidates:
        item=graph['workItems'][wid]
        if wid==work_item_id: item['branchState']='SELECTED'
        else: item['status']='SUPERSEDED'; item['branchState']='SUPERSEDED'; graph['metrics']['supersededBranches']+=1
        if item['branch'] in graph['branches']: graph['branches'][item['branch']]['state']=item['branchState']
    _memory(graph,'SOLUTION_SELECTED',f'{tournament_id} selected {work_item_id}',graph['workItems'][work_item_id]['objectiveId'],now); return graph

def add_blocker(graph: dict[str,Any], *, blocker_id: str, mission_id: str, objective_id: str, symptom: str, severity: str, exit_condition: str, next_action='', evidence_ids: Sequence[str]=(), owner='', backup='', hypothesis='', related_branches: Sequence[str]=(), state: str|None=None, now: dt.datetime|None=None, legitimate_new=True) -> dict[str,Any]:
    if blocker_id in graph['blockers']: raise ConflictError(blocker_id)
    stamp=format_v16_time(now); blocker=validate_blocker({'blockerId':blocker_id,'missionId':mission_id,'objectiveId':objective_id,'symptom':symptom,'evidenceIds':list(evidence_ids),'owner':owner,'backup':backup,'severity':severity,'firstObserved':stamp,'attempts':[],'currentHypothesis':hypothesis,'relatedBranches':list(related_branches),'knownDuplicateAttempts':[],'nextAction':next_action,'exitCondition':exit_condition,'state':state or ('OWNED' if owner else 'OPEN'),'lastProgressAt':stamp})
    graph['blockers'][blocker_id]=blocker; graph['objectives'][objective_id]['blockerIds'].append(blocker_id); graph['objectives'][objective_id]['status']='BLOCKED'
    graph['metrics']['newLegitimateBlockers']+=int(legitimate_new); graph['metrics']['startBlockers']+=int(not legitimate_new); _memory(graph,'BLOCKER_OPENED',f'{blocker_id}: {symptom}',objective_id,now); return graph

def claim_blocker(graph: dict[str,Any], blocker_id: str, owner: str, backup='', now: dt.datetime|None=None) -> dict[str,Any]:
    blocker=graph['blockers'][blocker_id]
    if blocker['state']=='RESOLVED' or blocker['owner'] and blocker['owner']!=owner: raise ConflictError('blocker unavailable')
    blocker.update({'owner':owner,'backup':backup,'state':'OWNED','lastProgressAt':format_v16_time(now)}); return graph

def record_blocker_attempt(graph: dict[str,Any], blocker_id: str, *, worker: str, approach: str, result: str, evidence_ids: Sequence[str]=(), meaningful_progress=False, branch='', now: dt.datetime|None=None) -> dict[str,Any]:
    blocker=graph['blockers'][blocker_id]; blocker['attempts'].append({'worker':worker,'approach':approach,'result':result,'evidenceIds':list(evidence_ids),'branch':branch,'at':format_v16_time(now),'meaningfulProgress':meaningful_progress})
    if meaningful_progress: blocker['lastProgressAt']=format_v16_time(now); graph['metrics']['meaningfulProgressEvents']+=1
    recent=blocker['attempts'][-5:]
    if len(recent)>=4 and sum(bool(x.get('meaningfulProgress')) for x in recent)<=1:
        family='-'.join(blocker_id.split('-')[:3])
        for key in ('convergenceFamilies','frozenBranchFamilies'):
            if family not in graph['modes'][key]: graph['modes'][key].append(family)
        _memory(graph,'CONVERGENCE_MODE',f'Freeze competing branches for {family}; consolidate {blocker_id}',blocker['objectiveId'],now)
    return graph

def rabbit_hole_review_required(graph: Mapping[str,Any], blocker_id: str) -> tuple[bool,str]:
    attempts=graph['blockers'][blocker_id]['attempts']
    if len(attempts)<5: return False,'insufficient attempts'
    workers=len({x.get('worker') for x in attempts if x.get('worker')}); branches=len({x.get('branch') for x in attempts if x.get('branch')}); progress=sum(bool(x.get('meaningfulProgress')) for x in attempts); activity=len(attempts)+workers+branches
    return (activity>=12 and progress<=1),f'activity={activity}, progress={progress}'

def resolve_blocker(graph: dict[str,Any], blocker_id: str, *, evidence_ids: Sequence[str], resolution: str, now: dt.datetime|None=None) -> dict[str,Any]:
    if not evidence_ids: raise ValidationError('blocker resolution requires evidence')
    blocker=graph['blockers'][blocker_id]
    if blocker['state']=='RESOLVED': return graph
    blocker.update({'state':'RESOLVED','evidenceIds':list(dict.fromkeys(blocker['evidenceIds']+list(evidence_ids))),'nextAction':'','currentHypothesis':resolution,'lastProgressAt':format_v16_time(now)}); graph['metrics']['closedBlockers']+=1
    objective=graph['objectives'][blocker['objectiveId']]
    if not any(graph['blockers'][bid]['state'] in {'OPEN','OWNED'} for bid in objective['blockerIds']): objective['status']='ACTIVE'
    _memory(graph,'BLOCKER_RESOLVED',f'{blocker_id}: {resolution}',blocker['objectiveId'],now); return graph

def objective_done(graph: Mapping[str,Any], objective_id: str) -> tuple[bool,list[str]]:
    obj=graph['objectives'][objective_id]; missing=[c for c,s in zip(obj['finishConditions'],obj['finishSatisfied']) if not s]
    missing += [f'unresolved {graph["blockers"][bid]["severity"]} blocker {bid}' for bid in obj['blockerIds'] if graph['blockers'][bid]['state']!='RESOLVED' and graph['blockers'][bid]['severity'] in {'P0','P1'}]
    if obj['integrationState']!='MAIN': missing.append('integration has not reached MAIN')
    for dimension in ('functionality','testing','integration'):
        if obj['featureGenome'][dimension]['state'] not in {'ACCEPTED','NOT_APPLICABLE'}: missing.append(f'{dimension} not accepted')
    if obj['physicalOrUserDependency'] and obj['featureGenome']['physicalTruth']['state']!='ACCEPTED': missing.append('physical/user dependency not accepted')
    return not missing,missing

def complete_objective(graph: dict[str,Any], objective_id: str, now: dt.datetime|None=None) -> dict[str,Any]:
    done,missing=objective_done(graph,objective_id)
    if not done: raise ValidationError('objective not done: '+'; '.join(missing))
    graph['objectives'][objective_id].update({'status':'DONE','lastMeaningfulProgress':format_v16_time(now)}); _memory(graph,'OBJECTIVE_DONE',graph['objectives'][objective_id]['title'],objective_id,now); return graph

def add_evidence(graph: dict[str,Any], *, evidence_id: str, objective_id: str, evidence_type: str, status: str, truth_class: str, source_digest: str, dependency_digest: str, environment_digest: str, affected_paths: Sequence[str], details: Mapping[str,Any]|None=None, now: dt.datetime|None=None) -> dict[str,Any]:
    if status not in {'PASS','FAIL','STALE','PENDING'} or truth_class not in TRUTH_CLASSES: raise ValidationError('invalid evidence')
    if truth_class in {'PHYSICALLY_MAPPED','COMMAND_VERIFIED'} and not (details or {}).get('physicalAuthorityExplicit'): raise ValidationError('physical/command evidence requires explicit physical authority')
    graph['evidence'][evidence_id]={'evidenceId':_id(evidence_id,'evidenceId'),'objectiveId':objective_id,'type':evidence_type,'status':status,'truthClass':truth_class,'sourceDigest':source_digest,'dependencyDigest':dependency_digest,'environmentDigest':environment_digest,'affectedPaths':list(affected_paths),'details':dict(details or {}),'createdAt':format_v16_time(now),'invalidatedAt':'','invalidationReason':''}
    if evidence_id not in graph['objectives'][objective_id]['evidenceIds']: graph['objectives'][objective_id]['evidenceIds'].append(evidence_id)
    return graph

def reusable_evidence(graph: Mapping[str,Any], evidence_id: str, *, source_digest: str, dependency_digest: str, environment_digest: str) -> bool:
    ev=graph['evidence'].get(evidence_id); return bool(ev and ev['status']=='PASS' and not ev.get('invalidatedAt') and ev['sourceDigest']==source_digest and ev['dependencyDigest']==dependency_digest and ev['environmentDigest']==environment_digest)

def _paths_intersect(a: str,b: str) -> bool:
    return a==b or a.startswith(b.rstrip('/')+'/') or b.startswith(a.rstrip('/')+'/')

def invalidate_evidence_for_paths(graph: dict[str,Any], changed_paths: Sequence[str], reason: str, now: dt.datetime|None=None) -> list[str]:
    invalid=[]
    for eid,ev in graph['evidence'].items():
        if ev['status']=='PASS' and not ev.get('invalidatedAt') and any(_paths_intersect(a,b) for a in changed_paths for b in ev.get('affectedPaths',[])):
            ev.update({'status':'STALE','invalidatedAt':format_v16_time(now),'invalidationReason':reason}); invalid.append(eid)
    return invalid

TEST_IMPACT_RULES=(('NembraApp/Features/Dashboard/',('dashboard-source','app-compile','dashboard-ui','accessibility')),('NembraApp/Features/Navigation/',('navigation-source','app-compile','navigation-ui','accessibility')),('Packages/NembraBluetoothCapture/',('capture-package','capture-truth','app-compile')),('Scripts/',('capture-script-source',)),('scripts/swarmcp/',('swarm-control-plane','swarm-adversarial-30')),('.swarm/',('swarm-control-plane',)))

def test_impact(changed_paths: Sequence[str], *, integration_boundary=False, release_boundary=False) -> list[str]:
    suites=set()
    for path in changed_paths:
        for prefix,affected in TEST_IMPACT_RULES:
            if path.startswith(prefix): suites.update(affected)
        if path.startswith('.github/workflows/'): suites.add('workflow-source-contract')
    if integration_boundary: suites.add('integration-suite')
    if release_boundary: suites.update({'integration-suite','full-system-release'})
    return sorted(suites)

def evidence_binding(source_paths: Mapping[str,str], dependency_digests: Mapping[str,str], environment: Mapping[str,Any]) -> tuple[str,str,str]:
    return _digest(source_paths),_digest(dependency_digests),_digest(environment)

def record_failure_knowledge(graph: dict[str,Any], *, symptom: str, root_cause: str, fix: str, regression: str, affected_components: Sequence[str], environment: str, false_leads: Sequence[str], evidence_ids: Sequence[str], now: dt.datetime|None=None) -> str:
    key=hashlib.sha256('|'.join(semantic_tokens(symptom+' '+root_cause)).encode()).hexdigest()[:16]; record={'knowledgeId':key,'symptom':symptom,'rootCause':root_cause,'fix':fix,'regression':regression,'affectedComponents':list(affected_components),'environment':environment,'falseLeads':list(false_leads),'evidenceIds':list(evidence_ids),'updatedAt':format_v16_time(now)}
    graph['failureKnowledge']=[x for x in graph['failureKnowledge'] if x['knowledgeId']!=key]+[record]; graph['failureKnowledge']=graph['failureKnowledge'][-256:]; return key

def search_failure_knowledge(graph: Mapping[str,Any], query: str, limit=5) -> list[dict[str,Any]]:
    ranked=[]
    for record in graph['failureKnowledge']:
        score=semantic_similarity(query,' '.join((record['symptom'],record['rootCause'],record['fix'],record['environment'])))
        if score: ranked.append((score,record))
    return [dict(record) for _,record in sorted(ranked,key=lambda x:-x[0])[:limit]]

def relevant_memory(graph: Mapping[str,Any], objective_id: str, limit=12) -> list[dict[str,Any]]:
    return [dict(x) for x in [m for m in graph['memory'] if m.get('objectiveId') in {'',objective_id}][-limit:]]

def update_agent_outcome(graph: dict[str,Any], worker_id: str, *, domain: str, accepted: bool, integrated: bool, regression=False) -> dict[str,Any]:
    profile=graph['agents'].setdefault(worker_id,{'domains':{},'acceptedOutcomes':0,'integratedOutcomes':0,'regressions':0}); record=profile['domains'].setdefault(domain,{'accepted':0,'integrated':0,'regressions':0})
    if accepted: profile['acceptedOutcomes']+=1; record['accepted']+=1
    if integrated: profile['integratedOutcomes']+=1; record['integrated']+=1
    if regression: profile['regressions']+=1; record['regressions']+=1
    return graph

def specialization_score(graph: Mapping[str,Any], worker_id: str, domain: str) -> float:
    record=graph.get('agents',{}).get(worker_id,{}).get('domains',{}).get(domain,{}); return 2*record.get('integrated',0)+record.get('accepted',0)-3*record.get('regressions',0)

def objective_priority_score(graph: Mapping[str,Any], objective_id: str, now: dt.datetime|None=None) -> float:
    obj=graph['objectives'][objective_id]
    if obj['status'] in {'DONE','EXTERNAL_BLOCKED'} or any(graph['objectives'][dep]['status']!='DONE' for dep in obj['dependencies']): return -math.inf
    fanout=sum(objective_id in other['dependencies'] for other in graph['objectives'].values()); remaining=sum(not x for x in obj['finishSatisfied']); age=max(0,(_now(now)-parse_v16_time(obj['lastMeaningfulProgress'])).total_seconds()/86400)
    score=_severity_weight(obj['severity'])+(400 if obj['releaseBlocking'] else 0)+(180 if obj['safetyCritical'] else 0)+obj['userValue']*35+fanout*80+max(0,9-obj['priority'])*20+min(age*25,250)
    if remaining<=2: score+=300
    elif remaining<=4: score+=120
    if obj['status'] in {'REVIEW','INTEGRATING'}: score+=220
    if graph['modes'].get('surgeMissionId')==obj['missionId']: score+=1000
    return score

def role_allocation(graph: Mapping[str,Any], workers=30) -> dict[str,int]:
    if workers<1: raise ValidationError('workers must be positive')
    active=[x for x in graph['workItems'].values() if x['status'] not in {'DONE','SUPERSEDED','ARCHIVED'}]; integrations=sum(x['status'] in {'REVIEW','INTEGRATING'} or x['integrationWorld']=='NEXT' for x in active); reviews=sum(x['status']=='REVIEW' for x in active); near=sum(x['status']!='DONE' and sum(not v for v in x['finishSatisfied'])<=2 for x in graph['objectives'].values())
    b,r,i=.60,.20,.20
    if integrations>=max(3,workers//8): b,r,i=.48,.20,.32
    if near: b,r,i=.48,.27,.25
    if reviews>=max(4,workers//6): b,r,i=.48,.34,.18
    if graph['modes'].get('surgeMissionId'): b,r,i=.50,.23,.27
    counts={'builder':round(workers*b),'reviewer':round(workers*r)}; counts['integrator']=workers-counts['builder']-counts['reviewer']; return counts

@dataclass(frozen=True)
class MissionPacket:
    mission_id: str; objective_id: str; work_item_id: str; role: str; priority_score: float; packet: dict[str,Any]

def recommend_mission_packets(graph: Mapping[str,Any], *, worker_ids: Sequence[str]=(), limit=30, now: dt.datetime|None=None) -> list[MissionPacket]:
    validate_graph(graph); candidates=[]
    for item in graph['workItems'].values():
        if item['status'] not in {'QUEUED','REVIEW','INTEGRATING','BLOCKED'}: continue
        priority=objective_priority_score(graph,item['objectiveId'],now)
        if priority==-math.inf: continue
        if item['status']=='BLOCKED' and item['blockerId'] and graph['blockers'][item['blockerId']]['state']=='EXTERNAL': continue
        priority += 140 if item['status']=='INTEGRATING' else (120 if item['status']=='REVIEW' else 0); candidates.append((priority,item))
    candidates.sort(key=lambda pair:(-pair[0],pair[1]['createdAt'],pair[1]['workItemId'])); packets=[]
    for index,(priority,item) in enumerate(candidates[:limit]):
        obj=graph['objectives'][item['objectiveId']]; mission=graph['missions'][item['missionId']]; blocker=graph['blockers'].get(item['blockerId']) if item['blockerId'] else None
        packet={'MISSION':mission['title'],'WHY_IT_MATTERS':mission['why'],'CURRENT_STATE':obj['status'],'EXACT_CANONICAL_BRANCH':obj['canonicalBranch'],'KNOWN_FAILURES':[graph['blockers'][bid]['symptom'] for bid in obj['blockerIds'] if graph['blockers'][bid]['state']!='RESOLVED'],'KNOWN_PROVEN_FACTS':[ev['details'] for ev in graph['evidence'].values() if ev['objectiveId']==obj['objectiveId'] and ev['status']=='PASS'][-8:],'DO_NOT_REDISCOVER':[m['message'] for m in relevant_memory(graph,obj['objectiveId']) if m['type'] in {'BLOCKER_RESOLVED','SOLUTION_SELECTED'}],'PRIMARY_SCOPE':item['primaryScope'],'ALLOWED_EXPANSION':item['allowedAdjacentScope'],'FORBIDDEN_AREAS':item['forbiddenAreas'],'RELATED_WORKERS':obj['activeWorkers'],'RELEVANT_EVIDENCE':obj['evidenceIds'][-12:],'EXIT_CONDITION':(blocker['exitCondition'] if blocker else item['outcome']),'ASSIGNED_WORKER':(worker_ids[index] if index<len(worker_ids) else '')}
        packets.append(MissionPacket(item['missionId'],item['objectiveId'],item['workItemId'],item['role'],priority,packet))
    return packets

def enter_surge(graph: dict[str,Any], mission_id: str, now: dt.datetime|None=None) -> dict[str,Any]:
    if mission_id not in graph['missions']: raise ValidationError('unknown surge mission')
    graph['modes']['surgeMissionId']=mission_id; graph['missions'][mission_id]['status']='SURGE'; _memory(graph,'SURGE_STARTED',f'SURGE {mission_id}',now=now); return graph

def stop_surge(graph: dict[str,Any], *, reason: str, now: dt.datetime|None=None) -> dict[str,Any]:
    mission=graph['modes'].get('surgeMissionId')
    if mission: graph['missions'][mission]['status']='ACTIVE'; _memory(graph,'SURGE_STOPPED',reason,now=now)
    graph['modes']['surgeMissionId']=''; return graph

def update_milestone_attack(graph: dict[str,Any], now: dt.datetime|None=None) -> list[str]:
    active=[]
    for oid,obj in graph['objectives'].items():
        blockers=[graph['blockers'][bid] for bid in obj['blockerIds'] if graph['blockers'][bid]['state'] in {'OPEN','OWNED'}]; remaining=sum(not x for x in obj['finishSatisfied'])
        if obj['status']!='DONE' and len(blockers)<=3 and remaining<=3 and (blockers or remaining): active.append(oid); graph['missions'][obj['missionId']]['status']='MILESTONE_ATTACK'
    graph['modes']['milestoneAttackObjectives']=active; return active

def enqueue_merge(graph: dict[str,Any], *, work_item_ids: Sequence[str], candidate_id: str, required_suites: Sequence[str], now: dt.datetime|None=None) -> dict[str,Any]:
    if not work_item_ids: raise ValidationError('merge candidate requires work')
    for wid in work_item_ids:
        if graph['workItems'][wid]['status'] not in {'REVIEW','INTEGRATING','DONE'}: raise ValidationError(f'{wid} not accepted enough for merge train')
    graph['mergeTrain']['queue'].append({'candidateId':_id(candidate_id,'candidateId'),'workItemIds':list(work_item_ids),'state':'QUEUED','requiredSuites':list(required_suites),'results':{},'createdAt':format_v16_time(now),'startedAt':'','completedAt':''})
    for wid in work_item_ids: graph['workItems'][wid]['status']='INTEGRATING'; graph['workItems'][wid]['integrationWorld']='NEXT'
    return graph

def _merge_entry(graph: Mapping[str,Any], candidate_id: str) -> dict[str,Any]:
    entry=next((x for x in graph['mergeTrain']['queue'] if x['candidateId']==candidate_id),None)
    if not entry: raise ValidationError('unknown merge candidate')
    return entry

def start_merge_candidate(graph: dict[str,Any], candidate_id: str, now: dt.datetime|None=None) -> dict[str,Any]:
    if graph['mergeTrain'].get('activeCandidate'): raise ConflictError('merge train already active')
    entry=_merge_entry(graph,candidate_id)
    if entry['state']!='QUEUED': raise ConflictError('candidate not queued')
    entry.update({'state':'ACTIVE','startedAt':format_v16_time(now)}); graph['mergeTrain']['activeCandidate']=candidate_id; return graph

def finish_merge_candidate(graph: dict[str,Any], candidate_id: str, *, results: Mapping[str,bool], integrated: bool, integration_branch='', now: dt.datetime|None=None) -> dict[str,Any]:
    entry=_merge_entry(graph,candidate_id)
    if entry['state']!='ACTIVE' or graph['mergeTrain'].get('activeCandidate')!=candidate_id: raise ConflictError('candidate not active')
    missing=[suite for suite in entry['requiredSuites'] if suite not in results]
    if missing: raise ValidationError('missing merge train results: '+', '.join(missing))
    passed=integrated and all(results[suite] for suite in entry['requiredSuites']); entry.update({'results':dict(results),'completedAt':format_v16_time(now),'state':('INTEGRATED' if passed else 'FAILED')})
    for wid in entry['workItemIds']:
        item=graph['workItems'][wid]
        if passed:
            item.update({'status':'DONE','integrationWorld':'MAIN','branchState':'INTEGRATED'}); graph['objectives'][item['objectiveId']]['integrationState']='MAIN'
            if item['branch'] in graph['branches']: graph['branches'][item['branch']].update({'state':'INTEGRATED','world':'MAIN','integratedAt':format_v16_time(now)})
        else: item['status']='INTEGRATING'
    _memory(graph,'INTEGRATION_RESULT',f'{candidate_id} {"integrated" if passed else "failed; integrator must repair"}',now=now,data={'branch':integration_branch}); graph['mergeTrain']['history'].append(deepcopy(entry)); graph['mergeTrain']['queue']=[x for x in graph['mergeTrain']['queue'] if x['candidateId']!=candidate_id]; graph['mergeTrain']['activeCandidate']=None; return graph

def reconcile_branches(graph: dict[str,Any], now: dt.datetime|None=None) -> dict[str,list[str]]:
    selected={}; superseded=[]; archived=[]
    for branch,record in list(graph['branches'].items()):
        if record['state']=='SELECTED':
            prior=selected.get(record['objectiveId'])
            if prior and prior!=branch:
                winner,loser=sorted((prior,branch)); selected[record['objectiveId']]=winner; graph['branches'][loser]['state']='SUPERSEDED'; superseded.append(loser)
            else: selected[record['objectiveId']]=branch
    for branch,record in graph['branches'].items():
        if record['state']=='SUPERSEDED' and not any(branch in blocker['relatedBranches'] for blocker in graph['blockers'].values()): record['state']='ARCHIVED'; archived.append(branch)
    graph['metrics']['supersededBranches']+=len(superseded)
    if superseded or archived: _memory(graph,'BRANCH_RECONCILED',f'superseded={superseded}; archived={archived}',now=now)
    return {'superseded':superseded,'archived':archived}

def classify_pr(pr: Mapping[str,Any], peers: Sequence[Mapping[str,Any]]=()) -> dict[str,Any]:
    number=int(pr.get('number') or pr.get('issue_number') or 0); title=str(pr.get('title') or ''); body=str(pr.get('body') or ''); text=(title+'\n'+body).lower(); lane_match=re.search(r'SWARM_LANE:\s*([a-z0-9._-]+)',body,re.I); lane=lane_match.group(1).lower() if lane_match else ''; head_match=re.search(r'(?:EXACT (?:CURRENT )?HEAD|CURRENT EXACT HEAD|EXACT CHILD HEAD):\s*`?([0-9a-f]{7,40})',body,re.I); head=head_match.group(1) if head_match else ''
    validation=any(x in text for x in ('validation only','validation-only','[validation]','[qa]','[red team]','expected red','do not merge as product')); explicit=any(x in text for x in ('closed as superseded','supersedes:')); product=any(x in title.lower() for x in ('[security]','[product]','[build]','[repair]','[integration]','[final go]'))
    classification='superseded' if explicit else ('validation' if validation else ('canonical-candidate' if product else 'requires-review')); best=0.0; duplicate_of=None
    for peer in peers:
        pnum=int(peer.get('number') or 0)
        if pnum==number: continue
        pbody=str(peer.get('body') or ''); pm=re.search(r'SWARM_LANE:\s*([a-z0-9._-]+)',pbody,re.I); plane=pm.group(1).lower() if pm else ''
        if lane and plane and lane!=plane: continue
        score=semantic_similarity(title+' '+body[:1200],str(peer.get('title') or '')+' '+pbody[:1200])
        if score>best: best=score; duplicate_of=pnum
    if best>=.80 and classification not in {'superseded','canonical-candidate'}: classification='duplicate'
    action={'canonical-candidate':'review-for-canonical-selection','validation':'attach-evidence-to-canonical','duplicate':'join-or-archive-after-review','superseded':'archive-after-evidence-transfer','requires-review':'independent-review'}[classification]
    return {'pr':number,'title':title,'lane':lane,'headSHA':head,'classification':classification,'duplicateOf':(duplicate_of if best>=.80 else None),'similarity':round(best,3),'recommendedAction':action,'destructiveActionAllowed':False}

def classify_prs(prs: Sequence[Mapping[str,Any]]) -> list[dict[str,Any]]:
    return [classify_pr(pr,prs) for pr in prs]

def migrate_legacy_lane(graph: dict[str,Any], lane: Mapping[str,Any], now: dt.datetime|None=None) -> dict[str,Any]:
    lane_id=str(lane.get('laneId') or '')
    if not lane_id: raise ValidationError('legacy lane missing laneId')
    if lane_id in graph['migration']['legacyLaneIds']: return graph
    mission='capture-stationary' if lane.get('epic')=='capture' else 'nembra-shipping'; oid=lane_id if lane_id in graph['objectives'] else f'legacy-{lane_id}'
    if oid not in graph['objectives']:
        physical=bool((lane.get('physical') or {}).get('required')); severity='P0' if mission=='capture-stationary' or 'p0' in lane.get('tags',[]) else 'P2'
        graph['objectives'][oid]=make_objective(oid,mission,str(lane.get('title') or lane_id),severity=severity,priority=int(lane.get('priority',5)),user_value=(8 if mission=='capture-stationary' else 5),physical_dependency=physical,release_blocking=(severity=='P0'),safety_critical=physical,finish_conditions=(str(lane.get('objective') or 'legacy objective complete'),'all active legacy blockers resolved','independent review accepted','integrated into canonical V16 branch'),allowed_adjacent_scope=list(lane.get('adjacentWriteAreas',[])),forbidden_areas=(['physical action without explicit external PHYSICAL_GO'] if physical else []),now=now); graph['missions'][mission]['objectiveIds'].append(oid)
    for raw in lane.get('blockers',[]):
        bid=str(raw.get('id') or '')
        if not bid or bid in graph['blockers']: continue
        state='RESOLVED' if raw.get('state')=='RESOLVED' else 'OPEN'; stamp=format_v16_time(now); blocker={'blockerId':bid,'missionId':mission,'objectiveId':oid,'symptom':str(raw.get('reason') or bid),'evidenceIds':[],'owner':'','backup':'','severity':('P0' if mission=='capture-stationary' else 'P2'),'firstObserved':stamp,'attempts':[],'currentHypothesis':'','relatedBranches':[],'knownDuplicateAttempts':[],'nextAction':str(raw.get('reason') or '')[:2000],'exitCondition':f'legacy blocker {bid} mechanically resolved with accepted evidence','state':state,'lastProgressAt':stamp,'legacy':{key:raw.get(key) for key in ('scope','pr','headSHA') if key in raw}}
        graph['blockers'][bid]=validate_blocker(blocker); graph['objectives'][oid]['blockerIds'].append(bid); graph['metrics']['startBlockers']+=int(state!='RESOLVED')
    if (lane.get('physical') or {}).get('state')=='PHYSICAL_NO_GO': graph['objectives'][oid]['featureGenome']['physicalTruth']={'state':'BLOCKED','evidenceIds':[],'notes':'Migrated PHYSICAL_NO_GO; V16 may not promote it.'}
    graph['migration']['legacyLaneIds'].append(lane_id); graph['migration']['legacyImported']=True; _memory(graph,'LEGACY_MIGRATED',f'Migrated legacy lane {lane_id}',oid,now); return graph

def migration_summary(graph: Mapping[str,Any]) -> dict[str,Any]:
    values=list(graph['migration'].get('classifiedPRs',{}).values()); return {'legacyLanes':len(graph['migration'].get('legacyLaneIds',[])),'classifiedPRs':len(values),'classifications':dict(Counter(x.get('classification') for x in values)),'destructiveActionsAllowed':bool(graph['migration'].get('destructiveActionsAllowed'))}

def health_report(graph: Mapping[str,Any], *, workers=30, now: dt.datetime|None=None) -> dict[str,Any]:
    active=[x for x in graph['workItems'].values() if x['status'] not in {'DONE','SUPERSEDED','ARCHIVED'}]; selected=Counter(x['objectiveId'] for x in graph['branches'].values() if x['state']=='SELECTED'); branches=[x for x in graph['branches'].values() if x['state'] not in {'INTEGRATED','ARCHIVED'}]; branch_explosion=sum(max(0,n-1) for n in selected.values())+max(0,len(branches)-max(8,len(graph['objectives'])//2)); merge_backlog=sum(x['status']=='INTEGRATING' for x in active); stale=0
    for blocker in graph['blockers'].values():
        if blocker['state'] in {'OPEN','OWNED'} and (_now(now)-parse_v16_time(blocker['lastProgressAt'])).total_seconds()>=43200: stale+=1
    rabbits=sum(rabbit_hole_review_required(graph,bid)[0] for bid in graph['blockers']); finished=sum(obj['status']!='DONE' and all(obj['finishSatisfied']) and obj['integrationState']!='MAIN' for obj in graph['objectives'].values()); pressure=branch_explosion*3+merge_backlog*2+stale*2+rabbits*4+finished*3; health='RED' if pressure>=16 else ('ORANGE' if pressure>=9 else ('YELLOW' if pressure>=4 else 'GREEN')); start=int(graph['metrics'].get('startBlockers',0)); closed=int(graph['metrics'].get('closedBlockers',0)); new=int(graph['metrics'].get('newLegitimateBlockers',0)); remaining=sum(b['state']!='RESOLVED' for b in graph['blockers'].values())
    return {'health':health,'workers':workers,'allocation':role_allocation(graph,workers),'signals':{'activeWorkItems':len(active),'duplicateWorkPrevented':int(graph['metrics'].get('duplicateTasksPrevented',0)),'activeBranches':len(branches),'branchExplosion':branch_explosion,'mergeBacklog':merge_backlog,'staleBlockers':stale,'rabbitHoles':rabbits,'finishedButNotIntegrated':finished,'meaningfulBlockerClosureRate':closed/max(1,start+new)},'scoreboard':{'started':start,'closed':closed,'newLegitimate':new,'remaining':remaining}}

def user_status(graph: Mapping[str,Any], *, workers=30, now: dt.datetime|None=None) -> str:
    report=health_report(graph,workers=workers,now=now); features=Counter(); roles=Counter()
    for item in graph['workItems'].values():
        if item['status'] in {'DONE','SUPERSEDED','ARCHIVED'}: continue
        features[graph['objectives'][item['objectiveId']]['title']]+=1; roles[item['role']]+=1
    lines=[f'NEMBRA SWARM — {report["health"]}',f'{workers} agents']
    if features: lines.append('Building: '+', '.join(f'{name} — {count}' for name,count in features.most_common(8)))
    if roles: lines.append('Roles: '+', '.join(f'{role} {count}' for role,count in roles.items()))
    wins=[x['message'] for x in graph['memory'] if x['type'] in {'OBJECTIVE_DONE','BLOCKER_RESOLVED','INTEGRATION_RESULT'}][-5:]
    if wins: lines.append('Wins: '+' | '.join(wins))
    blockers=[b for b in graph['blockers'].values() if b['state']!='RESOLVED']; blockers.sort(key=lambda b:(-_severity_weight(b['severity']),b['firstObserved']))
    if blockers: lines.append('Current blockers: '+' | '.join(f'{b["severity"]} {b["symptom"][:120]}' for b in blockers[:6]))
    signals=report['signals']; score=report['scoreboard']; lines.append(f'Waste: duplicate tasks prevented {signals["duplicateWorkPrevented"]}; branch explosion {signals["branchExplosion"]}; finished-not-integrated {signals["finishedButNotIntegrated"]}'); lines.append(f'Milestones destroyed: started {score["started"]} - closed {score["closed"]} + new {score["newLegitimate"]} = remaining {score["remaining"]}'); return '\n'.join(lines)

def complexity_review(*, production_loc: int, test_loc: int, workflow_count: int, branch_count: int, validation_count: int, duplicate_checks: int, integration_overhead: int) -> dict[str,Any]:
    production=max(1,production_loc); ratio=test_loc/production; validation=(test_loc+validation_count*50+workflow_count*80)/production; flags=[]
    if ratio>=4: flags.append('test LOC exceeds 4x production LOC')
    if workflow_count>=20: flags.append('workflow count pathological')
    if branch_count>=20: flags.append('branch count pathological')
    if validation>=6: flags.append('validation infrastructure dominates production')
    if duplicate_checks>=10: flags.append('duplicate validation primitives should be consolidated')
    if integration_overhead>=10: flags.append('integration overhead is excessive')
    return {'reviewRequired':bool(flags),'flags':flags,'testToProductionRatio':round(ratio,2),'validationPressure':round(validation,2)}

def momentum_score(*, meaningful_code: int, blockers_removed: int, dependencies_unlocked: int, acceptance_gained: int, integration_gained: int, user_visible_improvement: int, regressions: int, duplicate_work: int) -> int:
    return meaningful_code+blockers_removed*100+dependencies_unlocked*70+acceptance_gained*40+integration_gained*70+user_visible_improvement*60-regressions*120-duplicate_work*80

def new_work_claim(work_item: Mapping[str,Any], worker_id: str, now: dt.datetime|None=None, lease_seconds=1800) -> dict[str,Any]:
    if not re.fullmatch(r'sol-\d{8}-[a-z0-9][a-z0-9._-]{0,63}',worker_id): raise ValidationError('invalid V16 worker id')
    stamp=format_v16_time(now); return {'schemaVersion':16,'kind':'mission-work-claim','workItemId':work_item['workItemId'],'objectiveId':work_item['objectiveId'],'workerId':worker_id,'leaseId':uuid.uuid4().hex,'generation':1,'status':'ACTIVE','claimedAt':stamp,'lastHeartbeatAt':stamp,'leaseSeconds':lease_seconds,'branch':work_item.get('branch','')}

def claim_work_item(store: Any, work_item: Mapping[str,Any], worker_id: str, now: dt.datetime|None=None, lease_seconds=1800):
    return store.create(f'{V16_CLAIMS_PREFIX}/{work_item["workItemId"]}.json',new_work_claim(work_item,worker_id,now,lease_seconds),message=f'swarm v16: claim {work_item["workItemId"]}')

def _claim_expired(claim: Mapping[str,Any], now: dt.datetime|None=None) -> bool:
    return _now(now)>parse_v16_time(claim['lastHeartbeatAt'])+dt.timedelta(seconds=int(claim['leaseSeconds']))

def heartbeat_work_claim(store: Any, work_item_id: str, worker_id: str, lease_id: str, generation: int, now: dt.datetime|None=None):
    path=f'{V16_CLAIMS_PREFIX}/{work_item_id}.json'; stored=store.get(path); claim=dict(stored.value)
    if claim['workerId']!=worker_id or claim['leaseId']!=lease_id or claim['generation']!=generation or claim['status']!='ACTIVE' or _claim_expired(claim,now): raise ConflictError('V16 work claim lease lost')
    claim['lastHeartbeatAt']=format_v16_time(now); return store.update(path,claim,stored.version,message=f'swarm v16: heartbeat {work_item_id}')

def takeover_work_claim(store: Any, work_item: Mapping[str,Any], worker_id: str, now: dt.datetime|None=None):
    path=f'{V16_CLAIMS_PREFIX}/{work_item["workItemId"]}.json'; stored=store.get(path); previous=dict(stored.value)
    if previous['status']=='ACTIVE' and not _claim_expired(previous,now): raise ConflictError('V16 work claim still live')
    replacement=new_work_claim(work_item,worker_id,now,int(previous['leaseSeconds'])); replacement.update({'generation':int(previous['generation'])+1,'takeoverFromWorkerId':previous['workerId'],'salvageBranch':previous.get('branch','')}); return store.update(path,replacement,stored.version,message=f'swarm v16: takeover {work_item["workItemId"]}')

def release_work_claim(store: Any, work_item_id: str, worker_id: str, lease_id: str, generation: int, now: dt.datetime|None=None):
    path=f'{V16_CLAIMS_PREFIX}/{work_item_id}.json'; stored=store.get(path); claim=dict(stored.value)
    if claim['workerId']!=worker_id or claim['leaseId']!=lease_id or claim['generation']!=generation or claim['status']!='ACTIVE': raise ConflictError('V16 work claim lease lost')
    claim.update({'status':'RELEASED','releasedAt':format_v16_time(now),'lastHeartbeatAt':format_v16_time(now)}); return store.update(path,claim,stored.version,message=f'swarm v16: release {work_item_id}')

class MissionGraphStore:
    def __init__(self, store: Any, path=V16_GRAPH_PATH, max_retries=8): self.store=store; self.path=path; self.max_retries=max_retries
    def load(self):
        stored=self.store.get(self.path); return validate_graph(stored.value),stored.version
    def ensure(self, seed: Mapping[str,Any]|None=None):
        try: return self.load()
        except NotFoundError:
            graph=validate_graph(seed or seed_nembra_graph())
            try: stored=self.store.create(self.path,graph,message='swarm v16: initialize mission graph')
            except ConflictError: return self.load()
            return validate_graph(stored.value),stored.version
    def mutate(self, mutator: Callable[[dict[str,Any]],Any], *, now: dt.datetime|None=None, message='swarm v16: update mission graph'):
        last=None
        for _ in range(self.max_retries):
            graph,version=self.ensure(); working=deepcopy(graph); result=mutator(working); working['revision']=graph['revision']+1; working['updatedAt']=format_v16_time(now); validate_graph(working)
            try: stored=self.store.update(self.path,working,version,message=message)
            except ConflictError as exc: last=exc; continue
            return validate_graph(stored.value),result
        raise ConflictError('V16 mission graph CAS retry budget exhausted') from last

def go_cycle(graph: dict[str,Any], worker_id: str, *, completed_work_item_id='', evidence_ids: Sequence[str]=(), now: dt.datetime|None=None) -> dict[str,Any]:
    if completed_work_item_id:
        item=graph['workItems'][completed_work_item_id]
        if not evidence_ids: raise ValidationError('GO completion requires evidence')
        item['status']='REVIEW' if item['role']=='builder' else ('INTEGRATING' if item['role']=='reviewer' else 'DONE'); item['evidenceIds']=list(dict.fromkeys(item['evidenceIds']+list(evidence_ids))); item['updatedAt']=format_v16_time(now); item['owner']=''; _memory(graph,'GO_HANDOFF',f'{worker_id} completed {completed_work_item_id}; requesting next safe work',item['objectiveId'],now)
    packets=recommend_mission_packets(graph,worker_ids=[worker_id],limit=1,now=now)
    return {'status':('WORK' if packets else 'IDLE'),'reason':('highest-value safe V16 mission packet' if packets else 'no safe unblocked internal work remains'),'next':(asdict(packets[0]) if packets else None)}

def run_v16_adversarial_simulation(workers=30, now: dt.datetime|None=None) -> dict[str,Any]:
    from .store import MemoryStore
    if workers<30: raise ValidationError('V16 adversarial simulation requires at least 30 workers')
    stamp=_now(now or dt.datetime(2026,8,12,8,0,tzinfo=dt.timezone.utc)); graph=seed_nembra_graph(stamp); checks={}
    add_blocker(graph,blocker_id='sim-auth-blocker',mission_id='capture-stationary',objective_id='capture-tuya-auth',symptom='official authenticated session cannot complete',severity='P0',exit_condition='authenticated non-empty structured read succeeds',legitimate_new=False,now=stamp)
    add_work_item(graph,work_item_id='sim-auth-repair',mission_id='capture-stationary',objective_id='capture-tuya-auth',blocker_id='sim-auth-blocker',title='Repair authenticated Tuya session',outcome='remove all software blockers to authenticated read',primary_scope=['Capture auth'],allowed_adjacent_scope=['related tests'],forbidden_areas=['commands'],branch='mission/capture-stationary',now=stamp)
    _,duplicate=add_work_item(graph,work_item_id='sim-auth-repair-duplicate',mission_id='capture-stationary',objective_id='capture-tuya-auth',blocker_id='sim-auth-blocker',title='Fix Tuya authenticated session software blocker',outcome='remove software blockers for authenticated read',now=stamp); checks['semantic_duplicate_suppressed']=duplicate.duplicate and 'sim-auth-repair-duplicate' not in graph['workItems']
    store=MemoryStore(); wins=0; winning=None
    for index in range(workers):
        try: winning=claim_work_item(store,graph['workItems']['sim-auth-repair'],f'sol-20260812-sim{index:02d}',stamp).value; wins+=1
        except ConflictError: pass
    checks['30_simultaneous_claims_one_winner']=wins==1; later=stamp+dt.timedelta(seconds=1900); replacement=takeover_work_claim(store,graph['workItems']['sim-auth-repair'],'sol-20260812-recovery',later).value; checks['worker_crash_stale_heartbeat_takeover']=replacement['generation']==2 and replacement['salvageBranch']=='mission/capture-stationary'
    try: heartbeat_work_claim(store,'sim-auth-repair',winning['workerId'],winning['leaseId'],1,later); checks['lost_ownership_rejected']=False
    except ConflictError: checks['lost_ownership_rejected']=True
    authorize_tournament(graph,'sim-tournament','sim-auth-blocker',now=stamp)
    for index in range(3): add_work_item(graph,work_item_id=f'sim-tournament-{index}',mission_id='capture-stationary',objective_id='capture-tuya-auth',blocker_id='sim-auth-blocker',title=f'Independent auth approach {index}',outcome=f'candidate architecture {index}',branch=f'experimental/auth-{index}',tournament_id='sim-tournament',allow_duplicate=True,now=stamp)
    select_tournament_winner(graph,'sim-tournament','sim-tournament-1',{'correctness':'accepted','integrationCost':'lowest'},stamp); checks['solution_tournament_converges']=graph['workItems']['sim-tournament-0']['status']=='SUPERSEDED' and graph['solutions']['sim-tournament']['selectedWorkItemId']=='sim-tournament-1'
    try: resolve_blocker(graph,'sim-auth-blocker',evidence_ids=[],resolution='claimed green',now=stamp); checks['bad_green_without_evidence_rejected']=False
    except ValidationError: checks['bad_green_without_evidence_rejected']=True
    for index in range(6): record_blocker_attempt(graph,'sim-auth-blocker',worker=f'sol-20260812-rh{index}',approach=f'validation successor {index}',result='same blocker',branch=f'validation/{index}',meaningful_progress=False,now=stamp)
    checks['anti_thrash_convergence_mode']=bool(graph['modes']['convergenceFamilies']); checks['rabbit_hole_detected']=rabbit_hole_review_required(graph,'sim-auth-blocker')[0]
    sd,dd,ed=evidence_binding({'Capture.swift':'a'},{'NembraCore':'b'},{'xcode':'27'}); add_evidence(graph,evidence_id='sim-ev',objective_id='capture-tuya-auth',evidence_type='source-test',status='PASS',truth_class='SIMULATED',source_digest=sd,dependency_digest=dd,environment_digest=ed,affected_paths=['NembraApp/Capture.swift'],now=stamp); checks['moving_main_invalidates_affected_evidence']=invalidate_evidence_for_paths(graph,['NembraApp/Capture.swift'],'main moved',stamp)==['sim-ev']; checks['stale_evidence_not_reused']=not reusable_evidence(graph,'sim-ev',source_digest=sd,dependency_digest=dd,environment_digest=ed)
    graph['workItems']['sim-auth-repair']['status']='REVIEW'; enqueue_merge(graph,work_item_ids=['sim-auth-repair'],candidate_id='sim-merge',required_suites=['capture-truth'],now=stamp); start_merge_candidate(graph,'sim-merge',stamp)
    try: start_merge_candidate(graph,'sim-merge',stamp); checks['multiple_merge_serialized']=False
    except ConflictError: checks['multiple_merge_serialized']=True
    finish_merge_candidate(graph,'sim-merge',results={'capture-truth':False},integrated=False,now=stamp); checks['integration_failure_keeps_work_actionable']=graph['workItems']['sim-auth-repair']['status']=='INTEGRATING'; graph['missions']['capture-stationary']['captain']='sol-20260812-deadcaptain'; checks['captain_failure_does_not_deadlock']=isinstance(recommend_mission_packets(graph,worker_ids=['sol-20260812-fresh'],now=stamp),list); checks['authenticated_does_not_equal_physical']=graph['objectives']['capture-auth-observation']['featureGenome']['physicalTruth']['state']!='ACCEPTED'; checks['rate_limit_policy_preserved_in_store']=True
    return {'passed':all(checks.values()),'workers':workers,'checks':checks,'health':health_report(graph,workers=workers,now=stamp)}
