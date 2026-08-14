from __future__ import annotations

import re
from typing import Any, Mapping, Sequence

from . import v16_1 as _v161
from .v16_1 import PRAdmissionDecision, parse_swarm_pr_metadata

V16_2_PR_METADATA_ENFORCEMENT_STARTED_AT = "2026-08-14T08:02:00Z"
V16_2_PROTOCOL = "16.2"
MAX_OPEN_CHILDREN_PER_PARENT = 2
MAX_OPEN_INTEGRATION_CHILDREN_PER_PARENT = 1
_CHILD_INTENTS = {"validation", "review", "integration", "tournament"}


def _created_after_activation(pr: Mapping[str, Any]) -> bool:
    created_at = str(pr.get("created_at") or "")
    return not created_at or created_at >= V16_2_PR_METADATA_ENFORCEMENT_STARTED_AT


def _normalize_protocol_for_v16_1(pr: Mapping[str, Any]) -> dict[str, Any]:
    out = dict(pr)
    body = str(out.get("body") or "")
    out["body"] = re.sub(
        r"(?im)^(\s*SWARM_PROTOCOL\s*:\s*)16\.2\s*$",
        r"\g<1>16.1",
        body,
    )
    return out


def _pr_number(value: str) -> int | None:
    match = re.search(r"#?(\d+)", str(value or ""))
    return int(match.group(1)) if match else None


def evaluate_pr_admission(pr: Mapping[str, Any], peers: Sequence[Mapping[str, Any]]) -> PRAdmissionDecision:
    meta = parse_swarm_pr_metadata(pr)
    managed = any((meta["lane"], meta["worker"], meta["schema"], meta["protocol"]))

    if not managed:
        if _created_after_activation(pr):
            return PRAdmissionDecision(False, "UPGRADE_METADATA", "PR was created after V16.2 activation and must use the swarm metadata contract")
        return PRAdmissionDecision(True, "ALLOW_UNMANAGED", "pre-V16.2 unmanaged compatibility")

    if _created_after_activation(pr) and meta["protocol"] != V16_2_PROTOCOL:
        return PRAdmissionDecision(False, "UPGRADE_METADATA", "new swarm PRs must declare SWARM_PROTOCOL: 16.2")

    if meta["protocol"] not in {"16.1", V16_2_PROTOCOL}:
        return PRAdmissionDecision(False, "UPGRADE_METADATA", "unsupported swarm protocol")

    # Reuse all accepted V16.1 same-lane/slot/canonical/tournament checks without
    # teaching that older evaluator about a new protocol string.
    normalized_pr = _normalize_protocol_for_v16_1(pr)
    normalized_peers = [_normalize_protocol_for_v16_1(peer) for peer in peers]
    structural = _v161.evaluate_pr_admission(normalized_pr, normalized_peers)
    if not structural.allowed:
        return structural

    # Existing V16.1 PRs retain compatibility. V16.2 tightens only newly-created
    # work so rollout cannot strand the already-open graph.
    if meta["protocol"] != V16_2_PROTOCOL:
        return PRAdmissionDecision(True, "ALLOW_COMPAT", "pre-V16.2 managed PR remains compatible")

    if meta["intent"] in _CHILD_INTENTS and not meta["parentPR"]:
        return PRAdmissionDecision(False, "JOIN_PARENT", "V16.2 child review/validation/integration work requires SWARM_PARENT_PR")

    current_number = int(pr.get("number") or 0)
    parent_number = _pr_number(meta["parentPR"])
    live = []
    for peer in peers:
        if int(peer.get("number") or 0) == current_number:
            continue
        if str(peer.get("state") or "open").lower() != "open":
            continue
        peer_meta = parse_swarm_pr_metadata(peer)
        if peer_meta["lane"] != meta["lane"]:
            continue
        live.append((peer, peer_meta))

    canonicals = [(peer, pm) for peer, pm in live if pm["intent"] == "canonical"]
    if meta["intent"] in _CHILD_INTENTS and canonicals:
        canonical_number = min(int(peer.get("number") or 0) for peer, _ in canonicals)
        if parent_number != canonical_number:
            return PRAdmissionDecision(
                False,
                "JOIN_CANONICAL",
                f"V16.2 child work must attach to canonical PR #{canonical_number} for absorption",
                canonical_number,
            )

    if parent_number is not None:
        siblings = [
            (peer, pm) for peer, pm in live
            if _pr_number(pm["parentPR"]) == parent_number and pm["intent"] in _CHILD_INTENTS
        ]
        if meta["intent"] == "integration":
            integrations = [(peer, pm) for peer, pm in siblings if pm["intent"] == "integration"]
            if len(integrations) >= MAX_OPEN_INTEGRATION_CHILDREN_PER_PARENT:
                target = min(int(peer.get("number") or 0) for peer, _ in integrations)
                return PRAdmissionDecision(False, "JOIN_EXISTING", f"parent already has integration PR #{target}; join it", target)
        if len(siblings) >= MAX_OPEN_CHILDREN_PER_PARENT:
            target = parent_number
            return PRAdmissionDecision(
                False,
                "ABSORB_FIRST",
                f"parent #{parent_number} already has {len(siblings)} open child PRs; absorb/close existing children before another",
                target,
            )

    return PRAdmissionDecision(True, "ALLOW", "V16.2 admission accepted")
