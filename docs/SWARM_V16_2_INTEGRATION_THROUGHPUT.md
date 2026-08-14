# Nembra Swarm V16.2 — Integration Throughput

V16.2 keeps the V16 Mission Graph, V16.1 convergence rules, and V16.1 worker-persistence rules. It changes the scheduler's top priority from **producing more branches** to **getting accepted work into the canonical product**.

## Core invariant

When accepted or near-accepted work exists outside `MAIN`, the swarm must increase integration pressure until that work is either:

1. absorbed into the canonical branch and accepted;
2. explicitly rejected with a concrete blocker;
3. superseded after its useful evidence is preserved; or
4. genuinely externally blocked.

Green CI, review completion, or a good child PR are checkpoints, not reasons to start unrelated work.

## MERGE_PRESSURE

`MERGE_PRESSURE` activates when the graph contains integration work, queued Merge Train work, aged review work, multiple review/integration candidates, or canonical child work ready to absorb.

Under merge pressure:

- most burst capacity is routed to integration/review/test/conflict duties;
- integration work outranks capacity mining;
- role allocation shifts toward integrators;
- workers join the canonical branch instead of opening another successor;
- acceptance and physical truth gates remain unchanged.

One worker duty may require the exact work-item claim for writes. Other workers stay non-exclusive and red-team, test, inspect CI, or check conflicts against the same canonical candidate.

## Canonical absorption

Every objective has one canonical branch when possible. Accepted child work should be absorbed into that branch, not become a permanent branch family.

V16.2's graph-level absorption plan identifies review/integration work outside the canonical branch and points it back to the canonical branch. The control plane does not silently merge code; normal ownership and acceptance still apply.

## PR fanout limits

For newly created V16.2 swarm PRs:

- `SWARM_PROTOCOL: 16.2` is required;
- review, validation, integration, and tournament children require `SWARM_PARENT_PR`;
- child work attaches to the open canonical PR for its lane;
- at most **2 open child PRs per parent**;
- at most **1 open integration child per parent**;
- when the cap is reached, the next action is absorb/close/join, not another successor.

Open V16.1 work created before activation remains compatible so rollout does not strand useful work.

## Worker persistence remains active

Workers still receive `WORK`, `ASSIST`, or an explicit authorized `STOP`.

A lost claim, green CI, pending review, completed first task, full builder slots, or one empty scan is not permission to stop. Under V16.2, workers first help drain merge pressure before falling back to ordinary capacity mining.

## Safety boundary

Integration pressure changes scheduling only. It cannot weaken:

- exact-head evidence;
- independent review requirements;
- Apple signing/install custody;
- Tuya authentication truth;
- telemetry semantic authority;
- the read-only Capture boundary;
- physical ES80 GO rules;
- command authority requirements.

Simulator and source evidence remain non-physical. The scheduler cannot promote physical GO.

## Success metric

V16.2 should be judged by:

- accepted work reaching `MAIN` faster;
- fewer green PRs sitting unintegrated;
- fewer child/successor PRs per canonical objective;
- lower time from review-green to canonical composition;
- maintained worker persistence during 20–30 chat bursts;
- no increase in truth/safety regressions.
