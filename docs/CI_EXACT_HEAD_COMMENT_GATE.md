# Exact-head Xcode 27 PR command gate

Date: 2026-08-06

## Problem

Nembra's existing `Xcode 27 Simulator QA` workflow is push-driven for `main` and `feature/**`, with manual `workflow_dispatch` available in GitHub. During the v5 swarm, several connector-authored worker/recovery refs were updated successfully but did not emit the expected push-triggered Actions run. Those workers correctly refused to treat stale CI as proof for their changed final heads.

Changing every worker branch or asking each worker to own a shared workflow file would create contention. A separate explicit PR command gate provides a narrow recovery path without replacing the existing workflow.

## Usage

On a same-repository Nembra pull request, an owner/member/collaborator can add this exact PR conversation comment:

```text
/xcode27
```

The `Xcode 27 PR Exact-Head QA` workflow then:

1. resolves the PR through the GitHub API;
2. freezes the PR's current `head.sha`;
3. rejects a fork head before any PR code reaches the Xcode runner;
4. checks out that exact immutable SHA;
5. verifies `git rev-parse HEAD` equals the frozen SHA;
6. runs the same project-structure validation, NembraCore tests, Xcode 27/iPhone 12 Simulator capture script, and artifact upload used by the normal QA workflow.

A worker must still compare the workflow run's resolved/frozen head with the PR's current final head before accepting it. If the PR changes afterward, issue a new `/xcode27` command.

## Why a PR comment command

The command is deliberately event-driven rather than another automatic push workflow:

- it works even when connector-authored branch updates do not emit the repository's normal push workflow;
- it runs only when a worker needs a coherent exact-head acceptance gate;
- it avoids running the expensive Simulator job after every tiny checkpoint;
- it does not conflict with another lane that may add `parallel/**` to the normal push workflow;
- it lets draft recovery/dependent PRs request proof without inventing a fake green state.

## Security boundary

The workflow is designed for the repository's self-hosted `xcode-27` runner, so arbitrary fork code must not be checked out.

The command gate therefore requires:

- the comment to be exactly `/xcode27`;
- author association `OWNER`, `MEMBER`, or `COLLABORATOR`;
- a resolver job on a GitHub-hosted runner before the Xcode job;
- the PR head repository to equal the Nembra repository;
- read-only workflow permissions (`contents: read`, `pull-requests: read`);
- checkout by immutable resolved SHA rather than mutable branch name.

A collaborator intentionally requesting a gate for a fork PR still does not cause the fork head to execute on `xcode-27`; the same-repository check prevents the Simulator job from starting.

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
- PR #13 currently carries an independent `parallel/**` push-trigger change to that existing file; this lane does not edit or overwrite it.
- The comment gate is intentionally a separate workflow file so stale/recovery workers can obtain an exact-head run without waiting for that unrelated ride/location branch to merge.

If future CI infrastructure makes this command redundant, it can be retired deliberately after all affected worker lanes have another reliable exact-head dispatch path.
