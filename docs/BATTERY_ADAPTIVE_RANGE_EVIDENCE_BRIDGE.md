# Battery Evidence → Adaptive Range Learning Pipeline

Status: dependent software truth/integration layer. No physical AOVOPRO ES80 battery semantic is verified by this document or implementation.

## Purpose

Nembra separates battery-range learning into distinct truth domains:

1. **Battery evidence** owns normalized battery semantics, provenance, continuity, and process-local ordering.
2. **Adaptive range core** owns learned percentage-based efficiency and rejects untrustworthy windows.
3. **Window assembly** owns ephemeral SoC anchors, classified distance, coverage degradation, and observed transport-gap evidence.
4. **This lane** owns only the seams between those domains.

This lane does not own adaptive-model persistence, per-scooter identity, BLE/Tuya decoding, distance-source selection, or UI presentation.

## Live dependency lineage

The synthetic review base is composed from exact active/frozen dependency artifacts rather than modifying another worker's branch:

- adaptive-range/window integration PR #54 at `ec2a920eeaa9d435a0e4a6885c314f0d71aa2375`;
- authority-sealed battery-evidence PR #34 at `8e7ecdb7a6798ed23b147173d169dd35614d6ee7`;
- #54 carries coordinator adaptive-range recovery #40 and current `main@045a7a7c466e049d933439f608d387658f111ebf` in ancestry.

Synthetic dependency commit: `9eca0d5622ed694bc88b84d63b6320b4ec24eb0a`.

The worker-owned delta remains five files:

- `Packages/NembraCore/Sources/NembraCore/BatteryAdaptiveRangeEvidenceAdapter.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeEvidenceAdapterTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePipelineIntegrationTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeModelBoundaryTests.swift`;
- this document.

If any dependency moves or lands, this lane must reconcile to the accepted exact parent before final QA.

## Authority seal

PR #34 now prevents generic application/import code from self-asserting `verifiedVehicleMeasurement`.

`BatteryEvidenceObservation` has:

- an internal raw initializer used only inside the trusted NembraCore boundary;
- a public `nonAuthoritative(...)` factory that rejects `.verifiedVehicleMeasurement`;
- decoded imported observations that reject persisted `.verifiedVehicleMeasurement` rather than trusting serialized authority.

That means this pipeline can consume authoritative SoC only after a future trusted physical adapter inside the authority boundary creates it. Stock-app correlation, Simulator fixtures, derived estimates, presentation state, or imported JSON cannot manufacture measured scooter truth.

This worker preserves that seal. It does not expose a new authority constructor.

## Public API boundary

External production consumers are intentionally forced through `BatteryAdaptiveRangeLearningPipeline`.

Internal-only worker seams:

- `BatteryAdaptiveRangeEvidenceAdapter`;
- `BatteryAdaptiveRangeEvidenceBridge`;
- stream-validator state;
- ephemeral `BatteryRangeLearningWindowAssembler` state;
- `BatteryAdaptiveRangePipelineResult` initializer.

Public callers may:

- create a pipeline;
- mark a known unobserved interval;
- record caller-classified distance;
- record an observed transport gap;
- submit a `BatteryEvidenceObservation`;
- inspect the returned read-only action/window result.

A Swift 6.2.1 external-client build and symbol-graph audit confirmed that the raw adapter/bridge/assembler state/result initializer are not exported.

Two negative external compile probes also pass by **failing as required**:

- raw construction of a `.verifiedVehicleMeasurement` observation fails because the initializer is internal;
- direct construction of `BatteryAdaptiveRangePipelineResult` fails because its initializer is internal.

The legitimate public non-authoritative path compiles/runs and is ignored by range learning.

## Value-authority rule

Only `verifiedVehicleMeasurement + stateOfChargePercent` can become `BatterySOCReading(provenance: .authoritativeMeasurement)`.

The conversion preserves:

- the normalized percentage exactly;
- process-local receipt uptime;
- authoritative provenance.

Continuous stock-app, Simulator, derived, presentation-only, voltage, current, power, and charging-state evidence never becomes percentage-learning evidence.

No voltage→SoC conversion, energy integration, Wh/mi, or battery-health inference exists here.

## Continuity rule

`afterUnobservedInterval` is evidence about stream coverage, independent of whether the attached value is authoritative.

Therefore **every explicit continuity boundary resets in-flight range learning**.

This includes a boundary carried by:

- stock-app correlation evidence;
- simulation/derived/presentation evidence;
- verified non-SoC electrical evidence;
- verified SoC.

The attached number is promoted only if it independently satisfies the verified-SoC authority rule.

A spontaneous explicit boundary is also accepted conservatively even when the higher layer did not pre-call `markUnobservedInterval()`. It may start a numerically lower uptime epoch after process relaunch, and the assembler is reset at the same seam.

## Atomic pipeline

For each observation, `BatteryAdaptiveRangeLearningPipeline`:

1. copies the evidence bridge and window assembler;
2. validates stream continuity/uptime on the candidate bridge;
3. derives a truth action;
4. applies that action to the candidate assembler;
5. commits **both** candidates only if the whole transition succeeds.

