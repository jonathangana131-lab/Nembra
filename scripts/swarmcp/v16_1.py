from __future__ import annotations

import copy
import re
from dataclasses import asdict, dataclass
from typing import Any, Mapping, Sequence

from . import mission_graph as _v16

V16_1_POLICY_VERSION = '16.1'
V16_1_MAX_TOURNAMENT_CANDIDATES = 2
V16_1_MAX_DISTINCT_ATTEMPT_BRANCHES = 2
V16_1_MAX_OPEN_NONCANONICAL_PRS_PER_LANE = 6
V16_1_BLOCKER_DUPLICATE_THRESHOLD = 0.84
V16_1_LOW_PROGRESS_ATTEMPTS_BEFORE_FREEZE = 3


def _policy_defaults() -> dict[str, Any]:
    return {
        'policyVersion': V16_1_POLICY_VERSION,
        'oneBuilderBranchPerBlocker': True,
        'maxTournamentCandidates': V16_1_MAX_TOURNAMENT_CANDIDATES,
        'maxDistinctAttemptBranchesPerBlocker': V16_1_MAX_DISTINCT_ATTEMPT_BRANCHES,
        'maxOpenNoncanonicalPRsPerLane': V16_1_MAX_OPEN_NONCANONICAL_PRS_PER_LANE,
        'lowProgressAttemptsBeforeFreeze': V16_1_LOW_PROGRESS_ATTEMPTS_BEFORE_FREEZE,
        'claimBeforeBranch': True,
        'joinBeforeSuccessor': True,
        'automaticPRAdmission': True,
    }


def ensure_v16_1_policy(graph: dict[str, Any]) -> dict[str, Any]:
    modes = graph.setdefault('modes', {})
    modes.setdefault('convergenceFamilies', [])
    modes.setdefault('frozenBranchFamilies', [])
    modes.setdefault('milestoneAttackObjectives', [])
    modes.setdefault('surgeMissionId', '')
    modes['v16_1'] = {**_policy_defaults(), **dict(modes.get('v16_1') or {})}
    metrics = graph.setdefault('metrics', {})
    metrics.setdefault('duplicateTasksPrevented', 0)
    metrics.setdefault('duplicateBlockersPrevented', 0)
    metrics.setdefault('branchForksPrevented', 0)
    metrics.setdefault('prAdmissionsRejected', 0)
    return graph


def seed_nembra_graph(now=None) -> dict[str, Any]:
    graph = _v16.seed_nembra_graph(now)
    return ensure_v16_1_policy(graph)


def validate_graph(graph: Any) -> dict[str, Any]:
    validated = _v16.validate_graph(graph)
    return ensure_v16_1_policy(validated)


class V16_1MissionGraphStore(_v16.MissionGraphStore):
    """MissionGraphStore that lazily stamps the active graph with V16.1 policy.

    The graph schema remains 16. V16.1 is a convergence-policy upgrade, so old
    V16 state is upgraded in place without a destructive migration or graph reset.
    """

    def ensure(self, seed: Mapping[str, Any] | None = None):
        graph, version = super().ensure(seed or seed_nembra_graph())
        if (graph.get('modes', {}).get('v16_1') or {}).get('policyVersion') == V16_1_POLICY_VERSION:
            return graph, version
        last = None
        for _ in range(4):
            working = copy.deepcopy(graph)
            ensure_v16_1_policy(working)
            working['revision'] = int(graph.get('revision', 0)) + 1
            working['updatedAt'] = _v16.format_v16_time()
            try:
                stored = self.store.update(
                    self.path,
                    working,
                    version,
                    message='swarm v16.1: activate convergence policy',
                )
            except _v16.ConflictError as exc:
                last = exc
                graph, version = super().ensure(seed or seed_nembra_graph())
                if (graph.get('modes', {}).get('v16_1') or {}).get('policyVersion') == V16_1_POLICY_VERSION:
                    return graph, version
                continue
            return _v16.validate_graph(stored.value), stored.version
        raise _v16.ConflictError('V16.1 policy activation CAS retry budget exhausted') from last


def v16_graph_service(store: Any) -> V16_1MissionGraphStore:
    return V16_1MissionGraphStore(store, max_retries=64)


