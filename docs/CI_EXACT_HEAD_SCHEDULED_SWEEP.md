# Exact-head Xcode 27 scheduled sweep

Date: 2026-08-06

## Why this fallback exists

Nembra's v5 swarm needs exact-head Xcode 27 evidence before accepting worker pull requests. The repository already has direct push/manual QA and a PR exact-head workflow, but live connector testing exposed an event-delivery gap:

- connector-authored worker branch/content updates did not reliably emit the normal push-triggered workflow;
- owner `/xcode27` comments created through the connected GitHub App were persisted by GitHub but emitted no `issue_comment` Actions run;
- a same-repository validation PR transitioned from draft to ready-for-review through the same connected GitHub path and still produced no `Xcode 27 PR Exact-Head QA` run.

This is runtime evidence about the connected path, not a claim that GitHub UI or other authenticated clients cannot emit those events.

`Xcode 27 PR Scheduled Sweep` therefore uses GitHub's own `schedule` event as a polling fallback. GitHub documents five minutes as the shortest scheduled-workflow interval and runs scheduled workflows from the latest default-branch commit.

## Eligibility

The resolver runs only on a GitHub-hosted runner and never executes pull-request code. It considers a pull request only when all of these are true:

- the PR is open;
- the PR is not a draft;
- the PR head repository is exactly `jonathangana131-lab/Nembra`.

Fork heads never enter the self-hosted Xcode job.

## Exact-head behavior

For each eligible PR needing evidence, the resolver freezes the current immutable `head.sha`. The Xcode job then:

1. checks out that exact SHA;
2. compares `git rev-parse HEAD` with the frozen SHA and fails on mismatch;
3. validates the Xcode project and CI capture script;
4. runs the complete NembraCore package tests;
5. runs the existing Xcode 27 / iPhone 12 Simulator build-test-capture script;
6. uploads the same Simulator screenshots/logs used by the other Xcode gate.

The self-hosted job receives only `contents: read` permission.

## Dedupe and retry

The resolver writes a machine marker comment after claiming a head:

```text
<!-- nembra-xcode27-sweep:<40-char-head-sha>:<command-id> -->
```

A marker with command id `0` represents the normal ready/non-draft baseline request. This prevents every five-minute sweep from rerunning an unchanged head.

A trusted owner/member/collaborator can request another gate for the same unchanged head by adding a new exact comment:

```text
/xcode27
```

The sweep reads that comment even when its `issue_comment` event was not delivered to Actions. A newer trusted command id than the recorded marker is treated as an explicit retry and receives a new marker before it is queued.

When a ready PR's head SHA changes, the old marker cannot satisfy the new head, so the new exact head becomes eligible automatically.

## Direct-trigger coexistence

Before baseline-queueing an unchanged head, the sweep asks GitHub whether `xcode27-pr-command.yml` already has a run for that exact head. If the direct `pull_request` path worked for a GitHub UI or other client, the scheduled fallback does not intentionally duplicate that baseline gate.

Explicit `/xcode27` retry requests still win so a worker can rerun an unchanged head after a real CI failure or transient runner problem.

## Load control

A sweep selects at most three PR heads and runs the self-hosted matrix with `max-parallel: 1`. Explicit retries are prioritized, then older ready work. Per-PR concurrency cancels an older in-progress sweep job if a newer one for the same PR is legitimately queued.

This is deliberately conservative so a large swarm cannot create an unbounded Xcode-runner burst.

## Acceptance boundary

A scheduled run is valid evidence only for the frozen head printed by its verification step. Workers must still:

- inspect failures and artifacts;
- confirm the PR's current head is unchanged from the frozen successful head;
- reconcile fresh `main` and active overlap when required;
- merge with expected-head protection.

No CI result proves physical AOVOPRO ES80 behavior, outdoor GPS behavior, or physical iPhone performance.
