# Battery Evidence → Adaptive Range Learning Pipeline

Status: dependent software truth/integration layer. No physical AOVOPRO ES80 battery semantic is verified by this implementation.

## V7 ownership / dependency state

Incumbent lane: `battery-range-evidence-bridge`, Epoch 1, worker `chat-c9m4x`, PR #38.

Synthetic review base: `b3d78cb5475049785318c026781f5a68321a8785`.

That base carries exact assembler parent #54 head `76880f826604e941cd4d75d09edf2619fd774d26`, including its semantic fail-closed `recordDistance(... coverage: = .unknown)` behavior. Parent docs/workflow/test-only movement does not trigger churn rebases under Swarm OS v7; consumed semantic movement does.

Current worker delta is eight isolated paths:

- `Packages/NembraCore/Sources/NembraCore/BatteryAdaptiveRangeEvidenceAdapter.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeEvidenceAdapterTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePipelineIntegrationTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeModelBoundaryTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePublicDispositionTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePreAnchorEvidenceTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeSameCallbackTests.swift`;
- this document.

No dependency-owned source is modified by this worker.

## Battery authority boundary

The battery-evidence parent seals `verifiedVehicleMeasurement` authority:

- raw verified `BatteryEvidenceObservation` construction is module-internal;
- public non-authoritative construction rejects `.verifiedVehicleMeasurement`;
- generic Codable cannot create or carry verified observation authority.

Only `verifiedVehicleMeasurement + stateOfChargePercent` may become authoritative adaptive-range SoC through this pipeline. Stock-app, Simulator, derived, presentation-only, voltage, current, power, and charging-state evidence never becomes percentage-learning evidence.

No voltage→SoC conversion, Wh/mi, battery-health inference, or physical ES80 semantic is introduced.

## Upstream range-core authority blocker

Current adaptive-range parent #40 still allows authority bypass outside this worker's files:

- raw public `BatterySOCReading(... provenance: .authoritativeMeasurement ...)` construction;
- generic authoritative `BatterySOCReading` encode/decode;
- generic `AdaptiveBatteryRangeEstimate` import/export can restore `socProvenance == .authoritativeMeasurement`.

The v7 control plane has a compatibility-safe closure design: make raw SoC construction module-internal, expose estimated-only public construction, reject generic authoritative SoC transport, and reject generic authoritative derived-estimate transport. #38 tested the SoC portion of that proposed seal in a disposable Swift 6.2.1 parent contract without modifying #40; its trusted in-module adapter remained compatible and external raw-authoritative construction failed as required.

Production integration remains blocked until an accepted #40 descendant owns and proves that seal.

## Public API boundary

The evidence-bearing `BatteryAdaptiveRangeEvidenceAction` is module-internal. External callers see only:

- `BatteryAdaptiveRangeLearningPipeline` commands;
- payload-free `BatteryAdaptiveRangePipelineDisposition`;
- read-only `candidateLearningWindow` on a pipeline-created result.

Public dispositions describe pipeline ingestion, not learned-history acceptance:

- `ignored`;
- `continuityReset`;
- `authoritativeSOCIngested`;
- `continuityResetAndAuthoritativeSOCIngested`.

The old ambiguous `learningWindow` spelling remains internal only. `candidateLearningWindow` is deliberate: an emitted window can still be rejected by `AdaptiveBatteryRangeModel`.

Checked-in tests prove a valid candidate leaves a separate model completely unlearned until the caller explicitly invokes `model.ingest(candidate, policy:)`.

External client/symbol-graph probes prove the evidence action, result initializer, assembler state, and old `learningWindow` spelling are not publicly forgeable/visible while the disposition/result/candidate window remain usable.

## Continuity and atomicity

Every explicit `.afterUnobservedInterval` boundary resets in-flight range learning regardless of the attached value's truth role. A spontaneous boundary may establish a fresh lower process-uptime epoch after relaunch.

For each battery observation the pipeline copy-validates the stream and assembler, applies the internal action, and commits both only if the entire transition succeeds. Stream failure cannot mutate the assembler; assembler failure cannot partially advance stream state.

