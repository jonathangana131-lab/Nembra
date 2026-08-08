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
- after every checkpoint, refresh and continue;
- never stop merely because one task, PR, test, merge, or CI run finished;
- never sit idle behind another worker when another safe useful lane exists.

Optimize for total time-to-closed-feature and product quality, not PR count or visible activity.
