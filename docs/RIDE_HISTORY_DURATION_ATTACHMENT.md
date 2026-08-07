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

The joined type is intentionally not `Codable`, and construction is sealed in both build compositions: SwiftPM exposes only a `package` initializer for trusted NembraCore tests/adapters, while Nembra.app's current direct-source composition gets a `fileprivate` initializer. Persistence stores the two independently valid records, then the core coordinator revalidates their relationship when loading them. App code may consume a joined record returned by that coordinator but cannot directly manufacture one from arbitrary matching records. A matching UUID with mismatched continuity therefore fails closed instead of silently becoming ride history.

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

## Trusted statistics bridge

`RideDurationStatisticsRide` now owns the trusted history-duration bridge in its existing source file. Independent completed-ride + duration construction remains `package`-scoped under SwiftPM and becomes `fileprivate` in Nembra.app's direct-source composition. The public production initializer instead accepts `RideHistoryDurationJoinedRecord`, which app code can receive from the coordinator but cannot forge directly.

The bridge preserves the existing statistics semantics exactly:

- observed duration comes only from `CompletedRideDurationEvidence`;
- unavailable duration remains unavailable rather than becoming zero;
- partial recovered duration remains partial and never fills missing intervals;
- the caller must still explicitly choose `.rideBegan` or `.rideEnded` calendar attribution for rides that cross a bucket boundary.

This makes the durable history join usable by the existing duration-statistics domain without reopening a raw-record construction path or requiring a second adapter source file.

## App-target visibility boundary

The current iOS target manually compiles selected NembraCore source files rather than linking the full Swift package product. The new history-duration source remains package/domain-only until a Class-A integration owner deliberately adds its complete source dependency closure to the app target. `RideDurationStatistics.swift` also now compiles safely in both SwiftPM and direct-source modes, but current package acceptance still does not prove production-app visibility until that wiring exists.

## Parallel ownership boundary

This slice does not modify `RideHistoryCommit.swift`, `RideApplicationStore.swift`, `RidePersistence.swift`, `AppBootstrap.swift`, Dashboard/Home views, the Xcode project, or global project-memory files. It makes one focused change to the previously unowned `RideDurationStatistics.swift` trust/build boundary and otherwise adds isolated duration history/tests/docs. This avoids active ownership in the compact-history and ride-location lifecycle lanes.

The next production step, after those owners are clear, is a concrete app persistence implementation for `RideHistoryDurationStore` plus completion-handoff wiring from the authoritative `RideDurationObservationOwner`. Only after that durable app storage/handoff exists should Ride Details/Home/Statistics display completed observed duration; the statistics conversion boundary itself is now available once a validated joined record can be loaded.

## Truth boundary

This is software/domain persistence composition only. It does not verify AOVOPRO ES80 BLE timing, packet cadence, reconnect timing, app background execution, physical iPhone behavior, or any scooter protocol field. Simulator/package tests do not become physical-hardware proof.
