# PROJECT STATE

Updated: 2026-08-06

## Product
- Product: **Nembra**.
- First supported vehicle: **MAXSHOT V1S Pro**.
- Repository: public `jonathangana131-lab/Nembra`.
- Product stance: premium native iOS 27 scooter platform; MAXSHOT first; capability-based architecture; truthful telemetry; pessimistic/confirmed commands; simulation and real hardware share production UI through the same service boundary.

## Current branch / milestone
- Stable branch: `main`.
- Phase 11 is merged on `main` at `e102595e2a85c4857c093ccfacea39ba9ff06307`.
- Active branch: `feature/ride-application-persistence`.
- Active milestone: **Phase 12 — ride application + persistence**.
- PR: **#5 — Phase 12 ride application + persistence** (draft while acceptance gates run).
- Current implementation head before this memory update: `048db577515b79b8db647621af1fca50d9e13f00`.
- Phase 12 must continue from the existing `RideEngine`, `RideCheckpointCoordinator`, two-slot recovery journal, `completedPendingCommit`, `RideHistoryCommitCoordinator`, distance reconciliation, and live-distance systems rather than replacing them.

## Stable accepted UI/system milestones
### Portrait Home
- Functional and accepted for its current system milestone.
- Status-first vehicle console with honest unknown/retained/live presentation.
- Moving-state Lock safety, typed connection failures, low-battery priority, and confirmed controls are preserved.
- **Important:** this is an intermediate visual implementation, not final product-level visual acceptance.

### Phase 9 — dedicated landscape Dashboard
- Functional and accepted for its current system milestone.
- Dedicated cockpit rather than portrait Home rotated.
- Dominant speed, battery, Scooter Trip, ride mode, connection/model identity.
- Stopped-only mode/Light/Lock controls; state-changing controls disappear while moving.
- No fake throttle/current/power gauge.
- **Important:** current screenshot/layout acceptance proves functional composition only. It is not the final visual target.

### Phase 10 — measured-speed instrumentation
- Accepted and merged.
- Raw authoritative speed evidence is separate from `VehicleState` and separate from display frames.
- `SpeedInstrumentModel` wraps render-only `SpeedDisplayInterpolator` and rejects stale/motion-assist samples.
- `RollingSpeedValueView` reserves fixed digit geometry; rolling is presentation only.
- `DashboardSpeedInstrumentView` is the only 60 Hz-capable subtree and pauses its animation timeline outside active interpolation.
- Production interpolation remains disabled until real MAXSHOT cadence/latency/resolution is measured; explicit Simulator QA injects a presentation-only policy.
- VoiceOver announces authoritative/confirmed speed, never an interpolation midpoint.
- Simulator packet timestamps use real process monotonic arrival time; simulated ride duration never manufactures packet cadence.

### Phase 11 — confirmed-mode Dashboard personality
- Accepted and merged at `e102595e2a85c4857c093ccfacea39ba9ff06307`.
- `DashboardModePersonality` is pure presentation state derived only from confirmed `RideMode?`.
- Walk/Eco/Drive/Sport alter only restrained cockpit visual energy through center ambient intensity, speed scale, mode emphasis/marker, and secondary status emphasis.
- Unknown mode remains neutral.
- No RGB/gamer theme, fake performance gauge, fake MAXSHOT mode-to-DP mapping, or invented power/range/efficiency behavior.
- Reduce Motion preserves state while removing spatial/snappy personality animation.
- iPhone 12/iOS 27 captures were reviewed for Walk, Eco, Drive, Sport, confirmed Sport, and riding.
- **Important:** Phase 11 visual acceptance is an intermediate systems-era baseline, not final product-level visual completion.

## Phase 12 — active ride application + persistence slice
Target end-to-end behavior:
- root-owned automatic ride application state outside SwiftUI screen lifetime.
- vehicle UI and ride tracking subscribe to the same scooter service instance.
- only fresh raw authoritative speed packets can populate `RideObservation.speedSample`.
- vehicle-state updates may carry connection/odometer evidence but must never replay cached speed as a fresh sample.
- crash-safe checkpoints are driven by real application behavior.
- completed rides hand off through `completedPendingCommit` into idempotent, readback-verified local history.
- relaunch/recovery restores the same durable session identity where legitimate.
- explicit Simulator QA uses the same application path while keeping simulated storage isolated from future production history.
- production ride detection remains disabled until real MAXSHOT cadence/reconnect timing is measured; QA thresholds are explicitly simulation-only.
- UI consumes truthful ride application state and never invents measurements.

Current Phase 12 implementation includes:
- root `AppRuntime` ownership of `VehicleStore` + `RideApplicationStore`.
- `RideApplicationStore` bridge into the existing ride/recovery/history pipeline.
- SwiftData-backed completed ride history adapter preserving exact core records.
- simulation/production persistence namespace separation.
- transient Home ride-status strip for real application state.
- app tests for SwiftData idempotency, same-session recovery, completion handoff, and fresh-speed evidence semantics.
- UI relaunch test that exercises an automatic ride across process termination/relaunch with a unique simulation storage namespace.

The first Xcode gate exposed a test-autoclosure async issue; it was fixed without production changes. A later audit fixed a truth-boundary bug so cached raw speed is never replayed on ordinary state publications, and tightened state-only ingestion to real connection transitions / odometer advances. Stream subscriptions are now registered before `RideApplicationStore.start()` returns to avoid missing the first fresh QA packet.

## Future mandatory milestone — Production Visual Overhaul / Final Product Design Pass
This milestone is **required before Nembra can be called visually complete or product-complete**. It must not be silently dropped, indefinitely postponed, or treated as optional polish.

