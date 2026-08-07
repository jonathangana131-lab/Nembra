# Ride History Duration Attachment

Nembra now has a truthful monotonic ride-duration evidence model and a lifecycle-owned observation adapter, but the existing durable `RideHistoryRecord` still stores only `CompletedRideEvidence`. This slice closes the next safe, non-conflicting layer without rewriting the actively owned history record or deriving elapsed time from wall-clock dates.

## Product purpose

`RideHistoryDurationRecord` is an immutable supplemental record keyed by the same completed-ride session UUID. It stores only `CompletedRideDurationEvidence`, preserving the existing distinctions between:

- unavailable duration (`nil`, unknown coverage, zero segments);
- legitimately observed zero duration;
- complete single-segment monotonic observation;
- partial observation with one or more explicit unknown intervals.

The attachment never subtracts `beganAtDate`, `confirmedAtDate`, or `endedAtDate` to manufacture elapsed time. System-clock changes therefore cannot alter duration truth.

## Safe join

`RideHistoryDurationJoinedRecord` is a runtime-only validated join. It requires the attachment's session identity and recorded ride continuity to match the exact `RideHistoryRecord` before a consumer may present or aggregate duration.

The joined type is intentionally not `Codable`. Persistence stores the two independently valid records, then revalidates their relationship every time they are joined. A matching UUID with mismatched continuity therefore fails closed instead of silently becoming ride history.

A completed base ride without a duration attachment is ordinary duration unavailability. If an attachment exists without its required base history record, the coordinator treats that as a durable inconsistency and fails closed rather than hiding the orphan as normal unavailability.

## Commit order and durability

`RideHistoryDurationCommitCoordinator` requires the base completed ride to already exist. It then:

1. fetches the exact base `RideHistoryRecord` by session UUID;
2. validates `CompletedRideDurationEvidence` against that completed ride;
3. commits an immutable `RideHistoryDurationRecord` idempotently;
4. immediately reads the attachment back;
5. requires exact durable equivalence before reporting success.

A duration store must treat same-session replacement as a conflict. Replaying identical evidence is idempotent.

This ordering intentionally prefers a temporarily missing optional duration attachment over a corrupted or mismatched history metric. It does not yet solve how an app process durably carries in-flight duration evidence across the completion handoff; that remains an integration responsibility for the root ride lifecycle/persistence layer.

## Parallel ownership boundary

This slice is additive and does not modify `RideHistoryCommit.swift`, `RideApplicationStore.swift`, `RidePersistence.swift`, `AppBootstrap.swift`, Dashboard/Home views, the Xcode project, or global project-memory files. That avoids active ownership in the compact-history and ride-location lifecycle lanes.

The next production step, after those owners are clear, is a concrete app persistence implementation for `RideHistoryDurationStore` plus completion-handoff wiring from the authoritative `RideDurationObservationOwner`. Only after that durable app join exists should Ride Details/Home/Statistics display completed observed duration.

## Truth boundary

This is software/domain persistence composition only. It does not verify AOVOPRO ES80 BLE timing, packet cadence, reconnect timing, app background execution, physical iPhone behavior, or any scooter protocol field. Simulator/package tests do not become physical-hardware proof.
