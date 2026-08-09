# Ride History Duration Attachment — V14 Recovery

Status: software/domain persistence recovery on current main. No physical AOVOPRO ES80 timing or protocol behavior is verified by this slice.

## Purpose

Nembra already has monotonic completed-ride duration evidence, but current `main` does not contain the durable history attachment from the older #300 lane. This recovery restores the safe additive persistence boundary without deriving elapsed time from wall-clock dates and without touching current high-contention app persistence, Ride Details, Dashboard, Home, or project wiring.

`RideHistoryDurationRecord` stores only `CompletedRideDurationEvidence`, preserving the distinction between unavailable duration, legitimately observed zero, complete monotonic observation, and partial observation with explicit missing coverage.

## Durable join contract

`RideHistoryDurationCommitCoordinator` requires the exact base `RideHistoryRecord` to exist before duration can be attached. It validates duration evidence against that immutable completed ride, commits idempotently, reads the attachment back, and requires exact durable equivalence before reporting success.

Same-session replacement with different duration evidence is a conflict. An orphan duration attachment without base history fails closed. Base history without a duration attachment remains ordinary duration unavailability.

`RideHistoryDurationJoinedRecord` is runtime-only and non-Codable. Construction is `package`-scoped in SwiftPM and `fileprivate` in direct-source app composition so ordinary app/UI code cannot manufacture a trusted join from arbitrary matching records.

## Truth boundary

This slice never subtracts `beganAtDate`, `confirmedAtDate`, or `endedAtDate` to manufacture elapsed time. Calendar timestamps remain identity/bucketing metadata; duration truth comes only from accepted monotonic duration evidence.

Unavailable duration remains distinct from an observed zero. Partial coverage remains partial. Recovered continuity cannot silently join an uninterrupted base ride with the same UUID.

## V14 recovery scope

This recovery is re-anchored directly on current `main@f144286dfb3cb01a953328734b73b0ac7242af8f` from durable #300 implementation intent.

Current recovery deliberately contains only three additive paths:
- `Packages/NembraCore/Sources/NembraCore/RideHistoryDurationAttachment.swift`
- `Packages/NembraCore/Tests/NembraCoreTests/RideHistoryDurationAttachmentTests.swift`
- `docs/RIDE_HISTORY_DURATION_ATTACHMENT.md`

The older #300 branch also modified `RideDurationStatistics.swift` and added a statistics-adapter test. Current V14 recovery does **not** replay that shared-source modification blindly because `main` has evolved it independently. Statistics/app integration should consume this validated joined record in a separately coordinated follow-on after current ownership is refreshed.

## Next rung

After package acceptance, the next product step is a concrete app persistence implementation of `RideHistoryDurationStore` plus authoritative completion-handoff wiring from accepted monotonic duration evidence. That integration must preserve the same evidence distinctions and must not substitute wall-clock subtraction when duration evidence is absent.

## Hardware boundary

SOFTWARE PERSISTENCE / HISTORY TRUTH ONLY. No BLE/Tuya field, physical ES80 timing, background-execution guarantee, reconnect timing, command behavior, or physical iPhone result is claimed.
