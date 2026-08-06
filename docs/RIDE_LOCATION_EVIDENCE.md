# Ride Location Evidence

Status: active implementation contract for the phone-location evidence slice.

## Purpose

Nembra must not turn a noisy phone coordinate stream into a precise-looking ride path or a trusted trip distance by default. This layer separates three concerns:

1. Core Location transport and authorization state.
2. deterministic quality screening of raw phone observations.
3. independently durable route geometry and GPS-distance evidence.

The same accepted location observation may contribute to both route and distance evidence, but those outputs remain separate after screening. A MapKit line is never measured later and promoted into ride distance.

## Current Core Location boundary

`CoreLocationRideLocationSource` wraps the current async Core Location update API behind `RideLocationSource`.

The source:
- requests a ride-scoped when-in-use `CLServiceSession` only when a caller explicitly starts location capture.
- consumes `CLLocationUpdate.liveUpdates(.otherNavigation)`; the navigation configuration is appropriate for scooter navigation.
- exposes authorization/service diagnostics as typed source issues instead of hiding them.
- preserves Core Location timestamp and horizontal-accuracy metadata.
- marks software-simulated location explicitly from Core Location source information.
- never starts at ordinary production cold launch.

This is foreground capture infrastructure only. Nembra does **not** claim background ride continuity, force-quit recovery, or outdoor field accuracy from this implementation.

## Quality screen

`RideLocationQualityScreen` contains no production-tuned defaults. Every threshold is injected through `RideLocationQualityPolicy` because the correct values must be justified by real outdoor traces on the target iPhone.

The policy currently controls:
- maximum horizontal accuracy.
- maximum measurement age.
- maximum future wall-clock skew.
- maximum process-local continuity gap.
- maximum implied speed between adjacent accepted samples.
- whether software-simulated locations are allowed.

Reduced/approximate location authorization is always rejected as precise ride-path evidence. A user may still use Nembra with reduced location access, but Nembra must not draw that coarse position as an accurate ride route.

Reception uptime is the ordering authority only inside the current process lifetime. Wall-clock dates are retained as evidence metadata and are never used to repair ordering after a clock change, relaunch, or reboot.

## Rejection and continuity behavior

Rejected samples are transactional: they do not replace the previous accepted baseline.

A known source interruption such as denied/restricted authorization, limited accuracy, location unavailable, insufficient in-use eligibility, or a failed update stream forces route coverage to partial. If valid evidence later resumes, the next accepted coordinate begins a new segment when continuity was previously established. Nembra never draws a line or adds GPS distance across that explicit gap.

An elapsed process-local gap larger than the injected continuity threshold behaves the same way: the new valid point is retained as the start of a new segment and contributes no invented distance across the missing interval.

An implausible jump is rejected while continuity is otherwise intact. The rejection does not poison the previous accepted baseline.

## Distance evidence

Distance is computed only between adjacent accepted coordinates inside one continuous segment. Great-circle distance is used for that pairwise evidence calculation.

The resulting delta enters the already accepted `RideEngine` field `qualityScreenedGPSDistanceDeltaMeters`. It is not stored in a parallel trip-total system and it does not bypass the ride engine's existing session/recovery/completed-history semantics.

No distance is produced for:
- the first accepted point.
- the first accepted point after an explicit continuity gap.
- a rejected coordinate.
- a jump that fails the injected plausibility policy.

## Route evidence

Accepted coordinates are passed to the existing immutable `RideRouteRecorder` / `RideRouteStore` path.

Route persistence failure is additive: a route-store failure does not discard an otherwise valid screened GPS-distance delta. Conversely, successful route persistence does not make GPS distance valid if no continuous distance delta passed the quality screen.

A source interruption is propagated to the route recorder immediately. Before the first persisted point this forces partial coverage without inventing an empty segment. After recorded points exist, repeated gap notifications collapse until a subsequent accepted coordinate materializes the next segment.

## Simulator and tests

`RideLocationQualityPolicy.simulatorQA()` exists only for deterministic software verification. Its numeric thresholds are QA fixtures, not real-world recommendations or AOVOPRO ES80 facts.

Tests cover:
- invalid raw samples and invalid policy values.
- reduced-accuracy rejection.
- stale/future/poor-accuracy/software-simulated rejection.
- process-local ordering.
- implausible jumps.
- explicit gaps and continuity timeouts.
- route/distance separation.
- route-store failure while screened distance survives.
- coordinator reuse across ride sessions.
- screened GPS distance entering the existing RideEngine rather than a parallel trip model.

## Production enablement gate

Real automatic location capture must remain disabled until all of the following are implemented and field-validated:
- real AOVOPRO ES80 ride-detection thresholds are verified enough to define when ride-scoped location begins and ends.
- full-vs-reduced location authorization UX is exercised on current iOS 27 hardware.
- horizontal-accuracy, age, continuity-gap, and implied-speed thresholds are tuned from real outdoor traces rather than Simulator values.
- background continuation and SwiftUI lifecycle behavior are designed and tested without pretending force-quit behavior is recoverable.
- energy impact is measured so navigation-grade location does not run outside a legitimate ride.
- physical iPhone 12 tests verify route continuity, GPS distance behavior, relaunch gaps, permission changes, and low-signal environments.

Until that gate is met, this slice proves the software evidence architecture and current Core Location adapter only. It does not claim production GPS validation or real ES80 hardware validation.
