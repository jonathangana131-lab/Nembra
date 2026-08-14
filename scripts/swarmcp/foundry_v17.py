"""Repository congestion-control policy for Swarm Foundry 17.

This module is deliberately side-effect free. It consumes already-observed
GitHub pressure and mission-graph backlog counts, then reports how many new
workers may enter the existing claim system. Admission never replaces claims.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


class FoundryPolicyError(ValueError):
    pass


@dataclass(frozen=True)
class RepositoryPressure:
    open_product_prs: int
    open_branches: int

    def validate(self) -> None:
        if self.open_product_prs < 0 or self.open_branches < 0:
            raise FoundryPolicyError("repository pressure counts must be non-negative")


@dataclass(frozen=True)
class FoundryLimits:
    chat_capacity_ceiling: int = 20
    max_primary_builders: int = 6
    max_open_product_prs: int = 18
    max_open_branches: int = 24
    review_backlog_soft_limit: int = 4
    integration_backlog_soft_limit: int = 3
    retirement_workers: int = 4
    verification_workers: int = 2

    def validate(self) -> None:
        values = asdict(self)
        if any(not isinstance(value, int) or value < 1 for value in values.values()):
            raise FoundryPolicyError("all Foundry limits must be positive integers")
        if self.max_primary_builders > self.chat_capacity_ceiling:
            raise FoundryPolicyError("primary builder ceiling cannot exceed chat ceiling")


def admission_plan(
    *,
    requested_workers: int,
    ready_builders: int,
    active_builders: int,
    review_backlog: int,
    integration_backlog: int,
    retirement_candidates: int,
    pressure: RepositoryPressure,
    limits: FoundryLimits = FoundryLimits(),
    red_main: bool = False,
) -> dict[str, Any]:
    """Return a deterministic admission decision without granting authority."""

    limits.validate()
    pressure.validate()
    counts = {
        "requested_workers": requested_workers,
        "ready_builders": ready_builders,
        "active_builders": active_builders,
        "review_backlog": review_backlog,
        "integration_backlog": integration_backlog,
        "retirement_candidates": retirement_candidates,
    }
    if any(not isinstance(value, int) or value < 0 for value in counts.values()):
        raise FoundryPolicyError("worker/backlog counts must be non-negative integers")
    if requested_workers < 1:
        raise FoundryPolicyError("requested_workers must be positive")

    considered = min(requested_workers, limits.chat_capacity_ceiling)
    pr_headroom = max(0, limits.max_open_product_prs - pressure.open_product_prs)
    branch_headroom = max(0, limits.max_open_branches - pressure.open_branches)
    over_budget = pr_headroom == 0 or branch_headroom == 0
    throttle_reasons: list[str] = []

    builder_ceiling = limits.max_primary_builders
    if review_backlog >= limits.review_backlog_soft_limit:
        builder_ceiling = min(builder_ceiling, 2)
        throttle_reasons.append("review-backlog")
    if integration_backlog >= limits.integration_backlog_soft_limit:
        builder_ceiling = min(builder_ceiling, 1)
        throttle_reasons.append("integration-backlog")
    if over_budget:
        builder_ceiling = 1 if red_main else 0
        throttle_reasons.append("repository-congestion")

    new_builders = max(
        0,
        min(
            ready_builders,
            builder_ceiling - active_builders,
            pr_headroom if not red_main else max(1, pr_headroom),
            branch_headroom if not red_main else max(1, branch_headroom),
            considered,
        ),
    )
    remaining = considered - new_builders
    integrators = min(integration_backlog, remaining)
    remaining -= integrators
    if over_budget:
        retirement = min(retirement_candidates, limits.retirement_workers, remaining)
        remaining -= retirement
        reviewers = min(review_backlog, remaining)
        remaining -= reviewers
    else:
        reviewers = min(review_backlog, remaining)
        remaining -= reviewers
        retirement = min(retirement_candidates, limits.retirement_workers, remaining)
        remaining -= retirement
    verifiers = min(limits.verification_workers, remaining) if active_builders or new_builders else 0

    admitted = new_builders + integrators + reviewers + retirement + verifiers
    if over_budget:
        status = "RETIREMENT"
    elif new_builders:
        status = "WORK"
    elif admitted:
        status = "ASSIST"
    else:
        status = "STOP"

    return {
        "policyVersion": "17.0",
        "status": status,
        "stopAuthorized": status == "STOP",
        "requestedWorkers": requested_workers,
        "consideredWorkers": considered,
        "admittedWorkers": admitted,
        "parkedWorkers": requested_workers - admitted,
        "newPrimaryBuilders": new_builders,
        "integrators": integrators,
        "reviewers": reviewers,
        "retirementWorkers": retirement,
        "verifiers": verifiers,
        "prHeadroom": pr_headroom,
        "branchHeadroom": branch_headroom,
        "overRepositoryBudget": over_budget,
        "throttledBy": throttle_reasons,
        "redMainEmergencyException": bool(red_main and over_budget and new_builders),
        "authorityGranted": False,
    }
