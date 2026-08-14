from __future__ import annotations

"""Swarm V16.2 integration-throughput policy.

V16.1 solved premature worker idle and successor-branch fanout. V16.2 keeps those
safety/convergence rules and adds a second invariant: accepted/near-accepted work
must receive increasing integration pressure until it reaches the canonical
branch / MAIN, is explicitly rejected, or is genuinely externally blocked.
"""

import copy
import datetime as dt
import hashlib
from dataclasses import asdict
from typing import Any, Mapping, Sequence

from . import mission_graph as _v16
from . import v16_1 as _v161
from . import v16_1_persistence_v2 as _persist

V16_2_POLICY_VERSION = "16.2"
V16_2_MAX_OPEN_CHILDREN_PER_PARENT = 2
V16_2_MAX_OPEN_INTEGRATION_CHILDREN_PER_PARENT = 1
V16_2_REVIEW_AGE_PRESSURE_SECONDS = 10 * 60
V16_2_HEAVY_BACKLOG = 4


def _policy_defaults() -> dict[str, Any]:
    return {
        "policyVersion": V16_2_POLICY_VERSION,
        "integrationBeforeCapacityMining": True,
        "automaticMergePressure": True,
        "canonicalAbsorptionRequired": True,
        "maxOpenChildrenPerParent": V16_2_MAX_OPEN_CHILDREN_PER_PARENT,
        "maxOpenIntegrationChildrenPerParent": V16_2_MAX_OPEN_INTEGRATION_CHILDREN_PER_PARENT,
        "reviewAgePressureSeconds": V16_2_REVIEW_AGE_PRESSURE_SECONDS,
        "producerSchemaFence": True,
        "mergePressureMayBypassTruthGates": False,
    }


def ensure_v16_2_policy(graph: dict[str, Any]) -> dict[str, Any]:
    _v161.ensure_v16_1_policy(graph)
    modes = graph.setdefault("modes", {})
    modes.setdefault("mergePressureObjectives", [])
    modes.setdefault("canonicalAbsorptionObjectives", [])
    modes["v16_2"] = {**_policy_defaults(), **dict(modes.get("v16_2") or {})}
    metrics = graph.setdefault("metrics", {})
    metrics.setdefault("mergePressureCycles", 0)
    metrics.setdefault("canonicalAbsorptionsRequested", 0)
    metrics.setdefault("childPRsPrevented", 0)
    metrics.setdefault("integrationCandidatesPromoted", 0)
    return graph


def seed_nembra_graph(now=None) -> dict[str, Any]:
    graph = _v161.seed_nembra_graph(now)
    return ensure_v16_2_policy(graph)


def validate_graph(graph: Any) -> dict[str, Any]:
    validated = _v16.validate_graph(graph)
    return ensure_v16_2_policy(validated)


class V16_2MissionGraphStore(_v161.V16_1MissionGraphStore):
    """Lazily activate V16.2 on schema-16 state without resetting the graph."""

    def ensure(self, seed: Mapping[str, Any] | None = None):
        graph, version = super().ensure(seed or seed_nembra_graph())
        if (graph.get("modes", {}).get("v16_2") or {}).get("policyVersion") == V16_2_POLICY_VERSION:
            return graph, version
        last = None
        for _ in range(4):
            working = copy.deepcopy(graph)
            ensure_v16_2_policy(working)
            working["revision"] = int(graph.get("revision", 0)) + 1
            working["updatedAt"] = _v16.format_v16_time()
            try:
                stored = self.store.update(
                    self.path,
                    working,
                    version,
                    message="swarm v16.2: activate integration-throughput policy",
                )
            except _v16.ConflictError as exc:
                last = exc
                graph, version = super().ensure(seed or seed_nembra_graph())
                if (graph.get("modes", {}).get("v16_2") or {}).get("policyVersion") == V16_2_POLICY_VERSION:
                    return graph, version
                continue
            return validate_graph(stored.value), stored.version
        raise _v16.ConflictError("V16.2 policy activation CAS retry budget exhausted") from last


def v16_graph_service(store: Any) -> V16_2MissionGraphStore:
    return V16_2MissionGraphStore(store, max_retries=64)


