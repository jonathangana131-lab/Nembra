#!/usr/bin/env python3
"""Fail-closed cleanup for stale Xcode 27 PR QA runs.

The xcode-27 runner is scarce. This helper only cancels a queued or in-progress
xcode27-pr-command *pull_request* run when GitHub's current open-PR state proves
that the run's exact branch/SHA is no longer the exact head of any open PR.

`issue_comment` workflow runs are intentionally preserved. GitHub binds that
event's workflow ref/SHA to the default branch rather than the commented PR,
so workflow-run head_branch/head_sha cannot safely identify the requested PR
head. Current exact open PR heads, unsupported events, and ambiguous API/state
failures are always preserved.
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
ALLOWED_EVENTS = {"pull_request"}
CANCELLABLE_STATUSES = {"queued", "in_progress"}


@dataclass(frozen=True)
class Decision:
    cancel: bool
    reason: str


class GitHubHTTPError(RuntimeError):
    """HTTP failure retaining the status code for fail-closed recovery policy."""

    def __init__(self, method: str, path: str, status_code: int, body: str) -> None:
        self.method = method
        self.path = path
        self.status_code = status_code
        self.body = body
        super().__init__(
            f"GitHub API {method} {path} failed: HTTP {status_code}: {body}"
        )


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

    status = run.get("status")
    if status not in CANCELLABLE_STATUSES:
        return Decision(False, "status is not cancellable")
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
        return Decision(True, f"no open PR remains for {status} branch")

    return Decision(
        True,
        f"{status} SHA is not the current exact head of any open PR on branch",
    )


def may_force_cancel_after(error: BaseException) -> bool:
    """Use GitHub force-cancel only after the normal endpoint itself failed 500."""

    return isinstance(error, GitHubHTTPError) and error.status_code == 500


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
            raise GitHubHTTPError(method, path, exc.code, body) from exc

    def runs_with_status(self, status: str) -> list[dict[str, Any]]:
        if status not in CANCELLABLE_STATUSES:
            raise ValueError(f"unsupported cancellable status: {status}")
        runs: list[dict[str, Any]] = []
        for page in range(1, 21):
            query = urllib.parse.urlencode(
                {"status": status, "per_page": 100, "page": page}
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

    def candidate_runs(self) -> list[dict[str, Any]]:
        runs: list[dict[str, Any]] = []
        seen_ids: set[int] = set()
        for status in ("queued", "in_progress"):
            for run in self.runs_with_status(status):
                run_id = int(run.get("id", -1))
                if run_id in seen_ids:
                    continue
                seen_ids.add(run_id)
                runs.append(run)
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

    def force_cancel_run(self, run_id: int) -> None:
        self.request(
            "POST",
            f"/repos/{self.owner}/{self.repo}/actions/runs/{run_id}/force-cancel",
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
    assert classify_run(
        run(status="in_progress"), [], now=now, minimum_age_seconds=120
    ).cancel
    assert classify_run(
        run(status="in_progress"), [current_pr], now=now, minimum_age_seconds=120
    ) == Decision(False, "protected current exact head of an open PR")
    assert not classify_run(
        run(created_at="2026-08-08T12:29:30Z"),
        [],
        now=now,
        minimum_age_seconds=120,
    ).cancel
    # issue_comment run metadata is default-branch identity, not PR-head identity.
    # Preserve even if it otherwise looks stale; a future janitor can resolve the
    # commented PR from stronger evidence instead of guessing from run metadata.
    assert not classify_run(
        run(event="issue_comment", head_branch="main", head_sha="default-sha"),
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
        run(status="completed"), [], now=now, minimum_age_seconds=120
    ).cancel

    assert may_force_cancel_after(
        GitHubHTTPError("POST", "/actions/runs/1/cancel", 500, "failed")
    )
    assert not may_force_cancel_after(
        GitHubHTTPError("POST", "/actions/runs/1/cancel", 409, "conflict")
    )
    assert not may_force_cancel_after(RuntimeError("transport failure"))

    print("xcode27_queue_janitor self-test: PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--apply",
        action="store_true",
        help="cancel proven-stale queued/in-progress pull_request runs",
    )
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
    runs = api.candidate_runs()
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

    queued = sum(run.get("status") == "queued" for run in runs)
    in_progress = sum(run.get("status") == "in_progress" for run in runs)
    print(
        f"candidate_runs={len(runs)} queued={queued} in_progress={in_progress} "
        f"stale_candidates={len(candidates)} "
        f"protected_exact_open_heads={protected} "
        f"lookup_failures_preserved={ambiguous}"
    )

    cancelled = 0
    for run, decision in candidates[: args.max_cancellations]:
        run_id = int(run["id"])
        branch = run.get("head_branch")
        sha = run.get("head_sha")
        status = run.get("status")
        prefix = "CANCEL" if args.apply else "WOULD_CANCEL"
        print(
            f"{prefix} run={run_id} status={status} branch={branch} sha={sha} "
            f"reason={decision.reason}"
        )
        if not args.apply:
            continue
        try:
            api.cancel_run(run_id)
            cancelled += 1
            continue
        except RuntimeError as exc:
            if not may_force_cancel_after(exc):
                print(f"CANCEL_RACE run={run_id}: {exc}", file=sys.stderr)
                continue
            print(
                f"CANCEL_PRIMARY_FAILED run={run_id}; trying documented force-cancel: {exc}",
                file=sys.stderr,
            )

        try:
            api.force_cancel_run(run_id)
            cancelled += 1
            print(f"FORCE_CANCEL run={run_id} reason=normal cancel returned HTTP 500")
        except RuntimeError as exc:
            print(f"FORCE_CANCEL_RACE run={run_id}: {exc}", file=sys.stderr)

    if args.apply:
        print(f"cancelled={cancelled} cap={args.max_cancellations}")
    else:
        print(
            "dry-run only; pass --apply to cancel proven-stale "
            "queued/in-progress pull_request runs"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
