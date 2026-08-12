from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from .mission_graph import (
    BRANCH_STATES,
    GENOME_DIMENSIONS,
    MissionGraphStore,
    ValidationError,
    _memory,
    add_evidence,
    format_v16_time,
    specialization_score,
)

# Reusable Nembra Test Kit primitives. A primitive defines the minimum truth
# authority it is allowed to create; feature-specific semantics stay outside
# this registry.
NEMBRA_TEST_KIT = {
    'SourceCustody': {'truthClass': 'OBSERVED', 'dimension': 'testing'},
    'BuildIdentity': {'truthClass': 'OBSERVED', 'dimension': 'testing'},
    'SignedBuildIdentity': {'truthClass': 'AUTHENTICATED', 'dimension': 'testing'},
    'SimulatorIdentity': {'truthClass': 'SIMULATED', 'dimension': 'testing'},
    'DeviceIdentity': {'truthClass': 'OBSERVED', 'dimension': 'testing'},
    'PrivateInputCustody': {'truthClass': 'AUTHENTICATED', 'dimension': 'testing'},
    'InstallationCustody': {'truthClass': 'OBSERVED', 'dimension': 'integration'},
    'AccessibilityAcceptance': {'truthClass': 'OBSERVED', 'dimension': 'accessibility'},
    'VisualEvidence': {'truthClass': 'OBSERVED', 'dimension': 'visualQuality'},
    'PerformanceEvidence': {'truthClass': 'OBSERVED', 'dimension': 'performance'},
    'TelemetryTruth': {'truthClass': 'AUTHENTICATED', 'dimension': 'physicalTruth'},
    'PhysicalTruth': {'truthClass': 'PHYSICALLY_MAPPED', 'dimension': 'physicalTruth'},
    'IntegrationTruth': {'truthClass': 'OBSERVED', 'dimension': 'integration'},
}

# PhysicalTruth is the only generic primitive allowed to establish physical
# mapping. TelemetryTruth can establish authenticated observation, but cannot
# itself mark physicalTruth accepted.
PHYSICAL_ACCEPTANCE_PRIMITIVES = {'PhysicalTruth'}


def v16_graph_service(store: Any) -> MissionGraphStore:
    """Production V16 graph service with enough CAS retries for 30+ writers."""
    return MissionGraphStore(store, max_retries=64)


def assign_captain(
    graph: dict[str, Any],
    mission_id: str,
    worker_id: str,
    *,
    objective_ids: Sequence[str] = (),
    now: dt.datetime | None = None,
) -> dict[str, Any]:
    if mission_id not in graph['missions']:
        raise ValidationError('unknown mission')
    mission = graph['missions'][mission_id]
    mission['captain'] = worker_id
    targets = list(objective_ids) if objective_ids else list(mission['objectiveIds'])
    for objective_id in targets:
        objective = graph['objectives'].get(objective_id)
        if not objective or objective['missionId'] != mission_id:
            raise ValidationError('captain objective outside mission')
        objective['captain'] = worker_id
    _memory(graph, 'CAPTAIN_ASSIGNED', f'{worker_id} captains {mission_id}', now=now)
    return graph


def replace_failed_captain(
    graph: dict[str, Any],
    mission_id: str,
    replacement_worker_id: str,
    *,
    reason: str,
    now: dt.datetime | None = None,
) -> dict[str, Any]:
    old = graph['missions'][mission_id].get('captain', '')
    assign_captain(graph, mission_id, replacement_worker_id, now=now)
    _memory(
        graph,
        'CAPTAIN_RECOVERED',
        f'{mission_id}: replaced {old or "unowned"} with {replacement_worker_id}; {reason}',
        now=now,
    )
    return graph


