# Xcode 27 exact-head PR gate live evidence

Date: 2026-08-06
Worker: `chat-f2k7q`

This document is the durable live-validation record for Nembra's exact-head Xcode 27 acceptance infrastructure.

## Purpose

The v5 swarm needs a way to obtain required exact-final-head Xcode 27 / iPhone 12 / iOS 27 Simulator proof even when connector-authored `parallel/**` branch updates do not emit the repository's older push workflow.

The evidence below distinguishes failed event-trigger experiments, the schedule-based fallback now present on default `main`, an exact-SHA `feature/**` proxy experiment, and the external GitHub Actions incident active during these tests.

## Live trigger evidence

### Connector-created `issue_comment`

PR #34 comment `5209537634` was created with exact body `/xcode27`, repository-owner authorship, `author_association: OWNER`, and `performed_via_github_app: chatgpt-codex-connector`.

The exact-head command workflow was active on the default branch before the comment was created. GitHub's workflow-run endpoint still returned `total_count: 0` for `xcode27-pr-command.yml`.

Result: **CONNECTOR-CREATED ISSUE COMMENT DID NOT EMIT AN ACTIONS RUN IN THIS RUNTIME.**

### Connector-created `pull_request.opened`

PR #42 was originally opened non-draft at head `7472f13eb14c47b47da288b3bafccdbc9009ec61` after PR #39's pull-request trigger support was already on default main. GitHub again returned zero runs.

Result: **CONNECTOR-CREATED PR OPEN DID NOT EMIT AN ACTIONS RUN IN THIS RUNTIME.**

### Exact-SHA watched `feature/**` proxy

The established `.github/workflows/xcode27-simulator.yml` watches `main` and `feature/**`.

A CI-only ref `feature/xcode27-exact-pr42-chat-f2k7q` was created at current main, fast-forwarded without force to PR #42, then given a real evidence-document commit `4468a41f27e91d69c881167b9966de88d25bde29`. PR #42's own `parallel/**` ref was fast-forwarded to that exact same commit.

The normal watched workflow still reported zero runs for the proxy branch at the verification check.

Result: **CONNECTOR-CREATED WATCHED FEATURE PUSH DID NOT EMIT AN ACTIONS RUN AT THE OBSERVED CHECKPOINT.**

This experiment did not add a fake product commit: the changed file was this real CI-evidence record, and both refs shared the exact commit SHA.

## External GitHub Actions incident

During these experiments GitHub's official status page reported **Actions: Major Outage**.

The 2026-08-06 22:18 UTC GitHub status update said:

- a fix was deployed for runners being assigned invalid jobs;
- success rates for workflow runs that were starting had improved to 97%;
- standard/larger runners were draining queued work;
- mitigation for existing self-hosted runners not picking up jobs was still in progress;
- webhook triggers remained throttled and many push/pull-request events were not creating new workflow runs.

Earlier incident updates said only about 15% of webhooks were being processed during part of the outage and both GitHub-hosted and self-hosted runners were affected.

This official incident directly explains why missing connector-triggered runs cannot be treated as evidence that the workflow definitions are invalid. It also means delayed/absent scheduled runs during the incident are not proof that repository scheduling is disabled.

A separate ordinary `Xcode 27 Simulator QA` run was observed in progress on the repository's self-hosted path during the incident, with project validation and NembraCore validation already successful and Simulator capture running. Therefore the runner path was degraded/intermittent, not known permanently dead.

## Schedule fallback on default main

Merged PR #49 added `.github/workflows/xcode27-pr-scheduler.yml` plus its operating contract. GitHub registered `Xcode 27 Scheduled PR Exact-Head QA` active on the default branch.

Merged PR #58 hardened candidate selection so the scheduler refuses any ready PR whose exact head is already behind current main.

The scheduler's durable status context is `Nembra/Xcode27 Exact Head`.

A selected head must be:

- same-repository;
- `parallel/**`;
- non-draft;
- targeting current default branch;
- `behind_by == 0` against current default branch;
- lacking a completed/non-stale pending exact-head status.

Priority metadata can reorder eligible work but cannot bypass those gates.

As of this commit, the workflow is registered active but the repository has not yet recorded its first schedule run. That remains pending live proof while the GitHub Actions incident is active.

## Current queue state

PR #40 (`recover-adaptive-range-core`) and PR #42 are both current-main, non-draft, same-repo priority candidates.

Because this evidence lane was updated after #40's recovery was reconciled, the scheduler's priority/oldest-update ordering should prefer #40 first. That is useful product behavior because #40 unblocks adaptive-range dependents.

PR #42 remains the CI evidence/canary lane after higher-value eligible priority work.

## Evidence state

`connector issue_comment`: **FAILED TO EMIT WORKFLOW EVENT**

`connector pull_request.opened`: **FAILED TO EMIT WORKFLOW EVENT**

`connector feature/** push`: **FAILED TO EMIT WORKFLOW EVENT AT OBSERVED CHECKPOINT**

`GitHub Actions major outage / webhook throttling`: **VERIFIED EXTERNAL INCIDENT**

`schedule workflow registered active on default`: **VERIFIED**

`scheduler fresh-main eligibility hardening`: **MERGED**

`repository has emitted a schedule run`: **PENDING LIVE PROOF**

`scheduled exact-head Xcode result`: **PENDING LIVE PROOF**

`artifact + exact-head terminal status`: **PENDING LIVE PROOF**

No physical AOVOPRO ES80 behavior is tested or implied by this workflow evidence.

## What counts as exact-head proof

A real acceptance run must be inspected for all of the following:

1. run `head_sha` / resolved SHA exactly equals the candidate PR head;
2. project validation and NembraCore tests execute;
3. Xcode 27/iPhone 12 Simulator build/test/capture executes;
4. artifacts/logs are inspectable;
5. the PR head remains unchanged after successful QA.

For the scheduled workflow specifically, additionally require resolver selection, exact pending/final commit status, and immutable checkout equality.

A failure or outage-delayed run is useful evidence only when diagnosed truthfully. It does not become a green product gate.

## Final-head rule for this evidence PR

If a run succeeds on this evidence state, the run ID/result/artifact details still need to be written back into this file, creating another SHA. PR #42 therefore requires another exact-head gate on that final evidence SHA before merge. If main advances first, reconcile again and gate the new current SHA.

## Hardware truth boundary

This infrastructure can prove only the software commit exercised by Xcode/Simulator. It does not verify physical ES80 BLE/GATT/DP semantics, battery behavior, background reconnect, outdoor GPS, or physical iPhone 12 thermal/energy behavior.
