from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path

from .engine import claim_is_live, render_dashboard, scope_violations, validate_pr_metadata
from .enforcement import safe_recommend_slots, validate_config, validate_state_snapshot
from .model import (
    ConflictError,
    NotFoundError,
    ValidationError,
    claim_path,
    lane_path,
    parse_time,
    pretty_json,
    resource_path,
    validate_claim,
    validate_event,
    validate_lane,
    validate_worker,
)

GENERATED_DIR = Path(".swarm/runtime/generated")
VALIDATION_FILE = "VALIDATION.json"
METRICS_FILE = "METRICS.json"
DASHBOARD_FILE = "DASHBOARD.md"


def _load_json(path: Path) -> dict:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"{path}: invalid JSON") from exc
    if not isinstance(raw, dict):
        raise ValidationError(f"{path}: expected object")
    return raw


def _walk_json(root: Path, relative: str) -> list[tuple[Path, dict]]:
    base = root / relative
    if not base.exists():
        return []
    if not base.is_dir():
        raise ValidationError(f"{base}: expected directory")
    out = []
    for path in sorted(base.rglob("*.json")):
        if path.is_file():
            out.append((path, _load_json(path)))
    return out


def local_snapshot(root: Path):
    lanes = [value for _, value in _walk_json(root, ".swarm/runtime/lanes")]
    claims = [value for _, value in _walk_json(root, ".swarm/runtime/claims")]
    workers = [value for _, value in _walk_json(root, ".swarm/runtime/workers")]
    events = [value for _, value in _walk_json(root, ".swarm/runtime/events")]
    resources = [value for _, value in _walk_json(root, ".swarm/runtime/resources")]
    return lanes, claims, workers, events, resources


