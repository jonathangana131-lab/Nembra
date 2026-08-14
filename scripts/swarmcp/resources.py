from __future__ import annotations

from .engine import acquire_resources, claim_is_live
from .model import *
from .store import *


def heartbeat_resource(store: Store, resource: str, worker: str, lease_id: str, generation: int, now):
    if resource not in RESOURCE_CLASSES:
        raise ValidationError("unknown resource")
    path = resource_path(resource)
    current = store.get(path)
    claim = validate_claim(current.value)
    if claim.get("resource") != resource:
        raise ValidationError("resource claim subject mismatch")
    if (
        claim["workerId"] != worker
        or claim["leaseId"] != lease_id
        or claim["generation"] != generation
        or not claim_is_live(claim, now)
    ):
        raise LeaseLostError("resource ownership changed or expired")
    claim["lastHeartbeatAt"] = format_time(now)
    return store.update(path, claim, current.version, f"swarm: heartbeat resource {resource}")


def release_resource(store: Store, resource: str, worker: str, lease_id: str, generation: int, now):
    if resource not in RESOURCE_CLASSES:
        raise ValidationError("unknown resource")
    path = resource_path(resource)
    current = store.get(path)
    claim = validate_claim(current.value)
    if claim.get("resource") != resource:
        raise ValidationError("resource claim subject mismatch")
    if (
        claim["workerId"] != worker
        or claim["leaseId"] != lease_id
        or claim["generation"] != generation
    ):
        raise LeaseLostError("resource ownership changed")
    claim["status"] = "RELEASED"
    claim["lastHeartbeatAt"] = format_time(now)
    claim["releasedAt"] = format_time(now)
    return store.update(path, claim, current.version, f"swarm: release resource {resource}")


def release_resources(store: Store, resources, worker: str, leases, now):
    """Release a set of owned resources in reverse acquisition order.

    `leases` maps resource name to `(lease_id, generation)` and deliberately requires
    exact ownership tokens so one worker cannot release another worker's executor.
    """
    released = []
    for resource in reversed(list(resources)):
        if resource not in leases:
            raise ValidationError(f"missing lease token for {resource}")
        lease_id, generation = leases[resource]
        released.append(release_resource(store, resource, worker, lease_id, generation, now))
    return released
