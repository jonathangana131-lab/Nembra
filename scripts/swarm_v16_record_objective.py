#!/usr/bin/env python3
"""Record an accepted non-physical V16 objective integration into Mission Graph.

This is an operator primitive for exact, already-merged software objectives.  It
cannot accept physical/user-dependent objectives and it refuses to close over an
unresolved P0/P1 blocker.  The caller must independently bind the supplied PR,
source head, merge SHA, acceptance runs, and review reference to repository truth.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from typing import Any, Sequence

from swarmcp import (
    GitHubContentsStore,
    ValidationError,
    add_evidence,
    complete_objective,
    format_v16_time,
    utc_now,
    v16_graph_service,
)

_SHA40 = re.compile(r"[0-9a-f]{40}")
_ID = re.compile(r"[a-z0-9][a-z0-9._-]{0,95}")


def _digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def record_objective_integration(
    graph: dict[str, Any],
    *,
    objective_id: str,
    pr: int,
    source_head: str,
    merge_sha: str,
    acceptance_runs: Sequence[str],
    review_refs: Sequence[str],
    affected_paths: Sequence[str],
    now=None,
) -> dict[str, Any]:
    if not _ID.fullmatch(objective_id):
        raise ValidationError("invalid objective id")
    if not _SHA40.fullmatch(source_head) or not _SHA40.fullmatch(merge_sha):
        raise ValidationError("source/merge SHA must be exact lowercase 40-hex")
    if pr < 1 or not acceptance_runs or not review_refs or not affected_paths:
        raise ValidationError("integration requires PR, acceptance, review, and affected paths")
    objective = graph["objectives"].get(objective_id)
    if not objective:
        raise ValidationError("unknown objective")
    if objective["physicalOrUserDependency"]:
        raise ValidationError("operator software integration cannot accept physical/user-dependent objective")
    unresolved = [
        bid
        for bid in objective["blockerIds"]
        if graph["blockers"][bid]["state"] != "RESOLVED"
        and graph["blockers"][bid]["severity"] in {"P0", "P1"}
    ]
    if unresolved:
        raise ValidationError("objective still has unresolved P0/P1 blockers: " + ", ".join(unresolved))

    stamp = format_v16_time(now)
    source_digest = _digest({"pr": pr, "sourceHead": source_head, "affectedPaths": list(affected_paths)})
    dependency_digest = _digest({"objective": objective_id, "mergeSHA": merge_sha})
    acceptance_environment = _digest({"acceptanceRuns": list(acceptance_runs)})
    review_environment = _digest({"reviewRefs": list(review_refs)})
    integration_environment = _digest({"mergeSHA": merge_sha, "pr": pr})

    evidence_specs = (
        (
            f"{objective_id}-accept-{source_head[:12]}",
            "software-acceptance",
            acceptance_environment,
            {"pr": pr, "sourceHead": source_head, "acceptanceRuns": list(acceptance_runs)},
        ),
        (
            f"{objective_id}-review-{source_head[:12]}",
            "independent-review",
            review_environment,
            {"pr": pr, "sourceHead": source_head, "reviewRefs": list(review_refs)},
        ),
        (
            f"{objective_id}-main-{merge_sha[:12]}",
            "integration-truth",
            integration_environment,
            {"pr": pr, "sourceHead": source_head, "mergeSHA": merge_sha},
        ),
    )
    evidence_ids: list[str] = []
    for evidence_id, evidence_type, environment_digest, details in evidence_specs:
        add_evidence(
            graph,
            evidence_id=evidence_id,
            objective_id=objective_id,
            evidence_type=evidence_type,
            status="PASS",
            truth_class="OBSERVED",
            source_digest=source_digest,
            dependency_digest=dependency_digest,
            environment_digest=environment_digest,
            affected_paths=affected_paths,
            details=details,
            now=now,
        )
        evidence_ids.append(evidence_id)

    objective["finishSatisfied"] = [True] * len(objective["finishConditions"])
    objective["integrationState"] = "MAIN"
    objective["lastMeaningfulProgress"] = stamp
    for dimension in ("functionality", "testing", "integration", "knownBlockers"):
        objective["featureGenome"][dimension] = {
            "state": "ACCEPTED",
            "evidenceIds": list(evidence_ids),
            "notes": f"Accepted software integration PR #{pr} -> {merge_sha[:12]}",
        }
    complete_objective(graph, objective_id, now=now)

    branch_name = objective.get("canonicalBranch") or ""
    if branch_name:
        branch = graph["branches"].setdefault(
            branch_name,
            {
                "branch": branch_name,
                "missionId": objective["missionId"],
                "objectiveId": objective_id,
                "state": "SELECTED",
                "world": "MAIN",
                "selectedAt": stamp,
                "integratedAt": stamp,
                "pr": pr,
                "source": {},
            },
        )
        branch.update(
            {
                "state": "SELECTED",
                "world": "MAIN",
                "integratedAt": stamp,
                "pr": pr,
                "source": {"pr": pr, "headSHA": source_head, "mergeSHA": merge_sha},
            }
        )

    mission = graph["missions"][objective["missionId"]]
    mission["lastMeaningfulProgress"] = stamp
    graph["metrics"]["meaningfulProgressEvents"] = int(graph["metrics"].get("meaningfulProgressEvents", 0)) + 1
    return {
        "objectiveId": objective_id,
        "status": objective["status"],
        "integrationState": objective["integrationState"],
        "evidenceIds": evidence_ids,
        "canonicalBranch": branch_name,
        "physicalAuthorityPromoted": False,
    }


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Record accepted V16 software objective integration")
    p.add_argument("--repo", required=True)
    p.add_argument("--state-branch", default="swarm-state")
    p.add_argument("--token", default="")
    p.add_argument("--objective", required=True)
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--source-head", required=True)
    p.add_argument("--merge-sha", required=True)
    p.add_argument("--acceptance-run", action="append", default=[])
    p.add_argument("--review-ref", action="append", default=[])
    p.add_argument("--affected-path", action="append", default=[])
    return p


def main(argv=None) -> int:
    args = parser().parse_args(argv)
    token = args.token or os.getenv("GITHUB_TOKEN", "")
    if not token:
        raise SystemExit("GITHUB_TOKEN is required")
    store = GitHubContentsStore(args.repo, token, args.state_branch)
    service = v16_graph_service(store)

    def mutate(graph):
        return record_objective_integration(
            graph,
            objective_id=args.objective,
            pr=args.pr,
            source_head=args.source_head,
            merge_sha=args.merge_sha,
            acceptance_runs=args.acceptance_run,
            review_refs=args.review_ref,
            affected_paths=args.affected_path,
            now=utc_now(),
        )

    graph, result = service.mutate(mutate, message=f"swarm v16: integrate objective {args.objective}")
    print(json.dumps({"result": result, "revision": graph["revision"]}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
