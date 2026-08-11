from __future__ import annotations

import datetime as dt
import uuid

from . import engine as _engine
from .model import *
from .model import _worker
from .store import *

SCHEDULER_GUARD_PATH = ".swarm/runtime/reconciler/scheduler-mutation.json"
SCHEDULER_GUARD_LEASE_SECONDS = 300
REVIEW_SUBJECT_ROLES = {"implementation", "repair", "scheduler-reconciler", "recovery"}


def _scheduler_guard_claim(worker: str, now: dt.datetime, generation: int = 1, takeover_from: str | None = None):
    claim = {
        "schemaVersion": 1,
        "kind": "reconciler-claim",
        "laneId": "scheduler",
        "slot": "mutation",
        "role": "scheduler-reconciler",
        "workerId": _worker(worker),
        "leaseId": uuid.uuid4().hex,
        "generation": generation,
        "status": "ACTIVE",
        "claimedAt": format_time(now),
        "lastHeartbeatAt": format_time(now),
        "leaseSeconds": SCHEDULER_GUARD_LEASE_SECONDS,
        "branch": "",
        "pr": None,
    }
    if takeover_from is not None:
        claim["takeoverFromWorkerId"] = takeover_from
    return validate_claim(claim)


def _acquire_scheduler_guard(store: Store, worker: str, now: dt.datetime):
    fresh = _scheduler_guard_claim(worker, now)
    try:
        return store.create(SCHEDULER_GUARD_PATH, fresh, "swarm: acquire scheduler mutation guard")
    except ConflictError:
        current = store.get(SCHEDULER_GUARD_PATH)
        old = validate_claim(current.value)
        if _engine.claim_is_live(old, now):
            raise ConflictError("scheduler mutation already in progress")
        replacement = _scheduler_guard_claim(
            worker,
            now,
            generation=old["generation"] + 1,
            takeover_from=old["workerId"],
        )
        return store.update(
            SCHEDULER_GUARD_PATH,
            replacement,
            current.version,
            "swarm: take over stale scheduler mutation guard",
        )


def _release_scheduler_guard(store: Store, held: StoredValue, worker: str, now: dt.datetime):
    current = store.get(SCHEDULER_GUARD_PATH)
    claim = validate_claim(current.value)
    expected = held.value
    if (
        claim["workerId"] != worker
        or claim["leaseId"] != expected["leaseId"]
        or claim["generation"] != expected["generation"]
    ):
        raise LeaseLostError("scheduler mutation guard ownership changed")
    claim["status"] = "RELEASED"
    claim["lastHeartbeatAt"] = format_time(now)
    claim["releasedAt"] = format_time(now)
    return store.update(
        SCHEDULER_GUARD_PATH,
        claim,
        current.version,
        "swarm: release scheduler mutation guard",
    )


def _runtime_lanes(store: Store, target_lane):
    target = validate_lane(target_lane)
    by_id = {}
    for _, stored in store.list(".swarm/runtime/lanes"):
        lane = validate_lane(stored.value)
        by_id[lane["laneId"]] = lane
    if target["laneId"] not in by_id:
        by_id[target["laneId"]] = target
    return [by_id[key] for key in sorted(by_id)]


def _runtime_claims(store: Store):
    return [validate_claim(stored.value) for _, stored in store.list(".swarm/runtime/claims")]


def effective_blockers(lane, lanes):
    target = validate_lane(lane)
    all_lanes = [validate_lane(item) for item in lanes]
    result = []
    for owner in all_lanes:
        for blocker in _engine.active_blockers(owner):
            scope = blocker.get("scope", "lane")
            if scope == "project":
                result.append(dict(blocker))
            elif scope == "epic" and owner.get("epic") == target.get("epic"):
                result.append(dict(blocker))
            elif owner["laneId"] == target["laneId"] and scope in {"lane", "resource"}:
                result.append(dict(blocker))
    return result


def _slot_for(lane, slot_name: str):
    slots = {slot["name"]: slot for slot in validate_lane(lane)["slots"]}
    if slot_name not in slots:
        raise ValidationError("unknown lane slot")
    return slots[slot_name]


