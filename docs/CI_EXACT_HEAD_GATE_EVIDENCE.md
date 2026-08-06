# Xcode 27 exact-head PR gate live evidence

Date: 2026-08-06
Worker: `chat-f2k7q`

This document is the durable live-validation record for Nembra's exact-head Xcode 27 acceptance infrastructure.

## Purpose

The v5 swarm needs a way to obtain required exact-final-head Xcode 27 / iPhone 12 / iOS 27 Simulator proof even when connector-authored `parallel/**` branch updates do not emit the repository's older push workflow.

The evidence below distinguishes failed event-trigger experiments from the schedule-based fallback now present on default `main`.

## Live trigger evidence

### Connector-created `issue_comment`

PR #34 comment `5209537634` was created with:

- exact body `/xcode27`;
- author `jonathangana131-lab`;
- `author_association: OWNER`;
- `performed_via_github_app: chatgpt-codex-connector`.

The exact-head command workflow was active on the default branch before the comment was created. GitHub's workflow-run endpoint still returned `total_count: 0` for `xcode27-pr-command.yml`.

Result: **CONNECTOR-CREATED ISSUE COMMENT DID NOT EMIT AN ACTIONS RUN IN THIS RUNTIME.**

### Connector-created `pull_request.opened`

PR #42 was originally opened non-draft at head:

`7472f13eb14c47b47da288b3bafccdbc9009ec61`

Its base already contained PR #39's `pull_request` trigger support. After PR #42 was created through the connector, GitHub's workflow-run endpoint again returned `total_count: 0`.

Result: **CONNECTOR-CREATED PR OPEN DID NOT EMIT AN ACTIONS RUN IN THIS RUNTIME.**

Because two separate connector-originated event families produced no Actions run, event-driven triggers remain supplemental rather than the swarm's autonomous acceptance mechanism.

## Schedule fallback now on default main

Merged PR #49 added:

- `.github/workflows/xcode27-pr-scheduler.yml`;
- `docs/CI_EXACT_HEAD_SCHEDULER.md`.

GitHub registered `Xcode 27 Scheduled PR Exact-Head QA` active on the default branch.

Merged PR #58 then hardened candidate selection so the scheduler refuses any ready PR whose exact head is already behind current `main`. This prevents spending the self-hosted Xcode runner on a head that must be reconciled and re-gated anyway.

The scheduler's durable status context is:

`Nembra/Xcode27 Exact Head`

A selected head must be:

- same-repository;
- `parallel/**`;
- non-draft;
- targeting current default branch;
- `behind_by == 0` against current default branch;
- lacking a completed/non-stale pending exact-head status.

Priority metadata can reorder eligible work but cannot bypass those gates.

## This evidence PR's current preparation

After PR #58 merged, this branch was reconciled with fresh `main` through a normal two-parent merge while preserving this one evidence document.

The PR remains same-repository, `parallel/**`, non-draft, and carries:

`XCODE27_SCHEDULE_PRIORITY: true`

This document update is intentionally made **before** the live scheduler proof. Its resulting commit becomes the candidate whose status/run must be inspected. The PR must not be merged merely because the scheduler exists.

## Evidence state

`connector issue_comment`: **FAILED TO EMIT WORKFLOW EVENT**

`connector pull_request.opened`: **FAILED TO EMIT WORKFLOW EVENT**

`schedule workflow registered active on default`: **VERIFIED**

`scheduler fresh-main eligibility hardening`: **MERGED**

`scheduled resolver selected an exact current PR head`: **PENDING LIVE PROOF**

`pending commit status published`: **PENDING LIVE PROOF**

`immutable Xcode checkout expected SHA == actual SHA`: **PENDING LIVE PROOF**

`NembraCore + Xcode 27 / iPhone 12 Simulator gate`: **PENDING LIVE PROOF**

`artifact upload`: **PENDING LIVE PROOF**

`final exact-head commit status`: **PENDING LIVE PROOF**

No physical AOVOPRO ES80 behavior is tested or implied by this workflow evidence.

## What counts as live scheduler proof

A real scheduled run must be inspected for all of the following:

1. event is `schedule` (or a genuine human `workflow_dispatch`, if used independently);
2. resolver selects an eligible current same-repo `parallel/**` PR and records its immutable SHA;
3. pending status `Nembra/Xcode27 Exact Head` targets that same SHA/run;
4. the self-hosted Xcode job prints expected and actual checkout SHA and they are identical;
5. project validation and NembraCore tests execute;
6. Xcode 27/iPhone 12 Simulator build/test/capture executes;
7. artifacts/logs are inspectable;
8. final success/failure/error status targets the same exact SHA.

A failure is still useful live infrastructure evidence if it is diagnosed truthfully. It does not become a green product gate.

## Final-head rule for this evidence PR

If the first scheduled run succeeds on this document's new head, the run ID/result/artifact evidence must be written back into this file. That evidence update creates another SHA.

Therefore PR #42 itself requires **one more exact-head scheduled gate on that final evidence SHA** before it can merge. If `main` advances first, reconcile again and gate the new current SHA.

This intentionally demonstrates the same final-head rule other Nembra workers must follow rather than granting the CI-evidence lane an exception.

## Hardware truth boundary

This infrastructure can prove only the software commit exercised by Xcode/Simulator. It does not verify physical ES80 BLE/GATT/DP semantics, battery behavior, background reconnect, outdoor GPS, or physical iPhone 12 thermal/energy behavior.
