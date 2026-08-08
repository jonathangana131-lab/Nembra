# Ride-owned speed evidence session

Date: 2026-08-07
Worker: `chat-t6v9m`
Primary physical-validation target: **AOVOPRO ES80**
Dependency while this document was written: PR #185 telemetry-benchmark continuity

## Why this layer exists

Nembra already has separate truthful primitives for observed peak speed, ride-bound peak identity/provenance, raw telemetry benchmarking, and caller-supplied telemetry quality assessment.

Those primitives are intentionally independent, but independence leaves a dangerous composition seam: a clean benchmark from one ride could be paired with a peak from another ride if a future caller simply joins values by source name.

`RideSpeedEvidenceSessionAccumulator` closes that seam before History, Statistics, or Dashboard code is allowed to consume a qualified peak.

## One ride, one selected source, one callback stream

The session owns:

- one immutable ride UUID;
- one selected authoritative `SpeedTelemetrySource` inherited from `PeakSpeedPolicy`;
- one `RidePeakSpeedEvidenceAccumulator`;
- one `TelemetryBenchmarkCollector`.

Every raw callback is sent to both evidence pipelines through the same package-owned `record(_:)` operation.

Every selected-speed-source observation break is sent to both through package-owned `recordInterruption(_:)` using `RideSpeedEvidenceSessionInterruption`.

That interruption API is intentionally narrower than ride/vehicle lifecycle events:

- `.selectedSourceUnavailable` means the trusted lifecycle owner has already determined that the selected speed evidence source itself was unavailable;
- `.applicationLifecycleInterrupted` means the app/process lifecycle interrupted observation.

There is deliberately no `.vehicleConnectionLost` case here. A scooter BLE disconnect is a speed-source gap when BLE is the selected source, but it is not automatically a GPS evidence gap. The adapter that observes a physical vehicle event must translate it to `.selectedSourceUnavailable` only after making that source-specific determination.

`RideSpeedEvidenceSessionSnapshot` has no public free-form initializer, so external code cannot manufacture a snapshot by combining an arbitrary ride peak and an arbitrary benchmark after the fact.

This is a software composition guarantee. It does not identify which ES80 transport characteristic is physically authoritative.

## Live lifecycle authority is sealed

Current `main` package-seals `RidePeakSpeedEvidenceAccumulator` creation because a caller-selected UUID proves identity only; it does not authorize resetting or independently operating another observer for the same ride.

The ride-speed session must not reopen that hole one layer higher. Therefore its live observer surface is also package-owned:

- `RideSpeedEvidenceSessionAccumulator.init(...)` is `package`;
- `record(_:)` is `package`;
- `recordInterruption(_:)` is `package`;
- `snapshot` is `package`.

Unrelated dependent code cannot create a fresh clean session observer for an existing ride UUID, replace an observer to erase prior loss history, or independently drive the live evidence accumulator. A future app-facing adapter must mechanically bind this observer to the authoritative ride lifecycle rather than expose UUID-based construction directly.

A supplemental Swift 6.2.1 two-package warnings-as-errors probe confirms same-package construction/mutation/projection compiles, while an external package is rejected specifically because the initializer is inaccessible at `package` protection.

The session source is not currently wired into `Nembra.app`, and repository search found no accepted production consumer, so this seal does not remove an existing app API.

## Known gaps are not slow packets

This layer depends on the benchmark-continuity behavior from PR #185:

- a known observation break starts a new benchmark segment after accepted evidence resumes;
- cadence/jitter/speed-step math never bridges that known missing interval;
- the accepted-sample chronology anchor remains global across explicit gaps;
- a rejected callback does not consume a pending observation-gap marker.

The ride peak pipeline separately records the same selected-source interruption as evidence loss. Therefore a benchmark may remain useful for within-segment source characterization while the observed peak is still correctly rejected for reportable use because its ride observation was partial.

An initial recovery gap before the first accepted benchmark packet cannot be represented as a fictitious benchmark segment. Instead it remains explicit through `beganAfterKnownObservationGap` and through the ride peak's partial continuity.

### Unresolved dependency chronology question

PR #185 currently advances chronology only when a selected-source benchmark sample is **accepted**. A read-only review found an uncovered adversarial trace:

1. accepted selected-source callback at uptime 100;
2. newer selected-source callback at uptime 300 rejected because its required derived km/h overflows;
3. delayed valid callback at uptime 200.

With only `lastAcceptedUptimeNanoseconds`, callback 200 can appear newer than accepted 100 even though callback 300 was already observed. That can also make this ride-speed session clear a pending source interruption because the benchmark says `accepted` while the peak accumulator, which tracks selected-source observation chronology more strictly, rejects the callback as stale.

The dependency owner has independently promoted this trace to a **V13 merge blocker** in #185 comment `5215805753`. The earlier exact-head green run is therefore supporting evidence only; #185 must move to a fixed head and be re-gated before #208 can accept its chronology contract. This lane does not edit #185's owned files.

## One physical outage remains one logical gap

A single selected-source outage can produce repeated lifecycle notifications. The benchmark dependency already treats repeated gap marks as idempotent while evidence has not resumed, but the generic peak accumulator counts every interruption call. The ride-owned session normalizes those two behaviors before forwarding interruptions.

