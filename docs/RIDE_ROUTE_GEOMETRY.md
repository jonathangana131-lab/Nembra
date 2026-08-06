# Ride Route Geometry

Status: active implementation contract for the completed-ride route slice.

## Purpose

Nembra stores route geometry as evidence that is separate from ride-distance evidence. A believable-looking line on a map is never allowed to become proof of distance, coverage, or scooter movement.

## Durable model

Route evidence is keyed by the completed ride `sessionID` and persisted in a separate local SwiftData store (`RideRoutes.store`).

Each accepted coordinate becomes a `RideRoutePoint` with:
- a ride-local monotonic `sequence` assigned by the recorder
- latitude/longitude
- Nembra capture date
- optional source measurement date
- optional horizontal accuracy retained as evidence

Coordinates and horizontal accuracy are validated before the point can exist.

Points are saved in immutable `RideRouteChunk` batches. Chunk identity is:

`sessionID + segmentIndex + chunkIndex`

Equivalent retries are idempotent. Reusing the same chunk identity for different coordinates is a conflict and never overwrites the original evidence.

A completed route gets one immutable `RideRouteManifest` containing:
- session ID
- recorded coverage classification
- segment count
- point count
- known geometry-gap count

The manifest does not create missing geometry. Loading a route fails closed when chunks, segments, point ordering, counts, or session identities disagree.

## Segments and gaps

A route segment is one explicitly continuous piece of recorded geometry.

A segment boundary is a real discontinuity in Nembra's evidence. Presentation draws each segment independently and must never connect two segments with an invented line merely to make the route look complete.

`complete` means the recording layer explicitly classified the stored route as complete. No-gap appearance by itself is not proof of completeness.

`partial` means the route contains only some known ride coverage, including a recording start after the ride was already underway or a known recording gap.

`unknown` means Nembra cannot justify a complete/partial classification. An empty finalized route is unknown and contains no drawable geometry.

## Recorder

`RideRouteRecorder` is app-lifetime infrastructure above `RideRouteStore`.

It:
- accepts only coordinates that a location-quality layer has already screened
- assigns durable point sequence numbers
- writes immutable chunks incrementally rather than holding an entire ride in memory
- can validate and resume an unfinished persisted draft
- can start a new segment after a known gap
- requires the caller to supply final coverage instead of inferring it from visual continuity

The recorder is not a GPS-quality filter. Production Core Location capture must remain disabled until Nembra has an explicit permission, quality-screening, ride-lifecycle, background, and energy policy.

## Presentation

Completed ride detail loads route geometry through the root-owned presentation store rather than querying SwiftData directly from SwiftUI.

When validated geometry exists:
- SwiftUI MapKit is used
- each recorded segment becomes its own `MapPolyline`
- the camera is fitted only to stored coordinates
- recorded coverage, point count, and known gaps remain visible evidence

When no coordinates were stored, Nembra shows a truthful no-route state and no map.

When coordinates exist but cannot form a two-point continuous path, Nembra says that points were recorded but does not draw a line.

When persisted geometry fails validation, Nembra shows a route error rather than rendering plausible corrupted geometry.

## Simulator QA

The explicit `NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE=1` fixture may write deterministic simulated coordinates through the same `RideRouteRecorder -> RideRouteStore -> presentation -> MapKit` path used by production architecture.

That fixture is:
- Simulator-only
- physically namespaced away from production storage
- synthetic, not user location evidence
- classified partial because recording starts after the simulated ride is already confirmed
- never promoted into `CompletedRideEvidence.qualityScreenedGPSDistanceMeters`

It proves software/runtime wiring only. It does not validate real Core Location riding behavior, background location, GPS quality, MAXSHOT BLE, or physical iPhone performance.

## Production capture gate

Before real route capture is enabled, Nembra must define and validate at least:
- current iOS 27 Core Location authorization flow
- when location collection begins/ends relative to confirmed ride state
- horizontal-accuracy acceptance policy
- stale/out-of-order location rejection
- implausible-jump handling without silently rewriting raw evidence
- background continuity behavior and force-quit limitations
- energy policy so high-accuracy updates do not run continuously outside a legitimate ride
- how recovery/relaunch creates an explicit route gap instead of drawing across missing process coverage
- how quality-screened coordinate evidence contributes to GPS distance independently from displayed map interpolation

Until those are implemented and field-tested, production route recording remains off.