@dataclass(frozen=True)
class BranchAdmission:
    allowed: bool
    action: str
    join_branch: str
    existing_work_item_id: str
    reason: str


def _active_blocker_work(graph: Mapping[str, Any], blocker_id: str) -> list[Mapping[str, Any]]:
    return [
        item for item in graph.get('workItems', {}).values()
        if item.get('blockerId') == blocker_id
        and item.get('role') == 'builder'
        and item.get('status') not in {'DONE', 'SUPERSEDED', 'ARCHIVED'}
    ]


def _blocker_family(blocker_id: str) -> str:
    return '-'.join(blocker_id.split('-')[:3])


def branch_admission(
    graph: Mapping[str, Any],
    *,
    objective_id: str,
    blocker_id: str = '',
    branch: str = '',
    role: str = 'builder',
    tournament_id: str = '',
) -> BranchAdmission:
    if role != 'builder' or not blocker_id:
        return BranchAdmission(True, 'CREATE_OR_USE_ASSIGNED', branch, '', 'non-builder or objective-level work')
    blocker = graph.get('blockers', {}).get(blocker_id)
    if not blocker:
        raise _v16.ValidationError('unknown blocker')

    active = _active_blocker_work(graph, blocker_id)
    if tournament_id:
        tournament = graph.get('solutions', {}).get(tournament_id) or {}
        if not tournament.get('authorized') or tournament.get('blockerId') != blocker_id:
            return BranchAdmission(False, 'DENY', '', '', 'solution tournament is not authorized for this blocker')
        candidates = [item for item in active if item.get('tournamentId') == tournament_id]
        limit = min(int(tournament.get('candidateLimit', 0) or 0), V16_1_MAX_TOURNAMENT_CANDIDATES)
        if len(candidates) >= limit:
            return BranchAdmission(False, 'JOIN_TOURNAMENT', candidates[0].get('branch', '') if candidates else '', candidates[0].get('workItemId', '') if candidates else '', 'V16.1 tournament candidate limit reached')
        return BranchAdmission(True, 'CREATE_TOURNAMENT_CANDIDATE', branch, '', 'bounded tournament candidate admitted')

    if active:
        selected = sorted(
            active,
            key=lambda item: (
                0 if item.get('branchState') == 'SELECTED' else 1,
                0 if item.get('branch') else 1,
                item.get('createdAt', ''),
                item.get('workItemId', ''),
            ),
        )[0]
        join_branch = str(selected.get('branch') or graph['objectives'][objective_id].get('canonicalBranch') or '')
        if not branch or branch != join_branch:
            return BranchAdmission(False, 'JOIN_EXISTING', join_branch, str(selected.get('workItemId') or ''), f'blocker already has active builder work {selected.get("workItemId")}')

    attempts = blocker.get('attempts', [])
    prior_branches = list(dict.fromkeys(str(attempt.get('branch') or '') for attempt in attempts if attempt.get('branch')))
    family = _blocker_family(blocker_id)
    frozen = family in set(graph.get('modes', {}).get('frozenBranchFamilies', []))
    if branch and branch not in prior_branches and (frozen or len(prior_branches) >= V16_1_MAX_DISTINCT_ATTEMPT_BRANCHES):
        join_branch = active[0].get('branch', '') if active else str(graph['objectives'][objective_id].get('canonicalBranch') or '')
        return BranchAdmission(False, 'JOIN_EXISTING', join_branch, active[0].get('workItemId', '') if active else '', 'V16.1 convergence freeze blocks another successor branch')
    return BranchAdmission(True, 'CREATE_OR_USE_ASSIGNED', branch, '', 'no competing builder branch exists')