### Trigger
Begin the major visual/product-design pass once the foundational UI dependencies are sufficiently real and available, especially:
- battery telemetry / SoC behavior and range inputs that can be presented truthfully.
- automatic ride state and live trip information.
- maps/navigation and route state.
- persisted/completed ride data.
- relevant confirmed vehicle state and error/charging states.

Systems work should continue now; do not restart or prematurely redesign around missing data. But once these foundations exist, this overhaul becomes a first-class milestone.

### Quality bar
The final product must pursue the original master vision as a quality bar rather than a pixel-for-pixel mockup:
- world-class native iOS 27 appearance.
- premium modern EV instrumentation.
- Stark/Tesla-level cockpit polish without copying either product.
- huge, beautiful rolling MPH with truthful measurement semantics.
- Tesla-quality real-time battery presentation, including 1% behavior only where the underlying telemetry legitimately supports it.
- elegant range, trip, and duration information based on real evidence.
- deeply integrated navigation that dynamically rearranges the cockpit rather than looking bolted on.
- polished live ride information.
- restrained but meaningful Eco/Drive/Sport personalities.
- original premium scooter-aware graphics where useful and truthful.
- beautiful native materials / Liquid Glass used with hierarchy and restraint.
- excellent typography, spacing, depth, animation, accessibility, and haptics.
- minimal wasted space.
- no developer-dashboard feel, giant empty black regions, generic card mosaics, prototype rails, or placeholder-looking surfaces.

### Required redesign loop
Before visual completion, perform this loop screen by screen:
1. Capture the **current real Simulator screenshot**.
2. Critique it directly against the master product vision and actual available data.
3. Redesign substantially where the screen is visually underdeveloped.
4. Implement using production SwiftUI/domain state.
5. Build/run/interact on iPhone 12/iOS 27.
6. Capture real screenshots.
7. Critique again for hierarchy, polish, wasted space, motion, materials, accessibility, and truthfulness.
8. Repeat until the screen reaches product-level quality.

Required screen coverage:
- portrait Home.
- landscape Dashboard without navigation.
- landscape Dashboard with navigation and its dynamic rearrangement states.
- live ride states.
- battery / low-battery / charging states where supported.
- completed rides and route maps.
- history/stats.
- leaderboard when that product surface exists.
- controls/settings.
- major connection, permission, unsupported-hardware, persistence, and recovery error states.

A technically correct screen that looks mediocre is **not accepted as final**. Passing Simulator screenshots, clean constraints, or no clipping are necessary engineering gates but are not sufficient visual/product acceptance.

## Important truth boundaries
- Interpolated/display speed is never telemetry or ride evidence.
- Motion-assisted estimates never masquerade as authoritative scooter/GPS speed.
- Simulator ride duration is not packet-arrival cadence.
- Disconnect never fabricates a zero measurement.
- Device Trip is not labeled Today.
- Dashboard mode personality is presentation only and follows confirmed ride mode.
- DP101/DP102/DP103 remain unmapped to Walk/Eco/Drive/Sport until hardware evidence proves semantics.
- No VESC-style tuning, phase current, field weakening, regen current, or invented telemetry.
- Real BLE writes remain blocked until command meaning/transport/acknowledgement is verified sufficiently.
- Visual ambition never authorizes invented telemetry, range, battery precision, route safety claims, or vehicle capabilities.

## Core systems already implemented
- capability-based `VehicleProfile` / `ScooterService` boundary.
- `SimulatedScooterService` + hardware-gated `UnverifiedScooterService`.
- typed connection failures and live/retained/unavailable data availability.
- serialized pending/confirmed commands + connection-generation invalidation.
- raw speed evidence + telemetry benchmark collector.
- render-only `SpeedDisplayInterpolator` + fixed-slot `RollingNumberModel`.
- confirmed-mode visual Dashboard personality.
- automatic `RideEngine` with disconnect continuity.
- crash-safe two-slot ride journal + `completedPendingCommit` handoff.
- idempotent completed-history commit contract.
- independent ODO/GPS/live-distance reconciliation.
- process-local authoritative live-distance segment integration.

## Hardware validation still required
- real MAXSHOT advertisement identity.
- BLE services/characteristics/properties.
- notification cadence and speed latency/jitter/resolution.
- read/write/ack behavior and packet framing/checksum.
- MAXSHOT-specific DP101/DP102/DP103 semantics.
- AccessorySetupKit descriptors based on observed identity.

## Real Xcode / Simulator proof
GitHub-hosted `xcode-27` is the authoritative remote Mac gate when direct interactive Xcode tooling is unavailable.
- iPhone 12 / iOS 27 remains the explicit visual baseline.
- CI preserves `.xcresult`, logs, Simulator screenshots, and XCTest attachments on success/failure.
- Hosted Simulator proof is real iOS runtime evidence but is not physical MAXSHOT BLE validation or physical iPhone 12 performance profiling.
- Screenshot acceptance during system phases means the current slice is visually coherent and regression-free; it does **not** waive the future Production Visual Overhaul milestone.

## Acceptance rule
A vertical slice is accepted only after latest-lineage Mac build/test success, representative real Simulator interaction/screenshots, visual self-critique appropriate to the slice, relevant edge/failure/moving-state coverage, performance audit when relevant, tests, commit/push, and current project memory.

Separately, **final visual/product acceptance requires the dedicated Production Visual Overhaul / Final Product Design Pass above.** A compile, clean constraints, or one attractive screenshot is never enough to declare the application visually complete.
