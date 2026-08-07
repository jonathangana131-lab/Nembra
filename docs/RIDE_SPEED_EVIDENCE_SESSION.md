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
- the prior accepted uptime remains the chronology anchor, so delayed stale callbacks cannot become fresh;
- a rejected callback does not consume a pending observation-gap marker.

The ride peak pipeline separately records the same selected-source interruption as evidence loss. Therefore a benchmark may remain useful for within-segment source characterization while the observed peak is still correctly rejected for reportable use because its ride observation was partial.

An initial recovery gap before the first accepted benchmark packet cannot be represented as a fictitious benchmark segment. Instead it remains explicit through `beganAfterKnownObservationGap` and through the ride peak's partial continuity.

## Source switching / mixing fails closed

`TelemetryBenchmarkCollector` already rejects wrong-source callbacks. A generic quality policy could legitimately permit some rejected samples for other feature types, so rejected fraction alone is not strong enough for peak reporting.

The ride session therefore also keeps `foreignSourceCallbackCount`.

Any callback from a source other than the session's selected source increments that count, including a motion-assist estimate. Any nonzero count is an unconditional `foreignSourceTraffic` readiness failure, even if the caller's generic `maximumRejectedSampleFraction` would otherwise pass the benchmark.

This prevents a permissive quality policy from silently authorizing a mixed-source peak or making display-assist estimates disappear from the evidence trail.

## Feature-level observed-peak quality policy

`RideObservedPeakQualityPolicy` chooses **no ES80-specific numeric constants**. Instead, it refuses to exist unless the caller supplies the evidence dimensions peak reporting must not silently omit:

- an explicit required authoritative source;
- at least three accepted samples;
- a maximum rejected-sample fraction;
- maximum mean arrival interval;
- maximum observed arrival interval;
- maximum interval jitter;
- maximum empirical nonzero speed step / resolution.

The three-sample floor is a statistical shape invariant, not an ES80 quality threshold. Jitter is variation between intervals. Two accepted samples provide only one interval, whose population standard deviation is trivially zero and therefore is not meaningful jitter evidence. Three accepted samples are the minimum capable of providing two uninterrupted intervals.

For GPS, the policy additionally requires:

- a nonzero minimum delivery-latency sample fraction;
- a maximum mean delivery latency.

GPS peak evidence itself must also use an explicit `maximumSpeedAccuracyMetersPerSecond` in `PeakSpeedPolicy` before it can become reportable under this layer.

The actual threshold values must come from legitimate feature requirements and physical evidence. This package does not guess them.

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
5. refresh reviews, overlap, and mergeability;
6. merge only after the dependency is part of main and same-ride tests remain green.

## Verification

Before the lifecycle-authority and minimum-jitter-sample hardening, focused Swift 6.2.1 warnings-as-errors debug and release harnesses passed **18/18 tests in both configurations** against the #185 benchmark-continuity contract plus the merged ride-bound peak contract. Those results are supporting evidence only after the newer source changes.

Additional post-hardening evidence currently includes:

- same-package `package` access compile: pass with warnings-as-errors;
- external-package fresh observer construction: rejected at compile time as intended;
- new deterministic policy regressions reject minimum accepted sample counts of 1 and 2 and accept 3.

Exact post-hardening repository/package acceptance remains required after dependency #185 lands and this branch is rebuilt on current main.

Software verification is not physical AOVOPRO ES80 validation.