def add_work_item(graph: dict[str, Any], **kwargs):
    ensure_v16_1_policy(graph)
    role = kwargs.get('role', 'builder')
    blocker_id = kwargs.get('blocker_id', '')
    tournament_id = kwargs.get('tournament_id', '')
    branch = kwargs.get('branch', '')
    objective_id = kwargs['objective_id']
    allow_duplicate = bool(kwargs.get('allow_duplicate', False))

    admission = branch_admission(
        graph,
        objective_id=objective_id,
        blocker_id=blocker_id,
        branch=branch,
        role=role,
        tournament_id=tournament_id,
    )
    if not admission.allowed:
        graph['metrics']['branchForksPrevented'] += 1
        _v16._memory(
            graph,
            'V16_1_BRANCH_SUPPRESSED',
            f"Suppressed {kwargs['work_item_id']}; {admission.reason}; action={admission.action}; join={admission.join_branch}",
            objective_id,
            kwargs.get('now'),
        )
        decision = _v16.DuplicateDecision(True, 1.0, admission.existing_work_item_id, admission.action, admission.reason)
        return graph, decision

    # V16 allowed callers to force duplicates with allow_duplicate=True. V16.1
    # keeps that escape hatch only for reviewers/integrators or an explicitly
    # authorized bounded tournament. Builders cannot mint successor PRs by flag.
    if role == 'builder' and allow_duplicate and not tournament_id:
        kwargs['allow_duplicate'] = False
    return _v16.add_work_item(graph, **kwargs)


def authorize_tournament(graph: dict[str, Any], tournament_id: str, blocker_id: str, candidate_limit=2, now=None):
    ensure_v16_1_policy(graph)
    if candidate_limit > V16_1_MAX_TOURNAMENT_CANDIDATES:
        raise _v16.ValidationError('V16.1 solution tournament is limited to two candidates')
    return _v16.authorize_tournament(graph, tournament_id, blocker_id, candidate_limit, now)


def add_blocker(graph: dict[str, Any], **kwargs):
    ensure_v16_1_policy(graph)
    objective_id = kwargs['objective_id']
    symptom = kwargs['symptom']
    exit_condition = kwargs['exit_condition']
    for existing in graph.get('blockers', {}).values():
        if existing.get('objectiveId') != objective_id or existing.get('state') == 'RESOLVED':
            continue
        score = _v16.semantic_similarity(
            f'{symptom} {exit_condition}',
            f"{existing.get('symptom', '')} {existing.get('exitCondition', '')}",
        )
        if score >= V16_1_BLOCKER_DUPLICATE_THRESHOLD:
            graph['metrics']['duplicateBlockersPrevented'] += 1
            raise _v16.ConflictError(f"V16.1 duplicate blocker; join {existing['blockerId']} instead of creating {kwargs['blocker_id']}")
    return _v16.add_blocker(graph, **kwargs)


def record_blocker_attempt(graph: dict[str, Any], blocker_id: str, **kwargs):
    ensure_v16_1_policy(graph)
    blocker = graph['blockers'][blocker_id]
    branch = str(kwargs.get('branch') or '')
    meaningful = bool(kwargs.get('meaningful_progress', False))
    prior_branches = list(dict.fromkeys(str(attempt.get('branch') or '') for attempt in blocker.get('attempts', []) if attempt.get('branch')))
    if branch and branch not in prior_branches and len(prior_branches) >= V16_1_MAX_DISTINCT_ATTEMPT_BRANCHES and not meaningful:
        family = _blocker_family(blocker_id)
        for key in ('convergenceFamilies', 'frozenBranchFamilies'):
            if family not in graph['modes'][key]:
                graph['modes'][key].append(family)
        graph['metrics']['branchForksPrevented'] += 1
        _v16._memory(graph, 'V16_1_CONVERGENCE_FREEZE', f'Blocked third low-progress branch for {blocker_id}; join existing work', blocker['objectiveId'], kwargs.get('now'))
        raise _v16.ConflictError('V16.1 blocks a third low-progress successor branch for one blocker')

    result = _v16.record_blocker_attempt(graph, blocker_id, **kwargs)
    recent = blocker['attempts'][-V16_1_LOW_PROGRESS_ATTEMPTS_BEFORE_FREEZE:]
    if len(recent) >= V16_1_LOW_PROGRESS_ATTEMPTS_BEFORE_FREEZE and sum(bool(item.get('meaningfulProgress')) for item in recent) <= 1:
        family = _blocker_family(blocker_id)
        for key in ('convergenceFamilies', 'frozenBranchFamilies'):
            if family not in graph['modes'][key]:
                graph['modes'][key].append(family)
        _v16._memory(graph, 'V16_1_CONVERGENCE_MODE', f'V16.1 froze competing branches for {blocker_id} after {len(recent)} low-progress attempts', blocker['objectiveId'], kwargs.get('now'))
    return result


