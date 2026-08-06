# PROJECT STATE

Updated: 2026-08-06

## Product
- Product: **Nembra**.
- First supported vehicle: **MAXSHOT V1S Pro**.
- Repository: `jonathangana131-lab/Nembra`.
- Permanent charter: `MASTER_CONTINUATION_DIRECTIVE.md`.
- Product stance: premium native iOS 27 scooter platform, MAXSHOT first, capability-based architecture, truthful telemetry/evidence, pessimistic confirmed commands, simulation and hardware sharing the same production domain/service boundaries.

## Live repository state
- Stable branch before the current slice: `main` at `ea0dfd64f7cb0a6af64d14612c594f141ae1d2d0` (Phase 12 merged).
- Active branch: `feature/completed-ride-history`.
- Active PR: **#6 — Expose truthful completed ride history**.
- Active milestone: **Phase 13 — truthful completed ride history presentation**.
- Accepted implementation head: `5e2e4b93cdc41af148dc7e029f6da88465dea7ff`.
- That implementation head is 5 commits ahead of the Phase 12 `main` base and 0 behind.
- The project-memory documentation checkpoint is the next descendant of that accepted implementation head. Always resolve the exact current branch head from GitHub before gating or merging.

## Phase 13 implementation

Phase 13 exposes the already accepted durable completed-ride ledger through the production portrait application without inventing a parallel history model.

Implemented:
- root-owned `RideHistoryPresentationStore` reads the existing SwiftData history adapter rather than querying persistence directly from SwiftUI.
- portrait app shell now provides native Home/Rides tabs while landscape continues to route to the dedicated Dashboard cockpit.
- Home content gets bottom safe-area allowance so iOS 27's floating tab bar does not cover the final vehicle content.
- completed rides are loaded newest-first as immutable `RideHistoryRecord` evidence.
- history rows label scooter **ODO** and **GPS** evidence independently rather than silently promoting one to a reconciled final distance.
- detail view exposes start/confirmed/end evidence and ride continuity without fabricating a duration from wall-clock labels.
- detail view labels **Scooter odometer delta** explicitly.
- route UI states **No route geometry recorded** when no real stored quality-screened coordinates exist; no map/line is fabricated.
- history/persistence errors remain visible and truthful rather than silently presenting an empty successful state.
- `NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE=1` is an explicit Simulator-only fixture for the riding scenario. It drives the real `SimulatedScooterService` → `RideEngine` → checkpoint/history commit → presentation path instead of inserting fake history rows.
- the Simulator fixture first establishes the ride ODO baseline, then advances real simulated trip/ODO distance, then supplies authoritative stopped packets so completion traverses the real production application pipeline.
- production automatic ride detection remains disabled until real MAXSHOT speed cadence/latency/reconnect behavior is measured.

## Phase 13 truth boundaries
- no route coordinates means no drawn route.
- no reconciled final-distance coverage means no generic final ride distance claim.
- ODO and GPS stay independent evidence.
- no fake ride duration is inferred from formatted start/end wall-clock labels.
- Simulator auto-completion is QA-only and opt-in.
- Simulator records remain physically isolated from production persistence.
- completing this software slice does not validate real MAXSHOT BLE behavior.

## Phase 13 exact Xcode / Simulator evidence

Accepted implementation head: `5e2e4b93cdc41af148dc7e029f6da88465dea7ff`.

GitHub Actions:
- workflow: **Xcode 27 Simulator QA**
- run: `31073268597`
- job: `92525538715`
- artifact: `8956630995` / `nembra-xcode27-simulator-197-1`
- runner/toolchain evidence: macOS 26.5.2, Xcode 27.0 build `27A5228h`, iOS 27.0 runtime `24A5390f`
- conclusion: **success**
- project structure validation: passed
- core package validation: passed
- full Xcode/iOS 27 Simulator app/UI stage: passed
- artifact upload: passed

XCTest evidence from the preserved `.xcresult`/log:
- app/core test session: **21/21**, 0 failures
  - `NembraAppTests`: 14 tests
  - additional core package suite in Xcode session: 7 tests
- UI test session: **7/7**, 0 failures
  - `NembraUITests`: 5 tests
  - `RideUITests`: 2 tests

Phase 13 end-to-end UI test:
`RideUITests/testCompletedRideAppearsInHistoryThroughRealRidePipeline()`
- launches the production app with explicit isolated Simulator persistence
- waits for the real ride pipeline to complete a QA ride
- opens the Rides tab
- verifies `rides.completed-row`
- opens the record
- verifies `rides.detail`
- verifies `rides.evidence.odometer`
- verifies `rides.route-unavailable`

Kept iPhone 12 / iOS 27 attachments inspected:
- **Completed Ride History**
- **Completed Ride Details**
- existing recovery regression evidence also remained green: **Automatic Ride Active Home** and **Automatic Ride Recovered Home**

Visual/runtime self-critique for this systems slice:
- history row is readable, native, and clearly labels `ODO 0.2 mi`; it does not masquerade as a final reconciled distance.
- detail screen clearly separates ride timeline, odometer evidence, and route availability.
- missing route geometry is communicated directly rather than filling space with a fake map.
- the iOS 27 floating tab bar remains clear of important content.
- no clipping, overlap, unsafe-area regression, or misleading evidence presentation was observed in the accepted captures.
- the Rides UI is intentionally a functional systems-era baseline; its large empty areas/generic list treatment are not final product-design acceptance and remain covered by the mandatory Production Visual Overhaul release gate.

