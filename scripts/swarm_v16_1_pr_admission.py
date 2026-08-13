#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import swarm_control as sc


def _request_json(url: str, token: str):
    request = urllib.request.Request(
        url,
        headers={
            'Accept': 'application/vnd.github+json',
            'Authorization': f'Bearer {token}',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'nembra-swarm-v16.1-admission',
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode('utf-8'))


def list_open_prs(repo: str, token: str) -> list[dict]:
    results = []
    for page in range(1, 5):
        batch = _request_json(
            f'https://api.github.com/repos/{repo}/pulls?state=open&per_page=100&page={page}',
            token,
        )
        if not isinstance(batch, list):
            raise RuntimeError('GitHub open-PR response was not a list')
        results.extend(batch)
        if len(batch) < 100:
            break
    return results


def main() -> int:
    event_path = Path(os.environ.get('GITHUB_EVENT_PATH', ''))
    repo = os.environ.get('GITHUB_REPOSITORY', '')
    token = os.environ.get('GITHUB_TOKEN', '')
    if not event_path.is_file() or not repo or not token:
        raise SystemExit('GITHUB_EVENT_PATH, GITHUB_REPOSITORY and GITHUB_TOKEN are required')
    event = json.loads(event_path.read_text(encoding='utf-8'))
    pr = event.get('pull_request') or {}
    if not pr:
        raise SystemExit('pull_request event payload required')
    peers = list_open_prs(repo, token)
    decision = sc.evaluate_pr_admission(pr, peers)
    payload = {
        'policyVersion': sc.V16_1_POLICY_VERSION,
        'pr': pr.get('number'),
        'allowed': decision.allowed,
        'action': decision.action,
        'joinPR': decision.join_pr,
        'reason': decision.reason,
        'metadata': sc.parse_swarm_pr_metadata(pr),
        'openPRsInspected': len(peers),
    }
    text = json.dumps(payload, indent=2, sort_keys=True)
    print(text)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as handle:
            handle.write('## Swarm V16.1 PR admission\n\n')
            handle.write(f"**Verdict:** {'ALLOW' if decision.allowed else 'CONVERGE'}  \n")
            handle.write(f"**Action:** `{decision.action}`  \n")
            if decision.join_pr:
                handle.write(f"**Join PR:** `#{decision.join_pr}`  \n")
            handle.write(f"**Reason:** {decision.reason}\n")
    if not decision.allowed:
        print(f'::error title=Swarm V16.1 convergence::{decision.reason}')
        if decision.join_pr:
            print(f'::notice title=Join existing work::Continue on PR #{decision.join_pr}; do not create another successor PR.')
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
