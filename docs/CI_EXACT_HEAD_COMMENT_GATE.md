# Exact-head Xcode 27 PR gate

Date: 2026-08-06

## Problem

Nembra's existing `Xcode 27 Simulator QA` workflow is push-driven for `main` and `feature/**`, with manual `workflow_dispatch` available in GitHub. During the v5 swarm, several connector-authored worker/recovery refs were updated successfully but did not emit the expected push-triggered Actions run. Those workers correctly refused to treat stale CI as proof for their changed final heads.

PR #35 added a safe exact-head command workflow. Its first live test established an important runtime limitation: an owner-authored `/xcode27` PR comment created through the ChatGPT Codex GitHub App was recorded correctly by GitHub but emitted **no `issue_comment` Actions run**, even though the workflow was active on the default branch. The command path remains useful for comments created through surfaces that do emit the event, but it cannot be the swarm's only autonomous trigger.

The same workflow therefore also treats a ready same-repository pull request as an acceptance signal.

## Automatic acceptance usage

For same-repository PRs, `Xcode 27 PR Exact-Head QA` listens to these `pull_request` activity types:

- `opened`;
- `synchronize`;
- `reopened`;
- `ready_for_review`.

The resolver only accepts those events when the PR is **not draft** and its head repository is exactly `jonathangana131-lab/Nembra`.

The intended worker rhythm is:

1. open a draft PR early while implementation is still moving;
2. do focused/local/package verification and keep the V5 recovery capsule current;
3. when the exact head is genuinely acceptance-ready, mark the PR ready for review;
4. the ready event requests the Xcode 27 exact-head gate;
5. if code changes while the PR stays ready, `synchronize` automatically requests a new exact-head gate and cancels the older Simulator job for that same PR;
6. if work is no longer acceptance-ready, convert back to draft before further checkpoint commits to avoid expensive Simulator runs;
7. merge only when the required run corresponds to the final unchanged PR head.

A non-draft PR opened directly or reopened also gets a gate. Draft PR checkpoint churn does not.

## Optional PR comment command

On a same-repository Nembra pull request, an owner/member/collaborator may also add this exact PR conversation comment:

```text
/xcode27
```

When GitHub emits an `issue_comment` Actions event for that comment, the same resolver/gate runs.

Do **not** assume connector-created comments trigger it. On 2026-08-06, comment `5209537634` on PR #34 was created by the ChatGPT Codex Connector with `author_association: OWNER`; the workflow was active on `main`, but GitHub reported zero runs for the workflow afterward. That observation is connector/runtime evidence, not a claim that human-created GitHub UI comments can never trigger `issue_comment`.

## Exact-head behavior

For either supported trigger, the workflow:

1. resolves/freezes the PR's current `head.sha`;
2. records the PR number and verifies the head repository equals Nembra;
3. refuses a fork head before any PR code reaches the self-hosted Xcode runner;
4. checks out the exact immutable SHA;
5. prints the expected SHA and actual `git rev-parse HEAD`;
6. fails if those SHAs differ;
7. runs the same project-structure validation, NembraCore tests, Xcode 27/iPhone 12 Simulator capture script, and artifact upload used by the normal QA workflow.

A worker must still compare the run's frozen head with the PR's current final head before accepting it. A later commit invalidates older proof.

## Security boundary

The workflow is designed for the repository's self-hosted `xcode-27` runner, so arbitrary fork code must not be checked out.

The gate therefore requires:

- same-repository PR head before the Simulator job can start;
- read-only workflow permissions (`contents: read`, `pull-requests: read`);
- a GitHub-hosted resolver job that executes no PR code;
- checkout by immutable resolved SHA rather than mutable branch name;
- for comment requests, exact `/xcode27` body plus author association `OWNER`, `MEMBER`, or `COLLABORATOR`;
- for PR-event requests, a non-draft PR and a head repository equal to the base repository.

Fork PRs never reach `xcode-27` through this workflow.

## Concurrency

Concurrency is scoped to the Simulator job using the resolved PR number.

That means:

- a newer valid gate for the same PR supersedes its older in-progress Simulator job;
- unrelated issue/PR comments do not cancel a valid run;
- different PRs do not cancel each other.

## Truth / acceptance boundary

This workflow proves only the software state exercised by its scripts on the resolved commit.

It does not prove:

- physical AOVOPRO ES80 Bluetooth/GATT/DP behavior;
- real outdoor GPS behavior;
- physical iPhone 12 performance/thermal behavior unless a separate physical-device test explicitly supplies that evidence;
- a later PR head that differs from the resolved SHA.

Workers remain responsible for inspecting failures/artifacts, refreshing `main` and overlap, and using expected-head protection at merge.

## Relationship to existing workflows

This is supplemental infrastructure.

- `.github/workflows/xcode27-simulator.yml` remains the normal push/manual QA path.
- PR #13 carries an independent `parallel/**` push-trigger change to that existing file; this lane does not edit or overwrite it.
- Draft swarm work stays cheap; the PR gate is deliberately tied to acceptance-ready state rather than every parallel checkpoint.

## Evidence checked 2026-08-06

- GitHub documents `issue_comment` as a default-branch workflow event and `pull_request` activity types including `opened`, `synchronize`, `reopened`, and `ready_for_review`.
- GitHub documents a recursion exception for automated `pull_request` `opened`/`synchronize`/`reopened` events even when repository automation uses `GITHUB_TOKEN`; other event types do not receive that exception.
- GitHub security guidance warns against executing untrusted fork code on privileged/self-hosted workflows; this gate therefore fails closed before the Xcode job for non-Nembra heads.

If future CI infrastructure provides a reliable direct workflow-dispatch connector, this supplemental trigger can be simplified deliberately after affected worker lanes have another exact-head path.