# Authoritative live distance integration

This layer turns one selected stream of raw absolute speed measurements into a process-local distance segment. It exists to make trip distance responsive without allowing dashboard animation, motion-assist estimates, or missing packets to become fake mileage.

## What is allowed to add distance

`LiveDistanceSegmentAccumulator` accepts exactly one `SpeedTelemetrySource` chosen by an injected `LiveDistanceIntegrationPolicy`.

- scooter Bluetooth and GPS may be selected because `SpeedTelemetrySample` structurally requires those sources to be absolute measurements;
- `motionAssist` is rejected as a policy source and any short-horizon estimate is rejected at record time;
- a sample from a different absolute source is rejected rather than mixed into the same integration sequence;
- `SpeedDisplayFrame` / rolling-number output is a separate render layer and cannot enter this API.

There is deliberately no production AOVOPRO ES80 source or packet-gap threshold yet. Real ES80 BLE cadence/jitter traces must calibrate that policy.

## Integration method is explicit

The current method is `trapezoidalBetweenMeasurements`: for two consecutive raw speed measurements, the segment integrates the numerical area between those measured endpoints.

This is a numerical estimate from raw measurements. It is **not** the dashboard's render interpolation and it is never written back as a measured speed sample.

No interval is integrated until two valid endpoints exist. A single sample is only an anchor, so "no evidence yet" remains distinct from a measured zero-meter interval.

## Gaps are not crossed optimistically

The policy supplies `maximumIntegrationIntervalNanoseconds`.

- interval <= threshold: integrate it;
- interval > threshold: do not add distance across it, mark a known gap, and use the newer sample only as the next anchor;
- a first sample after the declared segment start creates a leading gap;
- a segment finalized after its last raw sample creates a trailing gap;
- out-of-order/repeated timestamps, wrong sources, pre-segment samples, and numeric overflow are rejected transactionally.

A known gap can make finalized coverage `partial`, but Nembra does not invent what happened inside it. Scooter ODO/reconciliation may later recover provable vehicle mileage while the missing path/speed trace remains unknown.

## Live state and finalized evidence are different types

`LiveDistanceSegmentSnapshot` is provisional. It exposes the integrated distance so the live ride UI can update, plus whether a known gap has already occurred. It intentionally has **no** `RideDistanceCoverage` property.

Only `FinalizedLiveDistanceSegment`, produced after a monotonic segment end is known, can carry:

- `complete` — at least one interval was integrated and there is no known leading/internal/trailing gap;
- `partial` — at least one interval was integrated but a known coverage gap exists;
- `unknown` — no interval was integrated, so zero must not be fabricated as evidence.

This type split prevents an in-progress snapshot that is merely current through the latest packet from being mislabeled as complete completed-ride evidence.

## Ride-level aggregation across process segments

`RideLiveDistanceSegmentEvidence` is the durable projection of one finalized process-local segment. It deliberately omits monotonic uptime because uptime from a previous process or boot is not valid ordering evidence after recovery. Instead it carries the ride session UUID, a durable segment UUID, source/method, known distance versus unavailable distance, coverage, known gap count, and an explicit `followsUnobservedInterval` recovery boundary.

`RideLiveDistanceAggregator` combines only records for one declared ride/source/method. It:

- deduplicates equivalent replay by segment UUID so retrying a durable commit cannot double mileage;
- rejects conflicting same-ID records rather than choosing one;
- never mixes scooter/GPS sources or motion-assisted estimates;
- sums only finite integrated segment distance;
- preserves recovery/process gaps as `partial` coverage without adding guessed meters;
- keeps all-unavailable evidence as `nil/.unknown` while preserving a real integrated zero-meter segment as measured zero;
- uses segment UUID ordering only to make floating-point summation deterministic, never as ride chronology.

The ride/recovery layer remains responsible for assigning stable segment IDs and explicitly marking unobserved intervals. The aggregate is derived evidence; it does not reconstruct what happened inside a gap or promote integrated speed distance into scooter ODO/GPS truth.

## Process recovery boundary

Monotonic uptime is process/boot-local and must not be persisted as if it survives relaunch or reboot. A recovered ride therefore starts a **new integration segment** in the new monotonic epoch. The durable segment projection above can carry already integrated distance across that boundary without replaying or comparing stale uptime.

## Still pending

- app/ride-coordinator wiring of durable live-distance segment records;
- persistence implementation for those records and aggregate reconstruction at launch;
- production source selection and gap threshold from real AOVOPRO ES80 telemetry benchmarks;
- GPS quality-screening policy before choosing GPS as an integration source;
- real iOS background and hardware validation;
- presentation-layer smoothing for trip distance (render only, never evidence).
