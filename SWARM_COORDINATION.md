# NEMBRA V14 SWARM COORDINATION

This file is a durable execution contract for concurrent Nembra workers. Live GitHub state still outranks stale prose.

## Core rule

A large swarm must increase useful parallel closure, not create a queue of workers waiting on the same file, PR, CI run, or blocker.

When 20+ workers are active, they should discover separate safe lanes inside the current flagship feature and work them concurrently. They must not all choose the same blocker simply because it is the most obvious one.

## No-wait / self-reassignment rule

Before editing, every worker must fresh-check open PRs, newest branches, recent commits, and active ownership.

If the highest-value lane is already actively owned or would collide on the same high-contention paths:
1. do not wait for that worker;
2. do not duplicate the implementation;
3. immediately choose the next highest-value non-conflicting lane inside the same flagship feature;
4. if the flagship is locally saturated, move to the next closure rung that can be safely parallelized;
5. only leave the flagship when additional workers would create more coordination cost than useful progress.

Waiting on another worker is not productive work when another safe closure lane exists.

## Feature gravity, not PR gravity

Workers belong to the flagship feature, not to one PR. Finishing one PR, test, review, or merge is a checkpoint. After each checkpoint, refresh GitHub and continue to the next safe unfinished rung in the same feature.

If a worker's original lane becomes blocked, superseded, merged, or owned by someone else, the worker should hot-swap to another useful lane rather than ending the session or polling.

## Useful parallel lanes

Within one flagship feature, workers may safely fan out across independent lanes such as:
- core/domain truth and lifecycle semantics;
- integration/composition;
- app-visible product wiring;
- visual/UI polish and screenshot critique;
- accessibility;
- performance/frame pacing;
- adversarial QA and regression tests;
- persistence/export/provenance;
- build/CI acceptance infrastructure;
- documentation/runbook truth;
- integration cleanup and superseded-branch pruning.

These are examples, not quotas. Workers must inspect actual current ownership before choosing a lane.

## Saturation rule

Do not hardcode a worker count. Count safe useful lanes, not agents.

Rough behavior:
- 1-4 workers: one flagship feature;
- 5-10 workers: one flagship heavily parallelized;
- 10-15 workers: one flagship plus a secondary only if the first is genuinely saturated;
- 15-25+ workers: usually no more than 2-3 major flagship areas at once.

Overflow moves only when adding another worker to the current flagship would create more collision/coordination cost than useful progress.

## High-contention paths

App bootstrap/root composition, Xcode project files, shared registries, global persistence factories, major Dashboard/Home files, global project-memory docs, and other central integration paths should normally have one active owner at a time.

Other workers should work adjacent lanes and hand off exact accepted blobs/tests/findings rather than all editing the same central file.

## Integration closer

The flagship should have an integration-closer role whenever practical. That worker continuously:
- composes accepted independent lanes;
- refreshes the true current spine;
- detects stale/diverged branches;
- closes or marks superseded duplicates;
- runs exact-head gates at meaningful composition checkpoints;
- keeps product work moving from package foundation into the real app.

The integration closer is not a reason for other workers to wait. Other workers keep advancing independent lanes.

## CI behavior

CI running is not a stop condition. While waiting for a build/test result, do another non-conflicting task in the same flagship: source review, adversarial testing, visual critique, accessibility, performance work, documentation truth, integration prep, or cleanup.

Do not repeatedly poll CI when useful work exists.

## GitHub durability — chat-only work is lost work

GitHub is the swarm's durable memory. Conversation text is not a valid handoff channel for material engineering state.

Before ending a worker run, every material result must exist durably on GitHub:
- code, fixes, tests, UI work, tooling, and documentation belong in a branch/commit/PR;
- review findings belong in the relevant PR review/comment or another durable GitHub checkpoint;
- blockers must name the exact SHA/path/state and next safe action on GitHub;
- visual/screenshot findings, accessibility failures, performance findings, test failures, rejected integrations, and exact-head acceptance results must be posted to GitHub;
- if a worker cannot safely implement a discovered defect, it must still leave the finding on GitHub for the owning/integration worker;
- PR bodies/checkpoints should be updated when they are the active durable handoff surface.

A result that exists only in a worker's chat is considered **LOST / NOT HANDED OFF** and does not count as completed swarm work. Never assume another worker will see conversation-only reviewer output.

Review-only workers are especially required to publish findings. A reviewer that says "I found X" only in chat has not completed the review handoff.

Durable handoffs should include enough specificity for hot-swap continuation: exact head SHA, relevant paths, observed failure or evidence, whether the finding is blocking, and the next concrete safe action when known.

## Night-relay continuity

Scheduled/night workers exist primarily to keep Nembra moving after interactive workers stop, time out, die, or go idle.

A night worker must not assume an old active branch means its worker is still alive. Fresh-check GitHub, determine what is actually moving, recover or claim a safe lane, and continue real repository work.

Night workers are relays, not status reporters. If an interactive lane appears abandoned, recover it safely from its durable exact head on a new branch when appropriate. If it is still active, self-reassign to another useful lane.

Every scheduled run must leave GitHub in a better, more recoverable state than it found it whenever meaningful safe work exists. Its final chat message is optional narration; GitHub is the required durable output.

## Existing workers / hot-swap

Any worker that refreshes GitHub and sees this file should apply it immediately, even if its chat began before this document existed.

When a lane is already occupied, self-reassign. When a branch is superseded, stop adding to it. When useful work has moved into a stronger current spine, follow the stronger spine.

Durable GitHub state must be sufficient for another worker to continue without chat history.

## GO meaning

For Nembra V14, `GO` means:
- read live GitHub first;
- read this swarm coordination contract and the current continuation/master directives;
- determine the current flagship and safe ownership map;
- claim the highest-value non-conflicting lane;
- execute real work immediately;
- persist every material result to GitHub, never chat-only;
- after every checkpoint, refresh and continue;
- never stop merely because one task, PR, test, merge, or CI run finished;
- never sit idle behind another worker when another safe useful lane exists.

Optimize for total time-to-closed-feature and product quality, not PR count or visible activity.