def slot_phase_allowed(lane, slot):
    lane = validate_lane(lane)
    role = slot["role"]
    state = lane["state"]
    if role in {"integration", "release"}:
        return state == "INTEGRATION_READY"
    if role in {"review", "adversarial-review", "architecture-review"}:
        return state == "REVIEW"
    if role in {"implementation", "repair"}:
        return state in {"READY", "CLAIMED", "IMPLEMENTING", "NEEDS_CHANGES"}
    if role == "scheduler-reconciler":
        return state in {"READY", "CLAIMED", "IMPLEMENTING", "NEEDS_CHANGES"}
    return state in RUNNABLE_LANE_STATES


def _review_subject_claims(store: Store, lane):
    lane = validate_lane(lane)
    prefix = f".swarm/runtime/claims/{lane['laneId']}"
    subjects = []
    for _, stored in store.list(prefix):
        claim = validate_claim(stored.value)
        if claim["laneId"] == lane["laneId"] and claim["role"] in REVIEW_SUBJECT_ROLES:
            subjects.append(claim)
    return subjects


def _enforce_claim_policy(store: Store, lane, slot_name: str, worker: str, now: dt.datetime, config):
    lane = validate_lane(lane)
    target_lane_id = lane["laneId"]
    _worker(worker)
    config = validate_config(config)

    lanes = _runtime_lanes(store, lane)
    lane_map = {item["laneId"]: item for item in lanes}
    lane = lane_map[target_lane_id]

    if lane["state"] in TERMINAL_LANE_STATES | {"BLOCKED", "BLOCKED_EXTERNAL"}:
        raise ValidationError("lane not claimable")

    blockers = effective_blockers(lane, lanes)
    if blockers:
        scopes = sorted({blocker.get("scope", "lane") for blocker in blockers})
        raise ValidationError("claim blocked by active " + ",".join(scopes) + " blocker")

    ready, reason = _engine.dependency_ready(lane, lane_map)
    if not ready:
        raise ValidationError(reason)

    slot = _slot_for(lane, slot_name)
    if not slot_phase_allowed(lane, slot):
        raise ValidationError(f"role {slot['role']} is not claimable while lane is {lane['state']}")
    physical_ok, physical_reason = _engine.physical_slot_runnable(lane, slot)
    if not physical_ok:
        raise ValidationError(physical_reason)

    if lane.get("acceptance", {}).get("independentReview", False) and slot["role"] in {
        "review",
        "adversarial-review",
        "architecture-review",
    }:
        subjects = _review_subject_claims(store, lane)
        if not subjects:
            raise ValidationError("independent review requires an existing work-subject claim")
        for subject in subjects:
            _engine.verify_review_independence(lane, subject, worker)

    if slot["role"] == "implementation":
        claims = _runtime_claims(store)
        total, by_epic = _engine.primary_claim_counts(lanes, claims, now)
        limits = config["wipLimits"]
        if total >= limits["maxPrimaryLanes"]:
            raise ValidationError("project primary WIP limit reached")
        if by_epic.get(lane["epic"], 0) >= limits["maxPrimaryPerEpic"]:
            raise ValidationError("epic primary WIP limit reached")

    return lane, slot


def claim_slot(store, lane, slot, worker, now, branch="", pr=None, source_sha=None, config=None):
    config = validate_config(config or default_config())
    held = _acquire_scheduler_guard(store, worker, now)
    try:
        lane, _ = _enforce_claim_policy(store, lane, slot, worker, now, config)
        claim = _engine.new_claim(lane, slot, worker, now, branch, pr, source_sha)
        return store.create(
            claim_path(lane["laneId"], slot),
            claim,
            f"swarm: claim {lane['laneId']}/{slot}",
        )
    finally:
        _release_scheduler_guard(store, held, worker, now)


def takeover_claim(store, lane, slot, worker, now, branch="", pr=None, source_sha=None, config=None):
    config = validate_config(config or default_config())
    held = _acquire_scheduler_guard(store, worker, now)
    try:
        lane, _ = _enforce_claim_policy(store, lane, slot, worker, now, config)
        path = claim_path(lane["laneId"], slot)
        current = store.get(path)
        old = validate_claim(current.value)
        if _engine.claim_is_live(old, now):
            raise ConflictError("claim still live")
        claim = _engine.new_claim(
            lane,
            slot,
            worker,
            now,
            branch or old.get("branch", ""),
            pr if pr is not None else old.get("pr"),
            source_sha or old.get("sourceSHA"),
            old["generation"] + 1,
            old["workerId"],
        )
        return store.update(
            path,
            claim,
            current.version,
            f"swarm: takeover {lane['laneId']}/{slot}",
        )
    finally:
        _release_scheduler_guard(store, held, worker, now)


