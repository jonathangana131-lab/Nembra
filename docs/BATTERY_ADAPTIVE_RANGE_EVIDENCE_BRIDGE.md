# Battery Evidence → Adaptive Range Learning Pipeline

Status: dependent software truth/integration layer. No physical AOVOPRO ES80 battery semantic is verified by this document or implementation.

## Purpose

Nembra is deliberately separating three software responsibilities:

1. **battery evidence truth** — normalized SoC/voltage/current/power/charging values retain explicit role, continuity, and process-local ordering evidence;
2. **adaptive range core** — learns percentage-based efficiency only from authoritative measured SoC plus trustworthy distance windows;
3. **learning-window assembly** — accumulates caller-classified real-distance evidence between authoritative SoC anchors without choosing telemetry sources or inventing energy data.

This worker owns the narrow seams between those responsibilities. Its code prevents a plausible battery number from becoming measured range evidence, preserves every known observation gap, validates battery-stream ordering, and applies accepted truth actions to the in-flight range-window assembler atomically.

## Dependency lineage

The current synthetic review base composes exact dependent heads rather than copying or rewriting other workers' branches:

- coordinator recovery PR #40 for the adaptive-range core;
- battery-evidence-domain PR #34, including `BatteryEvidenceStreamValidator`;
- adaptive-range-window-assembly PR #29.

The worker-owned delta remains only:

- `BatteryAdaptiveRangeEvidenceAdapter.swift`;
- `BatteryAdaptiveRangeEvidenceAdapterTests.swift`;
- this document.

If any dependency moves or lands, this lane must reconcile to the accepted parent head before final QA and production retargeting.

## Value-authority rule

Only an observation whose role is `verifiedVehicleMeasurement` and whose semantic field is `stateOfChargePercent` may become a `BatterySOCReading` for the adaptive-range domain.

The conversion preserves:

- normalized percentage exactly, including legitimate fractional values;
- `.authoritativeMeasurement` provenance;
- process-local receipt uptime as the ordering timestamp.

Wall-clock `Date` remains correlation metadata and is never substituted for monotonic ordering.

Continuous SoC values with these roles remain outside production learning:

- `stockAppCorrelationAnchor`;
- `simulationFixture`;
- `derivedEstimate`;
- `presentationOnly`.

A stock Tuya screen showing `73%` can be valuable physical/app correlation evidence without becoming decoded scooter SoC. Simulator success likewise never becomes physical ES80 efficiency history.

## Continuity truth is independent of value authority

An explicit `afterUnobservedInterval` marker means Nembra knows part of the battery-evidence stream was missed. That fact is independent of the attached value's role.

Therefore **every explicit unobserved-interval boundary resets in-flight range learning**, including when the first post-gap observation is:

- stock-app correlation evidence;
- a Simulator fixture;
- a derived estimate;
- presentation-only state;
- verified voltage/current/power/charging evidence.

The reset does not promote the attached value. A later verified SoC may enter only as fresh post-gap evidence.

This rule intentionally corrects the first bridge draft, which was too restrictive by resetting only for verified measurements. That could have allowed a later verified SoC to close a learning span across an interval already known to be unobserved when the first post-gap normalized field was non-authoritative.

## Non-SoC electrical fields

Verified voltage, current, power, or charging-state observations do not become percentage-based range samples.

This layer performs no:

- voltage→SoC conversion;
- current integration;
- power integration;
- watt-hour calculation;
- Wh/mi calculation;
- battery-health inference.

A future energy model may use physically verified electrical telemetry through a separate evidence-backed design.

## Truth actions

`BatteryAdaptiveRangeEvidenceAdapter` emits an explicit `BatteryAdaptiveRangeEvidenceAction`:

- `ignore` — continuous observation has no production range-learning effect;
- `resetContinuity` — discard the in-flight consumption span without promoting this value;
- `ingestSOC` — continuous verified SoC may enter adaptive-range assembly;
- `resetContinuityAndIngestSOC` — discard the old span first, then establish verified SoC as fresh evidence.

The explicit action avoids a lossy `BatterySOCReading?` API where continuity could be accidentally dropped when the attached value itself was not learning-eligible.

## Stateful battery stream validation

`BatteryAdaptiveRangeEvidenceBridge` wraps PR #34's `BatteryEvidenceStreamValidator` and should be used for ordered sequences.

It preserves the parent contract:

