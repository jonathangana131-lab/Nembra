# PROJECT STATE

Updated: 2026-08-05

## Product
- Product: **Nembra**
- First vehicle: **MAXSHOT V1S Pro**
- Repository: public `jonathangana131-lab/Nembra`
- Product stance: native iOS 27 scooter platform; MAXSHOT first; truthful telemetry and command confirmation; multi-vehicle architecture only after MAXSHOT quality is established.

## Current branch / milestone
- Active branch: `feature/landscape-dashboard`
- Stable branch: `main`
- Stable Home merge: `254b95a8d62d7d143df937cc0d8aa73f45548266`
- Active milestone: **Phase 9 — dedicated landscape Dashboard Mode, final polish gate**
- Next milestone after Dashboard acceptance: **Phase 10 — measured-speed instrumentation / render-only interpolation**

## Portrait Home — accepted and merged
- The rejected giant scooter-art Home direction is no longer used in the composition.
- Portrait Home prioritizes: human-readable vehicle identity, connection/lock truth, Battery/Trip/Mode, Light/Lock controls, Walk/Eco/Drive/Sport selector, and native vehicle details.
- Moving state disables Lock and says `Stop to lock`; the service remains the final safety boundary.
- Locked state offers `Unlock` rather than presenting a misleading Lock action.
- Battery <=15% receives semantic low-battery priority without recoloring the entire interface.
- Reconnecting/offline telemetry is explicitly last-known/read-only.
- Speed-limit editing remains absent until DP101/102/103 user-facing semantics are verified.
- Real UI interaction gate passed on Xcode 27 run `31056673050` after fixing stale XCTest element reuse for confirmed Lock state.
- PR #1 merged to `main` only after the latest Xcode 27 build/test/capture job completed successfully.

## Phase 9 Dashboard implementation
- Compact-height iPhone landscape routes to a dedicated `DashboardView`; portrait remains Home.
- Dashboard is an instrument-first black cockpit, not rotated portrait content.
- Left rail: MAXSHOT identity, truthful connection status, battery, scooter Trip.
- Center: dominant confirmed speed and unit. Phase 9 does not inject interpolation into the display.
- Right rail: confirmed ride mode plus compact stopped-only controls.
- While moving, state-changing controls remain hidden. The final polish replaces dead `Controls available when stopped` space with read-only confirmed Headlight + Lock status.
- Lock still uses a confirmation dialog and service acknowledgement semantics.
- Stable accessibility identifiers exist for cockpit, speed, mode, battery/trip, mode buttons, Light/Lock controls, and moving-state readouts.
- Root dashboard accessibility explicitly contains children so the cockpit marker does not hide instrument/control descendants from XCTest.
- Landscape XCUITests cover riding/hidden-controls/read-only state and stopped/mode-confirmation states and keep screenshots as XCTest attachments.
- CI preserves the full `.xcresult` and exports test attachments even when `xcodebuild test` fails.

## Real Xcode / Simulator proof
GitHub-hosted `xcode-27` is the remote Mac gate.
- macOS 26.5.2 / Xcode 27.0 beta build 27A5228h / iOS 27 Simulator has been proven by artifacts.
- Explicit visual baseline: iPhone 12 / iOS 27.
- `NembraCore`: **156/156 tests passing** on the Mac gate.
- Portrait Home latest interaction gate: **PASS** (`31056673050`).
- Simulator capture states already cover cold-disconnected, reconnecting, connected-stopped, riding, low-battery, Bluetooth-off, permission-denied, scooter-unavailable, unsupported-configuration, and representative dark states.
- Phase 9 run `31058989306` at `f3394cac` was **PASS** including landscape XCUITests and exported screenshots.
- Screenshot review found the stopped cockpit acceptable but the riding right rail underused. Final polish commits `cfb0f9fc` + `75fd6622` replace that dead space with truthful read-only Headlight/Lock state and test it.
- Latest final-polish run: `31059807152` at `75fd662222f344e4323554c6763a034cd0e775ae`; queued at this checkpoint. Do not merge PR #2 until this exact/newer lineage is green and its riding screenshot is visually inspected.

## Phase 10 work already available for selective reuse
- Old branch `feature/speed-instrumentation` diverged before accepted Home/Phase 9 and **must not be merged wholesale**.
- Valid pieces to transplant only after Phase 9 merge:
  - narrow `VehicleStore.speedTelemetryUpdates()` service stream
  - `SpeedInstrumentModel`
  - `RollingSpeedValueView`
  - targeted app tests for confirmed fallback / measured / interpolated / stale / estimated behavior
- Core `SpeedDisplayInterpolator` and `RollingNumberModel` are already on the accepted lineage and have interruption, no-overshoot, truth-boundary, carry/borrow, fixed-slot, and invalid-value tests.

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

## Next exact actions
1. Wait for Xcode 27 run `31059807152` (or newer head-equivalent final-polish run) to execute the final Phase 9 riding-state readout change.
2. If it fails, inspect the exact Mac/XCTest artifact and fix the real issue; do not weaken tests.
3. If it passes, download the exported `Dashboard Riding Landscape` and `Dashboard Stopped Landscape` attachments and inspect them at the iPhone 12 baseline.
4. If visually accepted, mark PR #2 ready and merge Phase 9 to `main`.
5. Immediately create a fresh Phase 10 branch from the merged `main`; do **not** merge the old divergent speed branch.
6. Selectively transplant the narrow raw-speed stream, `SpeedInstrumentModel`, `RollingSpeedValueView`, and targeted app tests; wire them into the accepted Dashboard.
7. Run Xcode 27 + landscape screenshot QA again, tune Simulator interpolation only from observed simulated cadence, and keep production MAXSHOT timing hardware-gated until real cadence is measured.
8. Continue autonomously through mode-responsive Dashboard, ride persistence/app wiring, background Bluetooth/location, maps/navigation, history/stats, acceleration tests, BLE diagnostics/real hardware, cloud/leaderboard, system integrations, and hardening per the master directive.

## Key files
- `DESIGN_SYSTEM.md`
- `DECISIONS.md`
- `PROTOCOL_NOTES.md`
- `CONTINUATION_PROMPT.md`
- `NembraApp/Features/Home/HomeView.swift`
- `NembraApp/Features/Home/VehicleControlsView.swift`
- `NembraApp/Features/Dashboard/DashboardView.swift`
- `NembraUITests/NembraUITests.swift`
- `Packages/NembraCore/Sources/NembraCore/`
- `.github/workflows/xcode27-simulator.yml`
- `scripts/ci/xcode27_simulator_capture.sh`

## Visual QA acceptance criteria
A vertical slice is accepted only when its latest code lineage has: Mac build/test success, representative Simulator screenshots, dark/light review where applicable, failure-state review, moving-state command review, and real UI interaction coverage. A screenshot looking clean is not by itself completion.
