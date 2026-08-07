# Battery Evidence → Adaptive Range Learning Pipeline

Status: dependent software truth/integration layer. No physical AOVOPRO ES80 battery semantic is verified by this document or implementation.

## Purpose

Nembra separates battery-range learning into distinct truth domains:

1. **Battery evidence** owns normalized battery semantics, provenance, continuity, and process-local ordering.
2. **Adaptive range core** owns learned percentage-based efficiency and rejects untrustworthy windows.
3. **Window assembly** owns ephemeral SoC anchors, classified distance, coverage degradation, and observed transport-gap evidence.
4. **This lane** owns only the seams between those domains.

This lane does not own adaptive-model persistence, per-scooter identity, BLE/Tuya decoding, distance-source selection, or UI presentation.

## V7 lane lineage

The lane is the incumbent Epoch-1 `battery-range-evidence-bridge` worker under Nembra Swarm OS v7.

Its synthetic review base is `9eca0d5622ed694bc88b84d63b6320b4ec24eb0a`. That base composes the then-current adaptive-range/window and authority-sealed battery-evidence dependencies so the worker-owned delta remains independently reviewable.

Live v7 parent movement is classified before reconciliation:

- parent changes that alter a consumed semantic contract require a narrow rebuild/revalidation;
- docs/workflow/test-only ancestry movement does not justify churn by itself;
- final production integration still rebuilds on the exact accepted parent heads.

## Worker-owned files

Current worker delta is six isolated paths:

- `Packages/NembraCore/Sources/NembraCore/BatteryAdaptiveRangeEvidenceAdapter.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeEvidenceAdapterTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePipelineIntegrationTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeModelBoundaryTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePublicDispositionTests.swift`;
- this document.

No dependency-owned source is modified by this worker.

## Authority seal inherited from battery evidence

The battery-evidence parent prevents generic application/import code from self-asserting `verifiedVehicleMeasurement`:

- raw `BatteryEvidenceObservation` construction is module-internal;
- the public non-authoritative factory rejects `.verifiedVehicleMeasurement`;
- generic Codable import/export cannot restore verified authority from serialized data.

This pipeline consumes that sealed observation boundary and exposes no alternate verified-observation constructor.

Only `verifiedVehicleMeasurement + stateOfChargePercent` may become authoritative adaptive-range SoC through this pipeline.

Continuous stock-app, Simulator, derived, presentation-only, voltage, current, power, and charging-state evidence never becomes percentage-learning evidence.

No voltage→SoC conversion, energy integration, Wh/mi, or battery-health inference exists here.

## Upstream authority dependency still open

A v7 cross-lane review found an upstream range-core trust-boundary gap outside this worker's owned files:

- `BatterySOCReading` currently has a public initializer;
- public `BatterySOCProvenance.authoritativeMeasurement` can therefore be selected by external callers;
- the window assembler also has a public SoC ingest API.

That combination can bypass the sealed `BatteryEvidenceObservation` path if generic app code constructs an authoritative range reading directly.

The range-core owner has been notified under the v7 control plane. #38 does not modify foreign parent files. Production integration is blocked until the accepted range parent seals authoritative `BatterySOCReading` construction/import consistently with the battery-evidence authority model.

## Public API boundary

External production consumers are forced through `BatteryAdaptiveRangeLearningPipeline` for this lane's evidence→window path.

Internal-only worker seams:

- `BatteryAdaptiveRangeEvidenceAction`;
- `BatteryAdaptiveRangeEvidenceAdapter`;
- `BatteryAdaptiveRangeEvidenceBridge`;
- stream-validator state;
- ephemeral `BatteryRangeLearningWindowAssembler` state;
- `BatteryAdaptiveRangePipelineResult` initializer.

The internal action may carry a validated authoritative SoC because the pipeline needs that payload to drive the assembler. It is deliberately **not exported**.

External callers receive only:

- pipeline commands;
- `BatteryAdaptiveRangePipelineDisposition`, a payload-free transition classification;
- the read-only optional learning window on a pipeline-created result.

Public dispositions are:

- `ignored`;
- `continuityReset`;
- `authoritativeSOCAccepted`;
- `continuityResetAndAuthoritativeSOCAccepted`.

A public disposition can describe what happened, but it cannot carry or manufacture an authoritative SoC reading.

External-client and symbol-graph checks verify:

- `BatteryAdaptiveRangeEvidenceAction` is absent from the exported API;
- `BatteryAdaptiveRangePipelineDisposition` and `BatteryAdaptiveRangePipelineResult` are exported;
- ephemeral assembler state remains absent from the exported pipeline surface;
- external code cannot construct a pipeline result through its internal initializer.

A negative external compile probe attempting to name `BatteryAdaptiveRangeEvidenceAction` fails because the type is not visible outside NembraCore.

## Continuity rule

`afterUnobservedInterval` is evidence about stream coverage, independent of whether the attached value is authoritative.

Therefore **every explicit continuity boundary resets in-flight range learning**.

This includes a boundary carried by:

- stock-app correlation evidence;
- simulation/derived/presentation evidence;
- verified non-SoC electrical evidence;
- verified SoC.

