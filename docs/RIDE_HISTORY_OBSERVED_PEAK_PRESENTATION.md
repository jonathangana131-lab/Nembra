# Ride History Observed-Peak Presentation

## Purpose

This layer turns one NembraCore-authorized `RideHistoryObservedPeakJoinedRecord` into a product-facing semantic projection suitable for a future Ride Details / accessibility integration.

It is deliberately downstream of durable observed-peak history and upstream of SwiftUI. It does not alter persistence, app wiring, telemetry collection, or selected-period statistics.

## Durable truth stays below presentation

`RideObservedPeakHistoryEvidence` retains descriptive raw evidence needed to re-evaluate quality after relaunch. It does not persist `isReady`, `qualified`, `isObservedMaximumEligible`, or this presentation state.

Structural consistency is not origin authority. Public callers can decode/retain the durable evidence, but the recovery parent keeps `RideObservedPeakHistoryAssessment`, `RideObservedPeakHistoryEvidence.assessment()`, and `RideHistoryObservedPeakJoinedRecord.assessment()` inside NembraCore. This presentation slice preserves that boundary: `RideHistoryObservedPeakPresenter` is also module-owned rather than public.

A future package-owned persistence/provenance adapter must be the public minting boundary. Only that sealed adapter may obtain trusted durable history inside NembraCore, call the presenter, and return the non-Codable `RideHistoryObservedPeakPresentation` value to app UI. Caller-authored Codable history must never be accepted directly by a public presenter.

## Product states

### `observedPeakUnavailable`

No accepted selected-source peak exists.

- no numeric speed is exposed;
- nil is not replaced with `0`;
- the selected source remains available as provenance;
- observed-maximum wording is forbidden.

A legitimately accepted `0 m/s` observation is different from missing evidence. The current `RideObservedPeakQualityPolicy` requires empirical speed-resolution evidence, so an all-zero trace cannot establish the required nonzero step and therefore remains an `unqualifiedAcceptedObservation`: the real accepted `0` is retained, but it does not earn observed-maximum wording. Do not collapse that state into unavailable evidence, and do not weaken the retained policy merely to make zero qualify.

### `unqualifiedAcceptedObservation`

A real accepted selected-source speed observation exists, but the retained quality evidence does not pass the complete observed-maximum gate.

Examples include recorded selected-source interruption, foreign-source traffic, unavailable required speed-resolution evidence, or another retained quality failure. Clean continuity alone is not sufficient when the telemetry benchmark fails its retained quality policy.

The accepted observation remains available as subordinate evidence because it is real. It is **not** copied into `qualifiedObservedMaximumMetersPerSecond`, `permitsObservedMaximumWording` is false, and `requiresQualityDisclosure` is true.

A consumer must not relabel this value as `Max speed`, `Observed max`, top speed, or a complete ride maximum.

### `qualifiedObservedMaximum`

The module-owned presenter revalidates the retained caller-supplied policy and also passes the stricter observed-maximum gate:

- no readiness failures;
- telemetry quality qualified;
- no foreign-source callbacks;
- no selected-source interruption;
- no recorded selected-source peak-evidence loss;
- authoritative non-motion-assist source.

Only this state exposes `qualifiedObservedMaximumMetersPerSecond` and permits observed-maximum wording.

## Accuracy and continuity provenance

When accepted peak evidence exists, presentation preserves:

- selected `SpeedTelemetrySource`;
- accepted speed in meters/second;
- accepted speed-accuracy value when the source supplied one;
- `PeakSpeedObservationContinuity`.

These are evidence/provenance fields, not permission to invent precision in formatting. A future UI should convert units at presentation time and should not imply more precision than the underlying source justifies.

## What this does not claim

This package slice does not establish:

- a mechanically sealed production persistence adapter yet;
- the production AOVOPRO ES80 speed source;
- BLE/Tuya/GATT/DP identity or semantics;
- physical cadence, latency, resolution, or GPS-quality thresholds;
- exact continuous-time top speed;
- throttle position, motor power, or rated/certified scooter maximum;
- SwiftData persistence of the attachment;
- Ride Details / Stats SwiftUI wiring;
- Simulator or physical-device visual acceptance.

The stored policy being satisfied means only that retained software evidence passes that retained policy after NembraCore has obtained it through an authorized path. It does not prove the policy has been physically validated for the ES80.

## Integration boundary

The current app `RideHistoryRecord` persistence and `AppRootView` / Ride Details surfaces are intentionally untouched because those are high-contention owned integration surfaces.

The next safe product rung is a mechanically sealed package-owned persistence/provenance adapter that can obtain durable history without accepting caller-authored evidence as authority, then return this presentation to app integration. Until that exists, this presenter remains module-owned and #421 must stay stacked/draft.
