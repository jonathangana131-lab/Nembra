# PROJECT STATE

Updated: 2026-08-06

## Product
- Product: **Nembra**.
- First supported vehicle: **MAXSHOT V1S Pro**.
- Repository: `jonathangana131-lab/Nembra`.
- Permanent charter: `MASTER_CONTINUATION_DIRECTIVE.md`.
- Product stance: premium native iOS 27 scooter platform, capability-based architecture, truthful telemetry/evidence, pessimistic confirmed commands, simulation and hardware sharing the same production domain/service boundaries.

## Live repository state
- Stable base before the current slice: `main` at `c79dec497bee7bc7047601963204b568acec8d5e` (Phase 13 merged).
- Active branch: `feature/durable-ride-routes`.
- Active PR: **#7 — Persist and present truthful completed-ride route geometry**.
- Active milestone: **Phase 14 — durable completed-ride route geometry**.
- Accepted implementation head before this memory checkpoint: `088c849757a1a688255acc1538c96aa725b24a12`.
- Always resolve the exact current branch head from GitHub before gating or merging; this documentation checkpoint is a descendant of the accepted implementation head.

## Phase 14 implementation
Phase 14 adds durable completed-ride route geometry without pretending that production GPS capture is already validated.

Implemented:
- validated `RideRoutePoint`, immutable `RideRouteChunk`, `RideRouteManifest`, `RideRouteGeometry`, and explicit segment/gap semantics in core.
- route point ordering is ride-local monotonic sequence evidence; wall-clock dates never repair or reorder geometry.
- chunk/session/index identities are verified against encoded payloads on read.
- equivalent route writes are idempotent; same identity with different evidence is a conflict and cannot overwrite prior geometry.
- persisted geometry fails closed on missing/reordered chunks, bad counts, non-monotonic points, session mismatch, corrupt payloads, or invalid manifest topology.
- `RideRouteRecorder` incrementally assigns sequence numbers, chunks accepted points, commits partial buffers, and makes process recovery an explicit discontinuity.
- recorder topology is transactional around rejected input/overflow; invalid coordinates or sequence/index exhaustion cannot silently advance route segment state.
- a route that observed a gap/recovery cannot be finalized as complete coverage.
- route storage is physically isolated in `RideRoutes.store` from the accepted `RideHistory.store` ledger/recovery journal.
- route-store startup/read failure does not erase completed ride history; presentation distinguishes storage failure from a ride that truthfully has no route.
- root-owned `RideRoutePresentationStore` keeps SwiftUI away from direct SwiftData access.
- Ride Details uses MapKit only for validated stored geometry and draws each recorded segment independently with `MapPolyline`.
- one-point/non-drawable geometry is reported as recorded points without inventing a line.
- missing geometry is reported as **No route geometry recorded**; corrupt/unavailable route storage is reported as an error, not as successful emptiness.
- explicit Simulator QA writes deterministic synthetic coordinates through the real recorder/store/presentation path. It is physically namespaced from production and classified **partial** because the fixture begins route capture after the simulated ride is already underway.
- Simulator route coordinates never become `qualityScreenedGPSDistanceMeters`; route display and GPS distance evidence remain separate truth domains.

## Phase 14 truth boundaries
- production Core Location route capture remains **disabled**.
- no route geometry is reconstructed from ODO, displayed map interpolation, or any other lower-fidelity source.
- no visual line is drawn across a known route gap.
- map geometry is not a final-distance claim.
- ODO and GPS distance evidence remain independently labeled/reconciled.
- Simulator coordinates are synthetic QA evidence only and never validate real outdoor GPS behavior.
- this slice does not validate MAXSHOT BLE, physical iPhone 12 performance, background location, or force-quit recovery.

## Phase 14 accepted implementation-head evidence
Accepted implementation head: `088c849757a1a688255acc1538c96aa725b24a12`.

GitHub Actions:
- workflow: **Xcode 27 Simulator QA**
- run: `31082309937`
- job: `92553689585`
- artifact: `8960225545` / `nembra-xcode27-simulator-222-1`
- conclusion: **success**
- project structure validation: passed
- core package validation: passed
- full Xcode/iOS 27 Simulator build/test/capture stage: passed
- artifact upload: passed

XCTest evidence from the preserved log:
- app/core Xcode session: **27/27**, 0 failures
- UI session: **7/7**, 0 failures
- existing Dashboard mode/recovery regression tests remain green.
- completed-ride route end-to-end UI test: `RideUITests/testCompletedRideAppearsWithDurableRouteThroughRealRidePipeline()`.

