# PROJECT STATE

Updated: 2026-08-05

## Product
- Product: **Nembra**
- First vehicle: **MAXSHOT V1S Pro**
- Repository: public `jonathangana131-lab/Nembra`
- Product stance: native iOS 27 scooter platform; MAXSHOT first; truthful telemetry and command confirmation; multi-vehicle architecture only after MAXSHOT quality is established.

## Current branch / milestone
- Active branch: `feature/home-rebuild`
- Stable branch: `main`
- Active milestone: **Phase 8 — portrait Home / vehicle experience, final interaction gate**
- Next milestone after merge: **Phase 9 — dedicated landscape Dashboard Mode**

## Home vertical slice status
- The rejected giant scooter-art Home direction is no longer used in the composition.
- Portrait Home now prioritizes: human-readable vehicle identity, connection/lock truth, Battery/Trip/Mode, Light/Lock controls, Walk/Eco/Drive/Sport selector, and native vehicle details.
- No giant decorative vehicle render is required on Home. Future exact vehicle graphics are contextual assets and must earn their space.
- Moving state disables Lock and says `Stop to lock`; the service remains the final safety boundary.
- Locked state offers `Unlock` rather than presenting a misleading Lock action.
- Battery <=15% receives semantic low-battery priority without recoloring the entire interface.
- Reconnecting/offline telemetry is explicitly last-known/read-only.
- Speed-limit editing remains absent until DP101/102/103 user-facing semantics are verified.

## Real Xcode / Simulator proof
GitHub-hosted `xcode-27` is the remote Mac gate.
- macOS 26.5.2 / Xcode 27.0 beta build 27A5228h / iOS 27 Simulator has been proven by artifacts.
- Explicit visual baseline: iPhone 12 / iOS 27.
- `NembraCore`: **156/156 tests passing** on the Mac gate.
- Actual iOS `xcodebuild test`: passing on the rebuilt Home visual commits prior to UI-test-target wiring.
- Simulator capture states: cold-disconnected, reconnecting, connected-stopped, riding, low-battery, Bluetooth-off, permission-denied, scooter-unavailable, unsupported-configuration, plus representative dark states.
- Visual polish run `30995159725` / commit `0a606a5`: **PASS**. Reviewed riding, low-battery, connected dark, reconnecting.
- A real `NembraUITests` UI-testing bundle is now wired into `Nembra.xcodeproj` and the shared scheme. The current Xcode run at the latest code commit is the final Home interaction gate; do not claim that gate passed until the workflow completes successfully.

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
1. Finish the current Xcode 27 run containing `NembraUITests`; fix any real interaction/accessibility failure rather than disabling the test.
2. Update memory docs with the result, open/finish the PR from `feature/home-rebuild`, and merge only when green.
3. Create `feature/landscape-dashboard` from the completed Home line and begin **Phase 9**.
4. Dashboard v1 is a dedicated landscape cockpit, not rotated portrait Home: huge confirmed speed, mode, battery, trip, connection, and stopped-only compact controls. No map/navigation yet.
5. Capture Dashboard on iPhone 12/iOS 27 in landscape through XCUITest orientation, critique/fix, then commit/merge.
6. Immediately continue to **Phase 10**: wire raw-speed telemetry to render-only interpolation and rolling digits; benchmark cadence before choosing transition timing.
7. Continue through mode-responsive Dashboard, ride persistence/app wiring, background Bluetooth/location, maps, navigation, history/stats, acceleration tests, BLE diagnostics/real hardware, cloud/leaderboard, system integrations, and hardening per the master directive.

## Key files
- `DESIGN_SYSTEM.md`
- `DECISIONS.md`
- `PROTOCOL_NOTES.md`
- `CONTINUATION_PROMPT.md`
- `NembraApp/Features/Home/HomeView.swift`
- `NembraApp/Features/Home/VehicleControlsView.swift`
- `NembraUITests/NembraUITests.swift`
- `Packages/NembraCore/Sources/NembraCore/`
- `.github/workflows/xcode27-simulator.yml`
- `scripts/ci/xcode27_simulator_capture.sh`

## Visual QA acceptance criteria
Home is accepted only when its latest code lineage has: Mac build/test success, representative Simulator screenshots, dark/light review, disconnected/reconnecting review, moving-state command review, low-battery review, and real UI interaction coverage. A screenshot looking clean is not by itself completion.
