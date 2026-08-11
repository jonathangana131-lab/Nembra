#!/usr/bin/env python3
"""Fail-closed cleanup for stale direct Capture PR Mac workflow runs.

Capture's final-candidate branch can move several times while visual/truth/accessibility
repairs converge. Each move schedules three scarce xcode-27 pull_request workflows.
GitHub does not automatically retire every queued ancestor run, so stale heads can
occupy most of the Mac queue and delay the one SHA that could actually be accepted.

This helper may cancel only queued/in-progress runs from the three explicitly
allowlisted direct Capture pull_request workflows. A run is cancellable only when
current GitHub PR truth proves its exact branch/SHA is no longer the exact head of
any open same-repository PR. Missing fields, unsupported events, API failures,
ambiguous PR objects, and explicitly protected synchronize-event heads are always
preserved.
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
from typing import Any, Iterable

API_ROOT = "https://api.github.com"
WORKFLOWS = (
    "capture-main-selective-graft-diagnostic.yml",
    "capture-field-build-provenance.yml",
    "capture-standalone-visual-evidence.yml",
)
WORKFLOW_PATHS = {f".github/workflows/{name}" for name in WORKFLOWS}
CANCELLABLE_STATUSES = ("queued", "in_progress")
ALLOWED_EVENTS = {"pull_request"}
HEX40 = re.compile(r"^[0-9a-f]{40}$")


@dataclass(frozen=True)
class Decision:
    cancel: bool
    reason: str


class GitHubAPIError(RuntimeError):
    def __init__(self, method: str, path: str, status_code: int, body: str) -> None:
        self.method = method
        self.path = path
        self.status_code = status_code
        self.body = body
        super().__init__(
            f"GitHub API {method} {path} failed: HTTP {status_code}: {body}"
        )


def _parse_time(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _valid_open_pr_subject(pr: dict[str, Any], repository: str, branch: str) -> bool:
    if pr.get("state") != "open":
        return False
    head = pr.get("head")
    if not isinstance(head, dict):
        return False
    repo = head.get("repo")
    if not isinstance(repo, dict) or repo.get("full_name") != repository:
        return False
    sha = head.get("sha")
    return head.get("ref") == branch and isinstance(sha, str) and bool(HEX40.fullmatch(sha))


def classify_run(
    run: dict[str, Any],
    open_prs: Iterable[dict[str, Any]],
    *,
    repository: str,
    now: dt.datetime,
    minimum_age_seconds: int,
    protected_heads: set[tuple[str, str]],
) -> Decision:
    if run.get("status") not in CANCELLABLE_STATUSES:
        return Decision(False, "status is not cancellable")
    if run.get("event") not in ALLOWED_EVENTS:
        return Decision(False, "unsupported event; preserve")
    if run.get("path") not in WORKFLOW_PATHS:
        return Decision(False, "workflow path is not allowlisted; preserve")

    branch = run.get("head_branch")
    sha = run.get("head_sha")
    created_at = run.get("created_at")
    if (
        not isinstance(branch, str)
        or not branch
        or not isinstance(sha, str)
        or not HEX40.fullmatch(sha)
        or not isinstance(created_at, str)
    ):
        return Decision(False, "missing/invalid branch, SHA, or creation time; preserve")

    if (branch, sha) in protected_heads:
        return Decision(False, "explicit synchronize-event head; preserve")

    try:
        age = (now - _parse_time(created_at)).total_seconds()
    except (TypeError, ValueError):
        return Decision(False, "invalid creation time; preserve")
    if age < minimum_age_seconds:
        return Decision(False, "inside API-consistency grace period")

    prs = list(open_prs)
    if any(not _valid_open_pr_subject(pr, repository, branch) for pr in prs):
        return Decision(False, "open-PR subject is ambiguous; preserve")

    for pr in prs:
        if pr["head"]["sha"] == sha:
            return Decision(False, "protected current exact head of an open PR")

    if not prs:
        return Decision(True, "no open same-repository PR remains for branch")
    return Decision(True, "run SHA is stale relative to current open-PR head")


class GitHubAPI:
    def __init__(self, token: str, repository: str) -> None:
        if "/" not in repository:
            raise ValueError("repository must be owner/name")
        self.token = token
        self.repository = repository
        self.owner, self.repo = repository.split("/", 1)

    def request(self, method: str, path: str) -> Any:
        request = urllib.request.Request(
            API_ROOT + path,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "nembra-capture-pr-queue-janitor",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read()
                return None if not body else json.loads(body.decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise GitHubAPIError(method, path, exc.code, body) from exc

    def runs_for_workflow(self, workflow: str, status: str) -> list[dict[str, Any]]:
        if workflow not in WORKFLOWS:
            raise ValueError("workflow is not allowlisted")
        if status not in CANCELLABLE_STATUSES:
            raise ValueError("status is not cancellable")
        runs: list[dict[str, Any]] = []
        for page in range(1, 21):
            query = urllib.parse.urlencode(
                {"status": status, "per_page": 100, "page": page}
            )
            payload = self.request(
                "GET",
                f"/repos/{self.owner}/{self.repo}/actions/workflows/{workflow}/runs?{query}",
            )
            batch = list((payload or {}).get("workflow_runs") or [])
            runs.extend(batch)
            if len(batch) < 100:
                break
        return runs

    def candidate_runs(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        seen: set[int] = set()
        for workflow in WORKFLOWS:
            for status in CANCELLABLE_STATUSES:
                for run in self.runs_for_workflow(workflow, status):
                    run_id = run.get("id")
                    if not isinstance(run_id, int) or run_id in seen:
                        continue
                    seen.add(run_id)
                    result.append(run)
        return result

    def open_prs_for_branch(self, branch: str) -> list[dict[str, Any]]:
        query = urllib.parse.urlencode(
            {"state": "open", "head": f"{self.owner}:{branch}", "per_page": 100}
        )
        payload = self.request(
            "GET", f"/repos/{self.owner}/{self.repo}/pulls?{query}"
        )
        return list(payload or [])

    def cancel_run(self, run_id: int) -> bool:
        ordinary = f"/repos/{self.owner}/{self.repo}/actions/runs/{run_id}/cancel"
        try:
            self.request("POST", ordinary)
            return False
        except GitHubAPIError as exc:
            if exc.status_code != 500:
                raise
        force = f"/repos/{self.owner}/{self.repo}/actions/runs/{run_id}/force-cancel"
        self.request("POST", force)
        return True


def parse_protected_head(value: str) -> tuple[str, str]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("protected head must be BRANCH=40HEX")
    branch, sha = value.rsplit("=", 1)
    if not branch or not HEX40.fullmatch(sha):
        raise argparse.ArgumentTypeError("protected head must be BRANCH=40HEX")
    return branch, sha


def self_test() -> None:
    now = dt.datetime(2026, 8, 11, 2, 30, tzinfo=dt.timezone.utc)
    repository = "owner/repo"

    def run(**overrides: Any) -> dict[str, Any]:
        base = {
            "id": 7,
            "status": "queued",
            "event": "pull_request",
            "path": ".github/workflows/capture-standalone-visual-evidence.yml",
            "head_branch": "agent/capture",
            "head_sha": "a" * 40,
            "created_at": "2026-08-11T02:00:00Z",
        }
        base.update(overrides)
        return base

    def pr(sha: str = "a" * 40) -> dict[str, Any]:
        return {
            "state": "open",
            "head": {
                "ref": "agent/capture",
                "sha": sha,
                "repo": {"full_name": repository},
            },
        }

    common = dict(
        repository=repository,
        now=now,
        minimum_age_seconds=120,
        protected_heads=set(),
    )
    assert classify_run(run(), [pr()], **common) == Decision(
        False, "protected current exact head of an open PR"
    )
    assert classify_run(run(), [pr("b" * 40)], **common).cancel
    assert classify_run(run(), [], **common).cancel
    assert not classify_run(
        run(),
        [pr("b" * 40)],
        **{**common, "protected_heads": {("agent/capture", "a" * 40)}},
    ).cancel
    assert not classify_run(
        run(created_at="2026-08-11T02:29:30Z"), [pr("b" * 40)], **common
    ).cancel
    assert not classify_run(run(event="workflow_dispatch"), [], **common).cancel
    assert not classify_run(
        run(path=".github/workflows/other.yml"), [], **common
    ).cancel
    assert not classify_run(run(head_sha="BAD"), [], **common).cancel
    assert not classify_run(run(status="completed"), [], **common).cancel

    ambiguous = pr()
    ambiguous["head"]["repo"] = None
    assert not classify_run(run(), [ambiguous], **common).cancel
    wrong_repo = pr()
    wrong_repo["head"]["repo"] = {"full_name": "fork/repo"}
    assert not classify_run(run(), [wrong_repo], **common).cancel

    assert parse_protected_head("agent/capture=" + "c" * 40) == (
        "agent/capture",
        "c" * 40,
    )

    class FakeAPI(GitHubAPI):
        def __init__(self, outcomes: list[Any]) -> None:
            self.owner = "owner"
            self.repo = "repo"
            self.repository = "owner/repo"
            self.outcomes = list(outcomes)
            self.calls: list[tuple[str, str]] = []

        def request(self, method: str, path: str) -> Any:
            self.calls.append((method, path))
            outcome = self.outcomes.pop(0)
            if isinstance(outcome, Exception):
                raise outcome
            return outcome

    ordinary = FakeAPI([None])
    assert ordinary.cancel_run(8) is False
    assert ordinary.calls == [("POST", "/repos/owner/repo/actions/runs/8/cancel")]

    failed = GitHubAPIError(
        "POST", "/repos/owner/repo/actions/runs/9/cancel", 500, "server error"
    )
    fallback = FakeAPI([failed, None])
    assert fallback.cancel_run(9) is True
    assert fallback.calls == [
        ("POST", "/repos/owner/repo/actions/runs/9/cancel"),
        ("POST", "/repos/owner/repo/actions/runs/9/force-cancel"),
    ]

    denied = GitHubAPIError(
        "POST", "/repos/owner/repo/actions/runs/10/cancel", 403, "forbidden"
    )
    try:
        FakeAPI([denied]).cancel_run(10)
    except GitHubAPIError as exc:
        assert exc.status_code == 403
    else:
        raise AssertionError("non-500 cancellation failure must fail closed")

    print("capture direct-PR queue janitor self-test: PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN"))
    parser.add_argument("--minimum-age-seconds", type=int, default=120)
    parser.add_argument("--max-cancellations", type=int, default=200)
    parser.add_argument(
        "--protected-head",
        action="append",
        default=[],
        type=parse_protected_head,
        metavar="BRANCH=SHA",
        help="exact event head that must never be cancelled during this sweep",
    )
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
    now = dt.datetime.now(dt.timezone.utc)
    protected_heads = set(args.protected_head)
    branch_cache: dict[str, list[dict[str, Any]] | None] = {}
    stale: list[tuple[dict[str, Any], Decision]] = []
    preserved = 0
    ambiguous = 0

    try:
        runs = api.candidate_runs()
    except RuntimeError as exc:
        print(f"REFUSE_MUTATION: workflow queue enumeration failed: {exc}", file=sys.stderr)
        return 2

    for run in runs:
        branch = run.get("head_branch")
        if not isinstance(branch, str) or not branch:
            preserved += 1
            continue
        if branch not in branch_cache:
            try:
                branch_cache[branch] = api.open_prs_for_branch(branch)
            except RuntimeError as exc:
                print(f"PRESERVE branch={branch!r}: open-PR lookup failed: {exc}")
                branch_cache[branch] = None
        prs = branch_cache[branch]
        if prs is None:
            ambiguous += 1
            continue
        decision = classify_run(
            run,
            prs,
            repository=args.repository,
            now=now,
            minimum_age_seconds=args.minimum_age_seconds,
            protected_heads=protected_heads,
        )
        if decision.cancel:
            stale.append((run, decision))
        else:
            preserved += 1

    stale.sort(key=lambda pair: str(pair[0].get("created_at") or ""))
    print(
        f"Capture direct-PR Mac queue: scanned={len(runs)} stale={len(stale)} "
        f"preserved={preserved} ambiguous={ambiguous} apply={args.apply}"
    )
    for run, decision in stale:
        print(
            "STALE "
            f"run={run.get('id')} workflow={run.get('path')} "
            f"branch={run.get('head_branch')} sha={run.get('head_sha')} "
            f"reason={decision.reason}"
        )

    if not args.apply:
        return 0

    cancelled = 0
    for run, decision in stale:
        if cancelled >= args.max_cancellations:
            print("Cancellation cap reached; remaining stale runs preserved.")
            break
        run_id = run.get("id")
        if not isinstance(run_id, int):
            continue
        try:
            forced = api.cancel_run(run_id)
        except RuntimeError as exc:
            print(f"REFUSE run={run_id}: cancellation failed closed: {exc}", file=sys.stderr)
            continue
        cancelled += 1
        print(f"CANCELLED run={run_id} forced={forced} reason={decision.reason}")

    print(f"Capture direct-PR Mac queue cancellations={cancelled}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
