# Nembra Swarm V16 — Mission Graph

This is the **canonical operational guide** for Nembra multi-agent development. `SWARM_GO.md` is the short worker entrypoint. Older V13/V14 lane-first documents are historical only.

V16 optimizes for **important product milestones completed and blockers eliminated**. PR count, branch count, commit count, validation count, and agents appearing busy are not progress metrics.

Existing Nembra product truth, authentication, exact-head CI, signing, private-input custody, accessibility, and physical-scooter safety rules remain authoritative. V16 coordinates those rules; it does not weaken them.

## The model

V16 organizes work as:

`MISSION → OBJECTIVES → DEPENDENCIES → BLOCKERS → WORK ITEMS → SOLUTIONS → EVIDENCE → INTEGRATION → MILESTONE`

Agents are execution resources underneath the graph, not the organizing abstraction.

Persistent V16 state lives on `swarm-state` at:

```text
.swarm/runtime/v16/mission-graph.json
.swarm/runtime/v16/claims/<work-item>.json
```

The mission graph uses GitHub Contents compare-and-swap updates. Work claims use separate deterministic files so 30 workers do not serialize their heartbeats through one graph document. V15 lane/claim state remains readable during migration.

## Missions and objectives

The seeded top-level missions are:

- **Nembra Shipping Mission** — Dashboard, Battery/Range, Charging, Navigation, Rides, Vehicle Controls, Connection, Settings, Performance, Accessibility, Premium UI, and Real ES80 Telemetry.
- **Capture Mission** — standalone build, Apple auth, Tuya auth, account/device verification, secure session, signed build, installation, stationary UX, authenticated read-only observation, secure export, final regression, and physical handoff.

Every objective has explicit status, priority, dependencies, blocker IDs, captain, active workers, evidence, integration world, severity, user value, physical/user dependency, last meaningful progress, canonical branch, adjacent scope, forbidden areas, and concrete finish conditions.

An objective cannot become `DONE` merely because CI is green. V16 requires all finish conditions, no unresolved P0/P1 blocker, accepted required feature-genome dimensions, and `MAIN` integration. Physical objectives also require accepted physical truth.

## Feature genomes

Every major objective exposes separate dimensions:

```text
functionality
visualQuality
accessibility
performance
testing
integration
physicalTruth
knownBlockers
```

Each dimension is independently `NOT_STARTED`, `ACTIVE`, `BLOCKED`, `ACCEPTED`, or `NOT_APPLICABLE` and carries its own evidence IDs. There is deliberately no universal fake completion percentage.

## Severity and priority

Severity is:

- **P0** — release blocker, unsafe behavior, or truth corruption.
- **P1** — major feature broken.
- **P2** — noticeable issue.
- **P3** — polish.

Scheduler priority combines severity, release blocking, safety, user-visible value, dependency fan-out, finish proximity, age/integration pressure, and active surge state. Near-finished important work receives more pressure, not less.

## Feature captains

Major missions may have a captain. Captains coordinate blocker ownership, workers, duplicate suppression, solution selection, integration, Definition of Done, escalation, and handoff. They do not need to write every line.

Captain failure is recoverable: replace the stale captain while preserving mission/blocker/work state. Captain disappearance never invalidates accepted evidence or deadlocks workers.

## Work items and mission packets

Workers receive coherent outcome-based work items, not isolated test-name chores. A work item includes:

- primary scope;
- allowed adjacent scope;
- forbidden areas;
- canonical/experimental branch state;
- role;
- blocker linkage;
- intended outcome;
- evidence and integration state.

The scheduler emits compact mission packets containing:

```text
MISSION
WHY_IT_MATTERS
CURRENT_STATE
EXACT_CANONICAL_BRANCH
KNOWN_FAILURES
KNOWN_PROVEN_FACTS
DO_NOT_REDISCOVER
PRIMARY_SCOPE
ALLOWED_EXPANSION
FORBIDDEN_AREAS
RELATED_WORKERS
RELEVANT_EVIDENCE
EXIT_CONDITION
```

