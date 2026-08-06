# Navigation route contract

Date: 2026-08-06
Worker: `chat-k8x5d`
Lane: `navigation-route-contract`

## Purpose

Provide the first framework-neutral domain boundary for Nembra navigation before MapKit app wiring. This slice turns a route request and provider route result into immutable, testable NembraCore values without letting a cycling route become scooter-legality, scooter-safety, ride-distance, or telemetry evidence.

This follows the live MapKit research lane's recommended implementation order while remaining independent of its unmerged documentation branch.

## Implemented contract

`NavigationCoordinate`
- validates finite latitude in `-90...90`;
- validates finite longitude in `-180...180`;
- is routing/guidance input only;
- does not become ride-location evidence merely because it is representable in the navigation domain.

`NavigationRouteRequestIntent`
- preserves immutable origin and destination;
- defaults to the only currently accepted first-party routing basis: `.cycling`;
- records whether alternate routes were requested;
- does not claim that alternates exist or that any route is suitable/legal for the ES80.

`NavigationRouteStepSnapshot`
- preserves the provider's localized instruction string verbatim;
- preserves the optional provider notice verbatim;
- validates nonnegative finite distance;
- preserves projected step geometry;
- deliberately has no inferred maneuver enum, so localized text is not scraped into stronger semantics.

`NavigationRouteSnapshot`
- records explicit `.appleMapKitCycling` provenance;
- preserves route distance, expected travel time, geometry, ordered steps, advisory notices, highway flag, and toll flag;
- rejects negative/nonfinite route distance or expected travel time;
- rejects an empty route geometry or empty step list rather than manufacturing a usable route;
- permits legitimate zero-distance/zero-duration provider boundaries;
- deliberately contains no scooter-legality or scooter-safety field because MapKit cycling provenance cannot establish either.

## Truth boundaries

This contract does **not** establish:
- scooter legality on any route segment;
- bike-lane availability;
- surface condition;
- accessibility;
- ES80-specific safety;
- live route progress;
- current maneuver selection;
- off-route state;
- reroute eligibility;
- ride distance;
- GPS quality;
- speed, battery, or scooter telemetry.

A future MapKit adapter may project `MKRoute` and `MKRoute.Step` facts into these values. Presentation snapping or route matching must remain one-way derivation for guidance and must never feed map-matched coordinates back into the existing ride-location evidence pipeline.

The `.cycling` routing basis means only a cycling-based route suggestion. User-facing copy must not relabel it as “scooter legal”, “ES80 approved”, “safe for scooters”, or equivalent.

## Why this is in NembraCore

The domain contract intentionally imports no MapKit or CoreLocation types. That gives Nembra:
- deterministic package tests without live Apple servers;
- a stable seam for Simulator fixtures;
- a future MapKit adapter that can be tested for exact projection behavior;
- a route snapshot that Dashboard/navigation UI can consume without owning route-provider APIs;
- separation between route-provider facts and ride/telemetry truth.

## Deterministic coverage

The focused suite covers:
1. default cycling request basis;
2. explicit alternate-route preference;
3. latitude/longitude fail-closed validation;
4. preservation of route geometry, provider instructions, notices, advisories, distance, duration, highway/toll flags, and provenance;
5. preservation of empty terminal/localized instruction strings instead of inference;
6. invalid step-distance rejection;
7. invalid route distance/duration rejection;
8. empty route-geometry rejection;
9. empty route-step rejection;
10. valid zero-distance/zero-duration boundaries.

Supplemental Swift 6.2.1 harness result on this worker checkpoint:
- debug: 10/10 passed;
- release: 10/10 passed.

These are package-level software checks only. Final repository acceptance still requires the repository's exact-head Xcode 27 gate on the final immutable worker head.

## Next safe dependent slices

After this contract is accepted, non-conflicting follow-up work can add:
- a MapKit adapter that maps `.cycling` request intent into `MKDirections.Request` and projects `MKRoute` results into these snapshots;
- cancellation/stale-request protection around route planning;
- Simulator route fixtures that never call live Apple routing servers;
- guidance-progress geometry/state driven by already-screened location evidence;
- sustained-deviation/cooldown reroute policy;
- Dashboard navigation composition after the domain behavior is proven.

Those later slices must preserve the same truth separation and avoid high-contention root wiring until integration is ready.

## Hardware status

Software navigation-domain contract only. No physical AOVOPRO ES80 routing behavior, outdoor GPS behavior, route legality, or physical iPhone performance is verified here.
