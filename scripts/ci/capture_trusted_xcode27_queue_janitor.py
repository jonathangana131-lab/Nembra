#!/usr/bin/env python3
"""Fail-closed cleanup for stale trusted Capture Xcode 27 owner-command runs.

GitHub reports issue_comment workflow runs with the default-branch SHA rather than
the commented pull request head.  This helper therefore never guesses identity
from workflow-run head_branch/head_sha.  It only considers a run cancellable
when all of the following are true:

1. the run belongs to capture-xcode27-trusted-command.yml and is still waiting
   for, queued on, or using the scarce Mac runner;
2. the trusted default-branch resolver job completed successfully;
3. that resolver's own retained log contains exactly one canonical
   `Resolved PR #<n> exact head <40-hex>` witness;
4. a fresh GitHub pull-request lookup proves that exact PR is now closed,
   detached, or at a different exact head.

Any missing/ambiguous resolver evidence or API failure is preserved.  Current
exact open PR heads are always preserved.  This script changes CI queue state
only; it is not product, Simulator, signing, or physical ES80 evidence.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any

API_ROOT = "https://api.github.com"
WORKFLOW = "capture-xcode27-trusted-command.yml"
RESOLVER_JOB_NAME = "Resolve trusted Capture PR head"
CANCELLABLE_STATUSES = {"pending", "queued", "in_progress"}
RESOLVED_RE = re.compile(
    rb"(?m)^Resolved PR #(\d+) exact head ([0-9a-f]{40})\r?$"
)


@dataclass(frozen=True)
class ResolvedIdentity:
    pr_number: int
    head_sha: str


@dataclass(frozen=True)
class Decision:
    cancel: bool
    reason: str


def _parse_github_time(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def parse_resolved_identity(log_bytes: bytes) -> ResolvedIdentity | None:
    """Accept one and only one canonical resolver witness from trusted job logs."""

    matches = RESOLVED_RE.findall(log_bytes)
    if len(matches) != 1:
        return None
    pr_text, sha_bytes = matches[0]
    try:
        pr_number = int(pr_text.decode("ascii"))
        head_sha = sha_bytes.decode("ascii")
    except (UnicodeDecodeError, ValueError):
        return None
    if pr_number < 1 or re.fullmatch(r"[0-9a-f]{40}", head_sha) is None:
        return None
    return ResolvedIdentity(pr_number=pr_number, head_sha=head_sha)


def classify_trusted_run(
    run: dict[str, Any],
    identity: ResolvedIdentity | None,
    live_pr: dict[str, Any] | None,
    *,
    repository: str,
    now: dt.datetime,
    minimum_age_seconds: int,
) -> Decision:
    """Return a cancellation decision only when fresh PR truth proves staleness."""

    status = run.get("status")
    if status not in CANCELLABLE_STATUSES:
        return Decision(False, "status is not cancellable")
    if run.get("event") != "issue_comment":
        return Decision(False, "unsupported event; preserve")

    created_at = run.get("created_at")
    if not created_at:
        return Decision(False, "missing creation time; preserve")
    try:
        age = (now - _parse_github_time(created_at)).total_seconds()
    except (TypeError, ValueError):
        return Decision(False, "invalid creation time; preserve")
    if age < minimum_age_seconds:
        return Decision(False, "inside API-consistency grace period")

    if identity is None:
        return Decision(False, "missing or ambiguous trusted resolver witness; preserve")
    if live_pr is None:
        return Decision(False, "live PR lookup unavailable; preserve")
    if live_pr.get("number") != identity.pr_number:
        return Decision(False, "live PR identity mismatch; preserve")

    head = live_pr.get("head") or {}
    head_repo = head.get("repo") or {}
    live_sha = head.get("sha")
    live_repo = head_repo.get("full_name")
    live_state = live_pr.get("state")
    if not live_sha or not live_repo or not live_state:
        return Decision(False, "live PR metadata incomplete; preserve")

    if live_state != "open":
        return Decision(True, "trusted run targets a PR that is no longer open")
    if live_repo != repository:
        return Decision(True, "trusted run PR source is no longer the trusted repository")
    if live_sha != identity.head_sha:
        return Decision(True, "trusted resolver SHA is no longer the live PR head")

    return Decision(False, "protected exact current head of the live open Capture PR")


class GitHubAPI:
    def __init__(self, token: str, repository: str) -> None:
        if "/" not in repository:
            raise ValueError("repository must be owner/name")
        self.token = token
        self.repository = repository
        self.owner, self.repo = repository.split("/", 1)

    def _request(self, method: str, path: str) -> bytes:
        request = urllib.request.Request(
            f"{API_ROOT}{path}",
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "nembra-capture-trusted-xcode27-queue-janitor",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"GitHub API {method} {path} failed: HTTP {exc.code}: {body}"
            ) from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"GitHub API {method} {path} failed: {exc}") from exc

    def request_json(self, method: str, path: str) -> Any:
        body = self._request(method, path)
        if not body:
            return None
        try:
            return json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RuntimeError(f"GitHub API {method} {path} returned non-JSON data") from exc

    def runs_with_status(self, status: str) -> list[dict[str, Any]]:
        if status not in CANCELLABLE_STATUSES:
            raise ValueError(f"unsupported cancellable status: {status}")
        runs: list[dict[str, Any]] = []
        for page in range(1, 21):
            query = urllib.parse.urlencode(
                {"status": status, "per_page": 100, "page": page}
            )
            payload = self.request_json(
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
        for status in ("pending", "queued", "in_progress"):
            for run in self.runs_with_status(status):
                run_id = int(run.get("id", -1))
                if run_id < 1 or run_id in seen_ids:
                    continue
                seen_ids.add(run_id)
                runs.append(run)
        return runs

    def resolver_identity(self, run_id: int) -> ResolvedIdentity | None:
        query = urllib.parse.urlencode({"filter": "latest", "per_page": 100})
        payload = self.request_json(
            "GET",
            f"/repos/{self.owner}/{self.repo}/actions/runs/{run_id}/jobs?{query}",
        )
        jobs = list((payload or {}).get("jobs") or [])
        resolvers = [job for job in jobs if job.get("name") == RESOLVER_JOB_NAME]
        if len(resolvers) != 1:
            return None
        resolver = resolvers[0]
        if resolver.get("status") != "completed" or resolver.get("conclusion") != "success":
            return None
        job_id = resolver.get("id")
        if not isinstance(job_id, int) or job_id < 1:
            return None
        log_bytes = self._request(
            "GET", f"/repos/{self.owner}/{self.repo}/actions/jobs/{job_id}/logs"
        )
        return parse_resolved_identity(log_bytes)

    def pull_request(self, pr_number: int) -> dict[str, Any]:
        payload = self.request_json(
            "GET", f"/repos/{self.owner}/{self.repo}/pulls/{pr_number}"
        )
        if not isinstance(payload, dict):
            raise RuntimeError("GitHub pull-request lookup returned an invalid payload")
        return payload

    def cancel_run(self, run_id: int) -> None:
        self._request(
            "POST", f"/repos/{self.owner}/{self.repo}/actions/runs/{run_id}/cancel"
        )


def self_test() -> None:
    now = dt.datetime(2026, 8, 9, 3, 20, tzinfo=dt.timezone.utc)
    repo = "jonathangana131-lab/Nembra"
    identity = ResolvedIdentity(
        pr_number=833,
        head_sha="1" * 40,
    )

    def run(**overrides: Any) -> dict[str, Any]:
        base = {
            "id": 123,
            "status": "pending",
            "event": "issue_comment",
            "created_at": "2026-08-09T03:00:00Z",
        }
        base.update(overrides)
        return base

    def pr(**overrides: Any) -> dict[str, Any]:
        base = {
            "number": 833,
            "state": "open",
            "head": {
                "sha": "1" * 40,
                "repo": {"full_name": repo},
            },
        }
        base.update(overrides)
        return base

    log = b"noise\nResolved PR #833 exact head " + (b"1" * 40) + b"\nmore\n"
    assert parse_resolved_identity(log) == identity
    assert parse_resolved_identity(log + log) is None
    assert parse_resolved_identity(b"Resolved PR #0 exact head " + (b"1" * 40) + b"\n") is None
    assert parse_resolved_identity(b"Resolved PR #833 exact head NOT-A-SHA\n") is None

    assert classify_trusted_run(
        run(), identity, pr(), repository=repo, now=now, minimum_age_seconds=120
    ) == Decision(False, "protected exact current head of the live open Capture PR")

    moved = pr()
    moved["head"] = {"sha": "2" * 40, "repo": {"full_name": repo}}
    assert classify_trusted_run(
        run(), identity, moved, repository=repo, now=now, minimum_age_seconds=120
    ).cancel

    closed = pr(state="closed")
    assert classify_trusted_run(
        run(), identity, closed, repository=repo, now=now, minimum_age_seconds=120
    ).cancel

    detached = pr()
    detached["head"] = {"sha": "1" * 40, "repo": {"full_name": "other/repo"}}
    assert classify_trusted_run(
        run(), identity, detached, repository=repo, now=now, minimum_age_seconds=120
    ).cancel

    assert not classify_trusted_run(
        run(), None, moved, repository=repo, now=now, minimum_age_seconds=120
    ).cancel
    assert not classify_trusted_run(
        run(), identity, None, repository=repo, now=now, minimum_age_seconds=120
    ).cancel
    assert not classify_trusted_run(
        run(event="pull_request"), identity, moved,
        repository=repo, now=now, minimum_age_seconds=120,
    ).cancel
    assert not classify_trusted_run(
        run(created_at="2026-08-09T03:19:30Z"), identity, moved,
        repository=repo, now=now, minimum_age_seconds=120,
    ).cancel
    assert not classify_trusted_run(
        run(status="completed"), identity, moved,
        repository=repo, now=now, minimum_age_seconds=120,
    ).cancel

    wrong_number = pr()
    wrong_number["number"] = 834
    assert not classify_trusted_run(
        run(), identity, wrong_number,
        repository=repo, now=now, minimum_age_seconds=120,
    ).cancel

    print("capture_trusted_xcode27_queue_janitor self-test: PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--apply",
        action="store_true",
        help="cancel only proven-stale trusted Capture issue_comment runs",
    )
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN"))
    parser.add_argument("--minimum-age-seconds", type=int, default=120)
    parser.add_argument("--max-cancellations", type=int, default=50)
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
    candidates: list[tuple[dict[str, Any], ResolvedIdentity, Decision]] = []
    protected = 0
    ambiguous = 0

    for run in runs:
        run_id = int(run.get("id", -1))
        if run_id < 1:
            ambiguous += 1
            continue

        try:
            identity = api.resolver_identity(run_id)
        except RuntimeError as exc:
            print(f"PRESERVE run={run_id}: trusted resolver evidence unavailable: {exc}")
            ambiguous += 1
            continue
        if identity is None:
            print(f"PRESERVE run={run_id}: missing or ambiguous trusted resolver witness")
            ambiguous += 1
            continue

        try:
            live_pr = api.pull_request(identity.pr_number)
        except RuntimeError as exc:
            print(f"PRESERVE run={run_id}: live PR lookup failed: {exc}")
            ambiguous += 1
            continue

        decision = classify_trusted_run(
            run,
            identity,
            live_pr,
            repository=args.repository,
            now=now,
            minimum_age_seconds=args.minimum_age_seconds,
        )
        if decision.cancel:
            candidates.append((run, identity, decision))
        elif "protected exact current head" in decision.reason:
            protected += 1

    pending = sum(run.get("status") == "pending" for run in runs)
    queued = sum(run.get("status") == "queued" for run in runs)
    in_progress = sum(run.get("status") == "in_progress" for run in runs)
    print(
        f"trusted_candidate_runs={len(runs)} pending={pending} queued={queued} "
        f"in_progress={in_progress} stale_candidates={len(candidates)} "
        f"protected_exact_open_heads={protected} ambiguous_preserved={ambiguous}"
    )

    cancelled = 0
    for run, identity, decision in candidates[: args.max_cancellations]:
        run_id = int(run["id"])
        prefix = "CANCEL" if args.apply else "WOULD_CANCEL"
        print(
            f"{prefix} run={run_id} status={run.get('status')} "
            f"pr={identity.pr_number} resolved_sha={identity.head_sha} "
            f"reason={decision.reason}"
        )
        if not args.apply:
            continue
        try:
            api.cancel_run(run_id)
            cancelled += 1
        except RuntimeError as exc:
            print(f"CANCEL_RACE run={run_id}: {exc}", file=sys.stderr)

    if args.apply:
        print(f"cancelled={cancelled} cap={args.max_cancellations}")
    else:
        print("dry-run only; pass --apply to cancel proven-stale trusted Capture runs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