- uptime is the process-local ordering authority;
- equal uptimes are valid because one callback may produce several normalized battery fields;
- backwards uptime inside one observed epoch fails closed;
- `markUnobservedInterval()` requires the next observation to carry an explicit boundary;
- an explicit post-gap boundary starts a fresh uptime epoch, including when its numeric uptime is lower after process/boot change.

The bridge evaluates on a candidate validator and commits only after validation succeeds.

## Atomic evidence → window pipeline

`BatteryAdaptiveRangeLearningPipeline` combines the stateful evidence bridge with PR #29's `BatteryRangeLearningWindowAssembler` without modifying either dependency's files.

The pipeline owns only ephemeral in-flight state:

- `evidenceBridge`;
- `windowAssembler`.

### Observation application

For each battery observation the pipeline:

1. copies both state components;
2. validates/order-checks the observation through the evidence bridge;
3. obtains the truth action;
4. applies that action to the candidate assembler;
5. commits **both** candidate states only after the entire transition succeeds.

This protects the seam in both directions:

- a stream-order failure cannot mutate the assembler;
- an assembler failure after stream acceptance cannot leave the evidence-stream baseline partially advanced.

### Action mapping

- `ignore` → no assembler mutation;
- `resetContinuity` → `windowAssembler.reset()`;
- `ingestSOC(reading)` → assembler `ingestSOC` under the caller's active `AdaptiveBatteryRangePolicy`;
- `resetContinuityAndIngestSOC(reading)` → reset first, then ingest the reading as the new clean anchor.

The returned `BatteryAdaptiveRangePipelineResult` includes both the truth action and any assembled `BatteryRangeLearningWindow` candidate.

## Known missing evidence versus observed transport gap

These remain distinct on purpose.

`markUnobservedInterval()` means battery evidence continuity itself is unknown. The pipeline immediately:

- marks the evidence stream as requiring an explicit boundary;
- resets the in-flight range-window assembler.

`recordTransportGap()` means a scooter transport gap was observed inside an otherwise represented span. That flag remains attached to the eventual candidate so the adaptive model can reject it explicitly rather than silently deleting evidence.

The pipeline does not infer which case occurred; a higher layer must classify it truthfully.

## Distance boundary

`recordDistance(deltaMeters:coverage:)` delegates to PR #29's assembler. This layer does not:

- select odometer versus GPS;
- upgrade partial/unknown coverage to complete;
- reconstruct distance across missing intervals;
- infer ride/session identity.

Those classifications must already be truthful when distance reaches this pipeline.

## Software validation

Focused worker coverage exercises:

- verified fractional SoC mapping/provenance;
- non-verified continuous SoC exclusion;
- explicit gap resets for every truth role;
- non-SoC electrical exclusion;
- stream boundary/uptime rules;
- equal-uptime multi-field evidence;
- atomic stream rejection;
- complete verified SoC + distance window emission;
- immediate discard of pre-gap anchor/distance;
- continuous stock-app SoC leaving an authoritative span unchanged;
- observed transport-gap preservation on emitted candidates;
- atomic stream failure across the combined pipeline;
- atomic assembler failure after candidate stream acceptance.

A disposable Swift 6.2.1 contract harness matching the dependent public APIs compiled the bridge and passed the focused bridge tests, then compiled the expanded pipeline and passed its focused end-to-end regressions. These supplemental checks are useful software evidence but do not replace final repository Xcode 27 QA on the reconciled exact head.

## Remaining merge boundary

This PR is a dependent integration lane, not an independently mergeable production parent.

Before production merge:

1. coordinator PR #40 must reach its accepted/final adaptive-range-core head;
2. PR #34 battery evidence and PR #29 window assembly must reach accepted/final heads;
3. this lane must reconcile those exact parents without rewriting their branches;
4. the worker three-file delta must be revalidated;
5. an exact-head repository Xcode 27/iPhone 12 Simulator gate must pass on the unchanged final head;
6. only then should the PR be retargeted to the correct production base and considered for merge.

## Hardware status

**IMPLEMENTED/TESTED IN SOFTWARE ONLY.** The physical 2025-generation AOVOPRO ES80 still requires verification of its real battery SoC source, percentage resolution/cadence, voltage/current/power semantics, charging behavior, and continuity characteristics before any observation can legitimately use `verifiedVehicleMeasurement` in production.