def recommend_slots(lanes, claims, resources, config, now, red_main=False):
    config = validate_config(config)
    lanes = [validate_lane(item) for item in lanes]
    if _engine.detect_dependency_cycles(lanes):
        raise ValidationError("dependency cycle detected")

    lane_map = {lane["laneId"]: lane for lane in lanes}
    live = {
        (claim["laneId"], claim["slot"]): claim
        for raw in claims
        for claim in [validate_claim(raw)]
        if _engine.claim_is_live(claim, now)
    }
    busy = {
        raw.get("resource")
        for raw in resources
        if raw.get("resource") in RESOURCE_CLASSES
        and _engine.claim_is_live(validate_claim(raw), now)
    }
    primary_total, primary_by_epic = _engine.primary_claim_counts(lanes, claims, now)
    limits = config["wipLimits"]
    review_backlog = sum(lane["state"] in {"REVIEW", "NEEDS_CHANGES"} for lane in lanes)
    integration_backlog = sum(lane["state"] == "INTEGRATION_READY" for lane in lanes)

    fanout = {lane["laneId"]: 0 for lane in lanes}
    for lane in lanes:
        for dependency in lane["dependencies"]:
            if dependency in fanout:
                fanout[dependency] += 1

    candidates = []
    for lane in lanes:
        if lane["state"] not in RUNNABLE_LANE_STATES or effective_blockers(lane, lanes):
            continue
        ready, dependency_reason = _engine.dependency_ready(lane, lane_map)
        if not ready:
            continue
        tags = set(lane.get("tags", []))
        for slot in lane["slots"]:
            if (lane["laneId"], slot["name"]) in live or not slot_phase_allowed(lane, slot):
                continue
            physical_ok, physical_reason = _engine.physical_slot_runnable(lane, slot)
            if not physical_ok or any(resource in busy for resource in slot.get("resources", [])):
                continue
            role = slot["role"]
            if role == "implementation" and (
                primary_total >= limits["maxPrimaryLanes"]
                or primary_by_epic.get(lane["epic"], 0) >= limits["maxPrimaryPerEpic"]
            ):
                continue
            pressure = (
                3
                if review_backlog >= limits["reviewBacklogThreshold"]
                and role not in {"review", "adversarial-review"}
                else 0
            ) + (
                3
                if integration_backlog >= limits["integrationBacklogThreshold"]
                and role != "integration"
                else 0
            )
            red = 0 if red_main and ("red-main-repair" in tags or role == "repair") else (20 if red_main else 0)
            state = {
                "INTEGRATION_READY": 0 if role == "integration" else 5,
                "REVIEW": 0 if role in {"review", "adversarial-review"} else 5,
                "NEEDS_CHANGES": 1 if role == "implementation" else 4,
                "VERIFYING": 1 if role in {"tests", "xcode-evidence", "performance", "accessibility"} else 4,
            }.get(lane["state"], 2)
            key = (
                red,
                pressure,
                lane["priority"],
                state,
                -fanout[lane["laneId"]],
                0 if "epic-closer" in tags else 1,
                ROLE_ORDER.get(role, 15),
            )
            reason = (
                f"{dependency_reason}; {physical_reason}; fanout={fanout[lane['laneId']]}; "
                f"review={review_backlog}; integration={integration_backlog}"
            )
            candidates.append(_engine.Recommendation(lane["laneId"], slot["name"], role, key, reason))

    ordered = sorted(candidates, key=lambda item: (item.priority_key, item.lane_id, item.slot))
    project_remaining = max(0, limits["maxPrimaryLanes"] - primary_total)
    epic_remaining = {
        epic: max(0, limits["maxPrimaryPerEpic"] - primary_by_epic.get(epic, 0))
        for epic in {lane["epic"] for lane in lanes}
    }
    result = []
    for recommendation in ordered:
        if recommendation.role == "implementation":
            epic = lane_map[recommendation.lane_id]["epic"]
            if project_remaining <= 0 or epic_remaining.get(epic, 0) <= 0:
                continue
            project_remaining -= 1
            epic_remaining[epic] = epic_remaining.get(epic, 0) - 1
        result.append(recommendation)
    return result


# Patch the engine module too so run_adversarial_simulation and any direct engine imports
# use the hardened claim boundary and scheduler rather than the pre-review implementations.
_engine.claim_slot = claim_slot
_engine.takeover_claim = takeover_claim
_engine.recommend_slots = recommend_slots