## Phase 13 final merge gate
1. Commit this project-memory acceptance plus the missing permanent master charter on the active branch.
2. Freeze the resulting documentation head.
3. Require **Xcode 27 Simulator QA** to pass on that exact new head; do not merge based only on the earlier implementation-head run.
4. If green, mark PR #6 ready for review.
5. Squash merge PR #6 with `expected_head_sha` equal to the exact green branch head.
6. Verify the resulting `main` head and PR state.
7. Re-inspect fresh `main`, open PRs, branches, commits, Actions, and current project-memory files.
8. Determine the next substantial vertical slice from fresh GitHub state rather than stale phase prose; create the next branch and immediately begin it.

## Accepted systems to preserve

### Portrait Home
- status-first vehicle console with honest unknown/live/retained state.
- typed connection failures and correct recovery actions.
- confirmed/pessimistic controls and moving-state Lock safety.
- low-battery priority.
- intermediate visual baseline only.

### Phase 9 — dedicated landscape Dashboard
- dedicated cockpit, not portrait Home rotated.
- dominant speed, battery, Scooter Trip, ride mode, connection/model identity.
- stopped-only state-changing controls; moving-state controls disappear.
- no fake throttle/current/power gauge.
- intermediate visual baseline only.

### Phase 10 — measured-speed instrumentation
- raw authoritative speed remains separate from `VehicleState` and display frames.
- `SpeedInstrumentModel` rejects stale/motion-assist samples.
- `SpeedDisplayInterpolator` is render-only and non-predictive.
- fixed rolling speed geometry.
- only the speed subtree can redraw at display cadence during active interpolation.
- production interpolation remains hardware-gated until real MAXSHOT timing is measured.

### Phase 11 — confirmed-mode Dashboard personality
- personality is pure presentation state derived from confirmed mode.
- restrained Walk/Eco/Drive/Sport differences only.
- no RGB/gamer theme or invented performance implications.
- Reduce Motion supported.

### Phase 12 — ride application + persistence
- one root-owned `RideApplicationStore` reuses the accepted `RideEngine` and checkpoint/history coordinators.
- only fresh raw authoritative speed can become ride speed evidence.
- state acknowledgements cannot replay cached speed or manufacture zero.
- reconnect ordering may hold only the newest unconsumed fresh raw packet and consume it once when state catches up.
- crash-safe two-slot checkpoint journal plus `completedPendingCommit` handoff.
- SwiftData exact completed-history adapter with idempotent equivalent duplicate, conflict rejection, and exact readback verification.
- recovery/history storage isolated by simulation namespace.
- automatic production detection remains disabled until real MAXSHOT timing/reconnect evidence exists.

### Phase 13 — completed ride presentation
- production portrait Rides surface reads the exact durable ledger through a root-owned presentation store.
- evidence sources remain explicitly separate.
- route geometry is unavailable unless real coordinates were actually persisted.
- Simulator-only auto-completion fixture exercises the real application/history path.

## Core truth boundaries
- interpolated display speed is never telemetry or ride evidence.
- motion-assisted estimates never masquerade as authoritative scooter/GPS speed.
- disconnect never fabricates measured zero.
- Device Trip is not Today mileage.
- Dashboard personality follows confirmed mode and is presentation only.
- DP101/DP102/DP103 remain unmapped to user ride modes until hardware evidence proves semantics.
- real BLE writes remain blocked until command transport/meaning/acknowledgement are verified sufficiently.
- no VESC-style tuning, phase current, field weakening, regen-current, or invented telemetry.
- visual ambition never authorizes invented battery precision, range, route safety, vehicle features, or protocol semantics.

## Hardware validation still required
- real MAXSHOT advertisement identity.
- BLE services/characteristics/properties.
- notification cadence and speed latency/jitter/resolution.
- packet framing/checksum.
- read/write/ack behavior and firmware differences.
- MAXSHOT-specific DP101/DP102/DP103 semantics.
- AccessorySetupKit descriptors based on observed hardware identity.

## Real Xcode / Simulator proof policy
GitHub-hosted `xcode-27` is the authoritative remote Mac gate when direct interactive Xcode tooling is unavailable.
- iPhone 12 / iOS 27 is the explicit visual baseline.
- CI preserves `.xcresult`, logs, Simulator screenshots, and XCTest attachments.
- hosted Simulator proof is real iOS runtime evidence.
- it is not physical MAXSHOT BLE validation and not physical iPhone 12 performance profiling.

## Mandatory future release gate — Production Visual Overhaul
Current Home/Dashboard/Rides screens are intermediate functional implementations. Once enough truthful dependencies exist—especially battery/SoC, live ride/trip state, maps/navigation, completed rides, and confirmed vehicle/error state—perform the dedicated **Production Visual Overhaul / Final Product Design Pass** defined by `MASTER_CONTINUATION_DIRECTIVE.md` and `DECISIONS.md`.

Every major screen must go through current real Simulator screenshot → critique → redesign → implement → run → screenshot → critique → repeat. A technically correct but mediocre screen is not final product acceptance.