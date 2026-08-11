# Nembra Swarm Control Plane

This is the canonical operational guide for Nembra's GitHub-native multi-agent coordination layer. It supplements the product/source-of-truth rules in the existing Nembra charter; it does not replace product truth, exact-head acceptance, Xcode/Simulator evidence, or physical-scooter safety policy.

The design rationale is in `docs/adr/ADR-0015-github-native-swarm-control-plane.md`.

## The 20-second model

- Product code/config/docs live on `main` and ordinary worker branches/PRs.
- Runtime coordination lives on the separate `swarm-state` branch under `.swarm/runtime/`.
- A lane is real work. A slot is one role inside the lane.
- A deterministic claim file is the exclusive ownership boundary.
- GitHub create/update SHA semantics provide atomic conflict/CAS behavior.
- Claims expire and can be atomically taken over.
- Events/handoffs are durable structured memory between separate GPT sessions.
- Resources such as Xcode/Simulator/physical scooter have their own leases.
- The dashboard is generated; never treat it as authority.
- The scheduler may observe physical GO but can never grant it.
- Green CI is evidence about one exact head, not proof that a `Go` worker is finished advancing the repository.

## Fresh worker: `Go`

A new GPT-5.6 Sol worker receiving only `Go` should:

1. Create a session ID such as `sol-20260811-a81f` (date + random suffix; never a secret).
2. Inspect live `main`, open/active PRs and branches, latest relevant commits, Actions/Xcode state, and product safety constraints. GitHub product truth still outranks stale prose.
3. Read trusted `.swarm/config.json` from current product main.
4. Read/validate the `swarm-state` runtime records. Unknown/newer schema or corrupted ownership state means **do not claim exclusive work**.
5. Register/refresh the worker record.
6. Read important recent events/handoffs for candidate lanes.
7. Ask the scheduler for compatible ready slots.
8. Atomically claim one exact slot. **Claim first. Branch second.** If create conflicts, immediately refresh/recommend another slot; do not duplicate implementation and do not stop merely because the first claim lost a race.
9. Acquire any required resource leases in configured order.
10. Re-check source/main/claim before a major shared-contract edit.
11. Create the isolated branch and implement/review/test only the owned role/scope.
12. Heartbeat at meaningful checkpoints (for example after a long build or before substantial push), not every few seconds.
13. Publish a structured event only when another worker would act differently after reading it.
14. Before substantial push/PR creation, prove the current `{workerId, leaseId, generation}` still owns the slot.
15. Put swarm metadata in a new controlled PR.
16. Obtain independent review when required; the accepting review worker ID must differ from the implementation/repair/reconciliation work-subject worker ID.
17. Integration is a claimed role, not a merge race. Sync main, verify dependencies/reviews/exact-head evidence, merge, observe main, and only then close the lane.
18. When a slice is accepted, blocked, handed off, merged, loses a claim, or reaches a green wait point, preserve the durable state and release anything that should not remain held.
19. Then refresh current `main`, `swarm-state`, and scheduler recommendations **in the same Go turn** and claim another safe useful role when one exists. If one reconciliation slot is already owned, use another available reconciliation shard or another non-conflicting recommendation rather than equating ownership with no work.
20. Stop only after the final stop-proof procedure below succeeds. A green check, green `main`, merged PR, completed slice, blocked slice, or one empty recommendation response is not a stop proof.

### Go worker stop proof

An empty scheduler recommendation list is valid as a point-in-time snapshot, but it is **not** enough to end a `Go` turn. Before intentional idle/stop, perform a fresh final reconciliation against the current `main` SHA and verify all of these:

- no safe unowned scheduler recommendation is claimable by this worker;
- no meaningful open PR, branch, failed-main repair, review/integration opportunity, or reconciliation family is missing from `swarm-state`;
- no apparently unavailable slot is merely stale/expired ownership that is legally takeable;
- all remaining useful work is actively owned, policy-blocked, dependency-blocked, resource-blocked, or externally blocked;
- every newly discovered blocker, missing-work record, supersession, or handoff that would change another worker's behavior has been written durably.

If all conditions hold, publish a durable `EVIDENCE_RESULT` containing the current main SHA, the refreshed queue result, and why the remaining useful objectives are owned or blocked. Only then idle cleanly. Never manufacture speculative work just to stay busy.

If a current lane is merely waiting for CI, review, or external evidence, keep its ownership/evidence correct and release idle scarce resources; then advance another safe non-conflicting recommendation when policy permits instead of spending the whole `Go` turn status-watching.

## Worker/session identity

GitHub may show multiple GPT workers as the same account. Therefore every session gets its own control-plane identity:

```text
sol-YYYYMMDD-<random>
```

