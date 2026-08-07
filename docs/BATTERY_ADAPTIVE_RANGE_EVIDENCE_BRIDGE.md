# Battery Evidence → Adaptive Range Learning Pipeline

Status: dependent software truth/integration layer. No physical AOVOPRO ES80 battery semantic is verified by this implementation.

## V7 ownership / dependency state

Incumbent lane: `battery-range-evidence-bridge`, Epoch 1, worker `chat-c9m4x`, PR #38.

Synthetic review base: `b3d78cb5475049785318c026781f5a68321a8785`.

That base carries exact assembler parent #54 head `76880f826604e941cd4d75d09edf2619fd774d26`, including fail-closed `recordDistance(... coverage: = .unknown)` semantics. Parent docs/workflow/test-only movement does not trigger churn rebases under Swarm OS v7; consumed semantic movement does.

Current worker delta is eight isolated paths:

- `Packages/NembraCore/Sources/NembraCore/BatteryAdaptiveRangeEvidenceAdapter.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeEvidenceAdapterTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePipelineIntegrationTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeModelBoundaryTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePublicDispositionTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePreAnchorEvidenceTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeSameCallbackTests.swift`;
- this document.

No dependency-owned source is modified.

## Battery authority boundary

The battery-evidence parent seals `verifiedVehicleMeasurement` authority. Generic app/import code cannot manufacture a verified `BatteryEvidenceObservation` through public construction or generic Codable.

Only `verifiedVehicleMeasurement + stateOfChargePercent` may become authoritative adaptive-range SoC through this pipeline. Stock-app, Simulator, derived, presentation-only, voltage, current, power, and charging-state evidence never becomes percentage-learning evidence.

No voltage→SoC conversion, Wh/mi, battery-health inference, or physical ES80 semantic is introduced.

## Upstream range-core authority blocker

Current adaptive-range parent #40 still allows authority bypass outside this worker's files through raw/generic authoritative `BatterySOCReading` construction/transport and generic `AdaptiveBatteryRangeEstimate.socProvenance` transport.

The v7 control plane has a compatibility-safe closure design: raw SoC construction module-internal, estimated-only public construction, generic authoritative SoC encode/decode rejected, and generic authoritative derived-estimate transport rejected. #38 tested the SoC portion in a disposable Swift 6.2.1 parent contract without modifying #40; its trusted in-module adapter remained compatible and external raw-authoritative construction failed as required.

Production integration remains blocked until an accepted #40 descendant owns and proves that seal.

## Public API boundary

The evidence-bearing `BatteryAdaptiveRangeEvidenceAction` is module-internal. External callers see only:

- `BatteryAdaptiveRangeLearningPipeline` commands;
- payload-free `BatteryAdaptiveRangePipelineDisposition`;
- read-only `candidateLearningWindow`.

Public dispositions describe pipeline ingestion, not learned-history acceptance:

- `ignored`;
- `continuityReset`;
- `authoritativeSOCIngested`;
- `continuityResetAndAuthoritativeSOCIngested`.

The old ambiguous `learningWindow` spelling is internal only. An emitted candidate does not mutate learned history until explicit `AdaptiveBatteryRangeModel.ingest`.

External client and symbol-graph probes keep the evidence action, result initializer, assembler state, continuity-coalescing state, and old `learningWindow` spelling out of the public API.

## Continuity and atomicity

Every explicit `.afterUnobservedInterval` marks a continuity break. A spontaneous boundary may establish a fresh lower process-uptime epoch after relaunch.

For each observation the pipeline copy-validates stream + assembler state and commits only if the entire transition succeeds. Stream failure cannot mutate the assembler; assembler failure cannot partially advance stream state.

### Repeated boundary tags from one receipt

One transport callback may normalize into several battery fields with the same receipt uptime. An upstream normalizer may conservatively attach `.afterUnobservedInterval` to more than one of those fields.

Before this hardening, a SoC boundary could establish a clean post-gap anchor and a later voltage field from the same callback carrying the same boundary could reset that fresh anchor away. The failure was reproduced locally before the fix.

`BatteryAdaptiveRangeEvidenceBridge` now tracks the receipt uptime whose continuity reset has already been applied to the range assembler. Repeated boundary tags at that **same receipt uptime** suppress only the duplicate reset:

- repeated non-SoC boundary → `ignored` for range assembly;
- repeated verified SoC boundary → `authoritativeSOCIngested` without another reset.