def record_test_kit_evidence(
    graph: dict[str, Any],
    *,
    primitive: str,
    evidence_id: str,
    objective_id: str,
    status: str,
    source_digest: str,
    dependency_digest: str,
    environment_digest: str,
    affected_paths: Sequence[str],
    details: Mapping[str, Any] | None = None,
    now: dt.datetime | None = None,
) -> dict[str, Any]:
    contract = NEMBRA_TEST_KIT.get(primitive)
    if not contract:
        raise ValidationError(f'unknown Nembra Test Kit primitive {primitive}')
    payload = dict(details or {})
    payload['primitive'] = primitive
    add_evidence(
        graph,
        evidence_id=evidence_id,
        objective_id=objective_id,
        evidence_type=primitive,
        status=status,
        truth_class=contract['truthClass'],
        source_digest=source_digest,
        dependency_digest=dependency_digest,
        environment_digest=environment_digest,
        affected_paths=affected_paths,
        details=payload,
        now=now,
    )
    dimension = contract['dimension']
    genome = graph['objectives'][objective_id]['featureGenome'][dimension]
    if evidence_id not in genome['evidenceIds']:
        genome['evidenceIds'].append(evidence_id)
    # Generic evidence can accept non-physical dimensions. Physical acceptance
    # requires the explicit PhysicalTruth primitive and physical authority flag.
    if status == 'PASS':
        if dimension != 'physicalTruth':
            genome['state'] = 'ACCEPTED'
        elif primitive in PHYSICAL_ACCEPTANCE_PRIMITIVES and payload.get('physicalAuthorityExplicit'):
            genome['state'] = 'ACCEPTED'
    elif status == 'FAIL':
        genome['state'] = 'BLOCKED'
    return graph


def canonical_branch_rank(record: Mapping[str, Any]) -> tuple[int, int, str]:
    source = record.get('source') or {}
    authority = source.get('selectionAuthority', '')
    authority_rank = {
        'legacy-selected-production': 500,
        'tournament-selected': 400,
        'captain-selected': 300,
        'merge-train-selected': 250,
    }.get(authority, 0)
    evidence_rank = int(source.get('acceptedEvidenceCount') or 0)
    return authority_rank, evidence_rank, str(record.get('branch') or '')


def reconcile_canonical_branches(
    graph: dict[str, Any],
    *,
    now: dt.datetime | None = None,
) -> dict[str, list[str]]:
    """Keep exactly one selected branch per objective without arbitrary lexical selection.

    Explicit selection authority and accepted evidence outrank all other candidates.
    A deterministic branch-name tie-break is used only after those semantic ranks tie,
    and the tie is recorded for review rather than silently treated as evidence.
    """
    by_objective: dict[str, list[dict[str, Any]]] = {}
    for record in graph['branches'].values():
        if record.get('state') == 'SELECTED':
            by_objective.setdefault(record['objectiveId'], []).append(record)
    superseded: list[str] = []
    ties: list[str] = []
    for objective_id, records in by_objective.items():
        if len(records) <= 1:
            continue
        ordered = sorted(records, key=canonical_branch_rank, reverse=True)
        winner = ordered[0]
        top_semantic = canonical_branch_rank(winner)[:2]
        tied = [r for r in ordered if canonical_branch_rank(r)[:2] == top_semantic]
        if len(tied) > 1:
            tied.sort(key=lambda r: r['branch'])
            winner = tied[0]
            ties.append(objective_id)
            _memory(
                graph,
                'CANONICAL_SELECTION_TIE',
                f'{objective_id}: semantic selection tie; kept {winner["branch"]} pending captain/review evidence',
                objective_id,
                now,
            )
        for record in records:
            if record['branch'] == winner['branch']:
                continue
            record['state'] = 'SUPERSEDED'
            superseded.append(record['branch'])
            graph['metrics']['supersededBranches'] = int(graph['metrics'].get('supersededBranches', 0)) + 1
    archived: list[str] = []
    for branch, record in graph['branches'].items():
        if record.get('state') != 'SUPERSEDED':
            continue
        referenced = any(branch in blocker.get('relatedBranches', []) for blocker in graph['blockers'].values())
        if not referenced:
            record['state'] = 'ARCHIVED'
            archived.append(branch)
    if superseded or archived:
        _memory(graph, 'BRANCH_RECONCILED', f'superseded={superseded}; archived={archived}', now=now)
    return {'superseded': superseded, 'archived': archived, 'ties': ties}


