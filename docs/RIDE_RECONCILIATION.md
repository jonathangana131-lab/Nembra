# Completed ride handoff and distance reconciliation

This layer sits after crash-safe ride detection. It has two separate responsibilities that must not be conflated:

1. transfer one `completedPendingCommit` ride into local history without duplicates or loss;
2. reconcile independent distance evidence without rewriting or averaging raw measurements.

## Idempotent history handoff

`RideHistoryRecord` owns the validated `CompletedRideEvidence` exactly as produced by the ride engine. It does **not** bake in a final reconciled distance, so the raw ride identity/evidence remains stable if reconciliation improves later.

`RideHistoryStore` defines these required semantics:

- first commit of a session UUID -> `inserted`;
- retry of the exact same record -> `alreadyPresent`;
- same UUID with different durable evidence -> conflict, never overwrite.

`RideHistoryCommitCoordinator` performs the crash-sensitive transfer:

1. read the pending completed evidence from `RideCheckpointCoordinator`;
2. commit the corresponding history record;
3. read the record back and verify exact equivalence;
4. only then acknowledge the recovery coordinator, allowing its journal to clear.

If history commit/readback/journal clear fails, the pending recovery record remains. A retry may see `alreadyPresent` in history and safely finish the acknowledgement without creating a duplicate ride.

## Concrete SwiftData history adapter

Phase 12 implements the local iOS history adapter with SwiftData while preserving the existing core contract rather than moving storage semantics into SwiftUI.

`SwiftDataRideHistoryStore`:

- runs behind a model actor;
- stores the exact encoded `RideHistoryRecord` with a unique session UUID;
- reads back the exact record after insertion before reporting durable success;
- treats an equivalent duplicate as idempotent success;
- treats the same UUID with different evidence as a conflict;
- rejects a stored payload whose embedded session UUID does not match the indexed row;
- uses local-only storage (`cloudKitDatabase: .none`) in this phase;
- keeps explicit Simulator persistence in a separate namespace from future production records.

The application path now drives this handoff through root-owned `RideApplicationStore`. Xcode 27/iOS 27 tests prove reopen/idempotency/conflict behavior, corruption rejection, same-session process recovery, completion commit, and recovery-journal acknowledgement.

This proves the local transaction architecture. It does not yet provide finished ride-history browsing, CloudKit sync, route storage, or physical MAXSHOT validation.

## Distance evidence stays independent

`RideDistanceEvidence` keeps three possible sources separate:

- scooter ODO delta;
- quality-screened GPS route distance;
- live speed-integrated distance.

Every source also carries explicit coverage:

- `complete` — the producing subsystem can explicitly account for the ride interval represented;
- `partial` — a known coverage gap exists;
- `unknown` — completeness cannot currently be proven either way.

A missing source must have `unknown` coverage. Critically, **unknown is not treated as complete** simply because no gap was recorded.

This matters for ODO. `RideEngine` intentionally permits the first ODO baseline to arrive after a ride has started, so a valid ODO delta is not automatically a full-ride distance. The future ODO/location/integration layers must supply coverage truth explicitly.

## Reconciliation policy is injected

`RideDistanceReconciliationPolicy` contains:

- an explicit priority ordering of all known sources;
- absolute agreement tolerance;
- relative agreement tolerance;
- the minimum denominator used for relative comparisons;
- whether complete ODO may recover mileage across an explicitly partial lower source.

There is no MAXSHOT production policy yet. Source priority and tolerances require real scooter/location traces and field validation.

The reconciler never averages sources. It selects one measured source according to the injected order and reports comparisons against the others.

Possible outcomes include:

- insufficient evidence;
- complete single-source evidence;
- corroborated evidence;
- incomplete coverage;
- vehicle mileage recovered across a known coverage gap;
- unresolved disagreement requiring review.

## Gap recovery is deliberately narrow

A lower GPS/live distance can be marked as explained by missing coverage only when **all** of these are true:

- policy explicitly enables gap recovery;
- selected final source is scooter ODO;
- scooter ODO coverage is explicitly `complete`;
- the lower source coverage is explicitly `partial`;
- the lower source distance is actually below the ODO distance.

Partial or unknown ODO cannot recover another source. Unknown secondary coverage cannot be reclassified as an explained gap. A partial secondary source that exceeds ODO remains a conflict.

`recoveredCoverageGapMeters` is recovered **mileage only**. It never reconstructs missing route geometry or implies the GPS path is complete.

## Example: ODO survives a transport/location gap

If a ride has a complete scooter ODO interval from 143.2 km to 147.8 km, the scooter proves approximately 4.6 km of vehicle movement between those endpoints. If GPS captured only 3.0 km and the location subsystem explicitly marks that route as partial, a policy may select 4.6 km as vehicle distance and report approximately 1.6 km of recovered coverage gap.

The exact missing GPS path remains unknown.

If the ODO baseline itself was late/partial, Nembra must not make that recovery claim.

## Still pending

- persistent route points/chunks and route-gap metadata;
- connection timeline persistence;
- process-local raw-speed segment integration is implemented, but crash-safe ride-level aggregation across recovery segments remains pending;
- app wiring of live-distance aggregation/reconciliation into the active ride and completed ride presentation;
- precise ODO coverage classification from real MAXSHOT reads/reconnects;
- GPS quality-screening/location policy and production reconciliation calibration;
- statistics/day/week/month queries and finished history UI over the real SwiftData ledger;
- iOS background integration and real hardware validation.