`selectedSourceInterruptionPending` stays true from the first recorded gap until accepted raw evidence from the selected benchmark source arrives again. While it is pending, repeated selected-source/application interruption notifications are ignored rather than inflating durable peak-loss counts.

The session also retains `knownSelectedSourceInterruptionCount`, a deduplicated logical gap count that is independent of whether a peak has been accepted or whether the benchmark had an observation segment available to break.

That matters before first evidence. For example, a clean observer can experience a selected-source outage before any accepted callback. The peak accumulator records the interruption internally but cannot publish `RidePeakSpeedEvidence` yet, and the benchmark correctly has no segment to mark. Without the ride-session count, that real known gap would disappear from the snapshot. The session therefore records it immediately.

Important distinctions:

- `beginsAfterKnownObservationGap` starts with logical interruption count 1;
- repeated startup/lifecycle notifications while that initial gap is pending do not increment the count;
- a first accepted selected-source benchmark sample after the outage re-arms interruption recording for a later distinct gap;
- a wrong-source callback does not end the selected-source outage;
- a selected-source callback rejected by the benchmark does not end the outage;
- an accepted GPS callback does prove the raw GPS source resumed even if the stricter peak-specific GPS accuracy gate rejects that same sample;
- whenever `RidePeakSpeedEvidence` exists, its known interruption count is expected to agree with the session's logical count; the session count simply remains available earlier than optional peak evidence.

This keeps peak and benchmark provenance describing the same logical outage topology rather than one counter reflecting notification multiplicity.

## Peak rejections remain visible before a peak exists

`RidePeakSpeedEvidence` is optional until at least one selected-source sample passes all peak-specific gates. That means an all-rejected session would otherwise lose the peak accumulator's reason/count information exactly when a caller needs to understand why no peak exists.

The session therefore retains a constant-memory `RideSpeedEvidencePeakRejectionSummary` with counts for:

- non-authoritative samples;
- source mismatches;
- non-increasing selected-source timestamps;
- finite raw SI values whose required derived speed is non-finite;
- missing required speed accuracy;
- speed accuracy worse than the caller's peak ceiling.

The summary deliberately stores counts rather than an unbounded event list. `selectedSourceQualityRejectedSampleCount` groups the same selected-source quality categories represented by `PeakSpeedEvidence.qualityRejectedSampleCount` once a peak exists, while foreign/non-authoritative traffic remains separate provenance.

This closes an important GPS case: three raw GPS callbacks can all be benchmark-accepted yet all fail a stricter peak accuracy ceiling. The benchmark may legitimately be clean while `peakEvidence == nil`; the snapshot/readiness still shows exactly how many peak callbacks were rejected for accuracy instead of collapsing the result to an unexplained `peakUnavailable`.

## Source switching / mixing fails closed

`TelemetryBenchmarkCollector` already rejects wrong-source callbacks. A generic quality policy could legitimately permit some rejected samples for other feature types, so rejected fraction alone is not strong enough for peak reporting.

The ride session therefore also keeps `foreignSourceCallbackCount`.

Any callback from a source other than the session's selected source increments that count, including a motion-assist estimate. Any nonzero count is an unconditional `foreignSourceTraffic` readiness failure, even if the caller's generic `maximumRejectedSampleFraction` would otherwise pass the benchmark.

The peak-rejection summary keeps the distinction as well: a foreign authoritative GPS/BLE callback is a peak `sourceMismatch`, while motion assist is rejected as `nonAuthoritativeSample`. Both remain visible rather than being collapsed into one generic foreign boolean.

## Feature-level observed-peak quality policy

`RideObservedPeakQualityPolicy` chooses **no ES80-specific numeric constants**. Instead, it refuses to exist unless the caller supplies the evidence dimensions peak reporting must not silently omit:

- an explicit required authoritative source;
- a maximum rejected-sample fraction;
- maximum mean arrival interval;
- maximum observed arrival interval;
- maximum interval jitter;
- maximum empirical nonzero speed step / resolution;
- at least three accepted samples.

Missing required dimensions are diagnosed before the statistical sample floor. A caller that omitted jitter or rejected-fraction requirements receives that missing-requirement error rather than a misleading sample-floor error for evidence it never asked to measure.

The three-sample construction floor is a statistical shape invariant, not an ES80 quality threshold. Jitter is variation between intervals. Two accepted samples provide only one interval, whose population standard deviation is trivially zero and therefore is not meaningful jitter evidence.

Three accepted samples are only the minimum *capable* of providing two intervals. A known observation gap can split those samples across segments and leave only one intra-segment interval. `observedPeakReadiness(using:)` therefore also requires `telemetryBenchmark.intervalCount >= 2`. If the ride has fewer than two actually observed intervals, readiness reports `insufficientJitterIntervalEvidence` even if the generic telemetry assessment would otherwise call that one interval qualified.

For GPS, the policy additionally requires:

- a nonzero minimum delivery-latency sample fraction;
- a maximum mean delivery latency.

