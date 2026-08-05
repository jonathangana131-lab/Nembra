# Ride checkpoint persistence

Nembra uses a small crash-recovery journal for **confirmed rides in progress** and for the narrow handoff between ride completion and the future completed-ride history database. This journal is deliberately separate from the eventual SwiftData ride ledger and route store.

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
- The journal is cleared only after the future completed-ride ledger durably commits the same session UUID and acknowledges it.
- If journal clearing fails, the pending completion remains blocked and retryable.

That final pending state closes the crash window between “ride detector emitted completion” and “history database actually owns this ride.”

## Not complete yet

This checkpoint is **crash-safe session/evidence persistence**, not the whole ride-storage product. Still pending:

- completed-ride SwiftData schema and ledger transaction,
- route-point/chunk persistence and route-gap metadata,
- connection timeline persistence,
- live integrated distance evidence,
- multi-source ODO/GPS/live-distance reconciliation,
- background Core Bluetooth and Core Location lifecycle wiring,
- production checkpoint cadence calibration on iPhone,
- real MAXSHOT hardware validation.
