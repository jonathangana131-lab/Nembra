from __future__ import annotations

from dataclasses import asdict
from typing import Any, Mapping, Sequence

from . import mission_graph as _v16
from . import v16_1 as _base
from . import v16_1_persistence as _p


def _dependencies_done(graph: Mapping[str, Any], objective_id: str) -> bool:
    obj = graph["objectives"][objective_id]
    return all(graph["objectives"].get(dep, {}).get("status") == "DONE" for dep in obj.get("dependencies", []))


def _safe_assists(graph: Mapping[str, Any]):
    return [
        packet for packet in _p._assist_candidates(graph)
        if _dependencies_done(graph, packet.objective_id)
    ]


def worker_continuation_plan(graph: Mapping[str, Any], worker_id: str, *, limit: int = 8, now=None):
    if limit < 1:
        return []
    primary = [_p._decorate_primary(packet) for packet in _base.recommend_mission_packets(
        graph,
        worker_ids=(),
        limit=max(64, len(graph.get("workItems", {})) + 8),
        now=now,
    )]
    if primary:
        start = _p._stable_index(worker_id, len(primary))
        primary = primary[start:] + primary[:start]
    combined = []
    seen = set()
    for packet in primary + _safe_assists(graph):
        key = (packet.work_item_id, str(packet.packet.get("MODE") or "PRIMARY"))
        if key in seen:
            continue
        seen.add(key)
        combined.append(packet)
        if len(combined) >= limit:
            break
    return combined


def recommend_mission_packets(
    graph: Mapping[str, Any],
    *,
    worker_ids: Sequence[str] = (),
    limit: int = 30,
    now=None,
):
    # Preserve the original operator/API contract when no worker identities are
    # supplied. Worker persistence is an execution-lifecycle feature, not a
    # reason to turn ordinary scheduler queries into synthetic work.
    if not worker_ids:
        return _base.recommend_mission_packets(graph, worker_ids=(), limit=limit, now=now)
    result = []
    for worker_id in list(worker_ids)[:limit]:
        plan = worker_continuation_plan(graph, worker_id, limit=8, now=now)
        if not plan:
            continue
        packet = plan[0]
        payload = dict(packet.packet)
        payload["ASSIGNED_WORKER"] = worker_id
        result.append(_v16.MissionPacket(
            packet.mission_id,
            packet.objective_id,
            packet.work_item_id,
            packet.role,
            packet.priority_score,
            payload,
        ))
    return result


def go_cycle(
    graph: dict[str, Any],
    worker_id: str,
    *,
    completed_work_item_id: str = "",
    evidence_ids: Sequence[str] = (),
    now=None,
):
    _base.ensure_v16_1_policy(graph)
    if completed_work_item_id:
        _base.go_cycle(
            graph,
            worker_id,
            completed_work_item_id=completed_work_item_id,
            evidence_ids=evidence_ids,
            now=now,
        )
    plan = worker_continuation_plan(graph, worker_id, limit=8, now=now)
    if not plan:
        return {
            "status": "STOP",
            "stopAuthorized": True,
            "reason": "no dependency-valid safe internal primary or assist work remains",
            "next": None,
            "fallbacks": [],
        }
    first = plan[0]
    mode = str(first.packet.get("MODE") or "PRIMARY")
    return {
        "status": "WORK" if mode == "PRIMARY" else "ASSIST",
        "stopAuthorized": False,
        "reason": "continue on primary V16.1 work" if mode == "PRIMARY" else "continue in dependency-valid non-exclusive assist mode",
        "next": asdict(first),
        "fallbacks": [asdict(packet) for packet in plan[1:]],
        "onClaimConflict": "use the next fallback immediately; do not stop and do not invent a successor branch",
    }
