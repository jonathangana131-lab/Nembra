from __future__ import annotations

"""V16.1 worker-persistence routing.

The convergence layer intentionally suppresses duplicate builder branches. Under a
large burst that can leave more workers than exclusive work items. An empty
exclusive recommendation is therefore *not* proof that the repository has no
useful internal work.

This module turns that condition into non-exclusive assist/capacity work and
reserves STOP for graphs that are genuinely exhausted or externally blocked.
"""

from dataclasses import asdict
import hashlib
from typing import Any, Mapping, Sequence

from . import mission_graph as _v16
from . import v16_1 as _base

WORKER_PERSISTENCE_VERSION = 1
_ASSIST_STATUSES = {"QUEUED", "REVIEW", "INTEGRATING", "BLOCKED"}
_TERMINAL_OBJECTIVE_STATUSES = {"DONE", "EXTERNAL_BLOCKED"}


def _stable_index(worker_id: str, size: int) -> int:
    if size <= 0:
        return 0
    digest = hashlib.sha256(worker_id.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") % size


def _objective_is_internal(graph: Mapping[str, Any], objective_id: str) -> bool:
    obj = graph["objectives"][objective_id]
    if obj.get("status") in _TERMINAL_OBJECTIVE_STATUSES:
        return False
    # Objective-level capacity mining must never invent a physical/user action.
    # Existing software work for a physical objective may still be reviewed via
    # the assist path below, but an otherwise-empty physical objective is not a
    # reason to keep a worker busy speculatively.
    if obj.get("physicalOrUserDependency"):
        return False
    blocker_ids = obj.get("blockerIds", [])
    if blocker_ids and all(
        graph["blockers"].get(bid, {}).get("state") in {"RESOLVED", "EXTERNAL"}
        for bid in blocker_ids
    ):
        # It may still have ordinary finish conditions to close, so keep it
        # internal unless every finish condition is already satisfied.
        return not all(obj.get("finishSatisfied", []))
    return True


def _decorate_primary(packet: _v16.MissionPacket) -> _v16.MissionPacket:
    payload = dict(packet.packet)
    payload.update(
        {
            "WORKER_PERSISTENCE_VERSION": WORKER_PERSISTENCE_VERSION,
            "MODE": "PRIMARY",
            "STOP_AUTHORIZED": False,
            "AFTER_TASK": "refresh and request another V16.1 continuation in the same chat execution window",
            "EMPTY_EXCLUSIVE_QUEUE_ACTION": "enter non-exclusive assist mode; do not stop",
        }
    )
    return _v16.MissionPacket(
        packet.mission_id,
        packet.objective_id,
        packet.work_item_id,
        packet.role,
        packet.priority_score,
        payload,
    )


def _assist_packet(graph: Mapping[str, Any], item: Mapping[str, Any], score: float) -> _v16.MissionPacket:
    obj = graph["objectives"][item["objectiveId"]]
    mission = graph["missions"][item["missionId"]]
    blocker_id = str(item.get("blockerId") or "")
    blocker = graph["blockers"].get(blocker_id) if blocker_id else None
    mode = "INTEGRATION_ASSIST" if item.get("status") == "INTEGRATING" else (
        "REVIEW_ASSIST" if item.get("status") == "REVIEW" else "DEBUG_ASSIST"
    )
    payload = {
        "WORKER_PERSISTENCE_VERSION": WORKER_PERSISTENCE_VERSION,
        "MODE": mode,
        "NON_EXCLUSIVE_ASSIST": True,
        "CLAIM_REQUIRED": False,
        "WRITE_AUTHORITY": False,
        "MAY_CREATE_BRANCH": False,
        "MAY_CREATE_SUCCESSOR_PR": False,
        "STOP_AUTHORIZED": False,
        "MISSION": mission["title"],
        "WHY_IT_MATTERS": mission["why"],
        "CURRENT_STATE": obj["status"],
        "CANONICAL_BRANCH": obj.get("canonicalBranch", ""),
        "JOIN_BRANCH": item.get("branch") or obj.get("canonicalBranch", ""),
        "BLOCKER_ID": blocker_id,
        "BLOCKER_OWNER": blocker.get("owner", "") if blocker else "",
        "PRIMARY_SCOPE": item.get("primaryScope", []),
        "ALLOWED_EXPANSION": item.get("allowedAdjacentScope", []),
        "FORBIDDEN_AREAS": item.get("forbiddenAreas", []),
        "EXIT_CONDITION": blocker.get("exitCondition", "") if blocker else item.get("outcome", ""),
        "SAFE_ASSIST_ACTIONS": [
            "review or red-team the existing candidate without creating a competing implementation",
            "inspect failing or pending CI and isolate the next actionable defect",
            "run or strengthen impacted tests without weakening acceptance",
            "help resolve integration conflicts or compose already-accepted work",
            "attach a concrete finding/evidence to the existing canonical work",
        ],
        "ASSIST_ESCALATION": "If a genuinely new blocker is proven, record it in Mission Graph first; branch creation still requires normal V16.1 admission.",
        "AFTER_TASK": "refresh and request another continuation; completion of assist work is not a stop condition",
    }
    role = "integrator" if item.get("status") == "INTEGRATING" else "reviewer"
    return _v16.MissionPacket(
        item["missionId"],
        item["objectiveId"],
        item["workItemId"],
        role,
        score,
        payload,
    )


def _capacity_packet(graph: Mapping[str, Any], objective_id: str, score: float) -> _v16.MissionPacket:
    obj = graph["objectives"][objective_id]
    mission = graph["missions"][obj["missionId"]]
    missing = [
        condition
        for condition, satisfied in zip(obj.get("finishConditions", []), obj.get("finishSatisfied", []))
        if not satisfied
    ]
    payload = {
        "WORKER_PERSISTENCE_VERSION": WORKER_PERSISTENCE_VERSION,
        "MODE": "CAPACITY_MINING_ASSIST",
        "NON_EXCLUSIVE_ASSIST": True,
        "CLAIM_REQUIRED": False,
        "WRITE_AUTHORITY": False,
        "MAY_CREATE_BRANCH": False,
        "MAY_CREATE_SUCCESSOR_PR": False,
        "STOP_AUTHORIZED": False,
        "MISSION": mission["title"],
        "WHY_IT_MATTERS": mission["why"],
        "CURRENT_STATE": obj["status"],
        "CANONICAL_BRANCH": obj.get("canonicalBranch", ""),
        "PRIMARY_SCOPE": obj.get("allowedAdjacentScope", []),
        "FORBIDDEN_AREAS": obj.get("forbiddenAreas", []),
        "UNSATISFIED_FINISH_CONDITIONS": missing,
        "SAFE_ASSIST_ACTIONS": [
            "inspect the shipping implementation for a concrete unowned correctness/performance/accessibility gap",
            "inspect current CI and active PR topology for integration-ready work",
            "produce a bounded red-team finding against existing code before proposing implementation",
            "identify reusable test/evidence work that closes an existing finish condition",
        ],
        "CAPACITY_RULE": "Do not invent speculative product scope. A proven new blocker must be recorded and admitted before implementation.",
        "AFTER_TASK": "refresh and request another continuation; capacity mining is a fallback, not permission for branch spam",
    }
    return _v16.MissionPacket(
        obj["missionId"],
        objective_id,
        f"assist::{objective_id}",
        "reviewer",
        score,
        payload,
    )


def _assist_candidates(graph: Mapping[str, Any]) -> list[_v16.MissionPacket]:
    status_weight = {"INTEGRATING": 500.0, "REVIEW": 420.0, "BLOCKED": 320.0, "QUEUED": 260.0}
    severity_weight = {"P0": 400.0, "P1": 250.0, "P2": 100.0, "P3": 20.0}
    packets: list[_v16.MissionPacket] = []
    for item in graph.get("workItems", {}).values():
        if item.get("status") not in _ASSIST_STATUSES:
            continue
        obj = graph["objectives"].get(item.get("objectiveId"))
        if not obj or obj.get("status") in _TERMINAL_OBJECTIVE_STATUSES:
            continue
        blocker_id = str(item.get("blockerId") or "")
        blocker = graph.get("blockers", {}).get(blocker_id) if blocker_id else None
        if blocker and blocker.get("state") == "EXTERNAL":
            continue
        score = status_weight[item["status"]] + severity_weight.get(obj.get("severity", "P3"), 0.0)
        score += float(obj.get("userValue", 0)) * 10.0
        packets.append(_assist_packet(graph, item, score))

    # If all exclusive work is occupied/empty, workers may still close finish
    # conditions on ordinary internal objectives without opening a branch.
    active_objectives = {packet.objective_id for packet in packets}
    for objective_id, obj in graph.get("objectives", {}).items():
        if objective_id in active_objectives or not _objective_is_internal(graph, objective_id):
            continue
        if any(graph["objectives"].get(dep, {}).get("status") != "DONE" for dep in obj.get("dependencies", [])):
            continue
        severity = severity_weight.get(obj.get("severity", "P3"), 0.0)
        score = 150.0 + severity + float(obj.get("userValue", 0)) * 8.0
        packets.append(_capacity_packet(graph, objective_id, score))

    packets.sort(key=lambda p: (-p.priority_score, p.objective_id, p.work_item_id))
    return packets


def worker_continuation_plan(
    graph: Mapping[str, Any],
    worker_id: str,
    *,
    limit: int = 8,
    now=None,
) -> list[_v16.MissionPacket]:
    """Return primary work plus safe non-exclusive fallbacks for one worker.

    The primary list is deterministically rotated by worker id so separately
    spawned chats do not all race the first Mission Graph item.
    """
    if limit < 1:
        return []
    primary = [_decorate_primary(p) for p in _base.recommend_mission_packets(
        graph,
        worker_ids=(),
        limit=max(64, len(graph.get("workItems", {})) + 8),
        now=now,
    )]
    if primary:
        start = _stable_index(worker_id, len(primary))
        primary = primary[start:] + primary[:start]
    assist = _assist_candidates(graph)

    combined: list[_v16.MissionPacket] = []
    seen: set[tuple[str, str]] = set()
    for packet in primary + assist:
        mode = str(packet.packet.get("MODE") or "PRIMARY")
        key = (packet.work_item_id, mode)
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
    """Persistent replacement for V16.1 recommendation.

    With explicit worker ids, return one deterministic continuation per worker.
    Without worker ids, expose a mixed primary+assist pool for operators.
    """
    if limit < 1:
        return []
    if worker_ids:
        result = []
        for worker_id in list(worker_ids)[:limit]:
            plan = worker_continuation_plan(graph, worker_id, limit=8, now=now)
            if plan:
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

    primary = [_decorate_primary(p) for p in _base.recommend_mission_packets(
        graph,
        worker_ids=(),
        limit=limit,
        now=now,
    )]
    result = list(primary)
    seen = {(p.work_item_id, str(p.packet.get("MODE") or "PRIMARY")) for p in result}
    for packet in _assist_candidates(graph):
        key = (packet.work_item_id, str(packet.packet.get("MODE") or "ASSIST"))
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
    """A Go cycle may STOP only after the internal fallback ladder is empty."""
    _base.ensure_v16_1_policy(graph)
    if completed_work_item_id:
        # Reuse V16.1's evidence-bound handoff mutation, then ignore its old
        # one-packet/IDLE routing decision.
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
            "reason": "all safe internal primary, review, integration, debug, and capacity-mining work is exhausted or externally blocked",
            "next": None,
            "fallbacks": [],
        }

    first = plan[0]
    mode = str(first.packet.get("MODE") or "PRIMARY")
    return {
        "status": "WORK" if mode == "PRIMARY" else "ASSIST",
        "stopAuthorized": False,
        "reason": "continue on primary V16.1 work" if mode == "PRIMARY" else "exclusive work is occupied/empty; continue in non-exclusive assist mode",
        "next": asdict(first),
        "fallbacks": [asdict(packet) for packet in plan[1:]],
        "onClaimConflict": "use the next fallback immediately; do not stop and do not invent a successor branch",
    }