This is the worker context budget. Workers should not reconstruct hundreds of PRs from scratch.

## Roles and specialization

Normal dynamic allocation begins near:

- builders — 60%;
- reviewers/red-team — 20%;
- integrators/debuggers — 20%.

The ratio shifts automatically when review or integration backlog grows or a milestone approaches closure. Agent specialization scores come from accepted/integrated outcomes and regressions in domains such as SwiftUI, MapKit, CoreBluetooth, Tuya, accessibility, performance, and integration. Deterministic exploration slots prevent specialization from becoming brittle.

## Canonical branches

Major active objectives should have one selected canonical feature branch. Branch lifecycle states are:

```text
EXPERIMENTAL
PROMISING
SELECTED
INTEGRATED
SUPERSEDED
ARCHIVED
```

V16 chooses canonical branches using explicit selection authority and accepted evidence. A semantic tie is recorded for captain/reviewer judgment rather than treated as proof. Redundant selected siblings are marked superseded; archived branches remain evidence-addressable.

Remote deletion/closure is **fail-closed during migration**. `branch_cleanup_plan` may identify safe archival candidates, but destructive GitHub actions remain disabled until V16 reaches the ACTIVE migration phase and unresolved evidence/blocker references are clear.

## Anti-duplication

Before new work is created, V16 compares it with active work by blocker identity plus semantic similarity of objective, title, and outcome. Same-blocker work is a duplicate unless an explicit solution tournament authorizes competition.

A duplicate is routed to one of:

- join the current owner;
- review/red-team the current solution;
- help integrate it.

It does not receive another accidental branch/PR.

Completed or archived work does not suppress a genuine later regression.

## Solution tournaments

Hard blockers may deliberately authorize 2–3 independent candidates. Tournament candidates are `EXPERIMENTAL`. Selection compares correctness, simplicity, maintainability, regression risk, test coverage, and integration cost. The winner becomes `SELECTED`; losing branches become `SUPERSEDED` and later `ARCHIVED` when evidence references permit it.

Duplication is therefore intentional and bounded instead of accidental and unbounded.

## Blockers, convergence, and rabbit holes

A blocker is a first-class object containing:

```text
blocker ID
mission / objective
symptom
evidence
owner / backup
severity
first observed
attempts
current hypothesis
related branches
known duplicate attempts
next action
exit condition
last meaningful progress
```

Only the owner or an intentionally scheduled tournament should create competing repair work.

Repeated attempts with little progress trigger **CONVERGENCE MODE**: freeze competing branch families, consolidate evidence, keep one canonical owner, add fresh review, integrate the best repair, and rerun only necessary acceptance.

High activity with almost no blocker removal triggers a **Rabbit Hole Review**. The review asks what is truly required, what is duplicated, which safety checks are load-bearing, which validation mechanisms can be consolidated, and what the smallest rigorous closure path is. It never weakens a real safety or truth boundary.

## Complexity budget and momentum

V16 can flag pathological production/test/workflow/branch/validation ratios. Large validation infrastructure relative to product code is a reason to consolidate reusable primitives.

Momentum rewards blockers removed, dependencies unlocked, acceptance gained, integration gained, user-visible improvement, and meaningful code. Regressions and duplicate work are negative. High activity with low momentum changes scheduling strategy instead of earning a high score.

## Nembra Test Kit

Reusable acceptance primitives live in `scripts/swarmcp/v16_ops.py`:

```text
SourceCustody
BuildIdentity
SignedBuildIdentity
SimulatorIdentity
DeviceIdentity
PrivateInputCustody
InstallationCustody
AccessibilityAcceptance
VisualEvidence
PerformanceEvidence
TelemetryTruth
PhysicalTruth
IntegrationTruth
```

The primitive defines the maximum authority it may create; feature-specific semantics remain feature-specific. `TelemetryTruth` may record authenticated telemetry evidence but **cannot** mark physical truth accepted. Only explicit `PhysicalTruth` evidence with legitimate physical authority can do that.