def _stable_number(value: str) -> int:
    return int.from_bytes(hashlib.sha256(value.encode("utf-8")).digest()[:8], "big")


def _parse_time(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _now(value=None) -> dt.datetime:
    if value is None:
        return dt.datetime.now(dt.timezone.utc)
    if value.tzinfo is None:
        value = value.replace(tzinfo=dt.timezone.utc)
    return value.astimezone(dt.timezone.utc)


def _item_age_seconds(item: Mapping[str, Any], now=None) -> float:
    try:
        return max(0.0, (_now(now) - _parse_time(str(item.get("updatedAt") or item.get("createdAt")))).total_seconds())
    except Exception:
        return 0.0


def integration_candidates(graph: Mapping[str, Any], now=None) -> list[tuple[float, Mapping[str, Any]]]:
    """Return integration/review work ordered by pressure, never by raw PR count."""
    severity = {"P0": 900.0, "P1": 550.0, "P2": 180.0, "P3": 40.0}
    out: list[tuple[float, Mapping[str, Any]]] = []
    for item in graph.get("workItems", {}).values():
        if item.get("status") not in {"REVIEW", "INTEGRATING"}:
            continue
        obj = graph.get("objectives", {}).get(item.get("objectiveId"))
        if not obj or obj.get("status") in {"DONE", "EXTERNAL_BLOCKED"}:
            continue
        blocker_id = str(item.get("blockerId") or "")
        blocker = graph.get("blockers", {}).get(blocker_id) if blocker_id else None
        if blocker and blocker.get("state") == "EXTERNAL":
            continue
        score = 1400.0 if item.get("status") == "INTEGRATING" else 900.0
        score += severity.get(str(obj.get("severity") or "P3"), 0.0)
        score += float(obj.get("userValue", 0)) * 25.0
        score += 300.0 if obj.get("releaseBlocking") else 0.0
        age = _item_age_seconds(item, now)
        score += min(age / 60.0, 240.0)
        if item.get("integrationWorld") == "NEXT":
            score += 180.0
        if item.get("branchState") == "SELECTED":
            score += 160.0
        out.append((score, item))
    out.sort(key=lambda pair: (-pair[0], str(pair[1].get("updatedAt") or ""), str(pair[1].get("workItemId") or "")))
    return out


def canonical_absorption_plan(graph: Mapping[str, Any]) -> list[dict[str, Any]]:
    """Describe where accepted child work should converge; never mutates branches itself."""
    plans: list[dict[str, Any]] = []
    terminal = {"DONE", "SUPERSEDED", "ARCHIVED"}
    for objective_id, obj in graph.get("objectives", {}).items():
        canonical = str(obj.get("canonicalBranch") or "")
        items = [
            item for item in graph.get("workItems", {}).values()
            if item.get("objectiveId") == objective_id and item.get("status") not in terminal
        ]
        children = [
            item for item in items
            if item.get("branch") and str(item.get("branch")) != canonical
            and item.get("status") in {"REVIEW", "INTEGRATING"}
        ]
        if not children:
            continue
        canonical_items = [item for item in items if canonical and item.get("branch") == canonical]
        plans.append({
            "objectiveId": objective_id,
            "canonicalBranch": canonical,
            "canonicalWorkItemIds": [str(item.get("workItemId")) for item in canonical_items],
            "childWorkItemIds": [str(item.get("workItemId")) for item in children],
            "action": "ABSORB_INTO_CANONICAL" if canonical else "SELECT_CANONICAL_THEN_ABSORB",
            "fanoutExcess": max(0, len(children) - V16_2_MAX_OPEN_CHILDREN_PER_PARENT),
        })
    plans.sort(key=lambda item: (-item["fanoutExcess"], item["objectiveId"]))
    return plans


def merge_pressure_report(graph: Mapping[str, Any], now=None) -> dict[str, Any]:
    candidates = integration_candidates(graph, now)
    review_aged = sum(
        item.get("status") == "REVIEW" and _item_age_seconds(item, now) >= V16_2_REVIEW_AGE_PRESSURE_SECONDS
        for _, item in candidates
    )
    integrating = sum(item.get("status") == "INTEGRATING" for _, item in candidates)
    queue = list((graph.get("mergeTrain") or {}).get("queue") or [])
    absorption = canonical_absorption_plan(graph)
    active = bool(integrating or queue or review_aged or len(candidates) >= 2 or absorption)
    objectives = sorted({str(item.get("objectiveId")) for _, item in candidates} | {p["objectiveId"] for p in absorption})
    return {
        "active": active,
        "candidateCount": len(candidates),
        "integratingCount": integrating,
        "agedReviewCount": review_aged,
        "mergeTrainQueue": len(queue),
        "absorptionObjectiveCount": len(absorption),
        "objectives": objectives,
        "heavy": len(candidates) >= V16_2_HEAVY_BACKLOG or len(queue) >= 2,
    }


def role_allocation(graph: Mapping[str, Any], workers: int = 30) -> dict[str, int]:
    if workers < 1:
        raise _v16.ValidationError("workers must be positive")
    pressure = merge_pressure_report(graph)
    if not pressure["active"]:
        return _v16.role_allocation(graph, workers)
    if pressure["heavy"]:
        builder = round(workers * 0.25)
        reviewer = round(workers * 0.18)
    else:
        builder = round(workers * 0.35)
        reviewer = round(workers * 0.20)
    integrator = workers - builder - reviewer
    return {"builder": builder, "reviewer": reviewer, "integrator": integrator}


def _merge_packet(graph: Mapping[str, Any], item: Mapping[str, Any], worker_id: str, score: float) -> _v16.MissionPacket:
    obj = graph["objectives"][item["objectiveId"]]
    mission = graph["missions"][item["missionId"]]
    canonical = str(obj.get("canonicalBranch") or item.get("branch") or "")
    duty_index = _stable_number(worker_id + "::" + str(item.get("workItemId"))) % 4
    duty = ("INTEGRATE", "RED_TEAM", "TEST", "CONFLICT_CHECK")[duty_index]
    exclusive = duty == "INTEGRATE"
    payload = {
        "CONVERGENCE_POLICY": V16_2_POLICY_VERSION,
        "MODE": "MERGE_PRESSURE",
        "MERGE_PRESSURE_DUTY": duty,
        "STOP_AUTHORIZED": False,
        "MISSION": mission["title"],
        "WHY_IT_MATTERS": mission["why"],
        "CURRENT_STATE": obj["status"],
        "CANONICAL_BRANCH": canonical,
        "JOIN_BRANCH": canonical,
        "SOURCE_BRANCH": str(item.get("branch") or ""),
        "CANONICAL_ABSORPTION_REQUIRED": bool(item.get("branch") and canonical and item.get("branch") != canonical),
        "CLAIM_REQUIRED": exclusive,
        "WRITE_AUTHORITY": "requires exact work-item claim" if exclusive else False,
        "MAY_CREATE_BRANCH": False,
        "MAY_CREATE_SUCCESSOR_PR": False,
        "PRIMARY_SCOPE": item.get("primaryScope", []),
        "FORBIDDEN_AREAS": item.get("forbiddenAreas", []),
        "SAFE_ACTIONS": [
            "absorb accepted child work into the canonical branch instead of opening another successor",
            "resolve compatible conflicts and keep both intended behaviors",
            "run impacted acceptance on the exact composed head",
            "close or mark superseded child work once its evidence is preserved",
            "promote to MAIN only after required evidence remains valid",
        ],
        "TRUTH_GATE": "Merge pressure never weakens signing, authentication, telemetry, exact-head, physical, or safety acceptance.",
        "AFTER_TASK": "refresh; if accepted work remains outside MAIN, continue merge pressure before capacity mining",
    }
    return _v16.MissionPacket(
        item["missionId"], item["objectiveId"], item["workItemId"],
        "integrator" if exclusive else "reviewer", score, payload,
    )


def worker_continuation_plan(graph: Mapping[str, Any], worker_id: str, *, limit: int = 8, now=None) -> list[_v16.MissionPacket]:
    if limit < 1:
        return []
    base = list(_persist.worker_continuation_plan(graph, worker_id, limit=max(limit, 8), now=now))
    candidates = integration_candidates(graph, now)
    if not candidates:
        return base[:limit]

    pressure_slot = _stable_number(worker_id + "::merge-pressure") % 10
    # Reserve most burst capacity for convergence while still leaving builders
    # available for genuinely release-blocking implementation.
    if pressure_slot >= (8 if len(candidates) >= V16_2_HEAVY_BACKLOG else 6):
        return base[:limit]

    index = _stable_number(worker_id + "::candidate") % len(candidates)
    score, item = candidates[index]
    first = _merge_packet(graph, item, worker_id, score + 2000.0)
    out = [first]
    seen = {(first.work_item_id, str(first.packet.get("MODE")))}
    for packet in base:
        key = (packet.work_item_id, str(packet.packet.get("MODE") or "PRIMARY"))
        if key in seen:
            continue
        out.append(packet)
        seen.add(key)
        if len(out) >= limit:
            break
    return out


def recommend_mission_packets(
    graph: Mapping[str, Any],
    *,
    worker_ids: Sequence[str] = (),
    limit: int = 30,
    now=None,
):
    if limit < 1:
        return []
    if worker_ids:
        result = []
        for worker_id in list(worker_ids)[:limit]:
            plan = worker_continuation_plan(graph, worker_id, limit=8, now=now)
            if not plan:
                continue
            packet = plan[0]
            payload = dict(packet.packet)
            payload["ASSIGNED_WORKER"] = worker_id
            result.append(_v16.MissionPacket(
                packet.mission_id, packet.objective_id, packet.work_item_id,
                packet.role, packet.priority_score, payload,
            ))
        return result

    pressure = integration_candidates(graph, now)
    result: list[_v16.MissionPacket] = []
    for index, (score, item) in enumerate(pressure[: min(limit, 6)]):
        result.append(_merge_packet(graph, item, f"operator-{index}", score + 2000.0))
    seen = {(p.work_item_id, str(p.packet.get("MODE") or "PRIMARY")) for p in result}
    for packet in _persist.recommend_mission_packets(graph, worker_ids=(), limit=limit, now=now):
        key = (packet.work_item_id, str(packet.packet.get("MODE") or "PRIMARY"))
        if key in seen:
            continue
        result.append(packet)
        seen.add(key)
        if len(result) >= limit:
            break
    return result[:limit]


def go_cycle(
    graph: dict[str, Any],
    worker_id: str,
    *,
    completed_work_item_id: str = "",
    evidence_ids: Sequence[str] = (),
    now=None,
) -> dict[str, Any]:
    ensure_v16_2_policy(graph)
    if completed_work_item_id:
        _persist.go_cycle(
            graph,
            worker_id,
            completed_work_item_id=completed_work_item_id,
            evidence_ids=evidence_ids,
            now=now,
        )
    pressure = merge_pressure_report(graph, now)
    graph["modes"]["mergePressureObjectives"] = pressure["objectives"] if pressure["active"] else []
    graph["modes"]["canonicalAbsorptionObjectives"] = [p["objectiveId"] for p in canonical_absorption_plan(graph)]
    if pressure["active"]:
        graph["metrics"]["mergePressureCycles"] += 1
    plan = worker_continuation_plan(graph, worker_id, limit=8, now=now)
    if not plan:
        return {
            "status": "STOP",
            "stopAuthorized": True,
            "reason": "no dependency-valid internal implementation, review, integration, or absorption work remains",
            "next": None,
            "fallbacks": [],
            "mergePressure": pressure,
        }
    first = plan[0]
    mode = str(first.packet.get("MODE") or "PRIMARY")
    return {
        "status": "WORK" if mode == "PRIMARY" else "ASSIST",
        "stopAuthorized": False,
        "reason": "V16.2 merge pressure" if mode == "MERGE_PRESSURE" else "continue on dependency-valid swarm work",
        "next": asdict(first),
        "fallbacks": [asdict(packet) for packet in plan[1:]],
        "mergePressure": pressure,
        "onClaimConflict": "use another merge/review/test duty or next fallback immediately; never create a successor just because integration ownership is busy",
    }
