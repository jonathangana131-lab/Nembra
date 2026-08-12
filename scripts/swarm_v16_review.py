#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc


def require(condition: bool, message: str) -> None:
    if not condition: raise AssertionError(message)


def main() -> int:
    checks=[]
    config=json.loads((ROOT/'.swarm/config.json').read_text(encoding='utf-8'))
    v16=config.get('v16') or {}
    require(v16.get('enabled') is True,'V16 must be enabled')
    require(config['physicalSafety']['schedulerMayPromotePhysicalGo'] is False,'legacy physical scheduler boundary weakened')
    require(config['physicalSafety']['simulatorEvidenceIsPhysicalEvidence'] is False,'simulator promoted to physical')
    require(v16['physicalSafety']['authenticatedEvidenceIsPhysicalEvidence'] is False,'authenticated evidence promoted to physical')
    require(v16['physicalSafety']['commandsRequirePhysicalMapping'] is True,'command physical mapping requirement weakened')
    require(v16['destructiveMigrationActionsAllowed'] is False,'destructive migration enabled by default')
    checks.append('config safety boundaries')

    graph=sc.seed_nembra_graph()
    require(graph['schemaVersion']==16,'wrong graph schema')
    require('capture-stationary' in graph['missions'],'Capture mission missing')
    for oid in graph['missions']['capture-stationary']['objectiveIds']:
        forbidden=graph['objectives'][oid]['forbiddenAreas']
        require('scooter commands' in forbidden,'Capture objective permits commands')
        require('outdoor ride procedure' in forbidden,'Capture objective regressed to outdoor procedure')
    checks.append('Capture mission read-only boundary')

    require(sc.NEMBRA_TEST_KIT['TelemetryTruth']['truthClass']=='AUTHENTICATED','TelemetryTruth authority changed')
    require(sc.NEMBRA_TEST_KIT['PhysicalTruth']['truthClass']=='PHYSICALLY_MAPPED','PhysicalTruth authority changed')
    require(sc.PHYSICAL_ACCEPTANCE_PRIMITIVES=={'PhysicalTruth'},'multiple generic primitives can create physical truth')
    checks.append('Test Kit authority separation')

    require(sc.GitHubContentsStore.RETRYABLE=={429,500,502,503,504},'GitHub retry safety changed unexpectedly')
    require(sc.V16_GRAPH_PATH=='.swarm/runtime/v16/mission-graph.json','graph escaped V16 state namespace')
    require(sc.V16_CLAIMS_PREFIX=='.swarm/runtime/v16/claims','claims escaped V16 state namespace')
    checks.append('CAS/store boundaries')

    sc.migration_phase(graph,'DOGFOOD')
    require(graph['migration']['destructiveActionsAllowed'] is False,'dogfood may delete branches')
    graph['branches']['old-review']={'branch':'old-review','missionId':'nembra-shipping','objectiveId':'dashboard','state':'ARCHIVED','world':'EXPERIMENTAL','selectedAt':'','integratedAt':'','pr':1,'source':{}}
    require(sc.branch_cleanup_plan(graph)[0]['remoteDeleteAllowed'] is False,'cleanup became destructive before activation')
    checks.append('migration fail-closed cleanup')

    activation=(ROOT/'.github/workflows/swarm-v16-activate.yml').read_text(encoding='utf-8')
    require('branches: [main]' in activation,'activation not restricted to main')
    require('contents: write' in activation,'activation cannot persist state')
    test_pos=activation.index('Run V16 deterministic and concurrency tests')
    dogfood_pos=activation.index('Dogfood current Nembra topology before state write')
    write_pos=activation.index('Atomically activate V16 on swarm-state')
    require(test_pos < dogfood_pos < write_pos,'activation writes before tests/dogfood')
    checks.append('post-main activation ordering')

    shadow=(ROOT/'.github/workflows/swarm-control-plane-shadow.yml').read_text(encoding='utf-8')
    require("test_swarm_*.py" in shadow,'legacy swarm tests dropped')
    require('v16-simulate --workers 30' in shadow,'V16 30-worker gate missing')
    require('live-v16-dogfood' in shadow,'live dogfood gate missing')
    checks.append('CI retains legacy + V16 acceptance')

    old_coord=(ROOT/'SWARM_COORDINATION.md').read_text(encoding='utf-8')
    old_os=(ROOT/'docs/SWARM_OPERATING_SYSTEM.md').read_text(encoding='utf-8')
    require('STATUS: RETIRED' in old_coord,'V14 still appears operational')
    require('STATUS: RETIRED' in old_os,'V13 still appears operational')
    checks.append('contradictory legacy docs retired')

    module=(ROOT/'scripts/swarmcp/mission_graph.py').read_text(encoding='utf-8')
    require(not re.search(r'\b(subprocess|os\.system|Popen)\b',module),'mission graph gained executable shell surface')
    require('COMMAND_VERIFIED' in module and 'PHYSICALLY_MAPPED' in module,'truth classes missing')
    checks.append('control plane remains data-only')

    result=sc.run_v16_adversarial_simulation(30)
    require(result['passed'],'independent review simulation failed')
    checks.append('30-worker adversarial convergence')

    print(json.dumps({'review':'APPROVE','independentInvariantChecks':checks,'count':len(checks)},indent=2,sort_keys=True))
    return 0

if __name__=='__main__': raise SystemExit(main())
