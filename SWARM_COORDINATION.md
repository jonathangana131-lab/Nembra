# NEMBRA V14 SWARM COORDINATION

This file is a durable execution contract for concurrent Nembra workers. Live GitHub state still outranks stale prose.

## REQUIRED ADAPTIVE CONTROL

Read `ADAPTIVE_SWARM_PRIORITY.md` before choosing work.

**A pending external gate is a REASSIGN signal, not a reason for the swarm to wait.** When Xcode, signing, review, device access, physical access, or another worker is the next dependency, reserve only the minimum closure crew needed to react and immediately move all other workers to the highest-value safe Nembra product lanes.

Default scarce-gate reservation is **2-3 workers maximum** unless concrete live evidence proves more parallel capacity is actionable. A large swarm must never collapse into twenty chats polling one Xcode job.

While Capture is frozen/pending, overflow product gravity is Dashboard/Cockpit -> Battery/Range -> Rides/Records -> Navigation -> Home -> Vehicle/Controls, skipping any saturated/conflicted/evidence-blocked lane. Feature work must remain isolated from the frozen Capture candidate.

If a gate later fails, only enough workers to own the demonstrated failure return. If it passes, the closure crew advances signing/install/field handoff while the rest of Nembra keeps developing.

## Core rule

A large swarm must increase useful parallel closure, not create a queue of workers waiting on the same file, PR, CI run, or blocker.

When 20+ workers are active, they should discover separate safe lanes across the current critical feature **and other high-value product features whenever the critical feature is externally blocked or saturated**. They must not all choose the same blocker simply because it is the most obvious one.

## No-wait / self-reassignment rule

Before editing, every worker must fresh-check open PRs, newest branches, recent commits, CI/Xcode state, and active ownership.

If the highest-value lane is already actively owned, externally waiting, or would collide on the same high-contention paths:
1. do not wait;
2. do not duplicate the implementation;
3. do not repeatedly poll the same gate;
4. immediately choose the next highest-value non-conflicting lane;
5. if the current flagship is saturated or externally blocked, overflow to the next product priority from `ADAPTIVE_SWARM_PRIORITY.md`;
6. checkpoint durably and continue.

Waiting on another worker or runner is not productive work when another safe closure lane exists.

## One-check wait budget

A worker may inspect a queued/running/pending gate once to establish its exact state. After that, the worker must reassign unless it is the designated closure owner or there is new terminal evidence to act on.

`queued`, `pending`, `in_progress`, `waiting for runner`, `awaiting review`, and `awaiting physical access` are all reassignment states.

## Feature gravity, not PR gravity

Workers belong to product closure, not one PR. Finishing one PR, test, review, or merge is a checkpoint. After each checkpoint, refresh GitHub and continue to the next safe unfinished rung.

If a worker's original lane becomes blocked, superseded, merged, externally waiting, or owned by someone else, the worker hot-swaps to another useful lane rather than ending the session or polling.

## Useful parallel lanes

Workers may safely fan out across independent lanes such as:
- core/domain truth and lifecycle semantics;
- integration/composition;
- app-visible product wiring;
- Dashboard/Cockpit;
- Battery/Range;
- Rides/Records;
- Navigation;
- Home;
- Vehicle/Controls;
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
- 10-15 workers: one flagship plus a secondary when the first is saturated or externally waiting;
- 15-25+ workers: normally 2-3 major product areas at once, with only a small crew attached to any scarce external gate.

When a critical path is waiting on Xcode/signing/device/physical access, it is considered locally saturated for scheduling purposes.

## High-contention paths

App bootstrap/root composition, Xcode project files, shared registries, global persistence factories, major Dashboard/Home files, global project-memory docs, and other central integration paths should normally have one active owner at a time.

Other workers should work adjacent lanes and hand off exact accepted blobs/tests/findings rather than all editing the same central file.

## Integration closer

