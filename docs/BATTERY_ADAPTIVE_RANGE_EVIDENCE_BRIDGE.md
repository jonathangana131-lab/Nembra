# Battery Evidence → Adaptive Range Learning Pipeline

Status: dependent software truth/integration layer. No physical AOVOPRO ES80 battery semantic is verified by this document or implementation.

## Purpose

Nembra deliberately separates three responsibilities:

1. **battery evidence truth** — normalized SoC/voltage/current/power/charging values retain explicit role, continuity, and process-local ordering evidence;
2. **adaptive range core** — learns percentage-based efficiency only from authoritative measured SoC plus trustworthy distance windows;
3. **learning-window assembly** — accumulates caller-classified real-distance evidence between authoritative SoC anchors without choosing telemetry sources or inventing energy data.

This worker owns only the seams between those domains. It does not take ownership of adaptive-model persistence, physical-scooter identity, telemetry decoding, distance-source selection, or UI presentation.

## Live dependency lineage

The synthetic review base is rebuilt from active/frozen dependency artifacts rather than rewriting another worker's branch:

- coordinator recovery PR #40 for the adaptive-range core;
- battery-evidence-domain PR #34, including `BatteryEvidenceStreamValidator`;
- active adaptive-range-window integration PR #54.

PR #54 supersedes closed/unmerged draft #29 and carries the corrected latest-authoritative cursor semantics. Its assembler tracks both the span anchor and the latest authoritative SoC so recovery such as `80 → 77 → 79` rebases at `79` instead of hiding recovery inside a later consumption window.

The worker-owned delta is five files:

- `Packages/NembraCore/Sources/NembraCore/BatteryAdaptiveRangeEvidenceAdapter.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeEvidenceAdapterTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangePipelineIntegrationTests.swift`;
- `Packages/NembraCore/Tests/NembraCoreTests/BatteryAdaptiveRangeModelBoundaryTests.swift`;
- this document.

If a dependency moves or lands, this lane must reconcile to its accepted exact head before final QA and production retargeting.

## Value-authority rule

Only `verifiedVehicleMeasurement + stateOfChargePercent` may become a `BatterySOCReading` for adaptive range.

The conversion preserves normalized percentage exactly, `.authoritativeMeasurement` provenance, and process-local receipt uptime. Wall-clock `Date` remains correlation metadata and never substitutes for monotonic ordering.

Continuous SoC from stock-app correlation, Simulator fixtures, derived estimates, or presentation-only state remains outside production learning. A stock Tuya screen showing `73%` can be useful physical/app correlation evidence without becoming decoded scooter SoC. Simulator success likewise never becomes physical ES80 efficiency history.

## Continuity truth is independent of value authority

An explicit `afterUnobservedInterval` marker means Nembra knows part of the battery-evidence stream was missed. That fact is independent of the attached value's role.

Therefore **every explicit unobserved-interval boundary resets in-flight range learning**, including when the first post-gap observation is stock-app, simulated, derived, presentation-only, or verified voltage/current/power/charging evidence.

The reset does not promote the attached value. A later verified SoC enters only as fresh post-gap evidence.

This intentionally corrects the first bridge draft, which reset only for verified measurements and could therefore have allowed a later verified SoC to close a span across an interval already known to be unobserved.

An explicit boundary is also accepted conservatively when it arrives without a prior local `markUnobservedInterval()` call. The parent stream validator treats that as a fresh continuity epoch, and this pipeline simultaneously resets the assembler. The higher layer does not get to erase a reported gap merely because it failed to preannounce it locally.

## Non-SoC electrical fields

Verified voltage, current, power, or charging-state observations do not become percentage-based range samples.

This layer performs no voltage→SoC conversion, current/power integration, watt-hour calculation, Wh/mi calculation, or battery-health inference. Any future energy model needs its own physically verified evidence contract.

## Truth actions

`BatteryAdaptiveRangeEvidenceAdapter` emits:

- `ignore` — continuous observation has no production range-learning effect;
- `resetContinuity` — discard the in-flight consumption span without promoting this value;
- `ingestSOC` — continuous verified SoC may enter adaptive-range assembly;
- `resetContinuityAndIngestSOC` — discard the old span first, then establish verified SoC as fresh evidence.

The explicit action avoids a lossy optional-reading API where continuity could disappear merely because the attached value itself was not learning-eligible.

## Stateful battery stream validation

`BatteryAdaptiveRangeEvidenceBridge` wraps PR #34's `BatteryEvidenceStreamValidator`.

It preserves the parent contract:

- uptime is the process-local ordering authority;
- equal uptimes are valid because one callback may produce multiple normalized battery fields;
- backwards uptime inside one observed epoch fails closed;
- `markUnobservedInterval()` requires the next observation to carry an explicit boundary;
- an explicit post-gap boundary starts a fresh uptime epoch, including after process/boot changes;
- a spontaneous explicit boundary is conservatively accepted as a new epoch rather than ignored.

The bridge validates on a candidate validator and commits only after acceptance succeeds.

## Atomic evidence → window pipeline

`BatteryAdaptiveRangeLearningPipeline` combines the evidence bridge with PR #54's `BatteryRangeLearningWindowAssembler` without modifying either dependency's files.

For each battery observation the pipeline copies both state components, validates/order-checks the observation, obtains the truth action, applies that action to the candidate assembler, and commits **both** candidate states only after the entire transition succeeds.

This protects both directions of the seam:

- a stream-order failure cannot mutate the assembler;
- an assembler failure after candidate stream acceptance cannot leave the stream baseline partially advanced.

Action mapping is direct:

- `ignore` → no assembler mutation;
- `resetContinuity` → `windowAssembler.reset()`;
- `ingestSOC(reading)` → assembler `ingestSOC` under the caller's active `AdaptiveBatteryRangePolicy`;
- `resetContinuityAndIngestSOC(reading)` → reset first, then ingest the reading as the new clean anchor.

The returned result contains the truth action plus any assembled `BatteryRangeLearningWindow` candidate.

## Latest-authoritative recovery semantics

PR #54 introduced a distinct `latestAuthoritativeSOC` cursor in addition to the span anchor. This pipeline preserves that behavior.

Example:

1. verified `80%` establishes the span anchor;
2. verified `77%` advances the latest-authoritative cursor while the span remains below closure thresholds;
3. verified `79%` is an increase relative to the latest `77%`, so the assembler rebases at `79%` and discards preceding distance;
4. a later clean `79 → 76` span can form its own candidate.

A continuous stock-app/Simulator/derived/presentation SoC never advances that authoritative cursor.

## Known missing evidence versus observed transport gap

These remain distinct.

`markUnobservedInterval()` means battery evidence continuity itself is unknown. The pipeline immediately marks the stream as requiring an explicit boundary and resets all in-flight assembler state, including anchor, latest-authoritative cursor, distance, coverage degradation, and observed-gap flag.

`recordTransportGap()` means a scooter transport gap was observed inside an otherwise represented span. That flag remains attached to the eventual candidate so the adaptive model can reject it explicitly rather than silently deleting evidence.

The pipeline does not infer which case occurred; a higher layer must classify it truthfully.

## Distance boundary

`recordDistance(deltaMeters:coverage:)` delegates to PR #54's assembler. This layer does not select odometer versus GPS, upgrade partial/unknown coverage to complete, reconstruct distance across missing intervals, or infer ride/session identity.

Distance coverage remains monotonic within a span: complete can degrade to partial or unknown and is preserved on the emitted candidate. Invalid/nonfinite/negative distance fails before state mutation.

Distance observed after a non-authoritative post-gap boundary but before the first verified SoC anchor is also not allowed to leak into the later learning span. The assembler may temporarily hold that distance while it has no anchor, but the first authoritative SoC establishes a new anchor via rebase and clears the pre-anchor distance. Only distance observed after that verified anchor can close a candidate.

## Model boundary stays separate

