# ADR-0015 — GitHub-native swarm control plane

Status: **Proposed / shadow rollout**  
Date: 2026-08-11  
Scope: engineering coordination only; no change to Nembra product telemetry or physical-device authority.

## Context discovered from live Nembra

The repository already has strong engineering mechanisms worth keeping: exact-head acceptance, fail-closed CI gates, Xcode/Simulator evidence, recovery branches, queue cleanup, and explicit product-truth / physical-safety rules. The problem is not absence of process. It is that coordination state is spread across too many weakly synchronized surfaces.

Live inspection found these concrete failure modes:

1. Many overlapping Capture P0 PRs and branches can exist at once, with new PRs superseding or re-anchoring earlier PRs minutes later. The system catches some stale CI after the fact, but ownership is not acquired atomically before implementation begins.
2. `docs/SWARM_OPERATING_SYSTEM.md` identifies V13 as current and explicitly retires V11 feature-cell ceremony, while old V11 feature-cell/control issues remain open and contain lock-like state. Fresh workers can see mutually incompatible instructions.
3. `ADAPTIVE_SWARM_PRIORITY.md` describes a V14 `REFRESH -> SCORE -> CLAIM` loop, but `CLAIM` is conceptual rather than an atomic ownership primitive.
4. `CAPTURE_HARD_FREEZE_ACTIVE.md` is a human-written routing pointer and had already drifted far behind the live Capture PR lineage. A mutable Markdown pointer cannot be scheduler truth.
5. `PROJECT_STATE.md` correctly calls itself a mutable snapshot and tells workers to prefer live GitHub. Its dated PR/SHA examples demonstrate why global prose must not be used as a lock or queue.
6. The existing Capture queue janitor is valuable evidence of a real scarce-executor bottleneck: stale exact-head runs can consume Mac/Xcode capacity long after the product lineage moved.
7. Many workers act through one GitHub account, so GitHub identity alone cannot distinguish independent implementer/reviewer reasoning sessions.
8. Current coordination happens too late. PR metadata, exact-head CI, and cleanup can detect races after a branch/PR exists; they do not prevent two workers from spending substantial time on the same exclusive implementation.

The new control plane must therefore improve ownership, recovery, durable communication, and throughput without replacing Nembra's accepted product/safety machinery or creating a second product.

## Invariants

1. **At most one live owner of an exclusive lane slot.**
2. **A claim is not ownership unless the authoritative GitHub write succeeded.** Uncertain writes fail closed.
3. **Claim first; branch second** for new controlled work.
4. **Leases expire.** A dead chat cannot permanently lock a lane or scarce resource.
5. **Takeover is compare-and-swap.** Two takeover workers may race; one wins.
6. **Generation + lease ID identify the current owner.** An old worker that wakes after takeover cannot heartbeat, release, or publish as primary.
7. **Structured events are data, not executable instructions.** Control records cannot carry arbitrary shell/Python/Swift/AppleScript execution fields.
8. **Generated board state is disposable.** It is reproducible from lanes, claims, resources, workers, and immutable events.
9. **No permanent boss agent exists.** Reconciler/integrator/reviewer are temporary claimable roles.
10. **Review independence is based on swarm worker ID**, not GitHub account, when a lane requires independent acceptance.
11. **Dependencies fail closed.** Missing, blocked, or cyclic dependencies remove downstream work from the runnable queue.
12. **Resource leases are acquired in deterministic global order** to avoid control-plane deadlocks.
13. **Scope is declared before work.** Actual PR paths are checked against lane write areas; expansion becomes a lane amendment/new lane/decision instead of silent drift.
14. **Physical GO is external authority.** The scheduler may observe it but can never promote `PHYSICAL_NO_GO`/Simulator/source readiness to `PHYSICAL_GO`.
15. **Simulator evidence remains Simulator evidence.** It never becomes physical scooter evidence.
16. **No telemetry is invented by coordination state.** Product truth boundaries remain unchanged.
17. **Unknown/newer control schemas fail closed** for exclusive writes.
18. **Idle is valid** when useful non-conflicting work is exhausted.

## Architectures considered

### A. Event/claim files committed directly to product `main`

**Strengths:** simple source-of-truth model; file creation/update can be atomic through GitHub SHA semantics.  
**Rejected as primary runtime design:** every heartbeat/claim/event would churn product history, increase merge contention, trigger unrelated automation, and make coordination itself compete with product shipping.

### B. GitHub Issues, labels, and comments as scheduler truth

**Strengths:** good human UI; already familiar in Nembra.  
**Rejected:** comments are append-friendly but weak for a single atomic exclusive-slot boundary; labels/issues invite multi-field race windows; same-account workers are hard to distinguish; stale historical issue generations already demonstrate ambiguity.

### C. Hybrid immutable events + mutable CAS claims on a dedicated state branch

**Strengths:** deterministic file paths give an atomic conflict boundary; claims/resources can use compare-and-swap; events stay append-only; generated views can be rebuilt; runtime churn is isolated from product history; same repository permissions and audit trail are retained.  
**Chosen.**