def state_digest(root: Path) -> str:
    runtime = root / ".swarm/runtime"
    if not runtime.exists():
        raise ValidationError("runtime state missing")
    digest = hashlib.sha256()
    for path in sorted(runtime.rglob("*.json")):
        rel = path.relative_to(runtime)
        if rel.parts and rel.parts[0] == "generated":
            continue
        digest.update(rel.as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def validate_local_state(root: Path, now: dt.datetime):
    lanes, claims, workers, events, resources = local_snapshot(root)
    errors = validate_state_snapshot(lanes, claims, workers, events, resources, now)
    if errors:
        raise ValidationError("\n".join(errors))
    return lanes, claims, workers, events, resources


def render_projection(root: Path, now: dt.datetime, red_main: bool = False) -> dict:
    lanes, claims, workers, events, resources = validate_local_state(root, now)
    config = validate_config(_load_json(root / ".swarm/config.json"))
    recommendations = safe_recommend_slots(lanes, claims, resources, config, now, red_main=red_main)
    lane_states: dict[str, int] = {}
    event_counts: dict[str, int] = {}
    live_claims = []
    stale_claims = []
    active_workers = []
    for raw in lanes:
        lane = validate_lane(raw)
        lane_states[lane["state"]] = lane_states.get(lane["state"], 0) + 1
    for raw in events:
        event = validate_event(raw)
        event_counts[event["type"]] = event_counts.get(event["type"], 0) + 1
    for raw in claims:
        claim = validate_claim(raw)
        (live_claims if claim_is_live(claim, now) else stale_claims).append(claim)
    for raw in workers:
        worker = validate_worker(raw)
        last = parse_time(worker["lastSeenAt"])
        if worker["status"] == "ACTIVE" and now - last <= dt.timedelta(hours=2):
            active_workers.append(worker)
    review_backlog = sum(validate_lane(x)["state"] in {"REVIEW", "NEEDS_CHANGES"} for x in lanes)
    integration_backlog = sum(validate_lane(x)["state"] == "INTEGRATION_READY" for x in lanes)
    digest = state_digest(root)
    metrics = {
        "schemaVersion": 1,
        "generatedAt": now.isoformat(),
        "stateDigest": digest,
        "readySlots": len(recommendations),
        "activeClaims": len(live_claims),
        "staleClaims": len(stale_claims),
        "activeWorkers": len(active_workers),
        "reviewBacklog": review_backlog,
        "integrationBacklog": integration_backlog,
        "laneStates": lane_states,
        "eventCounts": event_counts,
        "rolloutMode": config["rolloutMode"],
        "note": "Throughput is measured by verified retained work; gross line count is diagnostic only.",
    }
    generated = root / GENERATED_DIR
    generated.mkdir(parents=True, exist_ok=True)
    (generated / METRICS_FILE).write_text(pretty_json(metrics), encoding="utf-8")
    (generated / DASHBOARD_FILE).write_text(
        render_dashboard(lanes, claims, workers, resources, events, now, red_main=red_main),
        encoding="utf-8",
    )
    marker = {
        "schemaVersion": 1,
        "status": "PASS",
        "stateDigest": digest,
        "validatedAt": now.isoformat(),
    }
    (generated / VALIDATION_FILE).write_text(pretty_json(marker), encoding="utf-8")
    return {"metrics": metrics, "validation": marker}


def verify_projection(root: Path) -> dict:
    marker = _load_json(root / GENERATED_DIR / VALIDATION_FILE)
    if marker.get("schemaVersion") != 1 or marker.get("status") != "PASS":
        raise ValidationError("invalid live-state validation marker")
    if marker.get("stateDigest") != state_digest(root):
        raise ValidationError("live swarm-state changed after validation fence")
    parse_time(marker.get("validatedAt"))
    return marker


def _slot_definition(lane: dict, slot_name: str) -> dict:
    for slot in lane["slots"]:
        if slot["name"] == slot_name:
            return slot
    raise ValidationError("claim slot missing from lane")


def _load_lane(root: Path, lane_id: str) -> dict:
    return validate_lane(_load_json(root / lane_path(lane_id)))


def _load_claim(root: Path, lane_id: str, slot: str) -> dict:
    return validate_claim(_load_json(root / claim_path(lane_id, slot)))


def _resource_subject(root: Path, resource: str) -> dict:
    return validate_claim(_load_json(root / resource_path(resource)))


def _legacy_allowed(config: dict, created_at: str) -> bool:
    policy = config.get("enforcement", {})
    cutoff = policy.get("legacyCutoffUTC")
    if not isinstance(cutoff, str) or not cutoff:
        return False
    return parse_time(created_at) < parse_time(cutoff)


def enforce_pr(root: Path, event_path: Path, changed_files_path: Path, now: dt.datetime) -> dict:
    config = validate_config(_load_json(root / ".swarm/config.json"))
    event = _load_json(event_path)
    pr = event.get("pull_request")
    if not isinstance(pr, dict):
        raise ValidationError("pull_request event required")
    body = pr.get("body") or ""
    created_at = pr.get("created_at")
    if not isinstance(created_at, str):
        raise ValidationError("pull request created_at missing")
    changed_files = [
        line.strip()
        for line in changed_files_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    try:
        metadata = validate_pr_metadata(body)
    except ValidationError:
        if config["rolloutMode"] == "enforcement" and not _legacy_allowed(config, created_at):
            raise
        return {
            "status": "LEGACY_GRANDFATHERED",
            "createdAt": created_at,
            "changedFiles": len(changed_files),
        }

    if config.get("enforcement", {}).get("requireValidatedState", False):
        verify_projection(root)

    lane = _load_lane(root, metadata["laneId"])
    if lane["state"] in {"BLOCKED", "BLOCKED_EXTERNAL", "DONE", "SUPERSEDED", "CANCELLED"}:
        raise ValidationError("controlled PR lane is not writable")
    claim = _load_claim(root, metadata["laneId"], metadata["slot"])
    if not claim_is_live(claim, now):
        raise ValidationError("controlled PR requires a live claim")
    if claim["workerId"] != metadata["workerId"] or claim["generation"] != metadata["generation"]:
        raise ValidationError("controlled PR metadata does not match live claim owner/generation")

    head_ref = ((pr.get("head") or {}).get("ref"))
    if claim.get("branch") and head_ref != claim["branch"]:
        raise ValidationError("controlled PR head branch does not match live claim")
    if claim.get("pr") is not None and claim["pr"] != pr.get("number"):
        raise ValidationError("live claim is attached to another PR")

    bad = scope_violations(lane, changed_files)
    if bad:
        raise ValidationError("controlled PR exceeds lane scope: " + ", ".join(sorted(bad)[:20]))

    slot = _slot_definition(lane, metadata["slot"])
    for resource in slot.get("resources", []):
        subject = _resource_subject(root, resource)
        if (
            not claim_is_live(subject, now)
            or subject["workerId"] != metadata["workerId"]
            or subject["laneId"] != metadata["laneId"]
        ):
            raise ValidationError(f"controlled PR lacks matching live resource lease: {resource}")

    return {
        "status": "PASS",
        "laneId": metadata["laneId"],
        "slot": metadata["slot"],
        "workerId": metadata["workerId"],
        "generation": metadata["generation"],
        "changedFiles": len(changed_files),
        "stateDigest": state_digest(root),
    }


def stop_proof(root: Path, now: dt.datetime, red_main: bool = False) -> dict:
    lanes, claims, workers, events, resources = validate_local_state(root, now)
    config = validate_config(_load_json(root / ".swarm/config.json"))
    recommendations = safe_recommend_slots(lanes, claims, resources, config, now, red_main=red_main)
    stale_active = [
        validate_claim(x)
        for x in claims
        if validate_claim(x)["status"] == "ACTIVE" and not claim_is_live(validate_claim(x), now)
    ]
    if recommendations:
        raise ValidationError(f"stop proof denied: {len(recommendations)} safe scheduler slots remain")
    if stale_active:
        raise ValidationError(f"stop proof denied: {len(stale_active)} stale active claims require recovery/reconciliation")
    review_backlog = [validate_lane(x)["laneId"] for x in lanes if validate_lane(x)["state"] in {"REVIEW", "NEEDS_CHANGES"}]
    integration_backlog = [validate_lane(x)["laneId"] for x in lanes if validate_lane(x)["state"] == "INTEGRATION_READY"]
    if review_backlog or integration_backlog:
        raise ValidationError("stop proof denied: review/integration backlog remains")
    return {
        "status": "PASS",
        "mainStateDigest": state_digest(root),
        "readySlots": 0,
        "staleActiveClaims": 0,
        "reviewBacklog": 0,
        "integrationBacklog": 0,
        "reason": "No safe materialized work remains after validated state/recovery checks. Live GitHub reconciliation is still required by SWARM_GO before exit.",
    }


def _parse_now(value: str | None) -> dt.datetime:
    if value:
        return parse_time(value)
    return dt.datetime.now(dt.timezone.utc)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Nembra Swarm V16 maximum-development hardening")
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name in ("validate-local", "render", "verify-fence", "stop-proof"):
        cmd = sub.add_parser(name)
        cmd.add_argument("--root", default=".")
        cmd.add_argument("--now")
        if name in {"render", "stop-proof"}:
            cmd.add_argument("--red-main", action="store_true")
    cmd = sub.add_parser("pr-check")
    cmd.add_argument("--root", required=True)
    cmd.add_argument("--event", required=True)
    cmd.add_argument("--changed-files", required=True)
    cmd.add_argument("--now")
    args = parser.parse_args(argv)
    try:
        root = Path(args.root)
        if args.cmd == "validate-local":
            lanes, claims, workers, events, resources = validate_local_state(root, _parse_now(args.now))
            print(pretty_json({"status": "PASS", "lanes": len(lanes), "claims": len(claims), "workers": len(workers), "events": len(events), "resources": len(resources)}), end="")
        elif args.cmd == "render":
            print(pretty_json(render_projection(root, _parse_now(args.now), red_main=args.red_main)), end="")
        elif args.cmd == "verify-fence":
            print(pretty_json(verify_projection(root)), end="")
        elif args.cmd == "pr-check":
            print(pretty_json(enforce_pr(root, Path(args.event), Path(args.changed_files), _parse_now(args.now))), end="")
        elif args.cmd == "stop-proof":
            print(pretty_json(stop_proof(root, _parse_now(args.now), red_main=args.red_main)), end="")
        return 0
    except (ValidationError, NotFoundError, ConflictError) as exc:
        print(f"swarm-max error: {exc}", file=__import__("sys").stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
