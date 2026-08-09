#!/usr/bin/env python3
"""Fail-closed cleanup for stale trusted Capture issue-comment Mac runs.

GitHub identifies an issue_comment workflow run with the default-branch SHA, not
the commented PR SHA. This helper therefore ignores run.head_sha as authority.
It accepts only the completed successful hosted resolver job's closed-form log:
`Resolved PR #<number> exact head <40-lowercase-hex>`. Anything ambiguous is
preserved. A run is cancellable only when current GitHub PR truth proves that
frozen resolver authority is no longer the open same-repo exact head.
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

API = "https://api.github.com"
WORKFLOW = "capture-xcode27-trusted-command.yml"
WORKFLOW_PATH = f".github/workflows/{WORKFLOW}"
RESOLVER_JOB = "Resolve trusted Capture PR head"
PATTERN = re.compile(rb"Resolved PR #([1-9][0-9]*) exact head ([0-9a-f]{40})(?![0-9a-f])")
STATUSES = ("queued", "in_progress")

@dataclass(frozen=True)
class Authority:
    pr: int
    sha: str


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Expose GitHub's signed log Location instead of forwarding bearer auth."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        return None


def age_seconds(run: dict[str, Any], now: dt.datetime) -> float | None:
    raw = run.get("created_at")
    if not isinstance(raw, str):
        return None
    try:
        created = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if created.tzinfo is None:
        created = created.replace(tzinfo=dt.timezone.utc)
    return (now - created.astimezone(dt.timezone.utc)).total_seconds()


def parse_authority(log: bytes) -> Authority | None:
    values = {
        Authority(int(pr), sha.decode("ascii"))
        for pr, sha in PATTERN.findall(log)
    }
    return next(iter(values)) if len(values) == 1 else None


def stale_reason(authority: Authority, pr: dict[str, Any], repository: str) -> str | None:
    if pr.get("number") != authority.pr:
        return None
    if pr.get("state") != "open":
        return "trusted Capture PR is no longer open"
    head = pr.get("head") or {}
    if (head.get("repo") or {}).get("full_name") != repository:
        return "trusted Capture PR is no longer same-repository"
    if head.get("sha") != authority.sha:
        return "trusted Capture resolver SHA is stale"
    return None


class GH:
    def __init__(self, token: str, repository: str) -> None:
        if "/" not in repository:
            raise ValueError("repository must be owner/name")
        self.token = token
        self.repository = repository
        self.owner, self.repo = repository.split("/", 1)

    def request(self, method: str, path: str) -> bytes:
        req = urllib.request.Request(
            API + path,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "nembra-capture-trusted-queue-janitor",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"{method} {path}: HTTP {exc.code}: {body}") from exc

    def json(self, method: str, path: str) -> Any:
        body = self.request(method, path)
        return None if not body else json.loads(body.decode("utf-8"))

    def job_log(self, job_id: int) -> bytes:
        path = f"/repos/{self.owner}/{self.repo}/actions/jobs/{job_id}/logs"
        req = urllib.request.Request(
            API + path,
            method="GET",
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "nembra-capture-trusted-queue-janitor",
            },
        )
        opener = urllib.request.build_opener(NoRedirect)
        try:
            with opener.open(req, timeout=30) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            if exc.code not in {301, 302, 303, 307, 308}:
                body = exc.read().decode("utf-8", errors="replace")
                raise RuntimeError(f"GET {path}: HTTP {exc.code}: {body}") from exc
            location = exc.headers.get("Location")
            if not location:
                raise RuntimeError(f"GET {path}: redirect missing Location") from exc
            parsed = urllib.parse.urlparse(location)
            if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
                raise RuntimeError(f"GET {path}: unsafe log redirect") from exc
            signed_req = urllib.request.Request(
                location,
                method="GET",
                headers={"User-Agent": "nembra-capture-trusted-queue-janitor"},
            )
            try:
                with urllib.request.urlopen(signed_req, timeout=30) as response:
                    return response.read()
            except urllib.error.HTTPError as signed_exc:
                body = signed_exc.read().decode("utf-8", errors="replace")
                raise RuntimeError(
                    f"GET signed job log: HTTP {signed_exc.code}: {body}"
                ) from signed_exc

    def runs(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        seen: set[int] = set()
        for status in STATUSES:
            for page in range(1, 21):
                query = urllib.parse.urlencode({"status": status, "per_page": 100, "page": page})
                payload = self.json("GET", f"/repos/{self.owner}/{self.repo}/actions/workflows/{WORKFLOW}/runs?{query}")
                batch = list((payload or {}).get("workflow_runs") or [])
                for run in batch:
                    run_id = int(run.get("id", -1))
                    if run_id not in seen:
                        seen.add(run_id)
                        result.append(run)
                if len(batch) < 100:
                    break
        return result

    def authority(self, run_id: int) -> Authority | None:
        payload = self.json("GET", f"/repos/{self.owner}/{self.repo}/actions/runs/{run_id}/jobs?per_page=100")
        jobs = [
            job for job in list((payload or {}).get("jobs") or [])
            if job.get("name") == RESOLVER_JOB
            and job.get("status") == "completed"
            and job.get("conclusion") == "success"
        ]
        if len(jobs) != 1:
            return None
        return parse_authority(self.job_log(int(jobs[0]["id"])))

    def pull(self, number: int) -> dict[str, Any]:
        value = self.json("GET", f"/repos/{self.owner}/{self.repo}/pulls/{number}")
        if not isinstance(value, dict):
            raise RuntimeError(f"PR #{number} returned no object")
        return value

    def cancel(self, run_id: int) -> None:
        self.json("POST", f"/repos/{self.owner}/{self.repo}/actions/runs/{run_id}/cancel")


def self_test() -> None:
    authority = Authority(833, "a" * 40)
    assert parse_authority(b"Resolved PR #833 exact head " + b"a" * 40 + b"\n") == authority
    assert parse_authority(b"core.info(`Resolved PR #${pr.number} exact head ${pr.head.sha}`)") is None
    assert parse_authority(
        b"Resolved PR #833 exact head " + b"a" * 40 + b"\nResolved PR #833 exact head " + b"b" * 40
    ) is None
    current = {"number": 833, "state": "open", "head": {"sha": "a" * 40, "repo": {"full_name": "owner/repo"}}}
    assert stale_reason(authority, current, "owner/repo") is None
    moved = json.loads(json.dumps(current)); moved["head"]["sha"] = "b" * 40
    assert stale_reason(authority, moved, "owner/repo") == "trusted Capture resolver SHA is stale"
    closed = json.loads(json.dumps(current)); closed["state"] = "closed"
    assert stale_reason(authority, closed, "owner/repo") == "trusted Capture PR is no longer open"
    print("capture_trusted_queue_janitor self-test: PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
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
    if not args.repository or not args.token:
        parser.error("repository/token required")
    if args.minimum_age_seconds < 0 or args.max_cancellations < 1:
        parser.error("invalid limits")

    gh = GH(args.token, args.repository)
    now = dt.datetime.now(dt.timezone.utc)
    stale: list[tuple[int, Authority, str]] = []
    preserved = 0
    for run in gh.runs():
        run_id = int(run.get("id", -1))
        if run.get("event") != "issue_comment" or run.get("path") != WORKFLOW_PATH:
            continue
        if (run.get("actor") or {}).get("login") != gh.owner:
            preserved += 1
            continue
        age = age_seconds(run, now)
        if age is None or age < args.minimum_age_seconds:
            preserved += 1
            continue
        try:
            authority = gh.authority(run_id)
            if authority is None:
                print(f"PRESERVE run={run_id}: resolver authority unavailable/ambiguous")
                preserved += 1
                continue
            reason = stale_reason(authority, gh.pull(authority.pr), gh.repository)
        except RuntimeError as exc:
            print(f"PRESERVE run={run_id}: evidence lookup failed: {exc}")
            preserved += 1
            continue
        if reason is None:
            print(f"PRESERVE run={run_id}: current PR #{authority.pr}@{authority.sha}")
            preserved += 1
        else:
            stale.append((run_id, authority, reason))

    print(f"trusted_candidates={len(stale)} preserved={preserved}")
    cancelled = 0
    for run_id, authority, reason in stale[:args.max_cancellations]:
        action = "CANCEL" if args.apply else "WOULD_CANCEL"
        print(f"{action} run={run_id} PR=#{authority.pr} sha={authority.sha} reason={reason}")
        if not args.apply:
            continue
        try:
            gh.cancel(run_id)
            cancelled += 1
        except RuntimeError as exc:
            print(f"CANCEL_RACE run={run_id}: {exc}", file=sys.stderr)
    if args.apply:
        print(f"cancelled={cancelled}")
    else:
        print("dry-run only")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