### D. Separate control-plane repository

**Strengths:** strongest history/permission isolation.  
**Not chosen initially:** adds cross-repository authentication, setup, discoverability, and failure modes without a demonstrated need. A dedicated branch inside Nembra provides most of the isolation while keeping one durable GitHub home.

### E. PR/check-only lease enforcement

**Strengths:** good final gate; fits current exact-head practices.  
**Rejected as the scheduler:** a PR exists too late. Two workers may already duplicate implementation before the check can reject one. PR checks remain a later enforcement layer, not ownership origin.

## Decision

Use **trusted control-plane code/configuration on product `main`** and **runtime coordination state on the long-lived `swarm-state` branch**.

### Product-main responsibilities

- `.swarm/config.json` — schema version, rollout mode, WIP thresholds, deterministic resource order, immutable safety constraints.
- `scripts/swarm_control.py` — trusted stdlib implementation of validators, CAS claims/leases, takeover, worker identity, events/handoffs, resource acquisition, dependency graph, scheduler, PR metadata validation, generated dashboard, and GitHub Contents API store.
- `scripts/ci/tests/test_swarm_control_plane.py` — deterministic adversarial suite.
- `.github/workflows/swarm-control-plane-shadow.yml` — portable validation/simulation and non-blocking legacy PR metadata observation during shadow mode.
- this ADR and one canonical operator/developer guide.

### `swarm-state` responsibilities

Authoritative runtime state is stored only under `.swarm/runtime/`:

```text
.swarm/runtime/
  meta/
  lanes/<lane>.json
  claims/<lane>/<slot>.json
  workers/<worker>.json
  resources/<resource>.json
  events/YYYY/MM/DD/<event-id>.json
  handoffs/<lane>/<handoff-id>.json
  generated/DASHBOARD.md        # cache only
```

No runtime file contains secrets or arbitrary executable code.

## Atomicity model

### New claim

The exclusive slot has one deterministic path:

```text
.swarm/runtime/claims/<lane>/<slot>.json
```

The first worker creates it through the GitHub Contents API **without an existing content SHA**. GitHub accepts one create. A racing create receives conflict/unprocessable state and must immediately refresh/recommend another slot. The worker must not create its implementation branch before winning.

### Heartbeat / release

The worker reads the current claim, proves `{workerId, leaseId, generation}`, verifies the lease is live, then updates with the currently observed content SHA. A concurrent update changes the SHA and rejects the stale write.

Heartbeats occur at meaningful checkpoints, not continuously.

### Stale takeover

A worker may take over only a released/expired claim. It reads the current record, confirms staleness, writes a new owner with `generation + 1`, new random `leaseId`, and takeover lineage using the old content SHA. Two simultaneous takeover updates race on the same SHA; one succeeds. The old owner can no longer satisfy the ownership tuple.

### Immutable events

Events receive collision-resistant IDs and are create-only. They record only information that could change another worker's behavior: finding, blocker, decision, review result, handoff, evidence result, supersession, takeover, integration result, and similar high-value transitions.

## Scheduler

The scheduler is deliberately explainable rather than a giant opaque score. It first removes unrunnable work:

- terminal/blocked lane;
- active lane blocker;
- missing/incomplete dependency;
- dependency cycle;
- occupied required resource;
- live owner already present for the slot;
- physical slot without pre-existing `PHYSICAL_GO`;
- primary slot when project WIP limit is reached.

Then it orders useful work using visible tiers/signals:

1. real red-main repair;
2. review/integration closure pressure;
3. lane priority;
4. current lane state / role fit;
5. dependency fan-out / unblock value;
6. epic-closing work;
7. role fit.

When review or integration backlogs exceed configured thresholds, starting another primary becomes less attractive and support roles move upward. If no slot is useful, an empty recommendation set means **idle/stop cleanly**, not “invent a feature.”

## Resource model

Scarce/high-contention resources are explicit CAS leases. Initial classes:

- `PROJECT_STATE_WRITER`
- `HIGH_CONTENTION_FILE`
- `XCODE_BUILD`
- `IOS_SIMULATOR`
- `IOS_DEVICE`
- `SIGNING`
- `RELEASE_INTEGRATION`
- `BLUETOOTH_CAPTURE`
- `PHYSICAL_SCOOTER`

Multiple resources are acquired in the configured deterministic order. If a later acquisition fails, already acquired resources are released best-effort without overwriting a newer owner.

The existing Capture queue janitor remains useful: control-plane resource ownership prevents new avoidable contention, while the janitor continues removing stale executor work already admitted by legacy paths.

## Role model

A lane may expose several independent slots. A normal exclusive lane has at most one implementation primary and may also have tests, adversarial review, accessibility, performance, Xcode evidence, integration, recovery, and other complementary roles. This is how 5 workers deepen one system without producing 5 implementations.

Intentional duplicate implementation is allowed only in `tournament` mode with explicit authorization and 2–3 bounded candidate slots. Tournament lanes require later synthesis/judging.

## Physical-safety semantics

The control plane recognizes the states:

- `SOURCE_READY`
- `SIMULATOR_READY`
- `DEVICE_READY`
- `PHYSICAL_NO_GO`
- `PHYSICAL_GO`
- `PHYSICAL_EVIDENCE_ACCEPTED`

It does **not** contain a transition that grants `PHYSICAL_GO`. A physical-evidence slot is unrunnable unless reviewed external Nembra policy/evidence has already set that state. The scheduler cannot reinterpret CI, Xcode, Simulator, or source success as physical authorization.

No scooter command or write primitive is added by this ADR.

## PR enforcement model

New controlled PRs eventually carry:

```text
SWARM_SCHEMA: 1
SWARM_LANE: <lane-id>
SWARM_SLOT: <slot>
SWARM_WORKER: <sol-session-id>
SWARM_CLAIM_GENERATION: <integer>
```

In **shadow mode**, legacy PRs without this metadata are warned/observed rather than failed. This is required because Nembra currently has a large live Capture backlog created before the control plane. After import/reconciliation proves stable, enforcement can require:

- lane exists;
- current claim owner matches metadata;
- claim live/generation exact;
- branch/PR exact;
- lane not blocked/superseded;
- scope acceptable;
- required resources were held where policy requires them;
- independent reviewer differs when required.

Exact-head acceptance remains separate and authoritative for code acceptance.

## Schema and migration

Every record carries `schemaVersion`. Unknown newer schemas fail closed for exclusive mutation. Schema migration requires a temporary `PROJECT_STATE_WRITER`/migration lease. A future migration may support a bounded current+previous read window, write only the new schema, rebuild generated state, then retire the old reader once no active old-schema leases remain.

No worker may reinterpret a record from an unknown schema to “keep moving.”

## GitHub failure/rate-limit semantics

The GitHub store uses bounded retry with jitter for transient 429/5xx/network failures and secondary-rate-limit responses. It performs few meaningful writes: claims, meaningful heartbeats, transitions, resource changes, and high-value events. Ownership uncertainty is not retried into assumed success; if the final outcome cannot be proven, the worker refreshes state before writing product code.

## Control-plane corruption/recovery

- Malformed/unknown runtime records fail validation.
- Dependency cycles fail closed.
- Generated dashboard corruption is irrelevant to authority; rebuild it from source records.
- If global state is inconsistent, acquire the temporary state-writer/recovery role, repair or reconstruct state, and keep new exclusive implementation closed until ownership truth is again provable.
- Product code and accepted physical-safety policy do not depend on the generated board.

## Rollout decision

Nembra is too active to hard-flip enforcement safely. Roll out in stages:

1. **Foundation (this change):** trusted core, config, tests, ADR, canonical guide.
2. **Shadow:** create/seed `swarm-state`, import only current live work that can be proven, run recommendation/validation without rejecting legacy PRs.
3. **Coordination:** fresh `Go` workers register, recommend, and atomically claim before branch creation; use events/handoffs/resource leases.
4. **Enforcement:** require metadata/claim agreement for newly controlled PRs while retaining explicit legacy handling.
5. **Full Go protocol:** update canonical worker boot instructions so new implementation cannot start without claim success.
6. **Metrics/autotuning:** measure duplicate/superseded PR rate, prevented collisions, stale claims/takeovers, review/integration backlog, cycle time, executor queue time, merge conflicts, and retained vs gross code churn. Do not optimize lines written.

The shadow stage is intentionally compatible with ongoing V13/V14 Capture work. It avoids breaking active exact-head, Xcode, and physical-validation machinery while replacing stale prose-based scheduler truth with machine-checkable ownership.

## Consequences

### Positive

- Duplicate exclusive implementation is prevented before coding.
- Dead sessions recover without indefinite locks.
- Independent review and complementary roles become first-class.
- Runtime coordination churn no longer pollutes product-main history.
- Stale human dashboards no longer route work.
- Existing exact-head and physical safety mechanisms are preserved.
- 30 simultaneous `Go` workers can converge on different useful slots instead of racing one implementation.

### Costs / limitations

- The `swarm-state` branch becomes operational infrastructure and must be permissioned/protected sensibly.
- GitHub Contents API is not a high-throughput database; the design therefore avoids rapid polling/heartbeats and intentionally batches meaningful state changes.
- Initial rollout does not retroactively make every legacy PR compliant. Importing/reconciling the active backlog is explicit shadow-mode work.
- A worker still needs current live product-GitHub inspection; the state branch coordinates ownership but does not replace source/PR/CI truth.

## Acceptance evidence required before enforcement

- deterministic control-plane suite green;
- 30-worker single-slot race produces exactly one owner;
- stale takeover race produces exactly one new owner;
- old owner rejected after takeover;
- dependency/blocker propagation and recovery;
- review/integration WIP routing;
- resource exclusivity and deadlock ordering;
- scope and PR metadata checks;
- generated board reproducibility;
- malformed/executable-looking control payload rejection;
- physical NO-GO remains NO-GO;
- a real GitHub state-branch create conflict and stale-SHA update conflict;
- existing Nembra CI remains unaffected in shadow mode.