`BatteryAdaptiveRangeLearningPipeline` deliberately stops at a `BatteryRangeLearningWindow` candidate. It does **not** own or persist `AdaptiveBatteryRangeModel`.

That boundary matters because learned history eventually needs a stable per-physical-scooter persistence identity, which remains physical-verification work. Folding the long-lived model into this ephemeral stream/window object would make it easier to accidentally share or persist learned history under an unverified identity.

The parent model already has the correct fail-closed ingest boundary:

- clean complete/no-gap authoritative windows can be accepted;
- partial or unknown distance is rejected as `incompleteDistanceEvidence` without model mutation;
- observed transport gaps are rejected as `transportGap` without model mutation.

Worker tests prove pipeline-generated candidates preserve exactly those outcomes rather than sanitizing or dropping the rejection evidence before it reaches the model.

## Software validation

### Core bridge/pipeline suite

Covers truth-role gating, every explicit gap reset, non-SoC exclusion, stream boundary/ordering rules, equal-uptime multi-field behavior, complete-window emission, stock-app exclusion, observed transport gaps, and atomic stream/assembler failures.

### PR #54 seam suite

`BatteryAdaptiveRangePipelineIntegrationTests.swift` now adds eight explicit integration cases:

- partial→unknown distance coverage propagation;
- invalid distance atomicity;
- `markUnobservedInterval()` clearing anchor, latest-authoritative cursor, distance, coverage, and gap state;
- direct verified first-post-gap SoC reset + re-anchor;
- pre-anchor post-gap distance discarded when the first verified SoC establishes a clean anchor;
- spontaneous explicit boundary resetting stream and assembler without a prior local gap marker;
- `80 → 77 → 79` measured recovery rebasing at the latest authoritative reading and later clean `79 → 76` candidate formation;
- continuous stock-app SoC unable to advance the latest-authoritative cursor.

### Adaptive-model boundary suite

`BatteryAdaptiveRangeModelBoundaryTests.swift` proves:

- a clean pipeline candidate is accepted and teaches the expected 100 m/% sample;
- a partial candidate remains partial and is rejected without learned-state mutation;
- an unknown-coverage candidate remains unknown and is rejected without learned-state mutation;
- a transport-gap candidate preserves the gap and is rejected without learned-state mutation.

### Supplemental Swift 6.2.1 contract checks

- earlier bridge-focused harness: **10/10 passed**;
- earlier evidence→window pipeline harness: **6/6 passed**;
- PR #54 seam + model harness after latest continuity additions: **12/12 debug passed** and **12/12 release passed**.

The first two attempts to run an earlier compressed seam harness hit syntax mistakes only in the disposable harness (`=.complete`, `.5`, etc.); the committed GitHub files already used normal valid Swift syntax. After correcting the disposable copy, all subsequent debug/release contract runs were green. These checks are supplemental software evidence, not repository-wide Xcode acceptance.

## Remaining merge boundary

This PR is a dependent integration lane, not an independently mergeable production parent.

Before production merge:

1. coordinator PR #40 reaches its accepted/final adaptive-range-core head;
2. PR #54 reaches its accepted/final assembler head on the accepted #40 parent;
3. PR #34 reaches an accepted/final battery-evidence head;
4. this lane reconciles those exact parents without rewriting their branches;
5. the worker five-file delta is revalidated;
6. the PR is retargeted to the correct production base;
7. an exact-head repository Xcode 27/iPhone 12 Simulator gate passes on the unchanged final head;
8. merge uses expected-head protection.

Main contains the schedule-based exact-head QA fallback plus its stale-head eligibility guard. Missing scheduler execution is never considered green; acceptance remains tied to the immutable final SHA and durable `Nembra/Xcode27 Exact Head` status.

## Hardware status

**IMPLEMENTED/TESTED IN SOFTWARE ONLY.** The physical 2025-generation AOVOPRO ES80 still requires verification of its real battery SoC source, percentage resolution/cadence, voltage/current/power semantics, charging behavior, and continuity characteristics before any observation can legitimately use `verifiedVehicleMeasurement` in production.