Actions:

- `ignore` → no assembler mutation;
- `resetContinuity` → reset assembler;
- `ingestSOC` → ingest verified SoC under the caller's current policy;
- `resetContinuityAndIngestSOC` → reset then establish the new verified anchor.

A stream failure cannot mutate the assembler, and an assembler failure cannot partially advance the accepted stream baseline.

## Distance and latest-authoritative semantics

The pipeline delegates distance math to PR #54's assembler and does not select ODO versus GPS.

Preserved parent behavior includes:

- coverage degrades monotonically `complete → partial → unknown`;
- invalid/nonfinite/negative deltas fail atomically;
- finite-addition overflow fails before accumulator mutation;
- `latestAuthoritativeSOC` is distinct from the span anchor;
- `80 → 77 → 79` measured recovery rebases at `79` and discards preceding distance;
- continuous non-authoritative SoC never advances the authoritative cursor;
- distance accumulated after a non-authoritative post-gap boundary but before the first verified SoC anchor is discarded when that verified anchor arrives;
- policy thresholds are evaluated live at each SoC evaluation rather than frozen when the anchor was created.

### Omitted distance coverage fails closed

The public pipeline intentionally defaults an omitted `coverage:` argument to `.unknown`, **not `.complete`**.

This keeps older call sites source-compatible without allowing omission to silently assert trustworthy distance. A caller that has actually proven complete coverage must pass `.complete` explicitly.

A dedicated model-boundary regression omits coverage on a 300 m / 3% candidate and verifies:

- the emitted candidate is `.unknown` coverage;
- the adaptive model rejects it as `incompleteDistanceEvidence`;
- learned history remains unchanged.

Intentional complete-distance regressions, including outlier lifecycle tests, now pass `.complete` explicitly.

## Missing evidence versus observed transport gap

These are deliberately different:

- `markUnobservedInterval()` means battery evidence continuity itself is unknown, so all ephemeral assembler state is discarded immediately and the next observation must carry a boundary;
- `recordTransportGap()` means a non-connected vehicle state was actually observed inside an otherwise represented span, so that flag remains on the candidate for model rejection.

The pipeline never silently converts one classification into the other.

## Model boundary remains separate

The pipeline stops at `BatteryRangeLearningWindow`. It does not own or persist `AdaptiveBatteryRangeModel`.

That separation matters because durable learned history eventually requires a verified stable per-physical-scooter identity.

End-to-end model-boundary tests prove:

- clean complete/no-gap pipeline candidate → accepted;
- omitted coverage → unknown coverage, rejected as incomplete distance, model unchanged;
- explicit partial candidate → rejected as incomplete distance, model unchanged;
- explicit unknown candidate → rejected as incomplete distance, model unchanged;
- observed transport-gap candidate → rejected as transport gap, model unchanged.

### Rejected outlier lifecycle

A model rejection also must not reopen an already emitted assembler span.

The seam regression establishes a 100 m/% baseline, emits a later 300 m/% candidate, and verifies the model rejects it as `efficiencyOutlier` without mutating learned history. The assembler has nevertheless already closed that candidate at the new SoC anchor. A subsequent clean 300 m / 3% span is emitted from the new anchor only; the rejected span's 900 m is never replayed.

## Focused validation

Supplemental Swift 6.2.1 contract validation currently includes:

- earlier bridge-focused harness: **10/10 passed**;
- earlier evidence→window harness: **6/6 passed**;
- authority-sealed latest assembler/seam/model harness: **15/15 debug passed** and **15/15 release passed**;
- external legitimate non-authoritative client: passed;
- external verified-authority negative compile probe: failed as required;
- external forged-result negative compile probe: failed as required;
- public symbol graph audit: passed.

The reduced local model stub initially lacked the real parent's outlier check, causing the new lifecycle test to fail for the wrong reason. After matching the real `AdaptiveBatteryRangeModel.ingest` outlier/weighted-history boundary, the outlier lifecycle passed. The subsequent omitted-coverage regression raised the current combined contract suite to 15/15 in both debug and release.

This is supplemental software evidence, not repository-wide Xcode acceptance.

## Merge boundary

This PR remains a dependent draft on a synthetic review base.

Before production merge:

1. adaptive-range recovery reaches an accepted exact head;
2. PR #54 reaches an accepted assembler head on that parent;
3. PR #34 reaches its accepted/final authority-sealed evidence head;
4. this lane is rebuilt on those exact parents;
5. the five worker files are revalidated;
6. the PR is retargeted to production `main` and marked ready;
7. the unchanged final SHA passes exact-head Xcode 27 / iPhone 12 Simulator QA with durable `Nembra/Xcode27 Exact Head` success;
8. merge uses expected-head protection.

GitHub Actions is currently degraded/backlogged; missing workflow/scheduler runs are never considered green.

## Hardware status

**IMPLEMENTED/TESTED IN SOFTWARE ONLY.** Physical 2025-generation AOVOPRO ES80 SoC source/resolution/cadence, voltage/current/power semantics, charging behavior, continuity behavior, and stable scooter identity remain unverified.