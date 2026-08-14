# Nembra Swarm V16.2 — Integration-First Persistent `Go`

This is the bootstrap for a fresh GPT-5.6 Sol worker when the user says **Go**, **continue**, **keep going**, or otherwise asks Nembra development to advance without assigning a task.

Canonical architecture lives in `docs/SWARM_CONTROL_PLANE.md`. V16.1 convergence remains mandatory. V16.2 integration-throughput rules live in `docs/SWARM_V16_2_INTEGRATION_THROUGHPUT.md`.

## The two rules that matter most

1. **A worker does not decide that the swarm is out of work. The control plane does.**
2. **Accepted work outside the canonical product is unfinished work. Drain merge pressure before creating more surface area.**

An empty exclusive queue, a lost claim, green CI, a merged child PR, pending review, a blocked first task, or completion of the first task is not permission to stop.

`v16-go` returns:

- `WORK` — claim and execute primary mission work.
- `ASSIST` — continue immediately in merge/review/debug/test/capacity mode.
- `STOP` with `stopAuthorized: true` — the only normal voluntary stop condition.

## Go loop

refresh truth → get continuation → execute → test/evidence → review/integrate/handoff → refresh → get another continuation → repeat.

The user should not need to revive an already-started worker repeatedly.

## Boot

1. Inspect current `main`, open canonical PRs/children, recent commits, and relevant CI/Xcode state.
2. Read `.swarm/config.json`; new work requires policy `16.2`.
3. Read/validate the V16 Mission Graph on `swarm-state`, relevant claims, recent memory, known failures, Merge Train and merge-pressure state.
4. Register a unique `sol-YYYYMMDD-<unique>` worker identity.
5. Request V16.2 continuation before inventing work.
6. Treat live GitHub + Mission Graph as stronger authority than stale prose.

Unknown/corrupt/newer authority fails closed for exclusive writes. It does not mean the chat should stop; switch to safe read-only review/assist until authority is clear.

## MERGE_PRESSURE comes first

If the packet says `MODE: MERGE_PRESSURE`, accepted/near-accepted work is waiting outside `MAIN`.

Possible duties are `INTEGRATE`, `RED_TEAM`, `TEST`, and `CONFLICT_CHECK`.

- `INTEGRATE` requires the exact work-item claim before writes.
- Other duties are non-exclusive and do not grant write authority.
- Use the objective's canonical branch.
- Absorb accepted child work; do not open another successor.
- Resolve compatible conflicts instead of merely reporting them.
- Re-run impacted acceptance on the exact composed head.
- Preserve useful evidence, then close/supersede redundant children.
- Never weaken truth/safety/signing/physical gates to move faster.

As long as merge pressure remains, integration/review/test work outranks capacity mining and most new low-priority implementation.

## WORK mode

1. Claim first, branch second.
2. If another worker wins, consume the next fallback immediately.
3. Use the selected/canonical branch whenever one exists.
4. Solve a coherent outcome, including safe directly-adjacent defects inside the packet's expansion budget.
5. Run impacted tests and preserve evidence.
6. Builder completion goes to review; reviewed work goes to integration; integration-ready work goes to the Merge Train/canonical branch.
7. Refresh and request another continuation in the same chat execution window.

## ASSIST mode

ASSIST keeps 20–30 chat bursts productive without creating duplicate implementation.

By default ASSIST means:

- no new branch;
- no successor PR;
- no competing implementation;
- no physical/user action.

Assist priority:

1. merge/integration pressure;
2. review/red-team an existing candidate;
3. inspect failing/pending CI and isolate the concrete defect;
4. run/strengthen impacted tests without weakening acceptance;
5. attach a concrete finding/evidence to canonical work;
6. only after integration pressure is drained, capacity-mine an active internal objective for a real unowned gap.

A genuinely new blocker must be recorded/admitted before implementation.

## V16.1 convergence law still applies

- one active builder branch per blocker;
- no `allow_duplicate` builder escape hatch;
- intentional solution tournaments capped at two candidates;
- at most two distinct low-progress attempt branches per blocker;
- three low-progress attempts trigger convergence/rabbit-hole review;
- losing a claim means reroute, not successor creation.

## V16.2 PR topology

New swarm-managed PRs carry:

```text
SWARM_PROTOCOL: 16.2
SWARM_SCHEMA: 2
SWARM_LANE: <stable lane id>
SWARM_SLOT: <stable blocker/work slot>
SWARM_WORKER: sol-YYYYMMDD-<unique>
SWARM_BRANCH_INTENT: canonical|validation|review|integration|tournament
```

Review, validation, integration and tournament children require `SWARM_PARENT_PR`. Tournament children also require `SWARM_TOURNAMENT_ID`.

New V16.2 topology limits:

- child work attaches to the open canonical PR for the lane;
- at most 2 open child PRs per canonical parent;
- at most 1 open integration child per canonical parent;
- once the cap is reached, absorb/close/join before another PR can open.

Pre-V16.2 work remains compatible during rollout; do not duplicate it merely to get new metadata.

## Claims and ownership

A claim is temporary ownership, not a reason for everyone else to idle.

- never overwrite a live claim;
- stale takeover uses the normal fenced path;
- returning workers re-check ownership before pushing;
- if ownership is lost, stop writing that branch and reroute immediately.

## Truth and physical boundary

Truth classes remain distinct:

`SIMULATED → ESTIMATED → OBSERVED → AUTHENTICATED → PHYSICALLY_MAPPED → COMMAND_VERIFIED`

For ES80 Capture:

- physical NO-GO remains NO-GO until legitimate external physical authority changes it;
- simulator values are not physical values;
- authenticated observations are not automatically physically-mapped semantics;
- commands require physical mapping and command verification;
- do not invent battery/speed/power/current/mode/range semantics;
- do not send scooter commands during the stationary Capture mission.

V16.2 changes scheduling and integration pressure only. It cannot weaken exact-head evidence, signing, authentication, telemetry truth, physical safety, or command authority.

## Stop gate

A worker may voluntarily stop only when a fresh `v16-go` response says:

```text
status: STOP
stopAuthorized: true
```

Do not convert these into STOP yourself:

- claim lost;
- builder slots full;
- PR waiting for CI/review;
- first task completed;
- another worker owns the obvious branch;
- obvious task externally blocked;
- one empty recommendation scan.

If the runtime itself is forcibly ending, preserve durable handoff/evidence first. Otherwise continue.
