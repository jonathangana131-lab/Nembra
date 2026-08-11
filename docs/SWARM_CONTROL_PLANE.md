# Nembra Swarm Control Plane — V16

This is the canonical operational guide for Nembra's GitHub-native multi-agent engineering control plane. It coordinates engineering only. It does **not** replace product truth, exact-head acceptance, Xcode/Simulator evidence, private-input custody, signing authority, or physical-scooter safety policy.

The original architecture decision is preserved in `docs/adr/ADR-0015-github-native-swarm-control-plane.md`. V16 enforcement is recorded in `docs/adr/ADR-0016-swarm-v16-enforcement.md`.

## Current operating model

- Product code/config/docs live on `main` and normal worker branches/PRs.
- High-churn coordination lives on the long-lived `swarm-state` branch under `.swarm/runtime/`.
- A lane is real work; a slot is one role inside that lane.
- A deterministic claim file is the exclusive ownership boundary.
- GitHub create/update content-SHA semantics provide atomic create/CAS behavior.
- Claims and scarce-resource leases expire and support generation-fenced takeover.
- Worker IDs distinguish independent GPT-5.6 Sol sessions even when GitHub account identity is shared.
- Structured events/handoffs are durable shared memory, not chat logs.
- Dependencies/blockers remove unrunnable work instead of encouraging repeated retries.
- The scheduler controls WIP and prefers closing review/integration/recovery work when implementation outruns validation.
- Generated dashboard, metrics, and validation files are projections only.
- New controlled PRs are mechanically enforced against live ownership.
- The scheduler can observe physical authority but can never create `PHYSICAL_GO`.
- Green CI is evidence, never a completion signal for a `Go` worker.

## V16 enforcement

Nembra now uses `rolloutMode: enforcement` for work created after the configured V16 cutoff. The pre-V16 Capture backlog remains grandfathered by PR creation timestamp so ongoing accepted/recoverable work is not destroyed during migration.

For every new controlled PR, the enforcement job materializes:

1. trusted control code/config from the PR's **base** generation;
2. the exact current `swarm-state` runtime snapshot;
3. the exact changed-file set for the PR.

It then requires:

- valid swarm metadata;
- a real lane and slot;
- a live claim;
- exact worker ID + claim generation;
- exact claimed branch;
- the lane to remain writable/unblocked;
- changed files to remain inside declared/adjacent scope;
- every resource required by the slot to have a matching live resource lease.

The validator used to police a PR comes from trusted base code, not PR-head code. A PR cannot weaken the validator that approves itself.

### Controlled PR metadata

```text
SWARM_SCHEMA: 1
SWARM_LANE: <lane-id>
SWARM_SLOT: <slot>
SWARM_WORKER: sol-YYYYMMDD-<unique>
SWARM_CLAIM_GENERATION: <integer>
```

A post-cutoff PR without valid metadata fails. A pre-cutoff legacy PR can remain grandfathered, but a new worker may not use that compatibility path to bypass claims.

## Atomic ownership

The exclusive slot path is:

```text
.swarm/runtime/claims/<lane>/<slot>.json
```

**Claim first. Branch second.** Racing create attempts produce one winner. Losing workers refresh and select another useful slot rather than coding anyway.

A live owner is identified by:

```text
workerId + leaseId + generation
```

Heartbeats and release use the currently observed content SHA. Takeover is legal only after release/expiry and increments generation. Two takeover workers racing the same stale blob produce one winner. An old worker that wakes after takeover cannot prove the new generation and must hand off/salvage instead of continuing as owner.

## Worker roles

There is no permanent manager model. GPT-5.6 Sol workers are peers taking temporary roles such as:

- implementation primary;
- tests/adversarial tests;
- independent review;
- architecture review;
- accessibility/performance;
- Xcode/Simulator evidence;
- physical evidence when already authorized;
- integration;
- CI sheriff;
- recovery;
- scheduler reconciliation.

A normal exclusive lane has one implementation primary and multiple complementary roles. Intentional duplicate implementation is permitted only through explicitly bounded tournament mode followed by independent judgment/synthesis.

## Structured communication

Publish a durable event when another worker would act differently after reading it. Useful classes include `FINDING`, `BLOCKER`, `EXTERNAL_BLOCKER`, `DEPENDENCY_DISCOVERED`, `DECISION`, `REVIEW_REQUEST`, `REVIEW_RESULT`, `HANDOFF`, `SUPERSEDED`, `EVIDENCE_RESULT`, `RECOVERY`, and `INTEGRATION_RESULT`.

Events are immutable, collision-resistant data. Control records reject executable-control fields; no arbitrary shell/Python/Swift/AppleScript is supplied by runtime state. Repository-owned trusted code is the only executable control logic.

## Dependency, blocker, and WIP routing

A slot is removed from the ready set when its lane is terminal/blocked, a dependency is missing/incomplete, a dependency cycle exists, an exclusive slot/resource is already live-owned, physical authority is absent, or project/per-epic WIP limits forbid another primary.

Scheduler priorities remain explainable:

1. real red-main repair;
2. review/integration closure pressure;
3. high-value product work;
4. high fan-out unblockers;
5. epic-closing/support roles;
6. safe new implementation under WIP limits.

A worker losing one claim does not stop. An empty first recommendation does not stop. Green main does not stop. `SWARM_GO.md` defines the mandatory reconciliation/continuation loop.

## Scarce resources

Explicit resource classes include:

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

