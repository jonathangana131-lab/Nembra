# Battery Evidence → Adaptive Range Learning Pipeline

Status: dependent software truth/integration layer. No physical AOVOPRO ES80 battery semantic is verified by this document or implementation.

## Purpose

Nembra keeps these truth domains separate:

1. **Battery evidence** — normalized battery semantics, provenance, continuity, and process-local ordering.
2. **Adaptive range core** — percent-based efficiency learning and rejection policy.
3. **Window assembly** — ephemeral SoC anchors, classified distance, coverage degradation, and transport-gap evidence.
4. **This lane** — the atomic seams between those domains.

This lane does not own adaptive-model persistence, stable scooter identity, BLE/Tuya decoding, distance-source selection, or UI presentation.

## V7 lane lineage

Incumbent Swarm OS v7 lane: `battery-range-evidence-bridge`, Epoch 1, worker `chat-c9m4x`, PR #38.

Synthetic review base: `9eca0d5622ed694bc88b84d63b6320b4ec24eb0a`.

The synthetic base keeps dependency code out of the effective worker diff. Under v7, parent movement is classified before reconciliation:

- consumed semantic contract changed → reconcile narrowly and revalidate;
- docs/workflow/test-only movement → do not churn-rebase merely for ancestry;
- final production integration → always rebuild on the exact accepted parent heads.

## Worker-owned files

Current worker delta is six isolated paths:

- `Packages/NembraCore/Sources/NembraCore/BatteryAdaptiveRangeEvidenceAdapter.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeEvidenceAdapterTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePipelineIntegrationTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeModelBoundaryTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePublicDispositionTests.swift`;
- this document.

No dependency-owned source is modified by this worker.

## Battery authority seal

The battery-evidence parent prevents generic application/import code from self-asserting `verifiedVehicleMeasurement`:

- raw verified `BatteryEvidenceObservation` construction is module-internal;
- the public non-authoritative factory rejects `.verifiedVehicleMeasurement`;
- generic Codable import/export cannot restore verified authority from serialized data.

This pipeline consumes that sealed observation boundary and exposes no alternate verified-observation constructor.

Only `verifiedVehicleMeasurement + stateOfChargePercent` may enter this pipeline as authoritative adaptive-range SoC.

Continuous stock-app, Simulator, derived, presentation-only, voltage, current, power, and charging-state evidence never becomes percentage-learning evidence.

No voltage→SoC conversion, energy integration, Wh/mi, or battery-health inference exists here.

## Upstream range-core authority dependency

A v7 cross-lane review found an upstream trust-boundary gap outside this worker's owned files:

- `BatterySOCReading` currently has a public initializer;
- public `BatterySOCProvenance.authoritativeMeasurement` can therefore be selected by external callers;
- generic Codable can import that provenance;
- the public window assembler accepts `BatterySOCReading` directly.

That combination can bypass the sealed `BatteryEvidenceObservation` path if generic app/framework code manufactures an authoritative range reading directly.

The adaptive-range owner has been notified through the v7 control plane. #38 does not modify foreign parent files. Production integration remains blocked until the accepted range parent seals authoritative `BatterySOCReading` construction/import consistently with the battery-evidence authority model.

## Public API boundary

External production consumers are intentionally forced through `BatteryAdaptiveRangeLearningPipeline` for this lane's evidence→window path.

Internal-only seams:

- `BatteryAdaptiveRangeEvidenceAction`;
- `BatteryAdaptiveRangeEvidenceAdapter`;
- `BatteryAdaptiveRangeEvidenceBridge`;
- stream-validator state;
- ephemeral `BatteryRangeLearningWindowAssembler` state;
- `BatteryAdaptiveRangePipelineResult` initializer;
- the old ambiguous `learningWindow` compatibility spelling.

The internal evidence action may carry an authoritative SoC because the pipeline needs that payload to drive the assembler. It is deliberately **not exported**.

External callers see:

- pipeline commands;
- payload-free `BatteryAdaptiveRangePipelineDisposition`;
- read-only `candidateLearningWindow` on a pipeline-created result.

