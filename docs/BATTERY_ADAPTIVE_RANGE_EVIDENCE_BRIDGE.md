# Battery Evidence → Adaptive Range Learning Pipeline

Status: dependent software truth/integration layer. No physical AOVOPRO ES80 battery semantic is verified by this implementation.

## V7 ownership / exact dependency state

Incumbent lane: `battery-range-evidence-bridge`, Epoch 1, worker `chat-c9m4x`, PR #38.

Synthetic review base: `0bd09f959be40b7e812c7ef9ae8b8de34707c733`.
Current reconciled worker lineage started at head `f75a32edc70d48e3a017f4c3eb9339166a12aca3` before this documentation checkpoint.

The synthetic base now carries both consumed semantic parents:

- exact assembler parent #54 `76880f826604e941cd4d75d09edf2619fd774d26`, including fail-closed omitted distance coverage `.unknown`;
- exact battery-evidence parent #34 `accb40823a6fc830332c240b14019781a85f9fee`, including the direct-source authority seal.

Base→head review isolation was re-proved after reconciliation: exactly nine #38-owned files, with no #34/#54 dependency paths leaking into the worker diff.

Current worker-owned paths:

- `Packages/NembraCore/Sources/NembraCore/BatteryAdaptiveRangeEvidenceAdapter.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeEvidenceAdapterTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePipelineIntegrationTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeModelBoundaryTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePublicDispositionTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePreAnchorEvidenceTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeSameCallbackTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeGapRecoveryTests.swift`;
- this document.

No dependency-owned source is modified by this worker.

## Battery authority boundary — exact #34 direct-source seal

The reconciled #34 parent now protects verified battery authority in both package and the app's direct-source build graph.

`BatteryEvidenceObservation` construction rules are:

- lowest-level role-selecting initializer is `fileprivate`;
- under `SWIFT_PACKAGE`, a package-internal initializer supports `@testable` package tests and trusted package sources;
- that package-only initializer is absent when the file is manually compiled into the Nembra app target;
- public `nonAuthoritative(...)` rejects `.verifiedVehicleMeasurement`;
- generic Codable rejects restored verified authority.

Therefore ordinary direct-source app files cannot manufacture a verified observation merely because the NembraCore source is compiled into the same app module.

#38 production code consumes `BatteryEvidenceObservation`; it does not introduce a cross-file verified-observation constructor. Only `verifiedVehicleMeasurement + stateOfChargePercent` may become authoritative adaptive-range SoC through the pipeline.

Stock-app, Simulator, derived, presentation-only, voltage, current, power, and charging-state evidence never becomes percentage-learning evidence. No voltage→SoC conversion, Wh/mi, battery-health inference, or physical ES80 semantic is introduced.

## Upstream range-core authority blocker

The remaining authority gap is parent #40, outside this worker's owned files:

- raw public `BatterySOCReading(... provenance: .authoritativeMeasurement ...)` construction;
- generic authoritative `BatterySOCReading` transport;
- generic `AdaptiveBatteryRangeEstimate.socProvenance` can transport authoritative provenance.

The v7 control plane has a compatibility-safe closure design: raw SoC construction module-internal, estimated-only public construction, generic authoritative SoC encode/decode rejected, and generic authoritative derived-estimate transport rejected. #38 tested the SoC portion in a disposable Swift 6.2.1 parent contract without editing #40; the trusted in-module adapter remained compatible and external raw-authoritative construction failed as required.

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

The old ambiguous `learningWindow` spelling is internal. An emitted candidate does not mutate learned history until explicit `AdaptiveBatteryRangeModel.ingest`.

External client/symbol-graph probes keep the evidence action, result initializer, assembler state, continuity-coalescing state, and old `learningWindow` spelling out of the public API.

## Continuity and atomicity

Every explicit `.afterUnobservedInterval` marks a continuity break. A spontaneous boundary may establish a fresh lower process-uptime epoch after relaunch.

The pipeline copy-validates stream + assembler state and commits only if the entire transition succeeds. Stream failure cannot mutate the assembler; assembler failure cannot partially advance stream state.

### Repeated boundary tags from one receipt

