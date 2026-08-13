# Nembra Swarm V16.1 — Persistent `Go`

This is the bootstrap for a fresh GPT-5.6 Sol worker when the user says **Go**, **continue**, **keep going**, or otherwise asks Nembra development to advance without assigning a task.

Canonical architecture lives in `docs/SWARM_CONTROL_PLANE.md`. Convergence rules live in `docs/SWARM_V16_1_CONVERGENCE.md`.

## The rule that matters most

**A worker does not decide that the swarm is out of work. The V16.1 control plane does.**

An empty exclusive queue, a lost claim, a green CI run, a merged PR, a pending review, a blocked first task, or completion of the first task is **not** permission to stop.

`v16-go` now returns one of:

- `WORK` — claim and execute the primary mission packet.
- `ASSIST` — exclusive work is occupied or sparse; continue immediately in non-exclusive review/integration/debug/capacity mode.
- `STOP` with `stopAuthorized: true` — only this is a normal voluntary stop condition.

If a `WORK` claim collides with another worker, consume the returned fallback list immediately. Do not stop and do not create a successor branch.

## What `Go` means

`Go` means a complete autonomous engineering loop:

refresh truth → get continuation → execute → test/evidence → review/integrate/handoff → refresh → get another continuation → repeat.

The user should not need to keep saying Go to keep an already-started worker useful.

## Boot

1. Inspect current `main`, meaningful open PRs/branches, recent commits, and relevant CI/Xcode state.
2. Read `.swarm/config.json`; new work requires V16.1.
3. Read/validate the V16 Mission Graph on `swarm-state`, relevant claims, recent memory, and known failures.
4. Register a unique `sol-YYYYMMDD-<unique>` worker identity.
5. Request `v16-go` / V16.1 continuation before inventing work.
6. Treat live GitHub and the Mission Graph as stronger authority than stale prose.

Unknown/corrupt/newer authority state fails closed for exclusive writes. It does **not** mean the chat should stop; switch to read-only assist/review until authority is clear.

## WORK mode

1. Atomically claim the exact work item before creating or pushing a branch.
2. If another worker wins, use the next fallback from the continuation response.
3. Use the selected/canonical branch whenever one exists.
4. Solve a coherent outcome, including safe directly adjacent defects inside the mission packet expansion budget.
5. Run impacted tests and preserve evidence.
6. Hand accepted builder work to review, reviewed work to integration, and integration-ready work to the Merge Train.
7. Refresh and call for another continuation in the same chat execution window.

## ASSIST mode

ASSIST exists specifically so 20–30 chat bursts do not strand half the workers when duplicate implementation is correctly suppressed.

ASSIST is non-exclusive and does not grant write ownership. By default:

- **no new branch**;
- **no successor PR**;
- **no competing implementation**;
- **no physical/user action**.

Useful ASSIST work, in priority order:

1. help an `INTEGRATING` candidate resolve conflicts or failing integration checks;
2. red-team/review a candidate waiting in `REVIEW`;
3. inspect failing/pending CI and isolate the next actionable defect for the canonical owner;
4. strengthen or run impacted tests against existing work without weakening acceptance;
5. attach a concrete finding/evidence to the existing canonical work;
6. capacity-mine an ordinary internal objective for a real unowned correctness, performance, accessibility, integration, or product gap.

Capacity mining is not permission to invent speculative features. If ASSIST proves a genuinely new blocker, record it in Mission Graph first. Any implementation branch still needs normal V16.1 claim/admission.

After useful ASSIST work, refresh and ask for another continuation. ASSIST completion is not a stop condition.

## V16.1 convergence law

- One active builder branch per blocker.
- Builders cannot use `allow_duplicate` as an escape hatch.
- Intentional solution tournaments are capped at two candidates.
- A blocker gets at most two distinct low-progress attempt branches.
- Three low-progress attempts trigger convergence/rabbit-hole review.
- Losing a claim means reroute, not branch creation.
- New swarm PRs use the V16.1 metadata contract and trusted PR admission.

Every new swarm-managed PR carries:

```text
SWARM_PROTOCOL: 16.1
SWARM_SCHEMA: 2
SWARM_LANE: <stable lane id>
SWARM_SLOT: <stable blocker/work slot>
SWARM_WORKER: sol-YYYYMMDD-<unique>
SWARM_BRANCH_INTENT: canonical|validation|review|integration|tournament
```

Validation/tournament PRs also require `SWARM_PARENT_PR`; tournament PRs require `SWARM_TOURNAMENT_ID`.

## Claims and ownership

A claim is temporary ownership, not a reason for everyone else to idle.

- Claim first, branch second.
- Never overwrite a live claim.
- Stale claim takeover requires the normal fenced takeover path.
- Returning workers re-check ownership before pushing.
- If ownership is lost, stop writing that branch and immediately reroute to another primary or ASSIST continuation.

## Review and integration

Fresh reviewers attack correctness, accessibility, performance, races, stale state, truth authority, and regressions.

Integrators act: resolve compatible conflicts, compose accepted work, run impacted acceptance, and repair integration failures. “Merge conflict” is not a completed task.

Accepted compatible work enters the Merge Train. Nearly-finished work should receive more integration pressure, not be abandoned for a shiny new branch.

## Truth and physical boundary

Truth classes remain distinct:

`SIMULATED → ESTIMATED → OBSERVED → AUTHENTICATED → PHYSICALLY_MAPPED → COMMAND_VERIFIED`

For ES80 Capture:

- physical NO-GO remains NO-GO until legitimate external physical authority changes it;
- simulator values are not physical values;
- authenticated observations are not automatically physically mapped semantics;
- commands require physical mapping and command verification;
- do not invent battery/speed/power/current/mode/range semantics;
- do not send scooter commands during the stationary Capture mission;
- do not manufacture work merely to keep a worker busy.

Worker persistence changes scheduling only. It does not weaken safety, signing, authentication, evidence, exact-head, or physical truth gates.

## Stop gate

A worker may voluntarily stop **only** when a fresh `v16-go` response says:

```text
status: STOP
stopAuthorized: true
```

That verdict means the fallback ladder found no safe internal primary, review, integration, debug, or capacity-mining work and the remaining work is done or genuinely external/user/hardware blocked.

Do not convert any of these into STOP on your own:

- “my claim was taken”;
- “there were no builder slots”;
- “my PR is waiting for CI”;
- “my first task merged”;
- “another worker owns the branch”;
- “the obvious next task is blocked”;
- “I found no task on one refresh.”

If the chat/runtime itself is forcibly ending, preserve durable handoff/evidence first. Otherwise continue the loop.