Public dispositions describe the **pipeline stage**, not learned-history acceptance:

- `ignored`;
- `continuityReset`;
- `authoritativeSOCIngested`;
- `continuityResetAndAuthoritativeSOCIngested`.

“Ingested” means the verified SoC entered the ephemeral evidence/window pipeline. It does not mean `AdaptiveBatteryRangeModel` accepted a learning sample.

`candidateLearningWindow` is named deliberately. Emitting a window does not imply it entered learned history; model coverage, transport-gap, outlier, minimum-evidence, and numerical gates still apply.

A checked-in regression proves a valid emitted candidate leaves a separate `AdaptiveBatteryRangeModel` completely unlearned until the caller explicitly calls `model.ingest(candidate, policy:)`.

External-client and symbol-graph checks verify:

- `BatteryAdaptiveRangeEvidenceAction` is absent from the exported API;
- `BatteryAdaptiveRangePipelineDisposition` and `BatteryAdaptiveRangePipelineResult` are exported;
- `candidateLearningWindow` is exported;
- the old `learningWindow` spelling is not exported;
- ephemeral assembler state is not exported through the pipeline;
- external code cannot construct a pipeline result through its internal initializer.

Negative external compile probes block evidence-action naming/forging, forged pipeline results, and access to the old ambiguous `result.learningWindow` spelling.

## Continuity rule

`afterUnobservedInterval` is evidence about stream coverage, independent of whether the attached value is authoritative.

Therefore **every explicit continuity boundary resets in-flight range learning**.

This includes boundaries carried by stock-app, Simulator/derived/presentation, verified non-SoC electrical evidence, or verified SoC.

The attached number is promoted only if it independently satisfies the verified-SoC authority rule.

A spontaneous explicit boundary is accepted conservatively even when the higher layer did not pre-call `markUnobservedInterval()`. It may start a numerically lower process-uptime epoch after relaunch, and the assembler resets at the same seam.

## Atomic pipeline

For each observation, `BatteryAdaptiveRangeLearningPipeline`:

1. copies the evidence bridge and window assembler;
2. validates stream continuity/uptime on the candidate bridge;
3. derives an internal truth action;
4. applies that action to the candidate assembler;
5. commits **both** candidates only if the entire transition succeeds;
6. returns a payload-free public disposition plus any candidate learning window.

A stream failure cannot mutate the assembler, and an assembler failure cannot partially advance the accepted stream baseline.

### Equal-uptime authoritative rebound

Battery evidence may legitimately contain multiple normalized fields from one callback at the same process uptime. The range assembler is stricter for repeated authoritative SoC: a second measured SoC at the same uptime cannot advance or rebase the authoritative cursor.

A dedicated pipeline regression proves:

- `80 @ 10` establishes the anchor;
- `77 @ 20` advances the latest authoritative cursor without yet closing the span;
- `79 @ 20` fails with `nonMonotonicAuthoritativeSOC`;
- the entire pipeline remains equal to its pre-failure state;
- later `76 @ 21` closes the untouched `80 → 76` span;
- partial distance coverage and observed transport-gap evidence remain sticky through recovery.

## Distance semantics and provenance boundary

The pipeline does **not** select ODO versus GPS versus live speed integration. It receives distance that a higher layer has already classified.

Existing NembraCore distance architecture includes:

- `RideDistanceSource` (`scooterOdometer`, `gpsRoute`, `liveSpeedIntegration`);
- `RideDistanceCoverage` (`complete`, `partial`, `unknown`);
- `RideDistanceEvidence` and reconciliation status/confidence;
- finalized live-distance segments whose coverage is established only at a segment boundary.

This lane deliberately does not invent a second “trusted distance” authority token. The existing speed/distance chain is not sealed the same way as battery evidence: higher layers can construct first-party telemetry/evidence values, so simply wrapping those types would not create a real trust boundary.

Accordingly, #38's distance input remains **caller-classified**, not authority-sealed.

The safe rules are:

