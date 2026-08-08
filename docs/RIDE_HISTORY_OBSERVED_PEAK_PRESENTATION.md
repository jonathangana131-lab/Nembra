# Ride History Observed-Peak Presentation

## Purpose

This layer turns one trusted `RideHistoryObservedPeakJoinedRecord` into a product-facing semantic projection suitable for a future Ride Details / accessibility integration.

It is deliberately downstream of the durable observed-peak history attachment and upstream of SwiftUI. It does not alter persistence, app wiring, telemetry collection, or selected-period statistics.

## Durable truth stays below presentation

`RideObservedPeakHistoryEvidence` retains the raw evidence needed to re-evaluate quality after relaunch. It does not persist `isReady`, `qualified`, `isObservedMaximumEligible`, or this presentation state.

`RideHistoryObservedPeakPresenter.present(_:)` therefore calls the joined record's revalidation path each time it projects product state. `RideHistoryObservedPeakPresentation` is intentionally non-`Codable` so a derived presentation verdict does not become durable authority by convenience.

## Product states

### `observedPeakUnavailable`

No accepted selected-source peak exists.

- no numeric speed is exposed;
- nil is not replaced with `0`;
- the selected source remains available as provenance;
- observed-maximum wording is forbidden.

### `unqualifiedAcceptedObservation`

A real accepted selected-source speed observation exists, but the retained quality evidence does not pass the complete observed-maximum gate.

Examples include recorded selected-source interruption, foreign-source traffic, or another retained quality failure.

The accepted observation remains available as subordinate evidence because it is real. It is **not** copied into `qualifiedObservedMaximumMetersPerSecond`, `permitsObservedMaximumWording` is false, and `requiresQualityDisclosure` is true.

A consumer must not relabel this value as `Max speed`, `Observed max`, top speed, or a complete ride maximum.

### `qualifiedObservedMaximum`

The durable evidence revalidates under its retained caller-supplied policy and also passes the stricter observed-maximum gate:

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

- the production AOVOPRO ES80 speed source;
- BLE/Tuya/GATT/DP identity or semantics;
- physical cadence, latency, resolution, or GPS-quality thresholds;
- exact continuous-time top speed;
- throttle position, motor power, or rated/certified scooter maximum;
- SwiftData persistence of the attachment;
- Ride Details / Stats SwiftUI wiring;
- Simulator or physical-device visual acceptance.

The stored policy being satisfied means only that the retained software evidence passes that retained policy. It does not prove the policy has been physically validated for the ES80.

## Integration boundary

The current app `RideHistoryRecord` persistence and `AppRootView` / Ride Details surfaces are intentionally untouched because those are high-contention owned integration surfaces.

Once the durable attachment is accepted and an app persistence owner joins it into completed history, a Ride Details owner can consume this projection without reimplementing quality logic or reading a persisted qualification boolean.
