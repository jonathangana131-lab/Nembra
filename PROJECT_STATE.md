# PROJECT STATE

Updated: 2026-08-06

## Product
- Product: **Nembra**.
- First supported vehicle: **MAXSHOT V1S Pro**.
- Repository: `jonathangana131-lab/Nembra`.
- Permanent charter: `MASTER_CONTINUATION_DIRECTIVE.md`.
- Product stance: premium native iOS 27 scooter platform with capability-driven vehicle boundaries, truthful evidence, pessimistic confirmed commands, and simulation sharing production domain/service paths.

## Live repository state
- Stable `main`: `e0d584ec35e6c6eab2b0789c4d2fe74f5c82e213` after PR #7 merged durable completed-ride route geometry.
- Active branch: `feature/ride-location-capture`.
- Active PR: **#8 — Add truthful ride-scoped phone location evidence**.
- Active slice: ride-scoped phone location quality screening + Core Location source + capture coordinator.
- Resolve the exact current branch head and Actions run from GitHub before gating. This file is intentionally not a hard-coded head authority.

## Current implementation
Implemented on the active branch:
- platform-independent `RideLocationSample`, injected `RideLocationQualityPolicy`, deterministic `RideLocationQualityScreen`, explicit rejection reasons, continuity-gap segmentation, and adjacent accepted-point distance only.
- reduced/approximate location is rejected as precise route evidence; software-simulated locations require explicit policy permission.
- invalid/inaccurate/stale/future-dated/non-monotonic/implausible evidence cannot replace the last accepted baseline.
- current iOS Core Location async updates are wrapped behind `RideLocationSource` in `CoreLocationRideLocationSource`; Core Location types do not leak into the core evidence layer.
- receipt uptime is process-local ordering evidence; wall-clock timestamps are metadata and are not used to repair ordering.
- `RideLocationCaptureCoordinator` sends accepted coordinates to `RideRouteRecorder` while independently sending screened adjacent GPS-distance deltas to the existing `RideApplicationStore`/`RideEngine` path.
- route-store failure does not discard already screened GPS distance evidence; successful route persistence does not become a final-distance claim.
- explicit source interruptions force partial route coverage and never draw/integrate across the missing interval.
- app/core tests exercise route gap persistence, missing route-store behavior, coordinator reuse, GPS-distance integration into the existing ride engine, reduced-accuracy rejection, quality policy validation, jump/staleness/order behavior, and process-local reset behavior.
- `docs/RIDE_LOCATION_CAPTURE.md` records the software/field truth boundary.

## Current truth boundaries
- Production automatic ride detection remains disabled until real MAXSHOT cadence/reconnect behavior is measured.
- No production location quality thresholds have been selected yet; current thresholds are injected test/Simulator fixtures.
- The Core Location adapter is implemented in software but real outdoor route recording is **not field validated**.
- Background ride continuation is not yet claimed or accepted; it requires explicit lifecycle/background integration and physical-device QA.
- Reduced-accuracy location is not presented as a precise ride route.
- Simulator/software-generated locations are QA evidence only.
- No MAXSHOT BLE fact is inferred from GPS work and no motorized-hardware write behavior changes in this slice.
- Hosted iPhone 12/iOS 27 Simulator success is runtime evidence, not outdoor GPS or physical iPhone performance evidence.

## Current gate
1. Freeze the newest exact branch head after memory/docs commits.
2. Require `Xcode 27 Simulator QA` to pass project structure, core package, full Xcode app/tests/UI, and artifact upload on that exact head.
3. Inspect any failure rather than merging around it.
4. Confirm PR #8 is mergeable with no unresolved review threads/comments.
5. Mark ready only after the exact-head gate is green.
6. Squash merge with `expected_head_sha` equal to that exact green head.
7. Verify fresh `main` and immediately begin the next location vertical slice.

## Next location slice after this foundation
The next substantial step is ride-lifecycle ownership and real end-to-end QA:
- exercise the new capture coordinator through the explicit Simulator ride fixture rather than bypassing it with direct route-recorder writes,
- make quality-screened GPS distance appear through the real completed-ride history path while keeping ODO/GPS separate,
- begin/end capture from authoritative ride application state rather than SwiftUI view lifetime,
- then design foreground/background continuation using current iOS 27 location APIs before any production activation.

## Accepted systems to preserve
- capability-based `VehicleProfile` / `ScooterService` boundary and hardware-gated production service.
- typed connection failures and live/retained/unavailable semantics.
- serialized pessimistic confirmed commands with connection-generation invalidation.
- raw authoritative speed evidence separated from display interpolation.
- dedicated Dashboard speed instrumentation and confirmed-mode presentation personality.
- automatic `RideEngine`, two-slot crash recovery, and `completedPendingCommit` handoff.
- exact idempotent SwiftData completed-history ledger.
- independent ODO/GPS/live-distance coverage and reconciliation architecture.
- root-owned history/route presentation stores.
- immutable route chunks/manifests with explicit discontinuity topology and fail-closed assembly.

## Hardware / field validation still required
- MAXSHOT advertisement identity, GATT services/characteristics/properties, notifications, packet framing/checksum, read/write/ack behavior, firmware differences, DP101/102/103 semantics, and AccessorySetupKit descriptors.
- real iOS 27 location authorization/background behavior on device.
- outdoor GPS accuracy/staleness/jump/continuity policy from traces.
- stationary behavior and location energy impact.
- physical iPhone 12 profiling and real ride route continuity.

## Mandatory future release gate
Home/Dashboard/Rides/Route remain systems-era functional UI. The **Production Visual Overhaul / Final Product Design Pass** remains mandatory once enough truthful foundational inputs exist. A technically correct but mediocre screen is not final acceptance.
