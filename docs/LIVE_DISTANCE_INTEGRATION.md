# Authoritative live distance integration

This layer turns one selected stream of raw absolute speed measurements into a process-local distance segment. It exists to make trip distance responsive without allowing dashboard animation, motion-assist estimates, or missing packets to become fake mileage.

## What is allowed to add distance

`LiveDistanceSegmentAccumulator` accepts exactly one `SpeedTelemetrySource` chosen by an injected `LiveDistanceIntegrationPolicy`.

- scooter Bluetooth and GPS may be selected because `SpeedTelemetrySample` structurally requires those sources to be absolute measurements;
- `motionAssist` is rejected as a policy source and any short-horizon estimate is rejected at record time;
- a sample from a different absolute source is rejected rather than mixed into the same integration sequence;
- `SpeedDisplayFrame` / rolling-number output is a separate render layer and cannot enter this API.

There is deliberately no production MAXSHOT source or packet-gap threshold yet. Real BLE cadence/jitter traces must calibrate that policy.

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

## Process recovery boundary

Monotonic uptime is process/boot-local and must not be persisted as if it survives relaunch or reboot. A recovered ride therefore starts a **new integration segment** in the new monotonic epoch.

This primitive does not yet aggregate multiple process-local segments into one crash-safe live trip value. The next ride-level layer must preserve accumulated segment distance/checkpoints without replaying stale uptime, and must mark the unobserved recovery interval honestly so ODO reconciliation can account for proven missing mileage.

## Still pending

- ride-level aggregation across multiple monotonic segments;
- crash-safe persistence of accumulated live-distance evidence without persisting stale uptime clocks;
- production source selection and gap threshold from real MAXSHOT telemetry benchmarks;
- GPS quality-screening policy before choosing GPS as an integration source;
- app/ride-coordinator wiring;
- real iOS background and hardware validation;
- presentation-layer smoothing for trip distance (render only, never evidence).
