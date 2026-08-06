# PROJECT STATE

Updated: 2026-08-06

## Product
- Product: **Nembra**
- First vehicle: **MAXSHOT V1S Pro**
- Repository: public `jonathangana131-lab/Nembra`
- Product stance: native iOS 27 scooter platform; MAXSHOT first; truthful telemetry and command confirmation; multi-vehicle architecture only after MAXSHOT quality is established.

## Current branch / milestone
- Active branch: `feature/speed-instrumentation-v2`
- Stable branch: `main`
- Stable Home merge: `254b95a8d62d7d143df937cc0d8aa73f45548266`
- Stable Dashboard merge: `51613a990eb058ee83741645d8c551082d4ef268`
- Active milestone: **Phase 10 — measured-speed instrumentation / render-only interpolation**
- Draft PR: **#3 — Add measured-speed Dashboard instrumentation**

## Stable UI milestones
### Portrait Home
- Accepted and merged; status-first portrait vehicle console.
- Moving-state Lock safety, low-battery priority, last-known state labeling, and real interaction QA are preserved.

### Phase 9 Dashboard
- Accepted and merged dedicated landscape cockpit.
- Dominant confirmed speed, battery, scooter Trip, mode, connection/model identity.
- Stopped-only mode/Light/Lock controls; moving state removes state-changing controls.
- No fake throttle/current/power gauge.
- Final Xcode 27 gate run `31058989306` PASS; real iPhone 12 landscape screenshots reviewed and accepted.

## Phase 10 implementation already pushed
- `VehicleStore.speedTelemetryUpdates()` exposes raw evidence independently from `VehicleState`.
- `SpeedInstrumentModel` accepts authoritative `SpeedTelemetrySample` only and wraps the core render-only `SpeedDisplayInterpolator`.
- Stale samples and motion-assist estimates cannot move presentation state.
- Before fresh raw telemetry arrives, the instrument can show already-confirmed `VehicleState` speed without converting it into a raw packet.
- `RollingSpeedValueView` uses fixed-slot `RollingNumberModel`; integer digit rolling is subordinate to the packet interpolation timing rather than a second smoothing layer.
- `DashboardSpeedInstrumentView` is the only 60 Hz-capable subtree; Dashboard side rails, controls, safety, ride logic, distance, history, and stats remain on confirmed/raw domain state.
- SwiftUI animation timeline is paused outside active interpolation to avoid a permanent 60 Hz UI loop.
- VoiceOver announces the latest authoritative/confirmed speed, never a visual interpolation midpoint.
- Telemetry gaps are not visually bridged: a sample interval beyond the active policy’s continuous interval snaps to the new measured value.
- Xcode target wiring for `SpeedInstrumentModel.swift` and `RollingSpeedValueView.swift` is committed and passed PBX reference validation.
- CI now cancels obsolete Xcode runs per branch so new checkpoints do not queue behind their own stale runs.

## Critical Phase 10 timing policy
The app **does not choose MAXSHOT production interpolation timing before hardware measurement**.
- `SpeedInstrumentInterpolationPolicy.disabled` is the ordinary production default.
- Production/unverified hardware therefore snaps to authoritative measurements.
- Explicit Simulator QA launch injects `SpeedInstrumentInterpolationPolicy.simulatorQA` to exercise the animation system.
- Simulator QA currently uses 50 ms minimum / 300 ms maximum-continuous interval / 0.8 observed-interval fraction. These are test presentation values only, not MAXSHOT claims.
- Real MAXSHOT interpolation remains disabled until notification cadence/latency/resolution is measured on hardware and a calibrated policy is explicitly injected.

## Phase 10 tests already pushed
- confirmed VehicleState fallback before fresh raw telemetry.
- production/default uncalibrated model snaps even across close measurements.
- explicit simulation launch injects the QA interpolation policy.
- QA policy interpolates between close authoritative samples.
- stale and motion-assist samples are rejected.
- QA policy snaps across a long telemetry gap.
- ordinary production launch keeps interpolation policy disabled.

## Current quality gate
1. Latest Phase 10 code is waiting for the `xcode-27` Mac runner; an older pre-concurrency Phase 10 job is currently occupying the runner and remains useful compile/test evidence.
2. When the latest head runs, fix any real Swift 6 / Xcode 27 compiler or test issue without weakening truth boundaries.
3. Run the full landscape XCUITest gate.
4. Inspect real iPhone 12 riding/stopped screenshots for clipping, fixed digit geometry, unit alignment, rail shifts, and regression of Phase 9.
5. Keep PR #3 draft until latest Mac + visual evidence are green.
6. After Phase 10 merge, continue immediately into mode-responsive Dashboard / ride-engine application wiring.

## Real Xcode / Simulator proof
GitHub-hosted `xcode-27` is the authoritative remote Mac gate.
- Proven environment: macOS 26.5.2 / Xcode 27.0 beta build 27A5228h / iOS 27 Simulator.
- Explicit visual baseline: iPhone 12 / iOS 27.
- `NembraCore`: **156/156 tests passing** on the Mac gate.
- UI-test harness allows 120 seconds total for cold hosted-runner automation bootstrap while assertion waits remain tight.
- CI preserves `.xcresult` and exports XCTest screenshots/attachments on failure and success.

## Important truth boundaries
- Interpolated/display speed is never telemetry or ride evidence.
- Motion-assisted estimates never masquerade as authoritative scooter/GPS speed.
- Disconnect never fabricates a zero measurement.
- Device Trip is not labeled Today.
- DP101/102/103 are not mapped to ride modes without hardware proof.
- No VESC-style tuning, phase current, field weakening, regen current, or invented telemetry.
- Real BLE writes remain blocked until command meaning/transport/acknowledgment is verified.

## Core systems already implemented
- capability-based `VehicleProfile` / `ScooterService` boundary.
- `SimulatedScooterService` + hardware-gated `UnverifiedScooterService`.
- typed connection failures and live/retained/unavailable data availability.
- serialized pending/confirmed commands + connection-generation invalidation.
- raw speed evidence + telemetry benchmark collector.
- render-only `SpeedDisplayInterpolator` + fixed-slot `RollingNumberModel`.
- automatic `RideEngine` with disconnect continuity.
- crash-safe two-slot ride journal + `completedPendingCommit` handoff.
- idempotent completed-history commit contract.
- independent ODO/GPS/live-distance reconciliation.
- process-local authoritative live-distance segment integration.

## Hardware validation still required
- BLE advertisement identity.
- services/characteristics/properties.
- notification cadence, speed latency/jitter/resolution.
- read/write/ack behavior and packet framing/checksum.
- MAXSHOT-specific DP101/102/103 semantics.
- AccessorySetupKit descriptors from observed identity.

## Key files
- `DECISIONS.md`
- `DESIGN_SYSTEM.md`
- `PROTOCOL_NOTES.md`
- `CONTINUATION_PROMPT.md`
- `NembraApp/App/VehicleStore.swift`
- `NembraApp/Features/Dashboard/DashboardView.swift`
- `NembraApp/Features/Dashboard/SpeedInstrumentModel.swift`
- `NembraApp/Features/Dashboard/RollingSpeedValueView.swift`
- `NembraAppTests/NembraAppTests.swift`
- `NembraUITests/NembraUITests.swift`
- `.github/workflows/xcode27-simulator.yml`
- `scripts/ci/xcode27_simulator_capture.sh`

## Acceptance rule
A vertical slice is accepted only after latest-lineage Mac build/test success, representative Simulator screenshots, relevant dark/light/failure/moving-state review, interaction coverage, and any necessary performance audit. A clean compile or a good-looking screenshot alone is not completion.
