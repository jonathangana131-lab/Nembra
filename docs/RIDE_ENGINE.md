# Automatic ride engine

Nembra's ride session is domain state, not SwiftUI screen lifetime. `RideEngine` is a deterministic core state machine that accepts quality-screened observations and owns continuity across ordinary UI navigation and transport loss. `RideCheckpointCoordinator` adds the durable mutation boundary; see `docs/RIDE_PERSISTENCE.md`.

## Current phases

- `idle` — no candidate or confirmed scooter ride
- `candidate` — movement hints exist, but the evidence has not crossed the injected confirmation policy
- `active` — a scooter ride has been confirmed
- `temporarilyDisconnected` — the same confirmed ride remains alive while vehicle transport is unavailable
- `endingCandidate` — authoritative movement has stopped, but the stop-duration policy has not yet elapsed

The engine emits `CompletedRideEvidence` when end confirmation succeeds. In application composition, the checkpoint coordinator first writes that evidence as `completedPendingCommit`; the completed-history handoff must durably commit and read back the same session evidence before the recovery journal may be cleared.

## Evidence rules

Automatic detection can ingest:

- fresh authoritative BLE or GPS speed samples (freshness threshold is injected, not hard-coded as MAXSHOT truth)
- scooter odometer readings
- quality-screened GPS distance **increments**, accumulated by the engine rather than accepted as a caller-supplied route total
- a bounded Core Motion movement hint
- vehicle connection state
- monotonic and wall-clock timestamps

Motion is deliberately weak evidence. It may wake or keep a pre-ride candidate alive, but it cannot independently confirm a scooter ride and it does not keep a confirmed ride alive indefinitely.

A confirmed ride can be established by policy-qualified **fresh** authoritative speed, cumulative quality-screened GPS distance increments, or monotonic scooter ODO growth. A stale speed packet cannot start or sustain a ride. The exact MAXSHOT thresholds are **not** hard-coded; `RideDetectionPolicy` must be injected and will be calibrated only after hardware/field traces exist.

## Continuity rules

- a tiny movement blip may become `candidate` and then cancel without creating a ride
- disconnecting before confirmation cancels the candidate
- disconnecting after confirmation moves the same session to `temporarilyDisconnected`
- transport loss alone never finalizes a confirmed ride
- reconnecting with movement resumes the same session
- movement returning during `endingCandidate` resumes the same session instead of splitting the ride
- an increasing scooter ODO counts as movement even if a live speed notification is temporarily missing
- if the first ODO sample arrives after candidate or ride start, that first actually observed value becomes the baseline; Nembra never backdates it to pretend earlier mileage was measured
- stale authoritative speed older than the injected freshness policy cannot start, confirm, or sustain movement
- a stationary reconnect begins end confirmation without emitting a false `rideResumed` event
- invalid, overflowing, or out-of-order observations are rejected transactionally and cannot rewind phase or advance the monotonic observation clock
- session-ID generation is injectable so observation replays and recovery tests can be deterministic
- recovered sessions preserve their UUID and wall-clock evidence but do not fabricate historical uptime
- recovery itself is not a vehicle observation; fresh post-recovery evidence is required before the ride can resume or begin a new end-confirmation timer

## Application evidence boundary

Phase 12 adds a root-owned `RideApplicationStore` around this engine without changing its domain semantics.

- SwiftUI view lifetime never owns the ride.
- the application registers both vehicle-state and raw-speed streams before startup returns.
- only fresh raw authoritative speed packets may populate `RideObservation.speedSample`.
- cached `VehicleState.speedKilometersPerHour` is not converted into a new packet.
- mode/light/lock acknowledgements cannot replay an old speed measurement or fabricate a zero.
- state-only observations enter the ride engine for meaningful connection transitions or real ODO advancement.
- if state and raw-speed stream scheduling invert during reconnect, only the newest unconsumed packet may be held while state says connecting/reconnecting; it is consumed once when confirmed connected state catches up, cleared on disconnect, and remains freshness-limited by the engine.

The explicit Simulator QA application path proves process terminate/relaunch recovery of the same durable ride identity. Ordinary unverified production launch still has automatic ride detection disabled because real MAXSHOT speed cadence/reconnect timing has not yet calibrated the injected policy.

## Completed evidence integrity

`CompletedRideEvidence` validates its durable numeric shape both when constructed and when decoded. GPS distance must be finite and nonnegative. Scooter ODO evidence is either absent at both endpoints or finite/nonnegative at both endpoints with end ODO not below start ODO.

Wall-clock ordering is not used as the in-process truth source because the system clock can change while a ride is active. Monotonic uptime governs runtime ordering; wall-clock dates provide durable identity/history across process lifetime.

## Distance truth

`CompletedRideEvidence` currently exposes start/end scooter ODO evidence, a nonnegative ODO delta when both endpoints are valid, and accumulated quality-screened GPS route-distance evidence observed during the session. It does **not** yet choose a final reconciled ride distance.

Ride-level reconciliation/presentation must preserve separately:

- start ODO
- latest/end ODO
- ODO delta
- GPS route distance
- live integrated distance
- route gaps
- connection timeline
- final reconciled distance + confidence/status

## Implemented persistence boundary

Confirmed rides produce compact crash-recovery checkpoints. The two-slot journal restores the same session UUID after process loss, treats old uptime as unusable, falls back from a corrupt newest slot, and preserves a completed ride in `completedPendingCommit` until completed history acknowledges a durable exact commit.

Phase 12 also provides the concrete local SwiftData completed-history adapter through the pre-existing `RideHistoryStore` contract. Equivalent duplicate records are idempotent, conflicting same-ID evidence is rejected, and durable readback is verified before the journal can clear.

This does **not** mean the entire ride-storage/history product is complete.

## Not complete yet

Still pending:

- route-point/chunk persistence (the core currently retains screened GPS distance evidence, not path geometry)
- connection timeline persistence
- crash-safe ride-level aggregation of multiple process-local live integrated-distance segments
- ODO coverage classification/reconciliation after missed intervals
- history/stats queries and finished ride-history UI over the real ledger
- background Core Bluetooth integration
- background location capture
- final production detection/checkpoint/distance thresholds
- physical iPhone performance/profile validation
- real MAXSHOT hardware validation

Those layers must consume the same ride identity/evidence rather than tying ride lifetime to a view.