Each active flagship should have an integration-closer role whenever practical. That worker continuously:
- composes accepted independent lanes;
- refreshes the true current spine;
- detects stale/diverged branches;
- closes or marks superseded duplicates;
- runs exact-head gates at meaningful composition checkpoints;
- protects frozen candidates from optional churn;
- keeps product work moving from package foundation into the real app.

The integration closer is not a reason for other workers to wait. Other workers keep advancing independent lanes.

## CI behavior

CI running is not a stop condition. While waiting for a build/test result, do another non-conflicting task. If the current flagship has no safe local task because its exact candidate is frozen, move to the next adaptive product priority instead of inventing more validation around the same gate.

Do not repeatedly poll CI when useful work exists. Do not open duplicate mirrors merely to create activity.

## Capture TODAY freeze behavior

Until the first real stationary passive ES80 artifact exists, Capture remains P0 under `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`, but P0 does **not** monopolize the swarm when its next step is external.

When the Capture exact head is frozen and waiting on Xcode/signing/install/physical access:
- keep only the minimum Capture closure crew;
- do not mutate the frozen source for speculative hardening;
- move overflow workers to Dashboard/Cockpit, Battery/Range, Rides/Records, Navigation, Home, Vehicle/Controls, and cross-feature quality lanes;
- return workers to Capture only when new actionable evidence appears.

## GitHub durability — chat-only work is lost work

GitHub is the swarm's durable memory. Conversation text is not a valid handoff channel for material engineering state.

Before ending a worker run, every material result must exist durably on GitHub:
- code, fixes, tests, UI work, tooling, and documentation belong in a branch/commit/PR;
- review findings belong in the relevant PR review/comment or another durable GitHub checkpoint;
- blockers must name the exact SHA/path/state and next safe action on GitHub;
- visual/screenshot findings, accessibility failures, performance findings, test failures, rejected integrations, and exact-head acceptance results must be posted to GitHub;
- if a worker cannot safely implement a discovered defect, it must still leave the finding on GitHub for the owning/integration worker;
- PR bodies/checkpoints should be updated when they are the active durable handoff surface.

A result that exists only in a worker's chat is considered **LOST / NOT HANDED OFF** and does not count as completed swarm work.

Durable handoffs should include exact head SHA, relevant paths, observed failure/evidence, blocker classification, and next concrete safe action when known.

## Night-relay continuity

Scheduled/night workers exist primarily to keep Nembra moving after interactive workers stop, time out, die, or go idle.

Night workers are relays, not status reporters. Fresh-check GitHub, determine what is actually moving, recover or claim a safe lane, and continue real repository work.

If the Capture gate is pending and already has closure ownership, night workers must not pile onto it. They should use `ADAPTIVE_SWARM_PRIORITY.md` and advance the next safe product lane.

Every scheduled run must leave GitHub in a better, more recoverable state whenever meaningful safe work exists.

## Existing workers / hot-swap

Any worker that refreshes GitHub and sees this file must apply it immediately, even if its chat began before this document existed.

When a lane is occupied, self-reassign. When a branch is superseded, stop adding to it. When a gate is pending, stop polling it. When useful work has moved into a stronger current spine, follow the stronger spine.

Durable GitHub state must be sufficient for another worker to continue without chat history.

## GO meaning

For Nembra V14, `GO` means:
- read live GitHub first;
- read `ADAPTIVE_SWARM_PRIORITY.md`, this coordination contract, and the current continuation/master directives;
- determine the current critical path, ownership map, wait states, and safe overflow lanes;
- claim the highest-value non-conflicting **actionable** lane;
- execute real work immediately;
- persist every material result to GitHub, never chat-only;
- after every checkpoint, refresh and continue;
- never stop merely because one task, PR, test, merge, or CI run finished;
- never sit idle behind Xcode, signing, another worker, or physical access while another safe useful Nembra lane exists.

Optimize for total time-to-closed-product and product quality, not PR count, polling frequency, or visible activity.
