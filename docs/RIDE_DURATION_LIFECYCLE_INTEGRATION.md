# Ride Duration Lifecycle Integration

`RideDurationObservationOwner` closes the layer between the accepted duration evidence accumulator and a future root-owned application ride lifecycle.

It owns exactly one active session, converts explicit process-local monotonic observation boundaries into durable duration segments, and preserves gaps rather than filling them from wall-clock time or a UI timer.

## Contract

- `begin` creates the first zero-length observed segment at an authoritative ride/session boundary.
- `observe` extends only the current contiguous segment using checked monotonic uptime differences.
- `markObservationGap` closes the current segment and requires the next segment to be explicitly resumed as gap-following evidence.
- `resumeObservation` starts a new segment and never counts the missing interval between gap and resume.
- `end` returns the exact complete/partial snapshot and releases the owner for a later ride.
- recovered attachment uses `beginsAfterUnobservedInterval: true`, so its first segment is already partial instead of pretending the pre-recovery interval was observed.
- stale/equal uptime and foreign-session callbacks fail closed.

The owner does not contain `Date`, a display timer, a cadence guess, or scooter telemetry semantics. It does not infer app suspension or reconnect gaps by timeout. Those boundaries belong to the root lifecycle that actually knows when observation authority was interrupted.

## Next product step

The current app's `RideApplicationStore` is the natural eventual owner because it already outlives SwiftUI screens and owns authoritative ride session identity. That wiring should occur only after overlap with active ride-lifecycle work is clear. It should create one process-generation UUID per runtime, begin duration observation when the ride becomes authoritative, explicitly mark lifecycle gaps, and publish `RideDurationCockpitState` from the owner's snapshot.

Dashboard integration must consume that published truth state. It must not create another accumulator or increment seconds from a SwiftUI timer. Complete duration may render as normal elapsed ride context; partial duration needs a concise visible and accessibility qualifier; unavailable remains unavailable rather than `0:00`.

## Truth boundary

Software lifecycle integration only. This does not verify physical AOVOPRO ES80 timing, BLE cadence, background execution, reconnect timing, or scooter protocol behavior. Simulator and package tests remain software evidence only.