The attached number is promoted only if it independently satisfies the verified-SoC authority rule.

A spontaneous explicit boundary is accepted conservatively even when the higher layer did not pre-call `markUnobservedInterval()`. It may start a numerically lower process-uptime epoch after relaunch, and the assembler is reset at the same seam.

## Atomic pipeline

For each observation, `BatteryAdaptiveRangeLearningPipeline`:

1. copies the evidence bridge and window assembler;
2. validates stream continuity/uptime on the candidate bridge;
3. derives an internal truth action;
4. applies that action to the candidate assembler;
5. commits **both** candidates only if the whole transition succeeds;
6. returns a payload-free public disposition plus any emitted learning window.

A stream failure cannot mutate the assembler, and an assembler failure cannot partially advance the accepted stream baseline.

### Equal-uptime authoritative rebound

Battery evidence may legitimately contain multiple normalized fields from one callback at the same process uptime. The range assembler is stricter for repeated authoritative SoC: a second measured SoC at the same uptime cannot advance or rebase the authoritative cursor.

A dedicated pipeline regression proves:

- `80 @ 10` establishes the anchor;
- `77 @ 20` advances the latest authoritative cursor without yet closing the high-threshold span;
- a rebound `79 @ 20` fails with `nonMonotonicAuthoritativeSOC`;
- the whole pipeline remains byte-for-byte equal to its pre-failure state;
- later `76 @ 21` can still close the untouched `80 → 76` span;
- partial coverage and observed transport-gap evidence remain sticky through that recovery.

This is the evidence→window atomic seam implied by the assembler parent's same-timestamp hardening.

## Distance and latest-authoritative semantics

The pipeline delegates distance math to the assembler and does not select ODO versus GPS.

Preserved behavior includes:

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

This preserves source compatibility without allowing omission to silently assert trustworthy distance. A caller that has actually proven complete coverage must pass `.complete` explicitly.

A model-boundary regression omits coverage on a 300 m / 3% candidate and verifies:

- the emitted candidate is `.unknown` coverage;
- the adaptive model rejects it as `incompleteDistanceEvidence`;
- learned history remains unchanged.

Intentional complete-distance regressions pass `.complete` explicitly.

## Missing evidence versus observed transport gap

These remain deliberately different:

- `markUnobservedInterval()` means battery evidence continuity itself is unknown, so all ephemeral assembler state is discarded immediately and the next observation must carry a boundary;
- `recordTransportGap()` means a non-connected vehicle state was actually observed inside an otherwise represented span, so that flag remains on the candidate for model rejection.

The pipeline never silently converts one classification into the other.

## Model boundary remains separate

The pipeline stops at `BatteryRangeLearningWindow`. It does not own or persist `AdaptiveBatteryRangeModel`.

That separation matters because durable learned history eventually requires a verified stable per-physical-scooter identity.

End-to-end model-boundary tests prove:

- clean complete/no-gap candidate → accepted;
- omitted coverage → unknown coverage, rejected as incomplete distance, model unchanged;
- explicit partial candidate → rejected as incomplete distance, model unchanged;
- explicit unknown candidate → rejected as incomplete distance, model unchanged;
- observed transport-gap candidate → rejected as transport gap, model unchanged;
- efficiency outlier → rejected without learned-history mutation.

A rejected emitted span nevertheless remains closed by the assembler. Its distance is never replayed into a later clean learning window.

## Focused validation

Supplemental Swift 6.2.1 contract validation currently includes:

- earlier bridge-focused harness: **10/10 passed**;
- earlier evidence→window harness: **6/6 passed**;
- current authority-sealed seam/model/public-API harness: **17/17 debug passed** and **17/17 release passed** across 6 suites;
- legitimate external non-authoritative client: passed using the payload-free public disposition;
- external verified-observation construction negative probe: blocked as required by the battery-evidence parent contract;
- external forged-result negative probe: blocked as required;
- external evidence-action naming/forging negative probe: blocked as required;
- public symbol graph audit: evidence-bearing action absent, public disposition/result present, assembler state absent.

These are supplemental software checks, not repository-wide Xcode acceptance.

## Merge boundary

This PR remains a dependent draft on a synthetic review base.

Before production merge:

1. adaptive-range parent reaches an accepted exact head **with authoritative SoC construction/import sealed**;
2. assembler parent reaches an accepted exact head on that range parent;
3. battery-evidence parent reaches its accepted/final authority-sealed head;
4. this lane is rebuilt on those exact parents;
5. the six worker files are revalidated;
6. the PR is retargeted to production `main` and marked ready;
7. the unchanged final SHA passes exact-head Xcode 27 / iPhone 12 Simulator QA with durable `Nembra/Xcode27 Exact Head` success;
8. merge uses expected-head protection.

Queued, skipped, stale-head, or missing workflow evidence is never considered green.

## Hardware status

**IMPLEMENTED/TESTED IN SOFTWARE ONLY.** Physical current-generation AOVOPRO ES80 SoC source/resolution/cadence, voltage/current/power semantics, charging behavior, continuity behavior, and stable scooter identity remain unverified.
