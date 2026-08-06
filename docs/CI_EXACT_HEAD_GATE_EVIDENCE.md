# Xcode 27 exact-head PR gate live evidence

Date: 2026-08-06
Worker: `chat-f2k7q`

This document is the durable live-validation record for the supplemental `Xcode 27 PR Exact-Head QA` workflow.

## Purpose

The v5 swarm needs a way to obtain required exact-final-head Xcode 27 / iPhone 12 / iOS 27 Simulator proof even when connector-authored `parallel/**` branch updates do not emit the repository's older push workflow.

PR #35 introduced a trusted exact-head resolver and Xcode gate. PR #39 added same-repository non-draft `pull_request` triggers because a connector-created `/xcode27` comment on PR #34 produced no `issue_comment` workflow run.

This evidence PR intentionally opened **non-draft** from fresh `main` so its own `pull_request.opened` event could test the new automatic acceptance path without editing another worker's branch.

## Live trigger evidence

### Connector-created `issue_comment`

PR #34 comment `5209537634` was created with:

- exact body `/xcode27`;
- author `jonathangana131-lab`;
- `author_association: OWNER`;
- `performed_via_github_app: chatgpt-codex-connector`.

The workflow was active on the default branch before the comment was created. GitHub's workflow-run endpoint still returned `total_count: 0` for `xcode27-pr-command.yml`.

Result: **CONNECTOR-CREATED ISSUE COMMENT DID NOT EMIT AN ACTIONS RUN IN THIS RUNTIME.**

### Connector-created `pull_request.opened`

PR #42 was opened non-draft at head:

`7472f13eb14c47b47da288b3bafccdbc9009ec61`

Its base was fresh `main@e50a6549b971540f5aaf5e30349b50405ba9faf0`, which already contained the PR #39 workflow definition listening to `pull_request` `opened`, `synchronize`, `reopened`, and `ready_for_review`.

After PR #42 was created through the connector, GitHub's workflow-run endpoint again returned:

`total_count: 0`

Result: **CONNECTOR-CREATED PR OPEN DID NOT EMIT AN ACTIONS RUN IN THIS RUNTIME.**

This means event-driven workflows may still be useful for normal human/GitHub UI activity, but they are not a sufficient autonomous control surface for this swarm when repository mutations are performed through the current connector.

## Evidence state

`connector issue_comment`: **FAILED TO EMIT WORKFLOW EVENT**

`connector pull_request.opened`: **FAILED TO EMIT WORKFLOW EVENT**

`connector synchronize/ready_for_review`: **NOT ACCEPTED AS A RELIABLE AUTONOMOUS PATH AFTER BOTH PRIOR EVENT FAMILIES FAILED**

`schedule-based exact-head selection`: **NEXT SAFE FALLBACK TO IMPLEMENT/PROVE**

Exact final-head Simulator QA for this evidence PR: **PENDING**

No physical AOVOPRO ES80 behavior is tested or implied by this workflow evidence.

## Why schedule is the next fallback

A default-branch `schedule` trigger does not depend on a connector-created comment, push, PR-open, or ready-state mutation causing a webhook-driven Actions run. A scheduled resolver can inspect open ready same-repository PR heads from GitHub itself, choose a head that lacks a durable exact-head result, and execute the same immutable checkout gate.

A safe scheduler must avoid repeated expensive runs by publishing a durable result tied to the exact commit SHA and refusing to run fork heads on the self-hosted Xcode runner.

## Next evidence checkpoint

Keep this PR draft while the scheduler infrastructure is built in a separate isolated lane. Once that fallback is merged and produces a real run, mark this evidence PR ready so the scheduler can select its then-current head. Record the actual run ID, exact resolved SHA, job/step result, and artifact/status evidence here. A new documentation commit changes the head and therefore requires a final exact-head run before this PR can merge.