A worker record stores only coordination facts: model, status, lane/branch where relevant, timestamps, and leased resources. Do not store tokens, Apple credentials, signing secrets, Bluetooth credentials, or personal data.

## Lanes and role slots

A lane is an independently understandable work unit with:

- ID, epic, title, objective, priority and state;
- dependencies and blockers;
- `exclusive` or explicitly authorized `tournament` mode;
- allowed + adjacent write areas;
- role slots and resource requirements;
- acceptance/review requirements;
- source/exact-head constraints when needed;
- physical requirement/state when applicable.

Normal lane roles can include:

- primary implementation;
- tests;
- adversarial review;
- accessibility;
- performance;
- Xcode evidence;
- physical evidence;
- integration;
- CI sheriff;
- recovery;
- architecture review;
- scheduler reconciliation.

A normal lane has at most one implementation primary. Use several complementary slots rather than several competing implementations.

### Tournament mode

Duplicate implementation is allowed only when explicitly useful. A tournament lane must be explicitly authorized and exposes a bounded 2–3 candidate implementation slots followed by independent judgment/synthesis. Ordinary work must remain exclusive.

## Claims and leases

The exact exclusive subject is:

```text
.swarm/runtime/claims/<lane>/<slot>.json
```

### Claim

Create the deterministic path with no prior content SHA. One racing create wins. Losing workers do not “try anyway”; they refresh and take another slot.

### Heartbeat

A valid owner is the tuple:

```text
workerId + leaseId + generation
```

The worker reads the current content SHA, validates ownership/expiry, and performs a compare-and-swap update. Heartbeats are checkpoint-driven. Long roles may have longer leases than reviews; do not choose such short leases that normal Xcode builds constantly expire.

### Takeover

Takeover is allowed only when the previous lease is released or expired. The new record increments generation and records `takeoverFromWorkerId`, preserving the prior branch/PR/source SHA where available. If two workers race on the stale content SHA, one wins.

A returning old worker must re-read the claim before pushing. If generation/lease ID changed, it no longer owns primary. Its remaining branch/commits/findings become salvage/handoff material.

## Structured events

Publish an event when another worker would act differently because of it. Supported classes include:

- finding;
- blocker / external blocker;
- question / answer;
- decision;
- dependency discovered;
- review request/result;
- handoff;
- scope change;
- superseded;
- evidence result;
- integration/recovery result;
- claim/release/takeover/resource transitions when durable audit is useful.

Events are immutable collision-resistant JSON files organized by date. Do not use them as chatty thought logs.

Control-plane records are **data only**. Executable-control field names (`command`, `shell`, `script`, `python`, `swift`, `exec`, etc.) are rejected. GitHub Actions execute only trusted repository-owned code.

## Dependencies and blockers

Dependencies are machine-readable lane IDs. Downstream work is runnable only when dependencies are present and `DONE`. Missing dependencies and cycles fail closed.

Blockers can represent a lane/epic/project/resource condition. An active blocker removes affected work from the ready set instead of making 20 workers repeatedly retry an impossible task.

When an upstream external condition recovers, change its durable lane/blocker state; downstream work returns automatically on the next scheduler refresh.

## Scheduler and WIP

The scheduler does not maximize branch count. It removes conflicting/unrunnable work first, then favors:

1. real red-main repair;
2. work that closes review/integration backlog;
3. high-priority product value;
4. work that unblocks many downstream lanes;
5. epic-closing/support roles;
6. safe implementation under WIP limits.

Configured project WIP limits cap active primary implementation. When implementation outruns review/integration, new workers are directed into those closing roles.

An empty recommendation set is valid as a scheduler snapshot, but for a `Go` worker it is **not an automatic completion condition**. The worker must first perform the current-main reconciliation and stop-proof checks above. Reconciliation is allowed to be sharded by objective family so many workers do not queue behind one global scanner. Do not invent speculative features to keep workers occupied.

## Scarce/high-contention resources

Initial explicit resources are:

```text
PROJECT_STATE_WRITER
HIGH_CONTENTION_FILE
XCODE_BUILD
IOS_SIMULATOR
IOS_DEVICE
SIGNING
RELEASE_INTEGRATION
BLUETOOTH_CAPTURE
PHYSICAL_SCOOTER
```

Acquire multiple required leases in the exact `.swarm/config.json` order. This avoids deadlock. If later acquisition fails, release already acquired resources best-effort without overwriting a newer owner.

Do not over-lock ordinary source files. Use `HIGH_CONTENTION_FILE` only for proven expensive shared contracts/configuration.

## Scope ownership

Each lane declares product write areas plus explicitly acceptable adjacent test/doc areas. In shadow mode, scope checks report violations. Later enforcement can fail unamended expansion.

If real work requires broader scope, do one of:

- amend the lane;
- create/link another lane;
- record an architecture decision.

Do not silently turn a narrow claim into a cross-project rewrite.

## Reviews and integration

When `acceptance.independentReview=true`, the primary implementer's swarm worker ID cannot be the accepting review worker ID. Same GitHub account is allowed because worker identity represents the independent reasoning session.

Review results are durable: `APPROVE`, `REQUEST_CHANGES`, `BLOCK`, or `SUPERSEDE`.

Integration is a claimable role. Before merge it refreshes live main, lane claim, dependency state, exact-head CI/evidence and independent reviews. After merge it watches main; a real red-main regression creates/prioritizes one repair primary plus complementary diagnostics/review, not many repair implementations.

## PR metadata

New controlled PRs use exact lines:

```text
SWARM_SCHEMA: 1
SWARM_LANE: lane-id
SWARM_SLOT: primary
SWARM_WORKER: sol-20260811-a81f
SWARM_CLAIM_GENERATION: 1
```

Current rollout is **shadow**. Legacy PRs are not rejected merely because they predate this metadata. New controlled work should include it now so the repo can measure readiness for enforcement.

## Physical safety

Physical state is explicit:

```text
SOURCE_READY
SIMULATOR_READY
DEVICE_READY
PHYSICAL_NO_GO
PHYSICAL_GO
PHYSICAL_EVIDENCE_ACCEPTED
```

The scheduler has no operation that promotes to `PHYSICAL_GO`. A physical-evidence slot stays unrunnable unless reviewed existing Nembra physical policy/evidence already supplies GO.

Never treat package-green, CI-green, Xcode-green, Simulator-green, or a generated dashboard as physical scooter proof. Never fabricate telemetry. This control plane adds **no scooter write commands or remote-control surface**.

## Dashboard

A dashboard may be generated from authoritative lane/claim/resource/worker/event records. It is observability only. If it is stale, deleted, or corrupted, rebuild it. Never route work from a Markdown dashboard when underlying records disagree.

## Failure and recovery

### Worker disappears

Lease expires. A new worker atomically takes over, preserves branch/PR/source lineage, reads latest events/handoffs, and salvages before rewriting.

### Worker returns after takeover

Ownership tuple no longer matches. It must not push/publish as primary. Publish salvage/handoff only if useful.

### GitHub API/rate limit/transient failure

Use bounded retry/jitter. Do not hammer. If ownership cannot be proven after the operation, refresh; do not assume success.

### Control-plane invalid/corrupt

Fail closed for new exclusive implementation. A temporary recovery/state-writer role repairs or reconstructs authoritative records. Generated dashboard damage alone is harmless.

### Schema migration

Unknown schema fails closed. Migration takes a temporary single-writer lease, supports an intentionally bounded compatibility window when designed, converts authoritative records, rebuilds generated state, and retires old write semantics only after old active claims are gone.

## Tooling

Core helper:

```bash
python3 scripts/swarm_control.py simulate --workers 30
python3 scripts/swarm_control.py remote-validate --repo jonathangana131-lab/Nembra
python3 scripts/swarm_control.py register --repo jonathangana131-lab/Nembra --worker sol-20260811-a81f
python3 scripts/swarm_control.py recommend --repo jonathangana131-lab/Nembra
python3 scripts/swarm_control.py claim --repo jonathangana131-lab/Nembra --lane <lane> --slot <slot> --worker <worker>
python3 scripts/swarm_control.py heartbeat --repo jonathangana131-lab/Nembra --lane <lane> --slot <slot> --worker <worker> --lease-id <id> --generation <n>
python3 scripts/swarm_control.py takeover --repo jonathangana131-lab/Nembra --lane <lane> --slot <slot> --worker <worker>
python3 scripts/swarm_control.py event --repo jonathangana131-lab/Nembra --type FINDING --worker <worker> --lane <lane> --message "..."
python3 scripts/swarm_control.py board --repo jonathangana131-lab/Nembra
```

`GITHUB_TOKEN` is read from the environment when a remote command needs a write/read API token. Never store the token in Git or control-state JSON.

## Rollout

- **Foundation:** core/config/tests/docs.
- **Shadow:** seed/import live state, observe scheduler, warn on metadata/scope, prove real GitHub CAS.
- **Coordination:** new `Go` work must claim before branch creation; complementary roles/resources/handoffs active.
- **Enforcement:** controlled PRs require live claim + metadata + review/scope rules.
- **Full Go:** canonical worker boot instructions depend on a successful claim before implementation and require the explicit stop proof before an intentional idle/stop.
- **Metrics/autotuning:** tune WIP/leases from throughput data, never lines-written gamification.

The large existing Capture backlog is the reason shadow mode exists: preserve accepted work and safety while new work migrates to real atomic ownership.