Inspected iPhone 12 / iOS 27 test attachments:
- **Completed Ride History**: one truthful completed ride row, explicit `ODO 0.2 mi`, no generic final-distance claim.
- **Completed Ride Details With Route**: real MapKit surface from stored synthetic route points, explicit **Partial recorded coverage**, ODO evidence remains separate, no fake GPS-distance value.

Visual/runtime self-critique for this systems slice:
- route map is clearly visible and the stored line renders correctly through MapKit.
- the iOS 27 floating tab bar overlays part of the lower map area while the List remains scrollable; this is acceptable for the functional systems slice but is not final visual acceptance.
- history remains intentionally sparse/generic with a large empty region after one ride.
- no clipping, unsafe-area crash, fabricated route, fabricated distance, or evidence-boundary regression was observed.
- Rides/Route presentation remains subject to the mandatory **Production Visual Overhaul / Final Product Design Pass**.

## Phase 14 final merge gate
1. Freeze the exact documentation-checkpoint branch head.
2. Require **Xcode 27 Simulator QA** to pass on that exact head; do not merge based only on run `31082309937` from the implementation head.
3. Confirm PR #7 remains mergeable with no unresolved review threads/comments.
4. Mark PR #7 ready for review.
5. Squash merge PR #7 with `expected_head_sha` equal to the exact green branch head.
6. Verify merged PR state and fresh `main` SHA.
7. Re-inspect fresh `main`, open PRs, branches, newest commits, Actions, `PROJECT_STATE.md`, and `CONTINUATION_PROMPT.md`.
8. Choose the next substantial vertical slice from fresh repository state and immediately create/start its branch; do not stop merely because Phase 14 merged.

## Accepted systems to preserve
- capability-based `VehicleProfile` / `ScooterService` boundary.
- hardware-gated `UnverifiedScooterService`; ordinary production launch never silently falls into simulation.
- typed connection failures and live/retained/unavailable vehicle-state semantics.
- serialized pessimistic confirmed commands with connection-generation invalidation.
- raw authoritative speed evidence separate from `VehicleState` and display interpolation.
- fixed-slot rolling speed instrumentation and confirmed-mode-only Dashboard personality.
- automatic `RideEngine` with disconnect continuity and injected hardware-unverified thresholds.
- two-slot crash-recovery journal plus `completedPendingCommit` handoff.
- exact idempotent SwiftData completed-history ledger.
- independent ODO/GPS/live-distance coverage and reconciliation architecture.
- root-owned completed-history and route presentation stores.
- durable route chunks/manifests with explicit gap topology and fail-closed assembly.

## Hardware / field validation still required
- real MAXSHOT advertisement identity.
- BLE services/characteristics/properties.
- notification cadence and speed latency/jitter/resolution.
- packet framing/checksum.
- read/write/ack behavior and firmware differences.
- MAXSHOT-specific DP101/DP102/DP103 semantics.
- AccessorySetupKit descriptors from observed hardware identity.
- real Core Location authorization/background behavior for iOS 27.
- outdoor location accuracy/staleness/jump policy and energy impact.
- physical iPhone 12 profiling and real ride route continuity.

## Real Xcode / Simulator proof policy
GitHub-hosted `xcode-27` is the authoritative remote Mac gate when direct interactive Xcode tooling is unavailable.
- iPhone 12 / iOS 27 is the explicit visual baseline.
- CI preserves `.xcresult`, logs, Simulator screenshots, and XCTest attachments.
- hosted Simulator proof is real iOS runtime evidence.
- it is not physical MAXSHOT BLE validation, real outdoor GPS validation, or physical iPhone 12 performance profiling.

## Mandatory future release gate — Production Visual Overhaul
Current Home/Dashboard/Rides/Route screens are intermediate functional implementations. Once enough truthful dependencies exist—especially battery/SoC, live ride/trip state, maps/navigation, completed rides, and confirmed vehicle/error state—perform the dedicated **Production Visual Overhaul / Final Product Design Pass** defined by `MASTER_CONTINUATION_DIRECTIVE.md` and `DECISIONS.md`.

Every major screen must go through real Simulator screenshot → critique → redesign → implement → run → screenshot → critique → repeat. A technically correct but mediocre screen is not final product acceptance.