## Test impact and evidence reuse

V16 maps changed paths to affected tests. For example a Dashboard layout edit targets Dashboard source/UI/accessibility plus compile evidence, not unrelated Capture filesystem adversarial suites. Full-system suites still run at integration/release boundaries.

Evidence is bound to source, dependencies, environment, and affected paths. It is reusable only when all bindings still match. Relevant source/dependency movement invalidates it automatically. Unrelated movement does not force expensive proof to rerun.

## Truth classes

Shared evidence authority is:

```text
SIMULATED
ESTIMATED
OBSERVED
AUTHENTICATED
PHYSICALLY_MAPPED
COMMAND_VERIFIED
```

These are ordered concepts, not interchangeable labels. Simulator data never becomes authenticated or physical truth. Authenticated read-only ES80 data still does not authorize commands.

## Physical ES80 boundary

V16 does not grant physical GO. Existing Nembra physical policy remains external authority.

Capture’s target is a stationary, authenticated, **read-only** observation path:

1. accepted signed Capture build;
2. install on the intended iPhone;
3. supported account sign-in, including Sign in with Apple where implemented;
4. Tuya account/device verification;
5. official authenticated Tuya session;
6. scooter nearby and stationary;
7. genuine non-empty structured application data observed continuously for the required window;
8. secure accepted observation export;
9. clear success/failure result;
10. **no commands sent**.

Do not invent battery semantics, speed DP, power/current, mode/range mappings, commands, or acknowledgements. Do not return to an outdoor ride procedure unless later physical evidence specifically requires it.

## Integration worlds and Merge Train

V16 tracks:

- **MAIN** — accepted current product;
- **NEXT** — high-confidence work awaiting final promotion;
- **FRONTIER** — serious substantially built work;
- **EXPERIMENTAL** — unproven experiments.

The persistent Merge Train queues compatible accepted work, serializes the actual integration candidate, runs required affected suites, and either promotes it to MAIN or leaves it actionable in `INTEGRATING` for repair. An integrator is expected to resolve conflicts and compose both intents, not report “merge conflict” and stop.

## Milestone Attack and Surge

When an objective has only a few blockers/finish conditions left, V16 marks it for **MILESTONE ATTACK** and increases closure pressure.

`SURGE` concentrates the swarm on one mission. A 30-worker surge explicitly reserves one captain and allocates the remainder among implementation, review/testing, integration, debugging/research, UI/accessibility, and reserve. Workers are redistributed as blockers close. Surge ends when the milestone closes, only external/hardware work remains, or safety prevents further autonomous work.

## Red team after completion

A feature claiming completion receives fresh adversarial review covering UI/accessibility, performance, and truth failure modes. Physical objectives add authority-boundary tests. If no P0/P1 remains after the required acceptance, close the feature; do not reopen forever for P3 polish.

## Shared memory and failure knowledge

The graph keeps a bounded high-signal event stream and structured failure knowledge. Record information that changes another worker’s action: root cause, successful fix/evidence, relevant environment behavior, false leads, selected solution, blocker closure, or integration result. Do not write chain-of-thought or noisy polling logs.

Future workers must search this memory before repeating known investigations.

## Go lifecycle

`Go` means a complete productive cycle:

1. refresh current main, PR/branch/CI truth and V16 state;
2. reconcile missing/superseded active work;
3. request the highest-value safe mission packet;
4. detect duplicates before creating work;
5. atomically claim the work item;
6. use its canonical branch unless an experiment/tournament explicitly says otherwise;
7. implement a coherent outcome, including allowed adjacent repairs;
8. run impacted tests and required evidence;
9. hand to independent review or integration as required;
10. integrate/repair the candidate through the Merge Train;
11. preserve blockers/evidence/memory and release idle resources;
12. refresh again and request another safe mission.

A green check, merged PR, completed first task, or lost claim is a checkpoint—not completion.

