#!/usr/bin/env python3
"""Fail-closed cleanup for stale queued Xcode 27 PR QA runs.

The xcode-27 runner is scarce. This helper only cancels a queued
xcode27-pr-command run when GitHub's current open-PR state proves that the
run's exact branch/SHA is no longer the exact head of any open PR.

Current exact open PR heads are always preserved. Ambiguous API/state failures
fail closed and preserve the run.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Iterable

API_ROOT = "https://api.github.com"
WORKFLOW = "xcode27-pr-command.yml"
ALLOWED_EVENTS = {"pull_request", "issue_comment"}


@dataclass(frozen=True)
class Decision:
    cancel: bool
    reason: str


def _parse_github_time(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def classify_run(
    run: dict[str, Any],
    open_prs: Iterable[dict[str, Any]],
    *,
    now: dt.datetime,
    minimum_age_seconds: int,
) -> Decision:
    """Return a fail-closed cancellation decision using only current PR truth."""

    if run.get("status") != "queued":
        return Decision(False, "not queued")
    if run.get("event") not in ALLOWED_EVENTS:
        return Decision(False, "unsupported event; preserve")

    branch = run.get("head_branch")
    head_sha = run.get("head_sha")
    created_at = run.get("created_at")
    if not branch or not head_sha or not created_at:
        return Decision(False, "missing branch/SHA/time; preserve")

    try:
        age = (now - _parse_github_time(created_at)).total_seconds()
    except (TypeError, ValueError):
        return Decision(False, "invalid creation time; preserve")

    if age < minimum_age_seconds:
        return Decision(False, "inside API-consistency grace period")

    prs = list(open_prs)
    for pr in prs:
        head = pr.get("head") or {}
        if head.get("ref") == branch and head.get("sha") == head_sha:
            return Decision(False, "protected current exact head of an open PR")

    if not prs:
        return Decision(True, "no open PR remains for queued branch")

    return Decision(True, "queued SHA is not the current exact head of any open PR on branch")


class GitHubAPI:
    def __init__(self, token: str, repository: str) -> None:
        if "/" not in repository:
            raise ValueError("repository must be owner/name")
        self.token = token
        self.repository = repository
        self.owner, self.repo = repository.split("/", 1)

    def request(self, method: str, path: str) -> Any:
        request = urllib.request.Request(
            f"{API_ROOT}{path}",
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "nembra-xcode27-queue-janitor",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read()
                if not body:
                    return None
                return json.loads(body.decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"GitHub API {method} {path} failed: HTTP {exc.code}: {body}") from exc

    def queued_runs(self) -> list[dict[str, Any]]:
        runs: list[dict[str, Any]] = []
        for page in range(1, 21):
            query = urllib.parse.urlencode(
                {"status": "queued", "per_page": 100, "page": page}
            )
            payload = self.request(
                "GET",
                f"/repos/{self.owner}/{self.repo}/actions/workflows/{WORKFLOW}/runs?{query}",
            )
            batch = list((payload or {}).get("workflow_runs") or [])
            runs.extend(batch)
            if len(batch) < 100:
                break
        return runs

    def open_prs_for_branch(self, branch: str) -> list[dict[str, Any]]:
        query = urllib.parse.urlencode(
            {"state": "open", "head": f"{self.owner}:{branch}", "per_page": 100}
        )
        payload = self.request(
            "GET", f"/repos/{self.owner}/{self.repo}/pulls?{query}"
        )
        return list(payload or [])

    def cancel_run(self, run_id: int) -> None:
        self.request(
            "POST", f"/repos/{self.owner}/{self.repo}/actions/runs/{run_id}/cancel"
        )


def self_test() -> None:
    now = dt.datetime(2026, 8, 8, 12, 30, tzinfo=dt.timezone.utc)

    def run(**overrides: Any) -> dict[str, Any]:
        base = {
            "id": 1,
            "status": "queued",
            "event": "pull_request",
            "head_branch": "parallel/example",
            "head_sha": "aaa",
            "created_at": "2026-08-08T12:00:00Z",
        }
        base.update(overrides)
        return base

    current_pr = {"head": {"ref": "parallel/example", "sha": "aaa"}}
    newer_pr = {"head": {"ref": "parallel/example", "sha": "bbb"}}

    assert classify_run(
        run(), [current_pr], now=now, minimum_age_seconds=120
    ) == Decision(False, "protected current exact head of an open PR")
    assert classify_run(
        run(), [newer_pr], now=now, minimum_age_seconds=120
    ).cancel
    assert classify_run(
        run(), [], now=now, minimum_age_seconds=120
    ).cancel
    assert not classify_run(
        run(created_at="2026-08-08T12:29:30Z"),
        [],
        now=now,
        minimum_age_seconds=120,
    ).cancel
    assert not classify_run(
        run(event="workflow_dispatch"), [], now=now, minimum_age_seconds=120
    ).cancel
    assert not classify_run(
        run(head_branch=None), [], now=now, minimum_age_seconds=120
    ).cancel
    assert not classify_run(
        run(status="in_progress"), [], now=now, minimum_age_seconds=120
    ).cancel

    print("xcode27_queue_janitor self-test: PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="cancel proven-stale queued runs")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN"))
    parser.add_argument("--minimum-age-seconds", type=int, default=120)
    parser.add_argument("--max-cancellations", type=int, default=200)
    args = parser.parse_args()

    if args.self_test:
        self_test()
        if not args.apply:
            return 0

    if not args.repository:
        parser.error("--repository or GITHUB_REPOSITORY is required")
    if not args.token:
        parser.error("--token or GITHUB_TOKEN is required")
    if args.minimum_age_seconds < 0:
        parser.error("--minimum-age-seconds must be >= 0")
    if args.max_cancellations < 1:
        parser.error("--max-cancellations must be >= 1")

    api = GitHubAPI(args.token, args.repository)
    runs = api.queued_runs()
    now = dt.datetime.now(dt.timezone.utc)
    branch_cache: dict[str, list[dict[str, Any]] | None] = {}
    candidates: list[tuple[dict[str, Any], Decision]] = []
    protected = 0
    ambiguous = 0

    for run in runs:
        branch = run.get("head_branch")
        if not branch:
            decision = Decision(False, "missing branch/SHA/time; preserve")
        else:
            if branch not in branch_cache:
                try:
                    branch_cache[branch] = api.open_prs_for_branch(branch)
                except RuntimeError as exc:
                    print(f"PRESERVE branch={branch!r}: open-PR lookup failed: {exc}")
                    branch_cache[branch] = None

            open_prs = branch_cache[branch]
            if open_prs is None:
                ambiguous += 1
                continue

            decision = classify_run(
                run,
                open_prs,
                now=now,
                minimum_age_seconds=args.minimum_age_seconds,
            )

        if decision.cancel:
            candidates.append((run, decision))
        elif "protected current exact head" in decision.reason:
            protected += 1

    print(
        f"queued={len(runs)} stale_candidates={len(candidates)} "
        f"protected_exact_open_heads={protected} lookup_failures_preserved={ambiguous}"
    )

    cancelled = 0
    for run, decision in candidates[: args.max_cancellations]:
        run_id = int(run["id"])
        branch = run.get("head_branch")
        sha = run.get("head_sha")
        prefix = "CANCEL" if args.apply else "WOULD_CANCEL"
        print(f"{prefix} run={run_id} branch={branch} sha={sha} reason={decision.reason}")
        if not args.apply:
            continue
        try:
            api.cancel_run(run_id)
            cancelled += 1
        except RuntimeError as exc:
            # A queued run can race to completion/cancellation after listing. Preserve
            # the fail-closed classification log and continue with independent runs.
            print(f"CANCEL_RACE run={run_id}: {exc}", file=sys.stderr)

    if args.apply:
        print(f"cancelled={cancelled} cap={args.max_cancellations}")
    else:
        print("dry-run only; pass --apply to cancel proven-stale queued runs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
