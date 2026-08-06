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

## Portrait Home — accepted and merged
- Status-first Home is merged and remains the portrait experience.
- Large rejected scooter artwork is not part of the composition.
- Moving state disables Lock; locked state offers Unlock; low battery gets semantic priority.
- Retained telemetry is explicitly last-known/read-only.
- Real interaction gate passed before merge.

## Phase 9 Dashboard — accepted and merged
- Dedicated compact-height iPhone landscape `DashboardView`; portrait remains Home.
- Instrument-first black cockpit, not rotated portrait content.
- Dominant confirmed speed, battery, scooter Trip, mode, connection/model identity.
- Stopped-only Light/Lock and ride-mode controls; moving state removes state-changing controls.
- No fake throttle/current/power gauge and no interpolation presented as measurement in Phase 9.
- Landscape XCUITests passed on Xcode 27 / iPhone 12 / iOS 27.
- Riding and stopped landscape screenshots were visually reviewed and accepted.
- Final Phase 9 Mac gate: workflow run `31058989306` PASS.
- PR #2 merged to `main` at `51613a990eb058ee83741645d8c551082d4ef268`.

## Phase 10 current implementation
Already pushed on `feature/speed-instrumentation-v2`:
- `VehicleStore.speedTelemetryUpdates()` exposes raw speed evidence without publishing render frames into `VehicleState`.
- `SpeedInstrumentModel` is a main-actor presentation model around the existing core `SpeedDisplayInterpolator`.
- It accepts only authoritative `SpeedTelemetrySample` evidence.
- Stale packets and motion-assist estimates cannot move presentation state.
- Before fresh raw telemetry arrives, the instrument may display the latest already-confirmed `VehicleState` speed as an explicitly different origin.
- Animation duration derives from observed packet cadence and is bounded 50–300 ms; this is a presentation heuristic, not a claim about MAXSHOT notification rate.
- `RollingSpeedValueView` uses the existing fixed-slot `RollingNumberModel`; it is presentation-only.
- App tests now cover fallback confirmed state, authoritative interpolation, stale/estimated rejection, and long-gap duration bounding.
- Xcode project wiring for both Phase 10 Dashboard source files is committed at `64b9dc8e351f804c4d613d41f1e6b6e2142d810f` and passed repository PBX reference validation.

## Phase 10 next quality gates
1. Run Xcode 27 app/unit/UI tests against the wired presentation model before changing the visible cockpit.
2. Replace only the Dashboard center speed digits with a narrow local render loop; do not make the whole Dashboard redraw at display cadence.
3. Subscribe once to raw speed evidence and keep the render model local to the speed instrument.
4. Keep moving-state safety, ride detection, trip persistence, and stats driven by confirmed/raw evidence—not interpolated frames.
5. Run landscape Simulator QA and inspect riding/stopped frames for visual jitter, clipping, digit width changes, and unit alignment.
6. Add/adjust interaction or instrumentation tests if screenshot/runtime evidence exposes defects.
7. Merge Phase 10 only after Mac gate + visual review are green, then continue immediately into mode-responsive Dashboard / ride-engine app wiring.

## Real Xcode / Simulator proof
GitHub-hosted `xcode-27` is the remote Mac gate.
- macOS 26.5.2 / Xcode 27.0 beta build 27A5228h / iOS 27 Simulator proven by artifacts.
- Explicit visual baseline: iPhone 12 / iOS 27.
- `NembraCore`: **156/156 tests passing** on the Mac gate.
- UI-test harness allows 120 seconds total for cold hosted-runner automation bootstrap while individual assertion waits remain tight.
- CI preserves the `.xcresult` and exports XCTest screenshot attachments on failure or success.

## Core architecture already implemented
- Capability-based `VehicleProfile` / `ScooterService` boundary.
- `SimulatedScooterService` and hardware-gated `UnverifiedScooterService`.
- Production launch never silently enters simulation.
- Typed connection failures and explicit live/retained/unavailable data availability.
- Command serialization, confirmation semantics, and connection-generation invalidation.
- Raw speed evidence model + telemetry benchmark collector.
- Render-only `SpeedDisplayInterpolator` and fixed-slot `RollingNumberModel`.
- Automatic `RideEngine` with disconnect continuity.
- Crash-safe two-slot ride checkpoint journal/coordinator and `completedPendingCommit` handoff.
- Idempotent completed-history commit contract.
- ODO/GPS/live-distance reconciliation with explicit complete/partial/unknown coverage.
- Process-local authoritative live-distance segment integration.

## Important truth boundaries
- Interpolated/display speed is never telemetry or ride evidence.
- Motion-assisted estimates never masquerade as authoritative scooter/GPS speed.
- Disconnect never fabricates a zero measurement.
- Device Trip is not labeled Today.
- DP101/102/103 are not mapped to ride modes without hardware proof.
- No VESC-style tuning, phase current, field weakening, regen current, or invented telemetry.
- Real BLE writes remain blocked until command meaning/transport/acknowledgment is verified.

## Hardware validation still required
- Real BLE advertisement name and identity matching.
- Service/characteristic UUIDs and properties.
- Notification cadence, speed latency/jitter/resolution.
- Read/write/ack behavior and packet framing/checksum details.
- MAXSHOT-specific DP101/102/103 semantics.
- AccessorySetupKit descriptors based on observed advertisement/service identity.

## Key files
- `DESIGN_SYSTEM.md`
- `DECISIONS.md`
- `PROTOCOL_NOTES.md`
- `CONTINUATION_PROMPT.md`
- `NembraApp/Features/Home/HomeView.swift`
- `NembraApp/Features/Dashboard/DashboardView.swift`
- `NembraApp/Features/Dashboard/SpeedInstrumentModel.swift`
- `NembraApp/Features/Dashboard/RollingSpeedValueView.swift`
- `NembraUITests/NembraUITests.swift`
- `Packages/NembraCore/Sources/NembraCore/`
- `.github/workflows/xcode27-simulator.yml`
- `scripts/ci/xcode27_simulator_capture.sh`

## Visual QA acceptance criteria
A vertical slice is accepted only when its latest code lineage has Mac build/test success, representative Simulator screenshots, dark/light review where applicable, failure-state review, moving-state command review, and real UI interaction coverage. A screenshot looking clean is not by itself completion.
