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

## Validation required before production activation

1. Exercise the capture coordinator through the explicit Simulator ride fixture and verify both route and GPS-distance evidence through the real ride/history UI path.
2. Add ride-lifecycle ownership so capture begins/ends with the authoritative ride application state rather than a view lifetime.
3. Implement and test foreground/background transitions using current iOS 27 location lifecycle APIs.
4. Measure real outdoor traces on the target iPhone class and select production accuracy/staleness/gap/jump thresholds from evidence.
5. Validate energy impact and stationary behavior.
6. Verify permission denial, reduced accuracy, global location disablement, interruption, process recovery, and route-store failure states.
7. Keep production activation separate from AOVOPRO ES80 BLE validation; neither validates the other.