The rule is deliberately narrow:

- continuous evidence at a greater uptime clears the coalescing receipt marker;
- `markUnobservedInterval()` clears it immediately, so a genuinely new boundary is never suppressed even if a fresh epoch happens to reuse the same numeric uptime;
- duplicate authoritative SoC at one uptime remains subject to assembler monotonic-authoritative ordering and cannot silently rebase.

Regressions cover both repeated-boundary field orders, same-uptime ordinary voltage↔SoC ordering, fresh lower-uptime restart, marker clearing, and later clean window closure.

### Equal-uptime authoritative rebound

A second authoritative SoC at the same uptime cannot rebase the authoritative cursor. `80@10 → 77@20 → 79@20` rejects the rebound atomically, preserves prior partial/gap evidence, and later `76@21` can still close the untouched `80→76` span.

## Distance semantics

#38 does not select ODO, GPS, or live speed integration. Distance is higher-layer **caller-classified**, not authority-sealed.

Existing NembraCore already has `RideDistanceSource`, `RideDistanceCoverage`, `RideDistanceEvidence`, reconciliation status/confidence, and finalized live-distance segments. This lane does not invent a fake trusted-distance token around an unsealed distance chain.

Safe rules:

- omitted pipeline and assembler coverage defaults to `.unknown`, never `.complete`;
- `.complete` must be explicit only when the producing subsystem has complete-coverage evidence;
- `.partial` and `.unknown` cannot train the model;
- provider route geometry and presentation interpolation never become measured ride distance.

Pre-anchor partial distance and transport-gap state are proven to be discarded by the first verified SoC anchor.

## Reachable model rejection matrix

Every realistically reachable rejection from a legitimate #38 candidate is covered:

- `incompleteDistanceEvidence` — omitted/partial/unknown coverage;
- `transportGap`;
- `insufficientSOCConsumption` — stricter model policy after assembly;
- `insufficientDistance` — stricter model distance policy after assembly;
- `efficiencyOutlier`;
- `numericalOverflow`.

All leave model history unchanged and keep the emitted assembler span closed, so rejected distance never replays into later learning.

`nonAuthoritativeSOC` and `nonConsumptionWindow` are structurally unreachable from a legitimate #38 candidate.

## Exact normalized boundary

Verified `100% @1` → 1,000 m complete → verified `0% @2` under an exact 100-point / 1,000 m policy emits exactly 100 consumed points and trains one 10 m/% sample. The bridge introduces no empty/full SoC off-by-one distortion.

## Focused validation

Supplemental Swift 6.2.1 validation is split by parent contract.

**Current unsealed range parent + reconciled #54 assembler**
- **28/28 debug + 28/28 release passed** across 12 suites.

**Proposed authority-sealed range parent + reconciled #54 assembler**
- same 28 #38 cases plus three parent-seal probes: **31/31 debug + 31/31 release passed** across 13 suites;
- estimated-only public SoC round trip passed;
- authoritative SoC generic encode/decode rejected;
- external raw-authoritative SoC construction failed as required.

Additional API evidence:
- legitimate external client passes;
- external forged result/action/old-window probes are blocked;
- symbol graph excludes evidence action, old window, assembler/coalescing state and exports only intended public pipeline surfaces.

These are supplemental software checks, not repository-wide Xcode acceptance.

## Merge boundary

PR #38 remains a dependent draft on a synthetic review base.

Before production merge:

1. #40 reaches an accepted exact head with authoritative SoC and derived-estimate generic authority sealed;
2. #54 is reconciled/accepted on that exact range parent;
3. #34 reaches its accepted/final authority-sealed battery-evidence head;
4. #38 is rebuilt on those exact accepted parents;
5. the eight worker files are revalidated;
6. retarget to `main`, mark ready, and freeze final SHA;
7. exact final SHA passes NembraCore + Xcode 27 / iPhone 12 / iOS 27 Simulator acceptance;
8. merge only with expected-head protection.

Queued, skipped, stale-head, or missing workflow evidence is never green.

## Hardware status

**IMPLEMENTED/TESTED IN SOFTWARE ONLY.** Physical current-generation AOVOPRO ES80 SoC source/resolution/cadence, voltage/current/power semantics, charging behavior, continuity behavior, stable scooter identity, and final production distance-source selection remain unverified.