A worker stops only when no safe unblocked internal work remains for its capabilities, all relevant work is externally blocked, policy requires a stop, or the execution environment ends.

## Health and progress reporting

Health is `GREEN`, `YELLOW`, `ORANGE`, or `RED` based on convergence signals: active work, duplicate suppression, branch explosion, merge backlog, stale blockers, rabbit holes, and finished-but-not-integrated work.

Primary blocker scoreboard:

```text
started blockers - blockers closed + legitimate new blockers = remaining blockers
```

User-facing status names product areas such as Dashboard, Battery, Charging, Rides, Navigation, Bluetooth, Capture, and Controls. It reports wins, current blockers, active work, waste, and major milestones without drowning the user in internal provenance terms.

## Migration from V15/V15.1

Migration is in-place and additive:

1. seed the V16 mission graph;
2. import legacy lanes and their blocker truth;
3. preserve `PHYSICAL_NO_GO` exactly;
4. classify open PRs as canonical candidate, support/validation, duplicate, superseded/archive, integration-needed, or review-needed;
5. use legacy explicit production-selection metadata before making a new canonical choice;
6. dogfood duplicate suppression, scheduling, health, and Merge Train against live Nembra work;
7. only after accepted review and activation may destructive cleanup be enabled.

Legacy lane/claim CLI entrypoints remain available during the compatibility window. Unknown/corrupt V16 state fails closed for new V16 ownership rather than corrupting existing work.

## Recovery

- Worker crash: lease expires; takeover preserves the salvage branch.
- Old worker returns: stale lease/generation cannot heartbeat or publish as owner.
- Captain crash: assign a replacement; graph state remains valid.
- GitHub transient/rate limit: existing bounded retry/jitter policy remains in `GitHubContentsStore`.
- Main moves: invalidate affected evidence; unrelated evidence may remain reusable.
- Integration fails: candidate returns to actionable `INTEGRATING`; integrator repairs it.
- Corrupt/newer schema: fail closed for authority-changing work.

## Operator commands

Local deterministic proof:

```bash
python3 scripts/swarm_control.py simulate --workers 30
python3 scripts/swarm_control.py v16-simulate --workers 30
```

Remote V16 operations:

```bash
python3 scripts/swarm_control.py v16-init --repo jonathangana131-lab/Nembra
python3 scripts/swarm_control.py v16-migrate --repo jonathangana131-lab/Nembra
python3 scripts/swarm_control.py v16-status --repo jonathangana131-lab/Nembra
python3 scripts/swarm_control.py v16-recommend --repo jonathangana131-lab/Nembra --worker sol-YYYYMMDD-xxxx
python3 scripts/swarm_control.py v16-claim --repo jonathangana131-lab/Nembra --work-item <id> --worker <worker>
python3 scripts/swarm_control.py v16-go --repo jonathangana131-lab/Nembra --worker <worker> --completed <id> --evidence <evidence-id>
python3 scripts/swarm_control.py v16-captain --repo jonathangana131-lab/Nembra --mission capture-stationary --worker <worker>
python3 scripts/swarm_control.py v16-surge --repo jonathangana131-lab/Nembra --mission capture-stationary
python3 scripts/swarm_control.py v16-cleanup-plan --repo jonathangana131-lab/Nembra
```

Live read-only dogfood:

```bash
python3 scripts/swarm_v16_dogfood.py \
  --repo jonathangana131-lab/Nembra \
  --self-integration-proof
```

`GITHUB_TOKEN` comes from the environment. Never store tokens, Apple credentials, Tuya credentials, signing material, Bluetooth secrets, or private user data in graph state.

## Source of truth

For future workers:

1. current GitHub product/CI truth;
2. `docs/SWARM_CONTROL_PLANE.md` (this document);
3. `SWARM_GO.md` for the worker loop;
4. V16 structured state;
5. legacy V15 state only where migration has not yet represented it.

Generated dashboards, stale PR descriptions, old V13/V14 operating documents, and activity counts are never scheduler authority.