One resumed transport callback may normalize into several battery fields with the same receipt uptime, and a conservative normalizer may attach `.afterUnobservedInterval` to multiple fields from that one receipt.

A reproduced pre-fix bug showed that a SoC boundary could establish a fresh anchor and a later voltage boundary from the same callback could reset the fresh anchor away.

`BatteryAdaptiveRangeEvidenceBridge` now coalesces only duplicate resets for the same already-reset receipt uptime:

- repeated non-SoC boundary becomes observational for range assembly;
- repeated verified SoC retains SoC ingestion without another reset;
- advancing receipt time clears the coalescing marker;
- `markUnobservedInterval()` clears it immediately, so a genuinely new gap is never suppressed even if numeric uptime is reused;
- duplicate authoritative SoC at one uptime still fails authoritative ordering atomically.

Tests cover both ordinary same-callback field orders, both repeated-boundary field orders, fresh lower-uptime epochs, marker clearing, duplicate-SoC failure atomicity, and later clean closure.

### Missing-required-boundary recovery

After `markUnobservedInterval()`, distance may accumulate while the stream is waiting for its explicit boundary. A mistakenly continuous SoC fails `missingContinuityBoundary` without mutating bridge or assembler state. The later correct boundary resets that pending distance/coverage, establishes a clean anchor, and only fresh distance reaches the next candidate.

## Distance semantics

#38 does not select ODO, GPS, or live speed integration. Distance is higher-layer **caller-classified**, not authority-sealed.

Existing NembraCore already has `RideDistanceSource`, `RideDistanceCoverage`, `RideDistanceEvidence`, reconciliation status/confidence, and finalized live-distance segments. This lane does not invent a fake trusted-distance token around an unsealed distance chain.

Safe rules:

- omitted pipeline and assembler coverage defaults to `.unknown`, never `.complete`;
- `.complete` must be explicit only when the producing subsystem has complete-coverage evidence;
- `.partial` and `.unknown` cannot train the model;
- provider route geometry and presentation interpolation never become measured ride distance;
- pre-anchor partial distance and transport-gap state is discarded by the first verified SoC anchor.

## Reachable model rejection matrix

Every realistically reachable rejection from a legitimate #38 candidate is covered:

- `incompleteDistanceEvidence` — omitted/partial/unknown coverage;
- `transportGap`;
- `insufficientSOCConsumption` — stricter model policy after assembly;
- `insufficientDistance` — stricter model distance policy after assembly;
- `efficiencyOutlier`;
- `numericalOverflow`.

All leave model history unchanged and keep emitted assembler spans closed, so rejected distance never replays into later learning.

`nonAuthoritativeSOC` and `nonConsumptionWindow` are structurally unreachable from a legitimate #38 candidate.

## Exact normalized boundary

Verified `100% @1` → 1,000 m complete → verified `0% @2` under an exact 100-point / 1,000 m policy emits exactly 100 consumed points and trains one 10 m/% sample. The bridge introduces no empty/full SoC off-by-one distortion.

## Focused validation after #34 + #54 semantic reconciliation

Supplemental Swift 6.2.1 validation is split by range-parent contract.

**Current unsealed #40 + exact #34 direct-source battery seal + reconciled #54 assembler semantics**
- **30/30 debug + 30/30 release passed** across 12 suites.

**Proposed authority-sealed #40 + exact #34 direct-source battery seal + reconciled #54 assembler semantics**
- the same 30 #38 cases plus three #40 seal compatibility probes: **33/33 debug + 33/33 release passed** across 13 suites;
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
3. #34 reaches accepted/final exact direct-source authority-sealed head;
4. #38 is rebuilt on those exact accepted parents;
5. the nine worker files are revalidated;
6. retarget to `main`, mark ready, and freeze final SHA;
7. exact final SHA passes NembraCore + Xcode 27 / iPhone 12 / iOS 27 Simulator acceptance;
8. merge only with expected-head protection.

Queued, skipped, stale-head, or missing workflow evidence is never green.

## Hardware status

**IMPLEMENTED/TESTED IN SOFTWARE ONLY.** Physical current-generation AOVOPRO ES80 SoC source/resolution/cadence, voltage/current/power semantics, charging behavior, continuity behavior, stable scooter identity, and final production distance-source selection remain unverified.
