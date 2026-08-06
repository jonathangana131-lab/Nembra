# Ride checkpoint persistence

Nembra uses a small crash-recovery journal for **confirmed rides in progress** and for the narrow handoff between ride completion and the completed-ride history database. This journal is deliberately separate from the SwiftData completed-ride ledger and future route store.

## Durable states

`RideDurableCheckpoint` has two states:

- `inProgress(RideRecoveryCheckpoint)` — compact evidence for one confirmed ride that has not yet completed.
- `completedPendingCommit(CompletedRideEvidence)` — the ride detector has finished the ride, but the completed-ride ledger has not yet acknowledged a durable commit.

Unconfirmed candidates are not persisted as rides. A tiny movement hint should not become a durable ride record merely because the process terminated.

## What is persisted

An in-progress checkpoint contains the ride UUID, wall-clock start/confirmation times, the last observed wall-clock time, the current durable phase, scooter ODO endpoints when actually observed, and accumulated quality-screened GPS distance evidence.

Process-local monotonic uptime is **never persisted as historical time**. After process recovery, the same ride UUID and durable evidence are restored, but historical uptime fields are unavailable and the session returns as `temporarilyDisconnected` until fresh vehicle evidence establishes current state.

A recovered old `endingCandidate` timer is not resumed. Stop confirmation begins again from fresh post-recovery evidence, preventing an uptime value from another process or boot epoch from silently ending a ride.

## Journal design

`AtomicRideCheckpointStore` uses two alternating JSON slots with monotonically increasing generations. A save writes the older or unused slot using Foundation atomic replacement and immediately decodes the new file before reporting success. The previous known-good slot remains available as fallback.

The journal:

- loads the newest valid generation,
- falls back when the newest slot is corrupt,
- preserves a lone corrupt file and writes the unused slot instead of destroying forensic evidence,
- refuses to overwrite when both slots are corrupt,
- rejects divergent payloads with the same generation,
- rejects unsupported schema versions instead of silently downgrading them,
- rejects generation overflow,
- validates active and completed evidence again while decoding.

This protects against ordinary process interruption and partial/corrupt checkpoint files. It does **not** claim stronger power-loss durability than the filesystem/Foundation atomic-write semantics provide.

## Coordinator transaction rules

`RideCheckpointCoordinator` owns the mutation boundary between the ride engine and the journal.

- Ride start and significant confirmed-ride transitions are checkpointed immediately.
- Stable active observations checkpoint only at an injected cadence; Nembra does not write to disk for every telemetry frame.
- The cadence has no production default until iPhone write cost and recovery requirements are measured.
- Required persistence writes occur before the coordinator accepts the corresponding in-memory transition.
- If a required save fails, the old engine state remains intact so the exact observation can be retried.
- When a ride ends, `completedPendingCommit` is written before the coordinator accepts the completed state.
- While a completed ride is pending, new ride ingestion is blocked so the recovery journal cannot be overwritten.
- The journal is cleared only after the completed-ride ledger durably commits and reads back the same session evidence.
- If history commit/readback or journal clearing fails, the pending completion remains blocked and retryable.

That final pending state closes the crash window between “ride detector emitted completion” and “history database actually owns this ride.”

## Phase 12 application ownership

Phase 12 connects this existing journal to real app lifetime through root-owned `RideApplicationStore` rather than a SwiftUI view.

- `AppRuntime` owns one shared scooter service, `VehicleStore`, and `RideApplicationStore`.
- process relaunch restores the same durable ride UUID conservatively, then requires fresh evidence before resuming active state.
- the state and raw-speed service streams are registered before ride-store startup returns, so the first new packet cannot race past the subscriber.
- only fresh authoritative raw-speed packets can populate `RideObservation.speedSample`; cached vehicle-state speed and control acknowledgements are never replayed as measurements.
- independent reconnect state/speed stream ordering is handled by retaining at most the newest unconsumed authoritative packet while state is connecting/reconnecting, consuming it once when confirmed connected state catches up, clearing it on disconnect, and still enforcing ride-engine freshness.
- explicit Simulator QA has proven the active → process terminate → relaunch → recovered same-session path. This is application-path evidence, not physical MAXSHOT background validation.

## Completed history ledger

A concrete local SwiftData `RideHistoryStore` now implements the already-defined history contract.

- it stores the exact validated `RideHistoryRecord` payload with a unique session UUID;
- equivalent duplicate commits are idempotent success;
- the same UUID with different evidence is a conflict and never overwrites history;
- the record is read back and verified before `completedPendingCommit` may be acknowledged;
- a stored payload whose session UUID disagrees with its indexed row is treated as corruption;
- Simulator recovery/history storage is namespaced away from future production data.

Phase 12 Xcode 27/iOS 27 Simulator tests prove durable reopen, idempotency/conflict behavior, same-session recovery, completion handoff, journal clear only after history ownership, and process relaunch continuity.

## Still pending

This is not the whole ride-storage product. Still pending:

- persistent route-point/chunk storage and route-gap metadata,
- connection timeline persistence,
- crash-safe **ride-level** aggregation of multiple process-local live-distance segments,
- precise ODO coverage classification from real MAXSHOT reads/reconnects,
- production distance-reconciliation policy calibration,
- statistics/day/week/month queries and finished ride-history UI over the real ledger,
- background Core Bluetooth and Core Location lifecycle wiring,
- production checkpoint cadence calibration on physical iPhone hardware,
- real MAXSHOT hardware validation.
