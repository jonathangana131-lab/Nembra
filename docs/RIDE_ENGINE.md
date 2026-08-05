# Automatic ride engine

Nembra's ride session is domain state, not SwiftUI screen lifetime. `RideEngine` is a deterministic core state machine that accepts quality-screened observations and owns continuity across ordinary UI navigation and transport loss. `RideCheckpointCoordinator` adds the durable mutation boundary; see `docs/RIDE_PERSISTENCE.md`.

## Current phases

- `idle` — no candidate or confirmed scooter ride
- `candidate` — movement hints exist, but the evidence has not crossed the injected confirmation policy
- `active` — a scooter ride has been confirmed
- `temporarilyDisconnected` — the same confirmed ride remains alive while vehicle transport is unavailable
- `endingCandidate` — authoritative movement has stopped, but the stop-duration policy has not yet elapsed

The engine emits `CompletedRideEvidence` when end confirmation succeeds. In production composition, the checkpoint coordinator first writes that evidence as `completedPendingCommit`; a future completed-ride ledger must durably accept the same session before the recovery journal may be cleared.

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

## Completed evidence integrity

`CompletedRideEvidence` validates its durable numeric shape both when constructed and when decoded. GPS distance must be finite and nonnegative. Scooter ODO evidence is either absent at both endpoints or finite/nonnegative at both endpoints with end ODO not below start ODO.

Wall-clock ordering is not used as the in-process truth source because the system clock can change while a ride is active. Monotonic uptime governs runtime ordering; wall-clock dates provide durable identity/history across process lifetime.

## Distance truth

`CompletedRideEvidence` currently exposes start/end scooter ODO evidence, a nonnegative ODO delta when both endpoints are valid, and accumulated quality-screened GPS route-distance evidence observed during the session. It does **not** yet choose a final reconciled ride distance.

The next reconciliation/ledger layer must preserve separately:

- start ODO
- latest/end ODO
- ODO delta
- GPS route distance
- live integrated distance
- route gaps
- connection timeline
- final reconciled distance + confidence/status

## Implemented persistence boundary

Confirmed rides can now produce compact crash-recovery checkpoints. The two-slot journal restores the same session UUID after process loss, treats old uptime as unusable, falls back from a corrupt newest slot, and preserves a completed ride in `completedPendingCommit` until the future history ledger acknowledges a durable commit.

This does **not** mean the entire ride-storage feature is complete.

## Not complete yet

Still pending:

- completed-ride SwiftData ledger
- route-point/chunk persistence (the core currently retains screened GPS distance evidence, not path geometry)
- connection timeline persistence
- live integrated-distance evidence
- ODO reconciliation after a missed interval
- background Core Bluetooth integration
- background location capture
- final production detection/checkpoint thresholds
- real MAXSHOT hardware validation

Those layers must consume the same ride identity/evidence rather than tying ride lifetime to a view.
