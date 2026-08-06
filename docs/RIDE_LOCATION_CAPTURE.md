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

`RideLocationCaptureCoordinator` bridges one ride-scoped location source into:
- `RideRouteRecorder` for durable coordinates, and
- `RideApplicationStore.ingestQualityScreenedGPSDistanceDelta` for the existing `RideEngine` GPS-distance input.

The coordinator does not own a parallel trip counter or alternate ride state machine.

Route storage is additive. If route persistence is unavailable, already quality-screened GPS-distance evidence can still reach the ride engine. Conversely, successful route persistence does not prove GPS distance coverage by itself.

Explicit source interruptions force partial route coverage. Repeated gap notifications remain safe because route gap materialization is lazy until another accepted point exists.

## Root-owned ride lifecycle

The application/root layer now owns the location-capture lifetime for the explicit Simulator QA path.

`RideApplicationStore` emits ride-session lifecycle events only when the authoritative durable ride UUID changes. A temporary disconnect, an ending candidate, or recovery back to active riding keeps the same UUID and therefore does not stop/restart location capture merely because a SwiftUI screen changed state.

`AppRuntime` consumes that root lifecycle and starts `RideLocationCaptureCoordinator` only after a ride is confirmed. Because the candidate interval occurred before capture began, the Simulator route is intentionally classified as partial coverage rather than pretending the entire ride was recorded.

When `RideEngine` declares a ride complete, AppRuntime's completion barrier stops and drains the ride-scoped location source and finalizes its route manifest before completed history is committed/published. During that narrow finalization window, new session-scoped GPS engine input is rejected fail-safe so a buffered callback cannot re-enter the pending-completed ride and commit history early. Durable route coordinates already accepted by the coordinator remain an additive domain; they are not converted into missing ride distance after the engine has ended the session.

No SwiftUI view appearance/disappearance controls this lifetime.

## Explicit Simulator QA source

`SimulatorRideLocationSource` is an injected `RideLocationSource` used only by the opt-in completed-ride Simulator fixture.

It emits ordinary raw `RideLocationSample` values through the exact same source boundary as Core Location. Those samples then pass through:

`RideLocationSource` → `RideLocationQualityScreen` → `RideLocationCaptureCoordinator` → independent GPS-distance + route-persistence paths.

The fixture does **not** write `RideRouteRecorder` directly, does not inject a completed-history row, and does not fabricate GPS distance separately from screened adjacent coordinates. Its coordinates, cadence, accuracy, and policy are deterministic QA data only; they are not AOVOPRO ES80 motion evidence or outdoor iPhone GPS measurements.

The completed-ride UI test requires all of the following to remain independently observable:
- durable odometer distance evidence from the simulated scooter service,
- quality-screened GPS distance evidence from the injected location source,
- durable route geometry rendered by the real route/history presentation path.

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

Implemented on the current worker branch, with exact-head Xcode 27/iPhone 12 Simulator acceptance still required before merge:

1. Exercise the capture coordinator through an explicit injected Simulator location source and verify route plus separate GPS-distance evidence through the real ride/history UI path.
2. Drive capture begin/end from authoritative root-owned ride session identity rather than a SwiftUI view lifetime, including a deterministic regression for ending-candidate recovery preserving one session.

Still required before production activation:

3. Implement and test foreground/background transitions using current iOS 27 location lifecycle APIs.
4. Measure real outdoor traces on the target iPhone class and select production accuracy/staleness/gap/jump thresholds from evidence.
5. Validate energy impact and stationary behavior.
6. Verify permission denial, reduced accuracy, global location disablement, interruption, process recovery, and route-store failure states.
7. Keep production activation separate from AOVOPRO ES80 BLE validation; neither validates the other.