- omitted coverage fails closed as `.unknown`, never `.complete`;
- a caller must explicitly pass `.complete` only when its producing distance subsystem has evidence for complete coverage;
- `.partial` and `.unknown` remain sticky/rejectable learning evidence;
- final app wiring must feed legitimate ride-distance evidence and must not reinterpret presentation interpolation or provider route geometry as measured ride distance;
- this lane makes no claim that a caller-supplied `.complete` is cryptographically or architecturally impossible to misuse.

### Omitted distance coverage fails closed

The public pipeline defaults an omitted `coverage:` argument to `.unknown`.

A model-boundary regression omits coverage on a 300 m / 3% candidate and proves:

- the emitted candidate is `.unknown` coverage;
- the adaptive model rejects it as `incompleteDistanceEvidence`;
- learned history remains unchanged.

Intentional complete-distance tests pass `.complete` explicitly.

Preserved assembler behavior also includes:

- coverage degrades monotonically `complete → partial → unknown`;
- invalid/nonfinite/negative deltas fail atomically;
- finite-addition overflow fails before mutation;
- `latestAuthoritativeSOC` is distinct from the span anchor;
- `80 → 77 → 79` measured recovery rebases at `79` and discards preceding distance;
- continuous non-authoritative SoC never advances the authoritative cursor;
- distance recorded after a non-authoritative post-gap boundary but before the first verified SoC anchor is discarded when that verified anchor arrives;
- policy thresholds are evaluated live at each SoC evaluation instead of being frozen at anchor creation.

## Missing evidence versus observed transport gap

These remain deliberately different:

- `markUnobservedInterval()` means battery evidence continuity itself is unknown, so all ephemeral assembler state is discarded immediately and the next observation must carry a boundary;
- `recordTransportGap()` means a non-connected vehicle state was actually observed inside an otherwise represented span, so that flag remains attached to the candidate for model rejection.

The pipeline never silently converts one classification into the other.

## Model boundary remains separate

The pipeline stops at `BatteryRangeLearningWindow` candidates. It does not own or persist `AdaptiveBatteryRangeModel`.

That separation matters because durable learned history eventually requires a verified stable per-physical-scooter identity.

End-to-end model-boundary tests prove:

- clean complete/no-gap candidate → accepted only after explicit model ingest;
- omitted coverage → unknown coverage, rejected, model unchanged;
- explicit partial candidate → rejected, model unchanged;
- explicit unknown candidate → rejected, model unchanged;
- observed transport-gap candidate → rejected, model unchanged;
- efficiency outlier → rejected without learned-history mutation.

A rejected emitted span nevertheless remains closed by the assembler. Its distance is never replayed into a later clean learning window.

## Focused validation

Supplemental Swift 6.2.1 contract validation currently includes:

- earlier bridge-focused harness: **10/10 passed**;
- earlier evidence→window harness: **6/6 passed**;
- current authority-sealed seam/model/public-API harness: **18/18 debug passed** and **18/18 release passed** across six suites;
- legitimate external non-authoritative client: passed using payload-free disposition + `candidateLearningWindow`;
- external verified-observation construction negative probe: blocked as required by the battery-evidence parent contract;
- external forged-result negative probe: blocked;
- external evidence-action naming/forging negative probe: blocked;
- external old-`learningWindow` access probe: blocked;
- public symbol graph audit: evidence-bearing action/old window/assembler state absent; public disposition/result/candidate window present.

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
7. the unchanged final SHA passes exact-head NembraCore + Xcode 27 / iPhone 12 / iOS 27 Simulator QA with durable `Nembra/Xcode27 Exact Head` success;
8. merge uses expected-head protection.

Queued, skipped, stale-head, or missing workflow evidence is never considered green.

## Hardware status

**IMPLEMENTED/TESTED IN SOFTWARE ONLY.** Physical current-generation AOVOPRO ES80 SoC source/resolution/cadence, voltage/current/power semantics, charging behavior, continuity behavior, stable scooter identity, and final production distance-source selection remain unverified.