Acquire multiple resources in the exact order declared by `.swarm/config.json` to avoid deadlocks. Do not hold scarce resources while waiting on unrelated CI/review. Do not over-lock ordinary source files.

## Physical safety

Physical state remains explicit:

```text
SOURCE_READY
SIMULATOR_READY
DEVICE_READY
PHYSICAL_NO_GO
PHYSICAL_GO
PHYSICAL_EVIDENCE_ACCEPTED
```

There is no control-plane operation that promotes to `PHYSICAL_GO`. Simulator, package, source, CI, Xcode, dashboard, or swarm success cannot create physical authority. Nembra's existing reviewed safety/evidence path remains the only authority. The swarm adds no scooter write command, remote-control primitive, credential exposure, or telemetry fabrication path.

## Exact live-state fence and generated projection

V16 computes SHA-256 across authoritative runtime JSON, excluding `.swarm/runtime/generated/`. It writes:

```text
.swarm/runtime/generated/DASHBOARD.md
.swarm/runtime/generated/METRICS.json
.swarm/runtime/generated/VALIDATION.json
```

`VALIDATION.json` binds `PASS` to one exact runtime-state digest. If authoritative state changes afterward, fence verification fails until the projection is rebuilt.

The scheduled/push projector:

1. materializes one exact `swarm-state` commit;
2. validates all authoritative records;
3. renders dashboard/metrics/fence;
4. verifies the fence;
5. commits generated output on a detached copy of that exact state;
6. re-fetches `swarm-state` immediately before push;
7. refuses to publish if the branch advanced.

Thus stale automation cannot overwrite newer coordination state. Generated output is still a cache; authoritative records remain the source of ownership truth.

## Mechanical stop proof

After a fresh live-GitHub reconciliation, a worker can run:

```bash
PYTHONPATH=scripts python3 -m swarmcp.maximum stop-proof --root <materialized-state-root>
```

The proof fails when safe scheduler slots remain, stale active claims are recoverable, review backlog remains, or integration backlog remains. A state-only proof cannot establish that an unrecorded GitHub PR/branch does not exist, so live reconciliation is mandatory first.

A worker may intentionally idle only when both live reconciliation and the mechanical proof pass, and it publishes a durable `EVIDENCE_RESULT` explaining the current main SHA, state digest, empty queue, and remaining owned/blocked objectives.

## Failure recovery

- **Worker disappears:** lease expires; another worker may atomically take over and salvage branch/PR/findings.
- **Old worker returns:** generation/lease mismatch fences it from owner operations.
- **GitHub API/rate limit/transient failure:** bounded retry/jitter; uncertain ownership is never assumed successful.
- **Control state malformed/unknown schema:** new exclusive writes fail closed until recovery/reconciliation repairs truth.
- **Generated projection corrupt/deleted:** rebuild it; generated files are not ownership authority.
- **State publisher race:** expected branch-head mismatch causes refusal rather than overwrite.
- **Schema migration:** temporary single-writer migration ownership; unknown newer schema fails closed.

## Tooling

Existing GitHub-native worker operations remain available through `scripts/swarm_control.py`:

```bash
python3 scripts/swarm_control.py simulate --workers 30
python3 scripts/swarm_control.py remote-validate --repo jonathangana131-lab/Nembra
python3 scripts/swarm_control.py register --repo jonathangana131-lab/Nembra --worker <worker>
python3 scripts/swarm_control.py recommend --repo jonathangana131-lab/Nembra
python3 scripts/swarm_control.py claim --repo jonathangana131-lab/Nembra --lane <lane> --slot <slot> --worker <worker>
python3 scripts/swarm_control.py heartbeat --repo jonathangana131-lab/Nembra --lane <lane> --slot <slot> --worker <worker> --lease-id <id> --generation <n>
python3 scripts/swarm_control.py takeover --repo jonathangana131-lab/Nembra --lane <lane> --slot <slot> --worker <worker>
python3 scripts/swarm_control.py event --repo jonathangana131-lab/Nembra --type FINDING --worker <worker> --lane <lane> --message "..."
python3 scripts/swarm_control.py board --repo jonathangana131-lab/Nembra
```

V16 local enforcement/projection commands:

```bash
PYTHONPATH=scripts python3 -m swarmcp.maximum validate-local --root <root>
PYTHONPATH=scripts python3 -m swarmcp.maximum render --root <root>
PYTHONPATH=scripts python3 -m swarmcp.maximum verify-fence --root <root>
PYTHONPATH=scripts python3 -m swarmcp.maximum pr-check --root <root> --event <event.json> --changed-files <paths.txt>
PYTHONPATH=scripts python3 -m swarmcp.maximum stop-proof --root <root>
```

`GITHUB_TOKEN` is read from the environment for remote GitHub operations. Never store tokens, Apple/signing credentials, Bluetooth secrets, or private Tuya credentials in Git/control records.

## Rollout status

- Foundation: **complete**.
- Real GitHub CAS proof: **complete**.
- Coordination/claim-first workflow: **active**.
- Full `Go` continuation/stop-proof protocol: **active**.
- V16 enforcement for newly created work: **active after V16 merge**.
- Pre-V16 Capture backlog: **grandfathered and incrementally reconciled**, not forcibly rewritten.
- Digest-fenced live projection: **active after V16 merge**.
- Metrics/autotuning: ongoing; tune WIP/leases from verified throughput and contention, never gross lines written.

The control plane exists to reduce coordination cost. If a future rule costs more engineering throughput than the collisions/risks it prevents, measure it, simplify it, and preserve the invariants above.
