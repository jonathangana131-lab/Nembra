# Ride-scoped phone location capture

Status: software implementation in progress. Real outdoor/background validation is not complete.

## Purpose

This slice adds the evidence boundary that can eventually feed Nembra's automatic rides and durable route geometry from the iPhone's location system without treating every Core Location update as trustworthy ride data.

The implementation deliberately keeps three layers separate:

1. **Raw phone location** — coordinates, source timestamp, receipt uptime, horizontal accuracy, reduced-accuracy state, and software-simulation provenance.
2. **Quality-screened evidence** — only samples accepted by an injected policy; continuous adjacent accepted samples may produce a GPS-distance delta.
3. **Durable route geometry** — accepted coordinates are persisted through the already accepted immutable route chunk/manifest store. Route geometry and GPS distance originate from the same screened sample stream but remain separate evidence domains.

Map rendering is never measured later and promoted into ride distance. GPS distance is never used to reconstruct missing route geometry.

## Core quality screen

`RideLocationQualityScreen` owns deterministic, platform-independent screening.

Its policy is injected and currently has no production AOVOPRO ES80/iPhone default. The policy can constrain:
- maximum horizontal accuracy,
- measurement age,
- future timestamp skew,
- maximum continuous reception gap,
- maximum implied speed between accepted coordinates,
- whether software-simulated coordinates are allowed.

The screen rejects invalid/reduced-accuracy/too-inaccurate/stale/future-dated/non-monotonic/implausible evidence according to the supplied policy. Rejected samples do not replace the last accepted baseline.

A known interruption or continuity timeout makes the next accepted point start a new route segment. No distance is invented across that boundary.

## iOS Core Location adapter

`CoreLocationRideLocationSource` wraps the current asynchronous Core Location update APIs behind `RideLocationSource`.

The adapter:
- requests a ride-scoped when-in-use service session rather than silently starting location at cold launch,
- uses the navigation-oriented live update configuration for the active ride source,
- forwards authorization/service diagnostics separately from coordinates,
- records process-local receipt uptime for ordering,
- records whether Core Location identifies a location as software simulated,
- does not itself decide whether a coordinate is trustworthy ride evidence.

Apple documents reduced-accuracy location as intentionally coarse in both space and time, potentially kilometer-scale, so Nembra does not use reduced-accuracy updates as precise ride-path evidence.

## Capture coordinator

`RideLocationCaptureCoordinator` bridges one ride-scoped location source into the existing ride application and route domains. It does not own a parallel trip counter or alternate ride state machine.

Every quality-screened point now crosses one application-owned admission boundary before it can become route evidence. The admission carries the exact durable ride UUID plus the optional adjacent GPS-distance delta:

- the first accepted anchor carries no distance and is admitted by session identity only,
- a later point is admitted only if its screened distance delta successfully enters the same active `RideEngine` session,
- if the ride has completed, changed identity, or is already finalizing, admission returns false and that coordinate is excluded from the route as well.

This ordering makes route and GPS completion cutoff deterministic instead of scheduler-dependent. A buffered location callback cannot be persisted as route geometry after its paired GPS evidence has been rejected by the completed ride.

Route storage remains additive. If the optional route database is unavailable, quality-screened GPS evidence can still reach the ride engine. Conversely, successful route persistence does not prove GPS distance coverage by itself.

Explicit source interruptions force partial route coverage. A route gap is materialized only after a post-gap point is both quality-screened and admitted to the active ride, so a rejected post-completion point cannot create a phantom route segment.

## Root-owned ride lifecycle

The application/root layer owns the location-capture lifetime for the explicit Simulator QA path.

`RideApplicationStore` emits ride-session lifecycle events only when the authoritative durable ride UUID changes. A temporary disconnect, an ending candidate, or recovery back to active riding keeps the same UUID and therefore does not stop/restart location capture merely because a SwiftUI screen changed state.

`AppRuntime` consumes that root lifecycle and starts `RideLocationCaptureCoordinator` only after a ride is confirmed. Because the candidate interval occurred before capture began, the Simulator route is intentionally classified as partial coverage rather than pretending the entire ride was recorded.

When `RideEngine` declares a ride complete, `RideApplicationStore` closes new location admission and awaits AppRuntime's throwing completion barrier before publishing/committing completed history. AppRuntime stops and drains the ride-scoped source, finalizes or repairs durable route evidence where possible, and durably records the route outcome. Only then may the existing idempotent completed-history commit acknowledge and clear `completedPendingCommit`.

If the route-outcome durability step itself throws, the completed ride remains in `completedPendingCommit` and the same obligation is retried on a later observation or launch. This is intentionally different from an ordinary optional route-database failure: the route database may fail without losing ride history, but the fact that it failed must itself become durable before the checkpoint is cleared.

No SwiftUI view appearance/disappearance controls this lifetime.

## Route outcome ledger

Route truth cannot live only inside the optional route database because that database is one of the things that may fail. `AtomicRideRouteOutcomeStore` therefore records one small, atomically replaced JSON record per ride session under the recovery directory, independently of SwiftData route geometry.

The states are:

- `recorded` — verified durable route geometry exists,
- `noRecordedGeometry` — the completed in-process capture verified that no geometry was recorded,
- `storageFailed` — route recording/storage/finalization failed and must not later be presented as ordinary no-route,
- `unknown` — a legacy/process-gap recovery has insufficient durable evidence to distinguish no-route from lost route work.

