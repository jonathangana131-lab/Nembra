# Ride Location Lifecycle Durability Recovery — chat-d9v4k

PROTOCOL_VERSION: 7
WORKER_ID: chat-d9v4k
ROLE: RECOVERY / HARDENING
LANE_ID: recover-ride-location-lifecycle-durability
EPOCH: 2
CONTROL_CLAIM: issue #79 comment 5210954362
PREDECESSOR_PR: #50
PREDECESSOR_WORKER: chat-z4n8p
PREDECESSOR_HEAD: 3cb6e7ad3cacb8580131288edc89be517739fab0
RECOVERY_BRANCH: parallel/recover-ride-location-lifecycle-durability/chat-d9v4k
RECOVERY_BASE: exact predecessor head 3cb6e7ad3cacb8580131288edc89be517739fab0
LIVE_MAIN_AT_TAKEOVER: 8dcf1459bd9152a94d6616fe1597e4a835a4972a

## Owned paths

- NembraApp/App/AppBootstrap.swift
- NembraApp/App/RideApplicationStore.swift
- NembraApp/App/RideLocationCapture.swift
- NembraApp/App/RidePersistence.swift
- NembraAppTests/RideApplicationTests.swift
- NembraAppTests/RideLocationCaptureTests.swift
- NembraUITests/RideUITests.swift
- docs/RIDE_LOCATION_CAPTURE.md
- docs/swarm/RECOVER_RIDE_LOCATION_LIFECYCLE_DURABILITY_chat-d9v4k.md

No workflow, project.pbxproj, global project-memory, battery/range, BLE/protocol, or motorized-hardware command path is owned by this recovery.

## Source-backed blockers inherited from #50 review

### 1. Route persistence truth is discarded before history publication

`RideLocationCaptureCoordinator.finish()` already computes `routePersistenceFailed`, but AppRuntime currently discards the summary and recovered-draft errors with `try?`. Completed history can therefore become durable and clear `completedPendingCommit` while a ride whose route storage failed later looks indistinguishable from a ride for which no route was recorded.

Required truth boundary:
- successful durable route geometry remains recorded geometry;
- zero accepted route points without a storage failure remains no-route evidence;
- route begin/append/finish/recovery failure remains a durable storage-failed outcome;
- completed ride history remains independent and must not be blocked merely because optional map storage failed;
- failure classification itself must survive before the completed checkpoint is acknowledged.

### 2. Buffered location can cross the ride-completion cutoff asymmetrically

The current coordinator appends an accepted route point before sending its distance delta through the session-scoped ride gate. During the completion barrier, RideApplicationStore closes GPS acceptance with `isFinalizingCompletedRide`, so an already-yielded buffered point can be written into route geometry while its GPS-distance contribution is rejected from the already-frozen completed ride.

Required cutoff boundary:
- the authoritative ride-session acceptance decision happens before route persistence for that screened sample;
- a sample rejected because the ride is finalizing/ended contributes to neither route geometry nor completed GPS distance;
- completed ride evidence is never reopened or mutated after `rideEnded`.

### 3. Additive route-store failure must not silently disable independent GPS capture

The #50 coordinator supports `routeStore == nil` and continues screened GPS distance while reporting route persistence failure. AppBootstrap currently creates the Simulator ride-location coordinator only when the optional route store exists, which bypasses that intended independence. Recovery should preserve GPS/location evidence when the ride/history stack is available even if additive route persistence is unavailable.

## Planned packet order

1. Introduce a session-scoped location-evidence acceptance handshake and deterministic cutoff regression so route persistence cannot outrun ride-session GPS acceptance.
2. Add an app-side durable per-session route completion outcome/repair boundary that preserves recorded / no-route / storage-failed truth without widening `CompletedRideEvidence`.
3. Exercise same-process manifest-failure salvage and recovered-draft failure classification before checkpoint acknowledgment.
4. Keep GPS/history durable when route storage is unavailable; update presentation to distinguish no route from route-storage failure without inventing geometry.
5. Reconcile the coherent recovery tree onto fresh main only after blockers are closed, then obtain exact-final-head NembraCore + Xcode 27 / iPhone 12 / iOS 27 Simulator proof before merge.

## Dependency / overlap state

- #74 route-evidence summary is merged into main and was package-only; it has zero owned-file overlap. It summarizes only already-validated geometry and cannot replace the missing failure classification.
- #105 ride-provenance recovery owns NembraCore checkpoint/engine provenance paths and has zero changed-file overlap with this app-layer recovery. Do not mutate #105 ownership.
- Historical #50 branch remains untouched. This successor is a new branch from its exact durable head as required by v7.

## Validation truth

Historical #50 exact-head run 31131579958 was green and is useful regression evidence only. Independent v7 review found the blockers above afterward; the repaired successor requires a new exact-final-head gate.

Simulator/software evidence is not outdoor GPS validation, physical iPhone performance proof, or physical AOVOPRO ES80 verification. No ES80 BLE/GATT/DP semantics or motorized writes are part of this lane.