def rabbit_hole_review_required(graph: Mapping[str, Any], blocker_id: str) -> tuple[bool, str]:
    attempts = graph['blockers'][blocker_id]['attempts']
    if len(attempts) < V16_1_LOW_PROGRESS_ATTEMPTS_BEFORE_FREEZE:
        return False, 'insufficient attempts'
    workers = len({item.get('worker') for item in attempts if item.get('worker')})
    branches = len({item.get('branch') for item in attempts if item.get('branch')})
    progress = sum(bool(item.get('meaningfulProgress')) for item in attempts)
    activity = len(attempts) + workers + branches
    return (activity >= 7 and progress <= 1), f'activity={activity}, progress={progress}'


def recommend_mission_packets(graph: Mapping[str, Any], *, worker_ids: Sequence[str] = (), limit=30, now=None):
    packets = _v16.recommend_mission_packets(graph, worker_ids=worker_ids, limit=limit, now=now)
    filtered = []
    seen_builder_blockers: set[str] = set()
    for packet in packets:
        item = graph['workItems'][packet.work_item_id]
        blocker_id = str(item.get('blockerId') or '')
        if item.get('role') == 'builder' and blocker_id:
            if blocker_id in seen_builder_blockers:
                continue
            seen_builder_blockers.add(blocker_id)
        payload = dict(packet.packet)
        payload['CONVERGENCE_POLICY'] = V16_1_POLICY_VERSION
        payload['BLOCKER_ID'] = blocker_id
        payload['BLOCKER_OWNER'] = graph['blockers'].get(blocker_id, {}).get('owner', '') if blocker_id else ''
        payload['BRANCH_ACTION'] = 'USE_EXISTING' if item.get('branch') else 'USE_CANONICAL'
        payload['JOIN_BRANCH'] = item.get('branch') or graph['objectives'][item['objectiveId']].get('canonicalBranch', '')
        payload['MAY_CREATE_SUCCESSOR_PR'] = False
        payload['MAX_PARALLEL_SOLUTIONS'] = V16_1_MAX_TOURNAMENT_CANDIDATES
        payload['LOST_CLAIM_ACTION'] = 'refresh and claim different scheduled work; do not invent a successor branch'
        filtered.append(_v16.MissionPacket(packet.mission_id, packet.objective_id, packet.work_item_id, packet.role, packet.priority_score, payload))
    return filtered[:limit]


def go_cycle(graph: dict[str, Any], worker_id: str, *, completed_work_item_id='', evidence_ids: Sequence[str] = (), now=None) -> dict[str, Any]:
    ensure_v16_1_policy(graph)
    if completed_work_item_id:
        item = graph['workItems'][completed_work_item_id]
        if not evidence_ids:
            raise _v16.ValidationError('GO completion requires evidence')
        item['status'] = 'REVIEW' if item['role'] == 'builder' else ('INTEGRATING' if item['role'] == 'reviewer' else 'DONE')
        item['evidenceIds'] = list(dict.fromkeys(item['evidenceIds'] + list(evidence_ids)))
        item['updatedAt'] = _v16.format_v16_time(now)
        item['owner'] = ''
        _v16._memory(graph, 'GO_HANDOFF', f'{worker_id} completed {completed_work_item_id}; requesting next safe work', item['objectiveId'], now)
    packets = recommend_mission_packets(graph, worker_ids=[worker_id], limit=1, now=now)
    return {
        'status': 'WORK' if packets else 'IDLE',
        'reason': 'highest-value safe V16.1 mission packet' if packets else 'no safe unblocked internal work remains',
        'next': asdict(packets[0]) if packets else None,
    }


_META_RE = re.compile(r'^\s*(SWARM_[A-Z0-9_]+)\s*:\s*(.*?)\s*$', re.I | re.M)