def branch_cleanup_plan(graph: Mapping[str, Any]) -> list[dict[str, Any]]:
    """Return safe lifecycle actions; never performs destructive GitHub operations."""
    plan: list[dict[str, Any]] = []
    for branch, record in graph['branches'].items():
        state = record.get('state')
        if state not in {'SUPERSEDED', 'ARCHIVED'}:
            continue
        related = [b['blockerId'] for b in graph['blockers'].values() if branch in b.get('relatedBranches', []) and b['state'] != 'RESOLVED']
        plan.append({
            'branch': branch,
            'state': state,
            'preserveEvidence': True,
            'unresolvedBlockerReferences': related,
            'remoteDeleteAllowed': state == 'ARCHIVED' and not related and bool(graph['migration'].get('destructiveActionsAllowed')),
        })
    return plan


def objective_domain(graph: Mapping[str, Any], objective_id: str) -> str:
    title = graph['objectives'][objective_id]['title'].lower()
    mappings = (
        ('accessib', 'accessibility'), ('performance', 'performance'), ('navigation', 'MapKit'),
        ('bluetooth', 'CoreBluetooth'), ('tuya', 'Tuya integration'), ('capture', 'Tuya integration'),
        ('dashboard', 'SwiftUI'), ('rides', 'Swift concurrency'), ('integration', 'integration/conflict resolution'),
    )
    for needle, domain in mappings:
        if needle in title:
            return domain
    return 'general engineering'


def assign_specialized_workers(
    graph: Mapping[str, Any],
    work_item_ids: Sequence[str],
    worker_ids: Sequence[str],
) -> dict[str, str]:
    """Outcome-derived specialization with deterministic exploration slots.

    Every fifth assignment is exploration: it chooses the least-used worker among
    those not already selected instead of the highest domain score.
    """
    if len(worker_ids) < len(work_item_ids):
        raise ValidationError('not enough workers')
    available = list(worker_ids)
    assignments: dict[str, str] = {}
    usage = {worker: 0 for worker in worker_ids}
    for index, work_item_id in enumerate(work_item_ids):
        item = graph['workItems'][work_item_id]
        domain = objective_domain(graph, item['objectiveId'])
        if index % 5 == 4:
            chosen = min(available, key=lambda w: (usage[w], w))
        else:
            chosen = max(available, key=lambda w: (specialization_score(graph, w, domain), -usage[w], w))
        assignments[work_item_id] = chosen
        usage[chosen] += 1
        available.remove(chosen)
    return assignments


def surge_role_allocation(workers: int = 30) -> dict[str, int]:
    if workers < 5:
        raise ValidationError('surge requires at least five workers')
    captain = 1
    reserve = max(1, round(workers * 0.07))
    ui_accessibility = max(1, round(workers * 0.10))
    debugging = max(1, round(workers * 0.13))
    integration = max(1, round(workers * 0.13))
    review = max(1, round(workers * 0.20))
    implementation = workers - captain - reserve - ui_accessibility - debugging - integration - review
    return {
        'captain': captain,
        'implementation': implementation,
        'review/testing': review,
        'integration': integration,
        'debugging/research': debugging,
        'ui/accessibility': ui_accessibility,
        'reserve': reserve,
    }


def red_team_acceptance_plan(graph: Mapping[str, Any], objective_id: str) -> dict[str, list[str]]:
    objective = graph['objectives'][objective_id]
    base = {
        'ui': ['AX5/tiny layouts', 'stale/disconnected/reconnect states', 'VoiceOver', 'Reduce Motion', 'Reduce Transparency'],
        'performance': ['rapid state updates', 'memory growth', 'CPU/hitching', 'long-lived runtime'],
        'truth': ['stale simulator data', 'replayed values', 'malformed data', 'wrong authority'],
    }
    if objective['physicalOrUserDependency']:
        base['truth'].extend(['authenticated is not physical mapping', 'no command authority without physical evidence'])
    return base


def migration_phase(graph: dict[str, Any], phase: str, *, now: dt.datetime | None = None) -> dict[str, Any]:
    allowed = {'PREPARED', 'IMPORTING', 'DOGFOOD', 'READY_TO_ACTIVATE', 'ACTIVE'}
    if phase not in allowed:
        raise ValidationError('invalid migration phase')
    graph['migration']['phase'] = phase
    graph['migration']['phaseUpdatedAt'] = format_v16_time(now)
    if phase != 'ACTIVE':
        graph['migration']['destructiveActionsAllowed'] = False
    _memory(graph, 'MIGRATION_PHASE', f'V16 migration -> {phase}', now=now)
    return graph
