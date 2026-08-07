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

`RideLiveDistanceSegmentEvidence` is the durable projection of one finalized process-local segment. It deliberately omits monotonic uptime because uptime from a previous process or boot is not valid ordering evidence after recovery. Instead it carries:

- ride session UUID;
- durable segment UUID for idempotent replay;
- `processSegmentSequence`, assigned by the ride/recovery layer starting at zero and incremented for every new monotonic process epoch;
- source/method;
- known distance versus unavailable distance;
- segment-local coverage and known gap count.

`RideLiveDistanceAggregator` requires a complete contiguous sequence `0...N-1`. Duplicate replay of the same durable segment is ignored; two different segment IDs cannot claim the same process sequence; a missing earlier sequence fails closed. UUID order has no chronological meaning.

Every transition from process segment `N` to `N+1` is automatically counted as one unobserved interval. There is no caller-controlled “gap happened” Boolean to forget. Therefore:

- one complete process segment can remain `complete`;
- two or more process segments are necessarily `partial`, even if each individual segment is internally complete;
- the known distance still sums across segments, but no meters are invented inside process/recovery gaps;
- all-unavailable evidence remains `nil/.unknown`;
- a real integrated zero-meter segment remains measured zero rather than becoming unavailable.

The aggregator also rejects ride-session/source/method mixing, conflicting replay, non-finite total distance, and gap-count overflow.

## Reconciliation bridge is session-bound

`RideDistanceEvidence` can consume a `RideLiveDistanceAggregate` directly. That bridge requires the aggregate ride UUID to equal the `CompletedRideEvidence.sessionID` before copying the aggregate distance and coverage into reconciliation evidence. Valid scalar distance from one ride therefore cannot be paired with another ride merely because both values look numerically plausible.

A missing aggregate remains `nil/.unknown`; it is never converted to zero distance.

This binding applies only to live-distance aggregation. It does not solve unrelated identity/provenance work in statistics or other consumers.

## Process recovery boundary

Monotonic uptime is process/boot-local and must not be persisted as if it survives relaunch or reboot. A recovered ride therefore starts a **new integration segment** in the new monotonic epoch and increments the durable process segment sequence. The aggregate preserves already integrated distance while automatically preserving the intervening unobserved interval as partial coverage.

## Still pending

- app/ride-coordinator wiring that assigns/persists stable process segment IDs and contiguous sequences;
- persistence implementation for durable segment records and aggregate reconstruction at launch;
- production source selection and gap threshold from real AOVOPRO ES80 telemetry benchmarks;
- GPS quality-screening policy before choosing GPS as an integration source;
- real iOS background and hardware validation;
- presentation-layer smoothing for trip distance (render only, never evidence).