def parse_swarm_pr_metadata(pr: Mapping[str, Any]) -> dict[str, str]:
    body = str(pr.get('body') or '')
    values = {key.upper(): value.strip() for key, value in _META_RE.findall(body)}
    return {
        'protocol': values.get('SWARM_PROTOCOL', ''),
        'schema': values.get('SWARM_SCHEMA', ''),
        'lane': values.get('SWARM_LANE', '').lower(),
        'slot': values.get('SWARM_SLOT', '').lower(),
        'worker': values.get('SWARM_WORKER', ''),
        'intent': values.get('SWARM_BRANCH_INTENT', '').lower(),
        'parentPR': values.get('SWARM_PARENT_PR', ''),
        'tournamentId': values.get('SWARM_TOURNAMENT_ID', ''),
    }


@dataclass(frozen=True)
class PRAdmissionDecision:
    allowed: bool
    action: str
    reason: str
    join_pr: int | None = None


def evaluate_pr_admission(pr: Mapping[str, Any], peers: Sequence[Mapping[str, Any]]) -> PRAdmissionDecision:
    meta = parse_swarm_pr_metadata(pr)
    managed = any((meta['lane'], meta['worker'], meta['schema'], meta['protocol']))
    if not managed:
        return PRAdmissionDecision(True, 'ALLOW_UNMANAGED', 'not a swarm-managed PR')
    if meta['protocol'] != V16_1_POLICY_VERSION:
        return PRAdmissionDecision(False, 'UPGRADE_METADATA', 'new swarm PRs must declare SWARM_PROTOCOL: 16.1')
    required = ('lane', 'slot', 'worker', 'intent')
    missing = [field for field in required if not meta[field]]
    if missing:
        return PRAdmissionDecision(False, 'FIX_METADATA', 'missing V16.1 PR metadata: ' + ', '.join(missing))
    if meta['intent'] not in {'canonical', 'validation', 'review', 'integration', 'tournament'}:
        return PRAdmissionDecision(False, 'FIX_METADATA', 'SWARM_BRANCH_INTENT must be canonical, validation, review, integration, or tournament')
    if meta['intent'] in {'validation', 'tournament'} and not meta['parentPR']:
        return PRAdmissionDecision(False, 'JOIN_PARENT', 'validation/tournament PR requires SWARM_PARENT_PR')
    if meta['intent'] == 'tournament' and not meta['tournamentId']:
        return PRAdmissionDecision(False, 'FIX_METADATA', 'tournament PR requires SWARM_TOURNAMENT_ID')

    current_number = int(pr.get('number') or 0)
    live = []
    for peer in peers:
        if int(peer.get('number') or 0) == current_number:
            continue
        if str(peer.get('state') or 'open').lower() != 'open':
            continue
        peer_meta = parse_swarm_pr_metadata(peer)
        if peer_meta['lane'] == meta['lane']:
            live.append((peer, peer_meta))

    same_slot = [(peer, pm) for peer, pm in live if pm['slot'] and pm['slot'] == meta['slot']]
    if same_slot:
        target = sorted(same_slot, key=lambda pair: int(pair[0].get('number') or 0))[0][0]
        return PRAdmissionDecision(False, 'JOIN_EXISTING', f"lane/slot already has open PR #{target.get('number')}; join it instead of creating a successor", int(target.get('number') or 0))

    if meta['intent'] == 'canonical':
        canonical = [(peer, pm) for peer, pm in live if pm['intent'] == 'canonical']
        if canonical:
            target = sorted(canonical, key=lambda pair: int(pair[0].get('number') or 0))[0][0]
            return PRAdmissionDecision(False, 'JOIN_CANONICAL', f"lane already has canonical PR #{target.get('number')}; consolidate there", int(target.get('number') or 0))

    noncanonical = [(peer, pm) for peer, pm in live if pm['intent'] in {'validation', 'review', 'integration', 'tournament'} or not pm['intent']]
    if len(noncanonical) >= V16_1_MAX_OPEN_NONCANONICAL_PRS_PER_LANE:
        return PRAdmissionDecision(False, 'CONVERGE_FIRST', f'lane already has {len(noncanonical)} open noncanonical PRs; close/supersede/integrate before another branch')
    return PRAdmissionDecision(True, 'ALLOW', 'V16.1 admission accepted')


