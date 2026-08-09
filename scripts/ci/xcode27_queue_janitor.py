#!/usr/bin/env python3
"""Fail-closed cleanup for stale Xcode 27 PR QA runs.

The xcode-27 runner is scarce. This helper cancels only queued/in-progress runs whose
exact PR subject can be proven stale from GitHub-owned state.

Two workflow shapes are supported:
- `xcode27-pr-command.yml` pull_request runs expose branch/SHA directly in run metadata;
- `capture-xcode27-trusted-command.yml` issue_comment runs expose default-branch metadata,
  so their PR subject is recovered only from the completed trusted resolver job's log.

Missing/ambiguous resolver evidence, API failures, current exact open PR heads, unknown
events/workflows, and young runs inside the consistency grace period are preserved.
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
PR_WORKFLOW = "xcode27-pr-command.yml"
TRUSTED_WORKFLOW = "capture-xcode27-trusted-command.yml"
WORKFLOWS = (PR_WORKFLOW, TRUSTED_WORKFLOW)
CANCELLABLE_STATUSES = {"queued", "in_progress"}
TRUSTED_RESOLVER_JOB_NAME = "Resolve trusted Capture PR head"
TRUSTED_RESOLVER_PATTERN = re.compile(
    rb"Resolved PR #([1-9][0-9]*) exact head ([0-9a-f]{40})"
)


@dataclass(frozen=True)
class Decision:
    cancel: bool
    reason: str


@dataclass(frozen=True)
class TrustedRunSubject:
    pr_number: int
    head_sha: str


def _parse_github_time(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _age_decision(
    run: dict[str, Any], *, now: dt.datetime, minimum_age_seconds: int
) -> Decision | None:
    status = run.get("status")
    if status not in CANCELLABLE_STATUSES:
        return Decision(False, "status is not cancellable")
    created_at = run.get("created_at")
    if not created_at:
        return Decision(False, "missing creation time; preserve")
    try:
        age = (now - _parse_github_time(created_at)).total_seconds()
    except (TypeError, ValueError):
        return Decision(False, "invalid creation time; preserve")
    if age < minimum_age_seconds:
        return Decision(False, "inside API-consistency grace period")
    return None


def classify_run(
    run: dict[str, Any],
    open_prs: Iterable[dict[str, Any]],
    *,
    now: dt.datetime,
    minimum_age_seconds: int,
) -> Decision:
    """Classify a pull_request workflow run using direct branch/SHA metadata."""

    age = _age_decision(run, now=now, minimum_age_seconds=minimum_age_seconds)
    if age is not None:
        return age
    if run.get("event") != "pull_request":
        return Decision(False, "unsupported event for pull_request classifier; preserve")

    branch = run.get("head_branch")
    head_sha = run.get("head_sha")
    if not branch or not head_sha:
        return Decision(False, "missing branch/SHA; preserve")

    prs = list(open_prs)
    for pr in prs:
        head = pr.get("head") or {}
        if head.get("ref") == branch and head.get("sha") == head_sha:
            return Decision(False, "protected current exact head of an open PR")

    if not prs:
        return Decision(True, f"no open PR remains for {run.get('status')} branch")

    return Decision(
        True,
        f"{run.get('status')} SHA is not the current exact head of any open PR on branch",
    )


def parse_trusted_resolver_subject(log_bytes: bytes) -> TrustedRunSubject | None:
    """Recover one exact PR/SHA tuple from a trusted resolver log, or fail closed."""

    matches = {
        TrustedRunSubject(pr_number=int(pr_number), head_sha=head_sha.decode("ascii"))
        for pr_number, head_sha in TRUSTED_RESOLVER_PATTERN.findall(log_bytes)
    }
    if len(matches) != 1:
        return None
    return next(iter(matches))


def classify_trusted_run(
    run: dict[str, Any],
    subject: TrustedRunSubject | None,
    live_pr: dict[str, Any] | None,
    *,
    repository: str,
    now: dt.datetime,
    minimum_age_seconds: int,
) -> Decision:
    """Classify a trusted issue_comment run from resolver evidence + current PR truth."""

    age = _age_decision(run, now=now, minimum_age_seconds=minimum_age_seconds)
    if age is not None:
        return age
    if run.get("event") != "issue_comment":
        return Decision(False, "unsupported event for trusted classifier; preserve")
    if subject is None:
        return Decision(False, "trusted resolver subject unavailable/ambiguous; preserve")
    if live_pr is None:
        return Decision(False, "live PR truth unavailable; preserve")
    if int(live_pr.get("number", -1)) != subject.pr_number:
        return Decision(False, "live PR number mismatched resolver subject; preserve")

    state = live_pr.get("state")
    head = live_pr.get("head") or {}
    repo = head.get("repo") or {}
    live_sha = head.get("sha")
    same_repo = repo.get("full_name") == repository

    if state == "open" and same_repo and live_sha == subject.head_sha:
        return Decision(False, "protected trusted current exact head of an open PR")

    if state == "open" and live_sha and live_sha != subject.head_sha:
        return Decision(True, "trusted resolver SHA is no longer the live PR head")
    if state == "open" and not same_repo:
        return Decision(True, "trusted resolver PR no longer has same-repository source")
    if state == "closed":
        return Decision(True, "trusted resolver PR is closed")

    return Decision(False, "live PR state is incomplete/ambiguous; preserve")


class CrossOriginAuthorizationStrippingRedirectHandler(
    urllib.request.HTTPRedirectHandler
):
    """Never forward the GitHub bearer credential to a different origin."""

    @staticmethod
    def _origin(url: str) -> tuple[str, str, int | None]:
        parsed = urllib.parse.urlparse(url)
        return parsed.scheme.lower(), (parsed.hostname or "").lower(), parsed.port

    @staticmethod
    def _strip_header(request: urllib.request.Request, header_name: str) -> None:
        wanted = header_name.lower()
        for store in (request.headers, request.unredirected_hdrs):
            for key in list(store):
                if key.lower() == wanted:
                    del store[key]

    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: Any,
        code: int,
        msg: str,
        headers: Any,
        newurl: str,
    ) -> urllib.request.Request | None:
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected is None:
            return None
        if self._origin(req.full_url) != self._origin(newurl):
            self._strip_header(redirected, "Authorization")
        return redirected


class GitHubAPI:
    def __init__(self, token: str, repository: str) -> None:
        if "/" not in repository:
            raise ValueError("repository must be owner/name")
        self.token = token
        self.repository = repository
        self.owner, self.repo = repository.split("/", 1)
        self._opener = urllib.request.build_opener(
            CrossOriginAuthorizationStrippingRedirectHandler()
        )

    def _request(self, method: str, path: str) -> bytes:
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
            with self._opener.open(request, timeout=30) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"GitHub API {method} {path} failed: HTTP {exc.code}: {body}"
            ) from exc

    def request(self, method: str, path: str) -> Any:
        body = self._request(method, path)
        if not body:
            return None
        return json.loads(body.decode("utf-8"))

    def request_bytes(self, method: str, path: str) -> bytes:
        return self._request(method, path)

    def runs_with_status(self, workflow: str, status: str) -> list[dict[str, Any]]:
        if workflow not in WORKFLOWS:
            raise ValueError(f"unsupported workflow: {workflow}")
        if status not in CANCELLABLE_STATUSES:
            raise ValueError(f"unsupported cancellable status: {status}")
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
            for run in batch:
                run["_nembra_workflow"] = workflow
            runs.extend(batch)
            if len(batch) < 100:
                break
        return runs

    def candidate_runs(self) -> list[dict[str, Any]]:
        runs: list[dict[str, Any]] = []
        seen_ids: set[int] = set()
        for workflow in WORKFLOWS:
            for status in ("queued", "in_progress"):
                for run in self.runs_with_status(workflow, status):
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

    def pull_request(self, pr_number: int) -> dict[str, Any]:
        payload = self.request(
            "GET", f"/repos/{self.owner}/{self.repo}/pulls/{pr_number}"
        )
        if not isinstance(payload, dict):
            raise RuntimeError(f"PR #{pr_number} response was not an object")
        return payload

    def trusted_resolver_subject(self, run_id: int) -> TrustedRunSubject | None:
        jobs: list[dict[str, Any]] = []
        for page in range(1, 21):
            query = urllib.parse.urlencode({"per_page": 100, "page": page})
            payload = self.request(
                "GET",
                f"/repos/{self.owner}/{self.repo}/actions/runs/{run_id}/jobs?{query}",
            )
            batch = list((payload or {}).get("jobs") or [])
            jobs.extend(batch)
            if len(batch) < 100:
                break

        resolvers = [
            job
            for job in jobs
            if job.get("name") == TRUSTED_RESOLVER_JOB_NAME
            and job.get("status") == "completed"
            and job.get("conclusion") == "success"
        ]
        if len(resolvers) != 1:
            return None

        job_id = int(resolvers[0]["id"])
        logs = self.request_bytes(
            "GET", f"/repos/{self.owner}/{self.repo}/actions/jobs/{job_id}/logs"
        )
        return parse_trusted_resolver_subject(logs)

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
    assert not classify_run(
        run(event="issue_comment"), [], now=now, minimum_age_seconds=120
    ).cancel
    assert not classify_run(
        run(head_branch=None), [], now=now, minimum_age_seconds=120
    ).cancel
    assert not classify_run(
        run(status="completed"), [], now=now, minimum_age_seconds=120
    ).cancel

    redirect_handler = CrossOriginAuthorizationStrippingRedirectHandler()
    source_request = urllib.request.Request(
        "https://api.github.com/repos/owner/repo/actions/jobs/1/logs",
        headers={"Authorization": "Bearer secret"},
    )
    cross_origin = redirect_handler.redirect_request(
        source_request,
        None,
        302,
        "Found",
        {},
        "https://results-receiver.actions.githubusercontent.com/logs?sig=test",
    )
    assert cross_origin is not None
    assert cross_origin.get_header("Authorization") is None
    same_origin = redirect_handler.redirect_request(
        source_request,
        None,
        302,
        "Found",
        {},
        "https://api.github.com/repos/owner/repo/actions/jobs/1/logs-next",
    )
    assert same_origin is not None
    assert same_origin.get_header("Authorization") == "Bearer secret"

    exact_sha = "a" * 40
    moved_sha = "b" * 40
    trusted_log = f"prefix\nResolved PR #833 exact head {exact_sha}\nsuffix\n".encode()
    subject = parse_trusted_resolver_subject(trusted_log)
    assert subject == TrustedRunSubject(833, exact_sha)
    assert parse_trusted_resolver_subject(b"no resolver tuple") is None
    assert parse_trusted_resolver_subject(
        trusted_log + f"Resolved PR #833 exact head {moved_sha}\n".encode()
    ) is None
    # Duplicate copies of the same trusted tuple remain unambiguous.
    assert parse_trusted_resolver_subject(trusted_log + trusted_log) == subject

    trusted_run = run(event="issue_comment", head_branch="main", head_sha="main-sha")
    live_exact = {
        "number": 833,
        "state": "open",
        "head": {"sha": exact_sha, "repo": {"full_name": "owner/repo"}},
    }
    live_moved = {
        "number": 833,
        "state": "open",
        "head": {"sha": moved_sha, "repo": {"full_name": "owner/repo"}},
    }
    live_closed = {
        "number": 833,
        "state": "closed",
        "head": {"sha": exact_sha, "repo": {"full_name": "owner/repo"}},
    }
    live_fork = {
        "number": 833,
        "state": "open",
        "head": {"sha": exact_sha, "repo": {"full_name": "fork/repo"}},
    }

    assert classify_trusted_run(
        trusted_run,
        subject,
        live_exact,
        repository="owner/repo",
        now=now,
        minimum_age_seconds=120,
    ) == Decision(False, "protected trusted current exact head of an open PR")
    assert classify_trusted_run(
        trusted_run,
        subject,
        live_moved,
        repository="owner/repo",
        now=now,
        minimum_age_seconds=120,
    ).cancel
    assert classify_trusted_run(
        trusted_run,
        subject,
        live_closed,
        repository="owner/repo",
        now=now,
        minimum_age_seconds=120,
    ).cancel
    assert classify_trusted_run(
        trusted_run,
        subject,
        live_fork,
        repository="owner/repo",
        now=now,
        minimum_age_seconds=120,
    ).cancel
    assert not classify_trusted_run(
        trusted_run,
        None,
        live_exact,
        repository="owner/repo",
        now=now,
        minimum_age_seconds=120,
    ).cancel
    assert not classify_trusted_run(
        run(
            event="issue_comment",
            head_branch="main",
            head_sha="main-sha",
            created_at="2026-08-08T12:29:30Z",
        ),
        subject,
        live_moved,
        repository="owner/repo",
        now=now,
        minimum_age_seconds=120,
    ).cancel

    print("xcode27_queue_janitor self-test: PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--apply",
        action="store_true",
        help="cancel only proven-stale queued/in-progress Xcode runs",
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
    pr_cache: dict[int, dict[str, Any] | None] = {}
    candidates: list[tuple[dict[str, Any], Decision]] = []
    protected = 0
    ambiguous = 0

    for run in runs:
        workflow = run.get("_nembra_workflow")
        if workflow == PR_WORKFLOW:
            branch = run.get("head_branch")
            if not branch:
                decision = Decision(False, "missing branch/SHA; preserve")
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
        elif workflow == TRUSTED_WORKFLOW:
            run_id = int(run.get("id", -1))
            try:
                subject = api.trusted_resolver_subject(run_id)
            except (RuntimeError, ValueError) as exc:
                print(f"PRESERVE trusted run={run_id}: resolver evidence failed: {exc}")
                ambiguous += 1
                continue
            if subject is None:
                print(f"PRESERVE trusted run={run_id}: resolver subject unavailable/ambiguous")
                ambiguous += 1
                continue
            if subject.pr_number not in pr_cache:
                try:
                    pr_cache[subject.pr_number] = api.pull_request(subject.pr_number)
                except RuntimeError as exc:
                    print(
                        f"PRESERVE trusted run={run_id}: live PR #{subject.pr_number} lookup failed: {exc}"
                    )
                    pr_cache[subject.pr_number] = None
            decision = classify_trusted_run(
                run,
                subject,
                pr_cache[subject.pr_number],
                repository=args.repository,
                now=now,
                minimum_age_seconds=args.minimum_age_seconds,
            )
        else:
            decision = Decision(False, "unknown workflow; preserve")

        if decision.cancel:
            candidates.append((run, decision))
        elif "protected" in decision.reason:
            protected += 1
        elif "preserve" in decision.reason or "ambiguous" in decision.reason:
            ambiguous += 1

    queued = sum(run.get("status") == "queued" for run in runs)
    in_progress = sum(run.get("status") == "in_progress" for run in runs)
    trusted = sum(run.get("_nembra_workflow") == TRUSTED_WORKFLOW for run in runs)
    print(
        f"candidate_runs={len(runs)} queued={queued} in_progress={in_progress} "
        f"trusted_issue_comment_runs={trusted} stale_candidates={len(candidates)} "
        f"protected_exact_open_heads={protected} lookup_or_evidence_failures_preserved={ambiguous}"
    )

    cancelled = 0
    for run, decision in candidates[: args.max_cancellations]:
        run_id = int(run["id"])
        workflow = run.get("_nembra_workflow")
        status = run.get("status")
        prefix = "CANCEL" if args.apply else "WOULD_CANCEL"
        print(
            f"{prefix} run={run_id} workflow={workflow} status={status} "
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
        print(
            "dry-run only; pass --apply to cancel only proven-stale "
            "queued/in-progress Xcode runs"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
