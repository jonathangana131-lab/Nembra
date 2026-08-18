# Nembra autonomous development contract

This file is the execution authority for Codex and other coding agents working in this repository. It replaces the old swarm scheduler/claim/lease/mission-graph workflow as an operating model. Older `SWARM_*`, `.swarm/`, large-swarm, continuation, worker-ID, claim, lease, fencing, admission, merge-train, and capacity-mining documents are historical/reference material unless this file explicitly points to them for product or safety facts.

## Goal

Continuously move Nembra toward a finished, shippable Nembra 1.0 with real code landing on `main`. Optimize for working product, correctness, usability, physical-truth safety, and release quality — not worker count, PR count, issue count, or coordination ceremony.

When the user says `Go`, `continue`, `keep going`, `work on Nembra`, or gives similarly broad authorization, begin real repository work immediately. Do not ask the user to pick a task when GitHub and the product docs can determine the next useful action.

## Source of truth

Use, in this order:

1. current `main` code and tests;
2. current open PRs, checks, reviews, and recent commits;
3. current product/safety docs and exact runtime evidence;
4. issues that still reproduce on current code.

Do not treat an old swarm graph, stale continuation packet, historical worker claim, or old PR description as stronger than current GitHub reality.

## Startup loop

At the start of a broad autonomous run:

1. Refresh `main`, open PRs, red CI, recent merges, and release-critical issues.
2. Prefer finishing a strong existing PR over creating a new competing implementation.
3. If no near-merge work should be finished first, choose the highest-value current blocker to a coherent product/release outcome.
4. Read the affected code before changing it.
5. Implement, run relevant tests, review the result, and get it merged when the evidence is sufficient.
6. Refresh GitHub and continue to the next useful outcome while the current execution window permits.

A commit, PR, review, test pass, or merge is a checkpoint, not an automatic stopping point.

## Coordination: GitHub, not a custom swarm database

There is no fixed worker quota and no requirement to fill capacity.

Default to one active implementation per overlapping subsystem. Use parallel agents only when the work is obviously independent. A practical ceiling is four concurrent writers in this repository; fewer is usually better. Review/test work may happen alongside implementation.

Before creating a branch or large change, inspect current open PRs and branches for overlap. If another live PR already owns substantially the same code/problem:

- improve/review/fix that path when possible; or
- choose a genuinely independent target.

Do not create successor/recovery branches merely because a task is hard, CI is pending, a chat ended, or another agent exists. One problem should converge toward one mergeable implementation.

Use ordinary short-lived Git branches and PRs as the collision and handoff mechanism. No worker IDs, mission-graph revisions, leases, heartbeats, fencing tokens, admission controller, synthetic role allocation, or stop-authority protocol is required.

## Branch / PR / merge behavior

- Keep branches short-lived and outcome-focused.
- Do not open empty or placeholder PRs.
- Rebase or update stale work instead of stacking recovery PRs on recovery PRs.
- Prefer a PR directly against `main` unless there is a concrete integration reason not to.
- Fix review findings on the existing branch when possible.
- Close superseded/duplicate PRs rather than preserving a PR tree as process history.
- When checks and required review/evidence are satisfied and repository permissions allow it, merge the accepted PR and verify `main` afterward.
- If the current environment cannot merge, leave one clearly merge-ready PR with exact remaining blockers instead of spawning more work around it.

## Quality gates by risk

Do not drag final-release ceremony into every small change.

For ordinary changes, run the relevant focused tests plus build/type/static checks that cover the touched code. For user-visible iOS work, build/run the real app or simulator when the environment supports it and inspect the changed behavior. For risky persistence, BLE, auth, concurrency, security, or architecture changes, add targeted regression coverage and validate the real boundary being changed.

Use the broad release matrix, long soaks, full visual census, physical-device qualification, and whole-product acceptance at milestone/release-candidate time or when the change specifically requires them.

Never weaken tests just to make a branch green.

## Nembra physical-truth boundary

Removing swarm bureaucracy does **not** weaken the scooter/physical safety boundary.

- Simulator values are not physical scooter truth.
- Do not invent BLE/Tuya protocol semantics, telemetry mappings, battery/speed/power/current/mode meanings, or command behavior.
- Historical device IDs, accounts, captures, or authority do not automatically authorize a current physical run.
- Do not send scooter commands unless the current product/safety docs and fresh physical evidence explicitly authorize that exact operation.
- A software/simulator pass cannot be promoted to physical-device proof.
- If progress truly requires unavailable phone/scooter/account evidence, record the exact physical blocker and continue on another independent software/product task instead of manufacturing pseudo-evidence.

## Issue discipline

Fix small adjacent defects while already in the area when safe. Do not mass-mine issues to keep agents busy.

Create a new issue when a real defect cannot responsibly be fixed in the current change, requires external evidence, or deserves independent scheduling. Keep it reproducible and concise. Issue count is not progress.

## Codex behavior

Codex should treat this root `AGENTS.md` as the default repository instruction. Use repository tools, terminal commands, Xcode tooling, tests, and Git normally. If a deeper `AGENTS.md` exists, its scoped instructions may refine this file for that subtree.

For a broad prompt such as `work on Nembra until you cannot make more useful progress`, choose work from live GitHub using the loop above, make real changes, test them, commit them, and continue rather than returning only a plan.

## Ordinary ChatGPT / GitHub-connector behavior

A ChatGPT coding session should follow the same loop with the connected GitHub repository. If it can safely edit, review, merge, or update existing work, it should do so. If its tooling cannot perform a required local/Xcode action, use GitHub-visible evidence and make another useful non-conflicting contribution instead of reverting to swarm bookkeeping.

## Release behavior

The target is a coherent Nembra release, not endless `main` churn. Keep current product docs honest about what is actually integrated. As the release approaches, shrink the open-PR set, close obsolete branches, run the full applicable acceptance surface, fix release blockers, and only then tag/publish the release according to repository release policy.

The operating principle is simple:

**inspect live truth -> finish the highest-value real outcome -> test it -> merge it -> refresh -> continue**
