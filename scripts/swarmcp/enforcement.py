from __future__ import annotations

from . import engine as _engine
from . import model as _model
from . import policy as _policy
from .model import *
from .store import *

_BASE_VALIDATE_LANE = _model.validate_lane
_BASE_VALIDATE_CLAIM = _model.validate_claim
_BASE_VALIDATE_SNAPSHOT = _engine.validate_state_snapshot
_BASE_RECOMMEND = _policy.recommend_slots

_REVIEW_ROLES = {"review", "adversarial-review", "architecture-review"}


def validate_lane(raw):
    # Preflight slot resources before the base validator performs set membership.
    if isinstance(raw, dict):
        slots = raw.get("slots", [])
        if not isinstance(slots, list):
            raise ValidationError("slots must be array")
        for slot in slots:
            if not isinstance(slot, dict):
                raise ValidationError("slot must be object")
            resources = slot.get("resources", [])
            if not isinstance(resources, list):
                raise ValidationError("slot.resources must be array")
            if any(not isinstance(resource, str) for resource in resources):
                raise ValidationError("slot.resources must contain strings")
    lane = _BASE_VALIDATE_LANE(raw)
    tags = lane.get("tags", [])
    if not isinstance(tags, list):
        raise ValidationError("tags must be array")
    lane["tags"] = [_model._id(tag, "tag") for tag in tags]
    return lane


def validate_claim(raw):
    claim = _BASE_VALIDATE_CLAIM(raw)
    if claim.get("takeoverFromWorkerId") is not None:
        _model._worker(claim["takeoverFromWorkerId"], "takeoverFromWorkerId")
    prior = claim.get("priorWorkerIds", [])
    if not isinstance(prior, list):
        raise ValidationError("priorWorkerIds must be array")
    prior = [_model._worker(worker, "priorWorkerId") for worker in prior]
    if len(prior) != len(set(prior)):
        raise ValidationError("duplicate priorWorkerIds")
    if claim["workerId"] in prior:
        raise ValidationError("current worker cannot appear in priorWorkerIds")
    claim["priorWorkerIds"] = prior
    return claim


_model.validate_lane = validate_lane
_model.validate_claim = validate_claim
_engine.validate_lane = validate_lane
_engine.validate_claim = validate_claim
_policy.validate_lane = validate_lane
_policy.validate_claim = validate_claim


def _review_history_workers(subject):
    subject = validate_claim(subject)
    workers = [subject["workerId"]]
    workers.extend(subject.get("priorWorkerIds", []))
    predecessor = subject.get("takeoverFromWorkerId")
    if predecessor is not None:
        workers.append(predecessor)
    return set(workers)


def _enforce_full_review_independence(store: Store, lane, reviewer: str):
    lane = validate_lane(lane)
    if not lane.get("acceptance", {}).get("independentReview", False):
        return
    subjects = _policy._review_subject_claims(store, lane)
    if not subjects:
        raise ValidationError("independent review requires an existing work-subject claim")
    for subject in subjects:
        if reviewer in _review_history_workers(subject):
            raise ValidationError("independent review requires a worker with no implementation ownership history")


def _renew_scheduler_guard_before_write(store: Store, held: StoredValue, worker: str):
    """CAS-verify and renew scheduler ownership immediately before target mutation."""
    current = store.get(_policy.SCHEDULER_GUARD_PATH)
    guard = validate_claim(current.value)
    expected = validate_claim(held.value)
    if (
        guard["workerId"] != worker
        or guard["leaseId"] != expected["leaseId"]
        or guard["generation"] != expected["generation"]
        or guard["status"] != "ACTIVE"
    ):
        raise LeaseLostError("scheduler mutation guard ownership changed")
    guard["lastHeartbeatAt"] = format_time(utc_now())
    return store.update(
        _policy.SCHEDULER_GUARD_PATH,
        guard,
        current.version,
        "swarm: renew scheduler mutation guard before write",
    )


def claim_slot(store, lane, slot, worker, now, branch="", pr=None, source_sha=None, config=None):
    config = validate_config(config or default_config())
    held = _policy._acquire_scheduler_guard(store, worker, now)
    try:
        lane, slot_def = _policy._enforce_claim_policy(store, lane, slot, worker, now, config)
        if slot_def["role"] in _REVIEW_ROLES:
            _enforce_full_review_independence(store, lane, worker)
        claim = _engine.new_claim(lane, slot, worker, now, branch, pr, source_sha)
        _renew_scheduler_guard_before_write(store, held, worker)
        return store.create(
            claim_path(lane["laneId"], slot),
            claim,
            f"swarm: claim {lane['laneId']}/{slot}",
        )
    finally:
        _policy._release_scheduler_guard(store, held, worker, utc_now())