### Equal-uptime authoritative rebound

A second authoritative SoC at the same uptime cannot rebase the authoritative cursor. A regression proves `80@10 → 77@20 → 79@20` rejects the rebound atomically, preserves prior partial/gap evidence, and later `76@21` can still close the untouched `80→76` span.

### Multi-field same-callback evidence

Battery callbacks may legitimately yield multiple normalized fields with one receipt uptime.

Two regressions cover the seam:

1. `80% @100`, then 300 m complete, then verified voltage `40.0 V @200`, then verified `77% @200`: voltage is ignored for percentage learning but advances stream receipt order; the same-uptime SoC still closes the clean `80→77` 300 m candidate.
2. old `80% @100` span with partial/gap state, then verified voltage `39.5 V @1` carrying `.afterUnobservedInterval`, then verified `59% @1`: the voltage boundary resets the old epoch and clears old distance/gap state; same-callback SoC establishes the new 59% anchor; later `56% @2` closes only the fresh 300 m complete span.

This preserves equal-uptime multi-field callbacks without allowing same-uptime duplicate authoritative SoC rebasing.

## Distance semantics

#38 does not select ODO, GPS, or live speed integration. Distance is supplied by a higher layer and remains **caller-classified**, not authority-sealed.

Existing NembraCore distance architecture already includes `RideDistanceSource`, `RideDistanceCoverage`, `RideDistanceEvidence`, reconciliation status/confidence, and finalized live-distance segments. The underlying speed/distance chain is not sealed like battery evidence, so this lane does not invent a fake trusted-distance token.

Safe rules:

- omitted pipeline and assembler coverage defaults to `.unknown`, never `.complete`;
- `.complete` must be stated explicitly only when the producing subsystem has evidence for complete coverage;
- `.partial` and `.unknown` cannot train the model;
- provider route geometry and presentation interpolation must never be relabeled as measured ride distance.

Pre-anchor partial distance and transport-gap state are explicitly proven to be discarded by the first verified SoC anchor. No pre-anchor evidence can taint the next consumption window.

## Reachable model rejection matrix

For a legitimate #38-produced candidate, every realistically reachable rejection is covered:

- `incompleteDistanceEvidence` — omitted/partial/unknown coverage;
- `transportGap`;
- `insufficientSOCConsumption` — stricter model policy after assembly;
- `insufficientDistance` — stricter model distance policy after assembly;
- `efficiencyOutlier`;
- `numericalOverflow`.

All prove model history remains unchanged and the emitted assembler span stays closed, so rejected distance never replays into a later clean window.

`nonAuthoritativeSOC` is structurally unreachable because #38 emits only authoritative endpoints. `nonConsumptionWindow` is structurally unreachable from a legitimate candidate because valid `minimumConsumedPercentagePoints` is strictly positive and the assembler does not emit below it.

## Exact normalized boundary

A full vertical regression drives verified `100% @1` → 1,000 m complete → verified `0% @2` under an exact 100-point / 1,000 m policy. The pipeline emits exactly 100 consumed percentage points and the model accepts one 10 m/% sample. The evidence bridge introduces no empty/full SoC off-by-one distortion.

## Focused validation

Supplemental Swift 6.2.1 validation is split by parent contract.

**Current unsealed range parent + reconciled #54 assembler**
- **25/25 debug + 25/25 release passed** across 12 suites.

**Proposed authority-sealed range parent + reconciled #54 assembler**
- the same 25 #38 cases plus three parent-seal compatibility probes: **28/28 debug + 28/28 release passed** across 13 suites;
- estimated-only public SoC round trip passed;
- authoritative SoC generic encode rejected;
- forged authoritative SoC generic decode rejected;
- external raw-authoritative SoC construction failed to compile as required.

Additional API evidence:
- earlier bridge-focused harness: 10/10 passed;
- earlier evidence→window harness: 6/6 passed;
- legitimate external client passed with payload-free disposition + `candidateLearningWindow`;
- external forged result/action/old-window probes are blocked;
- symbol graph excludes evidence action/old window/assembler state and exports disposition/result/candidate window.

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
