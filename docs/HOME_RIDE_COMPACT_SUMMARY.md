# Home / Ride Compact Summary Truth Contract

## Purpose

V13 asks Home to surface a useful recent-ride summary without turning the screen into a history debugger. The product also requires ODO, GPS, integrated-speed distance, route geometry, estimates, and unknowns to remain distinct until evidence supports reconciliation.

`RideHistoryCompactSummary` is an additive NembraCore projection for that product layer. It transforms exactly one already-validated `RideHistoryRecord` into compact presentation semantics while preserving the limits of the current durable schema.

It does **not** decide which ride is the newest, does **not** persist a second copy of ride truth, and does **not** choose a final distance.

## Current compact facts

The projection exposes:

- the exact ride `sessionID`;
- the completed ride's wall-clock end date as presentation metadata;
- uninterrupted vs recovered-checkpoint continuity;
- scooter odometer delta evidence when both validated endpoints exist;
- positive accumulated quality-screened GPS distance evidence;
- an explicit unresolved state for a stored GPS value of zero;
- a count of independently displayable distance-evidence values.

## Why GPS zero is unresolved

`CompletedRideEvidence` currently stores `qualityScreenedGPSDistanceMeters` as a non-optional `Double` whose accumulation begins at zero. The durable record does not separately persist whether at least one usable GPS distance observation contributed to that value.

Therefore a stored `0` cannot safely answer whether:

1. GPS legitimately observed a zero-meter accumulated distance, or
2. no usable GPS distance observation existed.

The compact summary uses `unresolvedZeroOrNoObservation` rather than presenting `0 m` as measured truth or silently calling it unavailable. A future schema may remove this ambiguity by persisting explicit GPS observation/coverage provenance.

## Why there is no `latest(from:)`

Completed ride wall-clock timestamps are intentionally allowed to survive system-clock changes. The in-process ride state machine uses monotonic uptime for ordering, but that uptime cannot be used across process/boot epochs and is not a durable global history sequence.

Consequently `presentationEndedAtDate` is useful for display but is not promoted here to a monotonic commit-order authority. The current SwiftData store still sorts History by `endedAtDate` plus UUID; this compact summary does not deepen that assumption into a reusable domain API.

A future genuinely authoritative "most recently completed ride" contract should first establish durable ordering semantics rather than infer them from a clock that the ride model explicitly allows to move.

## Distance truth

The summary never emits a field named `distance`, `rideDistance`, or `finalDistance`.

- Odometer evidence is an observed delta in kilometers. The current history record does not carry odometer coverage authority, so the delta is not automatically the complete ride distance.
- GPS evidence is the positive accumulated quality-screened GPS value in meters. The current history record does not carry GPS route-coverage authority, so the value is not automatically the complete ride distance.
- If both are present, both remain independently displayable. Their presence count does not mean they corroborate one another.
- Reconciliation remains the responsibility of the dedicated ride-distance evidence/reconciliation system after source coverage and policy are available.

## Product integration boundary

The intended next product layer is a compact Home/history presentation that can use this projection to avoid reimplementing evidence semantics in SwiftUI.

This product slice deliberately does not edit `HomeView.swift`, `AppRootView.swift`, `RidePersistence.swift`, the Xcode project, or global project-memory files because those are active/high-contention parallel surfaces. App wiring should consume this contract after the owning UI/integration lane reconciles it safely.

Nembra's production app target currently does not link the NembraCore package product. It manually compiles a selected subset of NembraCore source files. To avoid creating a Class-A `project.pbxproj` race, the compact summary is intentionally co-located with `RideHistoryRecord` in `RideHistoryCommit.swift`, which is already part of the production app target. This means exact-head Xcode app compilation can prove the declaration itself is app-target visible without adding project-file wiring.

That visibility does **not** mean Home already presents the summary. No production SwiftUI consumer is added in this slice, and the owning Home/integration lane must still bind an exact `RideHistoryRecord` to the projection without inventing a globally monotonic "latest ride" selector.

## Hardware / physical truth

This is durable ride-history presentation semantics only. It does not verify AOVOPRO ES80 odometer behavior, GPS field performance, ride-distance accuracy, physical iPhone lifecycle behavior, BLE/Tuya semantics, battery/current/power fields, or motorized commands.