def takeover_claim(store, lane, slot, worker, now, branch="", pr=None, source_sha=None, config=None):
    config = validate_config(config or default_config())
    held = _policy._acquire_scheduler_guard(store, worker, now)
    try:
        lane, slot_def = _policy._enforce_claim_policy(store, lane, slot, worker, now, config)
        if slot_def["role"] in _REVIEW_ROLES:
            _enforce_full_review_independence(store, lane, worker)
        path = claim_path(lane["laneId"], slot)
        current = store.get(path)
        old = validate_claim(current.value)
        if _engine.claim_is_live(old, now):
            raise ConflictError("claim still live")
        history = list(old.get("priorWorkerIds", []))
        for previous in (old.get("takeoverFromWorkerId"), old["workerId"]):
            if previous is not None and previous != worker and previous not in history:
                history.append(previous)
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
        claim["priorWorkerIds"] = history
        claim = validate_claim(claim)
        _renew_scheduler_guard_before_write(store, held, worker)
        return store.update(path, claim, current.version, f"swarm: takeover {lane['laneId']}/{slot}")
    finally:
        _policy._release_scheduler_guard(store, held, worker, utc_now())


def _slot_declared_resources(lane, slot_name: str):
    lane = validate_lane(lane)
    slots = {slot["name"]: slot for slot in lane["slots"]}
    if slot_name not in slots:
        return set()
    return set(slots[slot_name].get("resources", []))


def _live_owned_resources(store: Store, worker: str, lane_id: str, now):
    try:
        lane = validate_lane(store.get(lane_path(lane_id)).value)
    except NotFoundError as exc:
        raise ValidationError("resource acquisition requires an existing lane") from exc
    if lane["state"] in TERMINAL_LANE_STATES | {"BLOCKED", "BLOCKED_EXTERNAL"}:
        raise ValidationError("resource acquisition lane is not active")
    allowed = set()
    for _, stored in store.list(f".swarm/runtime/claims/{lane_id}"):
        claim = validate_claim(stored.value)
        if claim["laneId"] != lane_id or claim["workerId"] != worker or not _engine.claim_is_live(claim, now):
            continue
        allowed.update(_slot_declared_resources(lane, claim["slot"]))
    return allowed


def acquire_resources_for_claim(store: Store, resources, worker: str, lane: str, now, resource_order):
    requested = list(dict.fromkeys(resources))
    allowed = _live_owned_resources(store, worker, lane, now)
    missing = [resource for resource in requested if resource not in allowed]
    if missing:
        raise ValidationError("resource acquisition requires a live owning slot declaring: " + ", ".join(missing))
    return _engine.acquire_resources(store, requested, worker, lane, now, resource_order)


def _resource_is_authorized(raw_resource, lane_map, claims, now):
    resource_claim = validate_claim(raw_resource)
    resource = raw_resource.get("resource")
    if resource not in RESOURCE_CLASSES or not _engine.claim_is_live(resource_claim, now):
        return False
    lane = lane_map.get(resource_claim["laneId"])
    if lane is None:
        return False
    for raw_claim in claims:
        claim = validate_claim(raw_claim)
        if (
            claim["laneId"] == resource_claim["laneId"]
            and claim["workerId"] == resource_claim["workerId"]
            and _engine.claim_is_live(claim, now)
            and resource in _slot_declared_resources(lane, claim["slot"])
        ):
            return True
    return False


def safe_recommend_slots(lanes, claims, resources, config, now, red_main=False):
    lanes = [validate_lane(lane) for lane in lanes]
    lane_map = {lane["laneId"]: lane for lane in lanes}
    authorized_resources = [
        resource for resource in resources if _resource_is_authorized(resource, lane_map, claims, now)
    ]
    return _BASE_RECOMMEND(lanes, claims, authorized_resources, config, now, red_main)


def validate_state_snapshot(lanes, claims, workers, events, resources, now):
    lanes = [validate_lane(lane) for lane in lanes]
    claims = [validate_claim(claim) for claim in claims]
    errors = list(_BASE_VALIDATE_SNAPSHOT(lanes, claims, workers, events, resources, now))
    lane_map = {lane["laneId"]: lane for lane in lanes}
    for index, resource in enumerate(resources):
        try:
            resource_claim = validate_claim(resource)
            if _engine.claim_is_live(resource_claim, now) and not _resource_is_authorized(resource, lane_map, claims, now):
                errors.append(f"resource[{index}]: live resource lease has no matching live owning slot claim")
        except ValidationError as exc:
            errors.append(f"resource[{index}]: {exc}")
    return errors


_policy.claim_slot = claim_slot
_policy.takeover_claim = takeover_claim
_engine.claim_slot = claim_slot
_engine.takeover_claim = takeover_claim
