# Completed ride handoff and distance reconciliation

This layer sits after crash-safe ride detection. It has two separate responsibilities that must not be conflated:

1. transfer one `completedPendingCommit` ride into local history without duplicates or loss;
2. reconcile independent distance evidence without rewriting or averaging raw measurements.

## Idempotent history handoff

`RideHistoryRecord` initially owns the validated `CompletedRideEvidence` exactly as produced by the ride engine. It does **not** bake in a final reconciled distance, so the raw ride identity/evidence remains stable if reconciliation improves later.

`RideHistoryStore` is the storage contract for the future iOS history database. Its required semantics are:

- first commit of a session UUID -> `inserted`;
- retry of the exact same record -> `alreadyPresent`;
- same UUID with different durable evidence -> conflict, never overwrite.

`RideHistoryCommitCoordinator` performs the crash-sensitive transfer:

1. read the pending completed evidence from `RideCheckpointCoordinator`;
2. commit the corresponding history record;
3. read the record back and verify exact equivalence;
4. only then acknowledge the recovery coordinator, allowing its journal to clear.

If history commit/readback/journal clear fails, the pending recovery record remains. A retry may see `alreadyPresent` in history and safely finish the acknowledgement without creating a duplicate ride.

The platform-independent contract and transaction tests are implemented. The concrete production SwiftData history-store adapter is still pending iOS/Xcode work.

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

- concrete production SwiftData `RideHistoryStore` adapter;
- persistent route points/chunks and route-gap metadata;
- connection timeline persistence;
- process-local raw-speed segment integration is implemented; crash-safe ride-level aggregation across recovery segments remains pending;
- precise ODO coverage classification from real MAXSHOT reads/reconnects;
- production reconciliation policy calibration;
- statistics/day/week/month queries over the real history store;
- iOS background integration and real hardware validation.