`storageFailed` and `unknown` are repairable. If a later recovery verifies a durable manifest, the outcome may be promoted to `recorded`. Contradictory terminal rewrites fail closed instead of silently rewriting historical truth.

`RideRoutePresentationStore` consults this outcome in addition to route geometry. A storage failure is surfaced as failure; `noRecordedGeometry` remains the ordinary unavailable/no-route state; a `recorded` outcome whose geometry cannot be verified is itself treated as failure.

## Manifest failure and crash-window recovery

A normal process can fail after one or more immutable route chunks have become durable but before the route recorder commits its final manifest. A process can also stop after `RideEngine` has made `completedPendingCommit` durable in the same window.

`RideRouteDraftFinalizer` handles only already-durable evidence:

- loads only existing chunks for the exact session,
- builds a conservative `.partial` manifest,
- validates the proposed result through the accepted `RideRouteGeometry` validator,
- commits the manifest idempotently,
- verifies the manifest by reading it back.

Normal completion uses the same salvage path immediately when manifest finalization reports failure. If durable chunks can be verified, the route becomes `recorded` with partial coverage. If they cannot be salvaged, the independent ledger records `storageFailed` before completed history may clear its checkpoint.

Recovery never invents coordinates, reorders points, joins unknown gaps, or measures stored geometry to manufacture missing GPS ride distance. A legacy recovered session with no manifest, no chunks, and no prior route outcome becomes `unknown`, not `noRecordedGeometry`, because a process boundary does not prove that nothing was recorded. Malformed/noncontiguous evidence fails closed and preserves a failure/repair obligation.

## Explicit Simulator QA source

`SimulatorRideLocationSource` is an injected `RideLocationSource` used only by the opt-in completed-ride Simulator fixture.

It emits ordinary raw `RideLocationSample` values through the exact same source boundary as Core Location. Those samples then pass through:

`RideLocationSource` → `RideLocationQualityScreen` → application session admission → independent GPS-distance + route-persistence paths.

The fixture does **not** write `RideRouteRecorder` directly, does not inject a completed-history row, and does not fabricate GPS distance separately from screened adjacent coordinates. Its coordinates, cadence, accuracy, and policy are deterministic QA data only; they are not AOVOPRO ES80 motion evidence or outdoor iPhone GPS measurements.

The strengthened completed-ride fixture uses two approximately 45 m legs delivered over real two-second intervals. This remains below the injected Simulator QA implied-speed ceiling while producing enough legitimate screened GPS distance to render visibly as about `0.1 mi`/`0.1 km` instead of merely existing internally and rounding to `0.0` in the completed-ride UI.

The completed-ride UI test requires all of the following to remain independently observable:
- durable nonzero odometer distance evidence from the simulated scooter service,
- quality-screened GPS distance evidence from the injected location source with a visibly nonzero localized value,
- durable route geometry rendered by the real route/history presentation path.

A preserved pre-hardening iPhone 12 Simulator screenshot proved why the stronger visible assertion is useful: that earlier path already produced legitimate nonzero GPS evidence and route geometry, but one-decimal presentation rounded the GPS row to `0.0 mi`.

## Current truth boundaries

- Production automatic ride detection remains disabled until real **AOVOPRO ES80** speed cadence/reconnect behavior is measured.
- Production location quality thresholds are not selected yet.
- The Core Location adapter is implemented in software but is not yet enabled as always-on production ride recording.
- Background ride continuation is not claimed yet. Apple's background location mechanisms still require lifecycle integration plus physical-device QA.
- Reduced/approximate location is not treated as precise route evidence.
- Simulator/software-generated coordinates may be enabled only by explicit QA policy.
- Simulator success is not outdoor GPS validation.
- No physical iPhone 12 energy/performance claim is made by hosted Simulator CI.
- This location slice does not verify ES80 BLE/protocol behavior, battery semantics, or motorized commands.

## Validation status and remaining gates

Implemented on the current worker branch, but not accepted until exact-head verification is green:

1. Route/GPS point admission uses one session-scoped application boundary and rejects post-completion buffered points from both domains.
2. Optional route-store startup failure no longer disables independent Simulator GPS capture/history behavior.
3. Root-owned ride lifecycle preserves one durable session identity through ending-candidate recovery.
4. Route outcomes are durably classified outside the optional route database as recorded / no recorded geometry / storage failed / unknown.
5. A throwing route-outcome completion barrier leaves completed history pending for retry rather than acknowledging the checkpoint first.
6. Durable chunks without a manifest are conservatively and idempotently recovered as partial coverage; empty legacy recovery is unknown and malformed evidence fails closed.
7. Deterministic unit/integration regressions cover admission cutoff, late GPS, lifecycle identity, route-outcome transitions/presentation, and completion-barrier retry. The inherited completed-ride UI test also requires visibly nonzero GPS evidence plus rendered route geometry.

Still required before merge:

8. Exact-final-head Xcode 27 / iPhone 12 / iOS 27 Simulator build and focused test acceptance.
9. V8 peer review appropriate to Class A/shared persistence composition; automated Codex review remains optional/disabled by default.

Still required before production activation:

10. Implement and test foreground/background transitions using current iOS 27 location lifecycle APIs.
11. Measure real outdoor traces on the target iPhone class and select production accuracy/staleness/gap/jump thresholds from evidence.
12. Validate energy impact and stationary behavior.
13. Verify permission denial, reduced accuracy, global location disablement, interruption, process recovery, and route-store failure states on real lifecycle paths.
14. Keep production activation separate from AOVOPRO ES80 BLE validation; neither validates the other.
