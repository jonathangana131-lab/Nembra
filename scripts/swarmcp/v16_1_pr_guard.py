from __future__ import annotations

from typing import Any, Mapping, Sequence

from .v16_1 import (
    PRAdmissionDecision,
    evaluate_pr_admission as _evaluate_v16_1_pr_admission,
    parse_swarm_pr_metadata,
)

# Exact accepted-main activation time for V16.1. PRs that already existed
# before rollout remain in the compatibility window. Anything created after
# rollout must participate in the convergence contract instead of escaping it
# by omitting SWARM_* metadata.
V16_1_PR_METADATA_ENFORCEMENT_STARTED_AT = '2026-08-13T12:00:43Z'


def _created_after_v16_1_activation(pr: Mapping[str, Any]) -> bool:
    created_at = str(pr.get('created_at') or '')
    # An unclassifiable creation time must not silently restore the unmanaged
    # bypass for a new PR authority decision.
    if not created_at:
        return True
    return created_at >= V16_1_PR_METADATA_ENFORCEMENT_STARTED_AT


def evaluate_pr_admission(
    pr: Mapping[str, Any],
    peers: Sequence[Mapping[str, Any]],
) -> PRAdmissionDecision:
    meta = parse_swarm_pr_metadata(pr)
    managed = any((meta['lane'], meta['worker'], meta['schema'], meta['protocol']))
    if not managed and _created_after_v16_1_activation(pr):
        return PRAdmissionDecision(
            False,
            'UPGRADE_METADATA',
            'PR was created after V16.1 activation and must declare SWARM_PROTOCOL/LANE/SLOT/WORKER/BRANCH_INTENT metadata',
        )
    return _evaluate_v16_1_pr_admission(pr, peers)
