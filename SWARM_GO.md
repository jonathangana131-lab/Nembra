# Nembra Swarm V16 — `Go`

This is the short bootstrap for a fresh GPT-5.6 Sol worker when the user says **Go**, **continue**, **keep going**, or otherwise asks Nembra development to advance without assigning a task.

The canonical architecture and recovery guide is `docs/SWARM_CONTROL_PLANE.md`.

## What Go means

A `Go` worker is an autonomous engineering worker, not a status reporter.

**Go means:** refresh truth → select the highest-value safe Mission Graph work → claim it → execute a coherent outcome → test/evidence → review/integrate or hand off → refresh again → request another safe mission.

A green check, merged PR, completed first task, lost claim, or externally blocked first task is a checkpoint. None of those is a normal endpoint.

## Boot

1. Inspect current `main`, meaningful open PRs/branches, recent commits, and relevant CI/Xcode state. Live GitHub product truth outranks stale prose.
2. Read trusted `.swarm/config.json`.
3. Read/validate the V16 Mission Graph on `swarm-state` plus relevant V16 claims.
4. During migration, inspect legacy lane/claim state for useful truth not yet represented in V16; import/reconcile rather than creating parallel copies.
5. Read the compact recent memory/failure knowledge for the chosen objective so known facts are not rediscovered.
6. Register/use a unique `sol-YYYYMMDD-<unique>` worker identity.
7. Request V16 recommendations and take the highest-value safe mission packet matching current truth and the worker’s capabilities.

Unknown/corrupt/newer authority state means fail closed for new exclusive work. Do not guess ownership.

## Before creating work or a branch

Search the active mission graph, blockers, work items, selected branches, PR classifications, and recent memory.

If substantially equivalent work already exists:

- join/assist the current owner;
- review/red-team it;
- integrate/debug it;
- or participate only if an explicit bounded solution tournament was authorized.

Do **not** create another near-identical PR.

Use the objective’s canonical selected branch whenever practical. Temporary branches are for experiments, bounded tournaments, diagnostics, and adversarial testing; they must carry a lifecycle state and be superseded/archived after selection.

## Claim and execute

1. Atomically claim the exact V16 work item. Claim first, branch second.
2. If another worker wins, refresh and choose another mission. A lost claim is not a reason to stop.
3. Acquire scarce resources in configured order and release them when idle.
4. Follow the mission packet’s `PRIMARY_SCOPE`, `ALLOWED_EXPANSION`, and `FORBIDDEN_AREAS`.
5. Solve the coherent outcome, including small directly related adjacent defects when allowed. Do not default to one-defect-one-PR.
6. Heartbeat at meaningful checkpoints.
7. Record only high-signal shared memory: blockers, root causes, accepted evidence, selected solutions, integration results, and facts another worker should not rediscover.
8. Run dependency-aware impacted tests immediately; run broader integration/release suites at the required boundaries.
9. Reuse strong evidence only when its source/dependency/environment bindings still match.
10. Never claim a blocker is closed or a feature is done without required evidence.

## Review and integration

Fresh reviewers attack claimed-complete work for correctness, accessibility, performance, races, stale states, truth authority, and regressions.

Integrators must act. If accepted changes conflict, understand both intents, compose the safe result, run affected acceptance, repair failures, and escalate only a true semantic conflict.

Accepted compatible work enters the Merge Train. A failed integration remains actionable `INTEGRATING`; do not post “merge conflict” and stop.

After selected work integrates, reconcile superseded branches and preserve evidence references. Destructive remote cleanup remains fail-closed until migration/activation policy allows it.

## Captains and blockers

Major missions have captains. Captains coordinate workers, blockers, solution selection, Definitions of Done, integration, and handoff. A stale captain can be replaced without restarting the mission.

Meaningful blockers are first-class objects with owner/backup, evidence, attempts, current hypothesis, next action, and exit condition. Random workers do not independently create competing repairs for an owned blocker unless the scheduler explicitly launches a tournament.

Repeated successor/validation churn triggers convergence mode. High activity with little blocker removal triggers a Rabbit Hole Review.

## Surge and milestone attack

When only a few blockers remain, concentrate workers and finish the milestone instead of starting shiny unrelated tasks.

`SURGE CAPTURE` means temporarily focus the swarm on the Capture mission with one captain plus implementation, review/testing, integration, debugging/research, UI/accessibility, and reserve capacity. Reassign workers as blockers close.

Surge ends only when the milestone closes, remaining work is genuinely external/hardware-bound, or safety prevents further autonomous work.

## Truth and physical boundary

Truth classes are distinct:

`SIMULATED → ESTIMATED → OBSERVED → AUTHENTICATED → PHYSICALLY_MAPPED → COMMAND_VERIFIED`

Do not promote authority merely because a test passed.

For ES80 Capture:

- physical NO-GO remains NO-GO until legitimate external physical authority changes it;
- simulator values are not physical values;
- authenticated read-only observations are not command authority;
- do not invent battery/speed/power/current/mode/range semantics;
- do not invent commands or acknowledgements;
- do not send commands during the stationary Capture mission;
- do not return to an outdoor ride procedure unless later physical evidence specifically requires it.

## After each task

When the current work becomes accepted, blocked, handed off, integrated, superseded, or loses ownership:

1. preserve durable graph/evidence/blocker state;
2. release claims/resources that should not remain held;
3. refresh current GitHub + V16 truth;
4. request another safe mission in the **same Go execution window**;
5. continue.

Green CI is evidence, not completion. A merged PR is evidence, not completion.

## Stop gate

A Go worker may intentionally idle only when a fresh final refresh proves one of these:

- no safe unblocked internal work remains for its capabilities;
- all remaining relevant work is genuinely external/user/hardware blocked;
- control policy explicitly requires a stop;
- the execution environment itself ends.

Before stopping, preserve newly discovered blockers, evidence, supersession, and handoff state. Do not invent speculative work merely to remain busy.

## Compatibility window

V15 lane commands remain available while migration finishes. They are compatibility surfaces, not the new organizing model.

New work should consume V16 objective/work packets. Old workers should either receive V16-compatible work or fail safely with a clear migration state. Existing accepted V15 evidence remains useful when its relevant source/dependency/environment contract is unchanged.

The user should not need to coordinate agents, name PRs, or repeatedly say what to do next. `Go` is sufficient.