GPS peak evidence itself must also use an explicit `maximumSpeedAccuracyMetersPerSecond` in `PeakSpeedPolicy` before it can become reportable under this layer.

The actual threshold values must come from legitimate feature requirements and physical evidence. This package does not guess them.

## Readiness is self-describing audit evidence

A later caller must not receive only an opaque boolean such as `isReady == true` after the thresholds and raw evidence that produced it have disappeared.

`RideObservedPeakReadiness` therefore retains the exact immutable inputs and outputs of the decision:

- ride `sessionID`;
- selected source;
- `beganAfterKnownObservationGap`;
- `knownSelectedSourceInterruptionCount`;
- `foreignSourceCallbackCount`;
- `RideSpeedEvidencePeakRejectionSummary`;
- ride-bound peak evidence, if one exists;
- the exact same-ride `TelemetryBenchmarkSummary`;
- the exact `RideObservedPeakQualityPolicy` supplied by the caller;
- the resulting `SpeedTelemetryQualityAssessment`;
- all peak-feature readiness failures.

This matters especially for failed/no-peak decisions. If a recovered observer starts after a known gap and then sees only foreign or peak-rejected callbacks, `peakEvidence` can stay nil—but the readiness result still preserves the initial-gap fact, logical interruption count, rejection reasons, foreign-source count, benchmark summary, policy and failures rather than collapsing the session into a generic `peakUnavailable` result.

`RideObservedPeakReadiness` is intentionally not `Codable`. This slice is runtime/domain audit evidence, not a persistence migration or a claim that caller-injected thresholds have been physically validated for ES80.

## Reportability failures remain distinct

`RideObservedPeakReadiness` can fail because:

- no selected-source peak was accepted;
- peak and benchmark sources disagree (defensive invariant);
- foreign-source callbacks were observed;
- selected-source peak observation is partial because of a known gap or peak-specific quality rejection;
- fewer than two actual intra-segment timing intervals exist for jitter evidence;
- GPS peak evidence had no explicit speed-accuracy ceiling;
- same-ride raw telemetry failed the supplied cadence/jitter/latency/resolution policy.

A clean raw benchmark cannot erase partial peak evidence. A clean peak number cannot erase weak raw-source cadence. Both must be adequate in the same ride-owned evidence session.

`isReady` means only that this software evidence satisfies the caller-supplied policy. It is **not** a statement that the policy thresholds themselves have been physically validated for the AOVOPRO ES80.

## Deliberate non-goals

This slice does not:

- choose BLE or GPS as the ES80 production peak source;
- choose real cadence, jitter, latency, resolution, rejection, or GPS-accuracy thresholds;
- persist a qualified peak into `RideHistoryRecord`;
- modify `CompletedRideEvidence`;
- change `RideStatistics`;
- wire Dashboard / History UI;
- modify RideEngine lifecycle;
- modify Bluetooth discovery, subscriptions, parsing, commands, or writes;
- claim a sampled maximum is the exact continuous physical top speed.

## Dependency / integration rule

While PR #185 is open, this lane is explicitly dependent on its exact benchmark-continuity feature blobs and must not be merged as a competing implementation.

After #185 merges with a resolved chronology contract:

1. refresh current main;
2. rebuild this branch from current main plus only this lane's owned files;
3. verify the effective diff no longer contains `TelemetryBenchmark.swift` or `TelemetryBenchmarkContinuityTests.swift`;
4. rerun focused package tests on the exact final head;
5. refresh reviews, overlap, and mergeability;
6. mark ready only after the exact-head package gate is green;
7. merge only with expected-head protection.

## Verification

Before the lifecycle-authority and later evidence hardening, focused Swift 6.2.1 warnings-as-errors debug and release harnesses passed **18/18 tests in both configurations** against the #185 benchmark-continuity contract plus the merged ride-bound peak contract. Those results are supporting evidence only after the newer source changes.

Additional post-hardening evidence currently includes:

- same-package `package` access compile: pass with warnings-as-errors;
- external-package fresh observer construction: rejected at compile time as intended;
- policy/sample-floor and validation-precedence focused checks: green in debug + release;
- logical interruption normalization probe: **4/4 debug + 4/4 release** with warnings-as-errors;
- extended logical interruption-count topology probe: **5/5 debug + 5/5 release** with warnings-as-errors, including pre-first-evidence and initial recovery gaps;
- observed-interval readiness probe: **2/2 debug + 2/2 release** with warnings-as-errors;
- readiness audit-provenance probe: **2/2 debug + 2/2 release** with warnings-as-errors;
- rejection-summary category probe: all six categories compile/account correctly in debug + release;
- deterministic logical-gap reference model: **100,000 mixed operations** passes debug + release.

Repository tests additionally cover all-rejected GPS peak accuracy provenance, foreign authoritative versus motion-assist peak rejection reasons, rejection-summary agreement once a peak exists, readiness retaining the summary when no peak exists, and a pre-first-peak interruption remaining visible when the benchmark has no segment to break.

These are supplemental local proofs. Exact post-hardening repository/package acceptance remains required after dependency #185 lands and this branch is rebuilt on current main.

Software verification is not physical AOVOPRO ES80 validation.