def run_v16_1_adversarial_simulation(workers=30, now=None) -> dict[str, Any]:
    if workers < 20:
        raise _v16.ValidationError('V16.1 swarm simulation requires at least 20 workers')
    graph = seed_nembra_graph(now)
    stamp = now
    add_blocker(
        graph,
        blocker_id='v161-auth-blocker',
        mission_id='capture-stationary',
        objective_id='capture-tuya-auth',
        symptom='authenticated Tuya session cannot complete after accepted account setup',
        severity='P0',
        exit_condition='authenticated structured read succeeds',
        legitimate_new=False,
        now=stamp,
    )
    add_work_item(
        graph,
        work_item_id='v161-auth-primary',
        mission_id='capture-stationary',
        objective_id='capture-tuya-auth',
        blocker_id='v161-auth-blocker',
        title='Repair authenticated Tuya session',
        outcome='close authenticated session blocker',
        branch='mission/capture-tuya-auth',
        now=stamp,
    )
    _, duplicate = add_work_item(
        graph,
        work_item_id='v161-auth-successor',
        mission_id='capture-stationary',
        objective_id='capture-tuya-auth',
        blocker_id='v161-auth-blocker',
        title='Different recovery for Tuya login',
        outcome='try another authentication recovery architecture',
        branch='recovery/v161-auth-successor',
        allow_duplicate=True,
        now=stamp,
    )
    checks = {
        'forced_successor_suppressed': duplicate.duplicate and 'v161-auth-successor' not in graph['workItems'],
        'one_builder_branch_per_blocker': len(_active_blocker_work(graph, 'v161-auth-blocker')) == 1,
    }
    authorize_tournament(graph, 'v161-auth-tournament', 'v161-auth-blocker', 2, stamp)
    for index in range(2):
        add_work_item(
            graph,
            work_item_id=f'v161-exp-{index}',
            mission_id='capture-stationary',
            objective_id='capture-tuya-auth',
            blocker_id='v161-auth-blocker',
            title=f'Bounded auth experiment {index}',
            outcome=f'candidate {index}',
            branch=f'experimental/v161-auth-{index}',
            tournament_id='v161-auth-tournament',
            allow_duplicate=True,
            now=stamp,
        )
    try:
        add_work_item(
            graph,
            work_item_id='v161-exp-2',
            mission_id='capture-stationary',
            objective_id='capture-tuya-auth',
            blocker_id='v161-auth-blocker',
            title='Third auth experiment',
            outcome='candidate 2',
            branch='experimental/v161-auth-2',
            tournament_id='v161-auth-tournament',
            allow_duplicate=True,
            now=stamp,
        )
        checks['third_tournament_candidate_blocked'] = 'v161-exp-2' not in graph['workItems']
    except _v16.ValidationError:
        checks['third_tournament_candidate_blocked'] = True

    packets = recommend_mission_packets(graph, worker_ids=[f'sol-20260813-v161{i:02d}' for i in range(workers)], limit=workers, now=stamp)
    blocker_builders = [packet for packet in packets if packet.role == 'builder' and packet.packet.get('BLOCKER_ID') == 'v161-auth-blocker']
    checks['scheduler_emits_one_builder_packet_per_blocker'] = len(blocker_builders) == 1
    checks['packet_forbids_successor_pr'] = bool(blocker_builders and blocker_builders[0].packet.get('MAY_CREATE_SUCCESSOR_PR') is False)

    first_pr = {'number': 100, 'state': 'open', 'body': 'SWARM_PROTOCOL: 16.1\nSWARM_SCHEMA: 2\nSWARM_LANE: capture-auth\nSWARM_SLOT: auth-login\nSWARM_WORKER: sol-20260813-a\nSWARM_BRANCH_INTENT: canonical'}
    second_pr = {'number': 101, 'state': 'open', 'body': 'SWARM_PROTOCOL: 16.1\nSWARM_SCHEMA: 2\nSWARM_LANE: capture-auth\nSWARM_SLOT: auth-login\nSWARM_WORKER: sol-20260813-b\nSWARM_BRANCH_INTENT: validation\nSWARM_PARENT_PR: #100'}
    admission = evaluate_pr_admission(second_pr, [first_pr, second_pr])
    checks['github_admission_routes_duplicate_to_existing_pr'] = not admission.allowed and admission.join_pr == 100
    return {'passed': all(checks.values()), 'workers': workers, 'checks': checks}
