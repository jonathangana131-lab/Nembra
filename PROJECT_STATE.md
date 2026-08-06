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
- PR: **#5 — Wire automatic ride recovery and local history**.
- Phase 12 functional implementation/runtime/visual acceptance is complete on implementation head `2da5843312b27732888984f64e64ec58c52a32d7`.
- Remaining Phase 12 work: commit this acceptance memory, require one exact docs-head `xcode-27` gate, mark PR #5 ready, squash merge with the exact expected head SHA, verify `main`, then choose the next slice from fresh repository state.

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

## Phase 12 — accepted functional implementation
Phase 12 turns the already-tested ride domain into real root-owned application behavior without creating a second ride engine or alternate recovery/history pipeline.

Implemented:
- root `AppRuntime` owns one shared scooter service, `VehicleStore`, and `RideApplicationStore` outside SwiftUI screen lifetime.
- `RideApplicationStore` drives the existing `RideCheckpointCoordinator`, two-slot journal, `completedPendingCommit`, and `RideHistoryCommitCoordinator`.
- stream registration completes before `RideApplicationStore.start()` returns, preventing the first fresh packet from racing past startup.
- only fresh raw authoritative speed packets may populate `RideObservation.speedSample`; cached `VehicleState.speedKilometersPerHour` is never promoted to a new measurement.
- state-only light/mode/lock acknowledgements do not replay a prior speed packet or fabricate zero-speed evidence.
- state publications enter ride detection only for meaningful connection transitions or real odometer advancement.
- because scooter state and raw speed are independent streams, a packet that arrives while state still says connecting/reconnecting may be held as the newest **unconsumed** packet and consumed exactly once when confirmed connected state catches up; disconnect clears it and `RideEngine` still enforces freshness.
- unchanged active/session/continuity/error values are not repeatedly republished through Observation on every high-rate packet.
- a concrete local SwiftData `RideHistoryStore` preserves the exact core ride record, provides session-ID uniqueness, exact readback verification, idempotent duplicate success, conflict rejection, and payload/session corruption checks.
- simulation history/recovery is physically namespaced away from future production data.
- production/default `UnverifiedScooterService` keeps automatic ride detection disabled until real MAXSHOT cadence, latency, and reconnect behavior are measured.
- Simulator-only detection thresholds exercise the production application path but are not hardware defaults.
- a restrained portrait Home ride-status strip appears only for meaningful transient/active/recovery/error ride application state.
- explicit Simulator QA uses the same real application coordinator, checkpoint, history, and UI path.

## Phase 12 Xcode / Simulator acceptance
Implementation head: `2da5843312b27732888984f64e64ec58c52a32d7`.

GitHub Actions:
- workflow: **Xcode 27 Simulator QA**
- run: `31067831584`
- job: `92509801452`
- conclusion: **success**
- runner label: `xcode-27`
- project structure validation: passed
- core package validation: passed
- full Xcode/iOS 27 Simulator app/UI stage: passed
- QA artifact upload: passed

Exported `.xcresult` evidence:
- `NembraAppTests`: **20/20**, 0 failures.
- `NembraUITests`: **6/6**, 0 failures.
- Phase 12 app coverage includes SwiftData idempotent reopen/conflict behavior, stored-payload identity corruption rejection, single-use raw-speed semantics, deliberate raw-speed-before-connected-state stream inversion, same-session recovery/completion/history handoff, and production-disabled automatic detection.
- the UI suite includes a real app terminate/relaunch test using an isolated simulation persistence namespace.

Kept iPhone 12/iOS 27 attachments inspected:
- `Automatic Ride Active Home`
- `Automatic Ride Recovered Home`

Visual/runtime acceptance for this systems slice:
- the ride-status strip remains subordinate to vehicle status and does not crowd Home.
- no safe-area clipping or hierarchy regression was observed.
- process relaunch returns as `Ride resumed` rather than presenting a fake new ride.
- screenshots are accepted as Phase 12 functional UI evidence only; they do **not** satisfy the future Production Visual Overhaul release gate.

Performance review:
- high-frequency Dashboard speed rendering remains isolated by the accepted Phase 10 subtree.
- Phase 12 packet processing may schedule the root application bridge, but unchanged published ride status/session/continuity/error state is no longer reassigned on every active packet.
- no code-first evidence justifies replacing the current architecture before real device profiling.
- hosted Simulator QA is not physical iPhone 12 performance profiling.

Only observed build warnings on the accepted run were Xcode AppIntents metadata skips because the app does not currently depend on `AppIntents.framework`; they are not Phase 12 compile/test failures.

## Phase 12 final quality gate
1. Commit this acceptance into project memory as one documentation checkpoint.
2. Freeze the branch and require the newest docs-head `xcode-27` run to pass on that exact SHA.
3. Do not reopen accepted Phase 12 architecture unless that final lineage gate exposes a real regression.
4. When green, mark PR #5 ready and **squash merge** it with `expected_head_sha` set to the exact docs head.
5. Verify updated `main` and recover the next vertical slice from fresh GitHub state before creating the next feature branch.

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
- Only a fresh raw authoritative speed packet may populate ride speed evidence; state acknowledgements cannot replay cached speed.
- A reconnect-order speed packet may be buffered only as newest unconsumed evidence, consumed once after connected state catches up, and remains freshness-limited.
- Simulator ride detection policy is never a MAXSHOT hardware default.
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
- root-owned ride application coordinator.
- local SwiftData exact completed-history adapter.
- idempotent completed-history commit/readback contract.
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
