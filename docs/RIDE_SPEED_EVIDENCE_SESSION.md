# Ride-owned speed evidence session

Date: 2026-08-07
Worker: `chat-t6v9m`
Primary physical-validation target: **AOVOPRO ES80**
Dependency while this document was written: PR #185 telemetry-benchmark continuity

## Why this layer exists

Nembra already has separate truthful primitives for:

- observed peak speed from one selected authoritative source;
- ride-bound peak identity/provenance;
- raw telemetry benchmarking;
- caller-supplied telemetry quality assessment.

Those primitives are intentionally independent, but independence leaves a dangerous composition seam: a clean benchmark from one ride could be paired with a peak from another ride if a future caller simply joins values by source name.

`RideSpeedEvidenceSessionAccumulator` closes that seam before History, Statistics, or Dashboard code is allowed to consume a qualified peak.

## One ride, one selected source, one callback stream

The session owns:

- one immutable ride UUID;
- one selected authoritative `SpeedTelemetrySource` inherited from `PeakSpeedPolicy`;
- one `RidePeakSpeedEvidenceAccumulator`;
- one `TelemetryBenchmarkCollector`.

Every raw callback is sent to both evidence pipelines through the same `record(_:)` method.

Every known selected-source interruption is sent to both through the same `recordInterruption(_:)` method.

`RideSpeedEvidenceSessionSnapshot` has no public free-form initializer, so external code cannot manufacture a snapshot by combining an arbitrary ride peak and an arbitrary benchmark after the fact.

This is a software composition guarantee. It does not identify which ES80 transport characteristic is physically authoritative.

## Known gaps are not slow packets

This layer depends on the benchmark-continuity behavior from PR #185:

- a known observation break starts a new benchmark segment after accepted evidence resumes;
- cadence/jitter/speed-step math never bridges that known missing interval;
- the prior accepted uptime remains the chronology anchor, so delayed stale callbacks cannot become fresh;
- a rejected callback does not consume a pending observation-gap marker.

The ride peak pipeline separately records the same interruption as evidence loss. Therefore a benchmark may remain useful for within-segment source characterization while the observed peak is still correctly rejected for reportable use because its ride observation was partial.

An initial recovery gap before the first accepted benchmark packet cannot be represented as a fictitious benchmark segment. Instead it remains explicit through `beganAfterKnownObservationGap` and through the ride peak's partial continuity.

## Source switching / mixing fails closed

`TelemetryBenchmarkCollector` already rejects wrong-source callbacks. A generic quality policy could legitimately permit some rejected samples for other feature types, so rejected fraction alone is not strong enough for peak reporting.

The ride session therefore also keeps `foreignSourceCallbackCount`.

Any nonzero foreign-source callback count is an unconditional `foreignSourceTraffic` readiness failure, even if the caller's generic `maximumRejectedSampleFraction` would otherwise pass the benchmark.

This prevents a permissive quality policy from silently authorizing a mixed-source peak.

## Feature-level observed-peak quality policy

`RideObservedPeakQualityPolicy` chooses **no numeric ES80 constants**. Instead, it refuses to exist unless the caller explicitly supplies the evidence dimensions peak reporting must not silently omit:

- an explicit required authoritative source;
- a maximum rejected-sample fraction;
- maximum mean arrival interval;
- maximum observed arrival interval;
- maximum interval jitter;
- maximum empirical nonzero speed step / resolution.

For GPS, the policy additionally requires:

- a nonzero minimum delivery-latency sample fraction;
- a maximum mean delivery latency.

GPS peak evidence itself must also use an explicit `maximumSpeedAccuracyMetersPerSecond` in `PeakSpeedPolicy` before it can become reportable under this layer.

The values of those thresholds must come from legitimate feature requirements and physical evidence. This package does not guess them.

## Reportability failures remain distinct

`RideObservedPeakReadiness` can fail because:

- no selected-source peak was accepted;
- peak and benchmark sources disagree (defensive invariant);
- foreign-source callbacks were observed;
- selected-source peak observation is partial because of a known gap or peak-specific quality rejection;
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

After #185 merges:

1. refresh current main;
2. rebuild this branch from current main plus only this lane's own files;
3. verify the effective diff no longer contains `TelemetryBenchmark.swift` or `TelemetryBenchmarkContinuityTests.swift`;
4. rerun focused package tests on the exact final head;
5. merge only after the dependency is part of main and same-ride tests remain green.

## Verification

Focused Swift 6.2.1 warnings-as-errors debug and release harnesses pass against the #185 benchmark-continuity contract plus the merged ride-bound peak contract.

Covered behavior includes:

- clean same-ride BLE peak + benchmark qualification under explicit complete policy;
- large known observation gap excluded from benchmark intervals while peak becomes partial;
- initial recovery gap remaining disqualifying even though the benchmark begins with a clean first segment;
- GPS peak-specific accuracy rejection remaining visible when raw benchmark quality itself is clean;
- GPS quality policy requiring explicit latency evidence;
- incomplete feature policies failing construction instead of silently using defaults;
- foreign-source traffic failing peak readiness even under a permissive generic rejected-sample policy.

Software verification is not physical AOVOPRO ES80 validation.
