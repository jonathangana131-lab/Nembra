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

`AtomicRideCheckpointStore` uses two alternating JSON slots with monotonically increasing generations. A save writes the older or unused slot using Foundation atomic replacement and immediately decodes the new file before reporting success. When both active slots are readable, the previous generation remains a known-good fallback.

An unreadable active slot is different from a readable older generation: its generation, ride session, and checkpoint kind cannot be proven. A read I/O failure and malformed bytes are therefore both treated as ambiguous journal authority. Nembra fails closed rather than promoting or overwriting the readable sibling.

The journal:

- loads the newest generation only when every present active slot is readable and supported,
- fails closed on any `corrupt + valid` or `corrupt + missing` active-journal state instead of guessing which bytes are authoritative,
- preserves unreadable forensic bytes and refuses to write a new peer while authority is ambiguous,
- refuses to overwrite when both slots are corrupt,
- rejects divergent payloads with the same generation,
- rejects unsupported schema versions instead of silently downgrading them,
- rejects generation overflow,
- validates active and completed evidence again while decoding,
- clears fully readable journals from older/equivalent fallback to newest authority so interruption cannot expose an older ride after completion acknowledgement.

This intentionally trades single-slot corruption liveness for restart safety in the current schema. Recovering from an ambiguous unreadable slot requires a future explicit recovery/authority protocol; the app must not silently resume a ride from the readable peer. The journal does **not** claim stronger power-loss durability than the filesystem/Foundation atomic-write semantics provide.

## Coordinator transaction rules

`RideCheckpointCoordinator` owns the mutation boundary between the ride engine and the journal.

- Ride start and significant confirmed-ride transitions are checkpointed immediately.
- Stable active observations checkpoint only at an injected cadence; Nembra does not write to disk for every telemetry frame.
- The cadence has no production default until iPhone write cost and recovery requirements are measured.
- Required persistence writes occur before the coordinator accepts the corresponding in-memory transition.
- A required save error can have an indeterminate filesystem outcome. The coordinator keeps its prior in-memory engine state but latches ride mutation unavailable for that coordinator instance; later or already-queued observations cannot create a newer checkpoint from stale memory. A fresh `restoring(...)` pass is required to reconcile durable authority before ride mutation resumes.
- The first failing save still surfaces its underlying error. Later ingestion on the faulted coordinator fails with `checkpointPersistenceUnavailable` before staging or calling the store.
- The persistence-fault guard is checked after the FIFO mutation permit is acquired so a waiter that queued while the first save was suspended cannot slip through after that save faults.
- When a ride ends, `completedPendingCommit` is written before the coordinator accepts the completed state.
- While a completed ride is pending, new ride ingestion is blocked so the recovery journal cannot be overwritten.
- The journal is cleared only after the completed-ride ledger durably commits and reads back the same session evidence.
- If history commit/readback or journal clearing fails, the pending completion remains blocked and retryable; a clear failure is not treated as the same condition as an indeterminate checkpoint save.

That final pending state closes the crash window between “ride detector emitted completion” and “history database actually owns this ride.”

## Application ownership

The app connects this journal to application lifetime through root-owned `RideApplicationStore` rather than a SwiftUI view.

- `AppRuntime` owns one shared scooter service, `VehicleStore`, and `RideApplicationStore`.
- process relaunch restores the same durable ride UUID conservatively, then requires fresh evidence before resuming active state.
- corrupt/ambiguous checkpoint restore fails before live ride evidence streams are admitted; the app must expose persistence unavailable rather than silently resuming a fallback.
- the state and raw-speed service streams are registered before ride-store startup returns, so the first new packet cannot race past the subscriber.
- only fresh authoritative raw-speed packets can populate `RideObservation.speedSample`; cached vehicle-state speed and control acknowledgements are never replayed as measurements.
- independent reconnect state/speed stream ordering is handled by retaining at most the newest unconsumed authoritative packet while state is connecting/reconnecting, consuming it once when confirmed connected state catches up, clearing it on disconnect, and still enforcing ride-engine freshness.
- existing Simulator QA is application-path evidence only. It does not verify physical AOVOPRO ES80 telemetry, outdoor GPS quality, or iPhone background behavior that has not been measured on hardware.

## Completed history ledger

A concrete local SwiftData `RideHistoryStore` implements the completed-history contract.

- it stores the exact validated `RideHistoryRecord` payload with a unique session UUID;
- equivalent duplicate commits are idempotent success;
- the same UUID with different evidence is a conflict and never overwrites history;
- the record is read back and verified before `completedPendingCommit` may be acknowledged;
- a stored payload whose session UUID disagrees with its indexed row is treated as corruption;
- Simulator recovery/history storage is namespaced away from future production data.

Simulator/software proof remains separate from physical ES80 field proof.

## Still pending

This is not the whole ride-storage product. Still pending:

- explicit product recovery/repair UX for an ambiguous unreadable checkpoint journal,
- deterministic injected read/write I/O fault coverage for “bytes changed, verification failed” boundaries beyond the coordinator-level fail-closed latch,
- persistent route-point/chunk storage and route-gap metadata where not already accepted by the active Ride cell,
- connection timeline persistence,
- crash-safe **ride-level** aggregation of multiple process-local live-distance segments,
- precise ODO coverage classification from real AOVOPRO ES80 reads/reconnects,
- production distance-reconciliation policy calibration,
- statistics/day/week/month queries and finished ride-history UI over the real ledger,
- background Core Bluetooth and Core Location lifecycle wiring/acceptance within actual iOS constraints,
- production checkpoint cadence calibration on physical iPhone hardware,
- real AOVOPRO ES80 hardware validation.

MAXSHOT V1S Pro hardware validation remains deferred/unverified; reusable generic vehicle architecture is preserved.
