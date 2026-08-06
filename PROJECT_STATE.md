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
- PR: **#3 — Add measured-speed Dashboard instrumentation**
- Phase 10 implementation/runtime acceptance is complete; only the newest documentation-head Mac gate and PR merge remain before the next slice begins.

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

## Phase 10 accepted implementation
- `VehicleStore.speedTelemetryUpdates()` exposes raw evidence independently from `VehicleState`.
- `SpeedInstrumentModel` accepts authoritative `SpeedTelemetrySample` only and wraps the core render-only `SpeedDisplayInterpolator`.
- Stale samples and motion-assist estimates cannot move presentation state.
- Before fresh raw telemetry arrives, the instrument can show already-confirmed `VehicleState` speed without converting it into a raw packet.
- `RollingSpeedValueView` uses fixed-slot `RollingNumberModel`; integer digit rolling is subordinate to packet interpolation timing rather than a second smoothing layer.
- `DashboardSpeedInstrumentView` is the only 60 Hz-capable subtree; Dashboard side rails, controls, safety, ride logic, distance, history, and stats remain on confirmed/raw domain state.
- SwiftUI animation timeline is paused outside active interpolation to avoid a permanent 60 Hz UI loop.
- VoiceOver announces the latest authoritative/confirmed speed, never a visual interpolation midpoint.
- Telemetry gaps are not visually bridged: a sample interval beyond the active policy’s continuous interval snaps to the new measured value.
- Xcode target wiring for `SpeedInstrumentModel.swift` and `RollingSpeedValueView.swift` is committed and PBX reference validation is green.
- CI cancels obsolete Xcode runs per branch so new checkpoints do not queue behind their own stale runs.

## Critical Phase 10 timing policy
The app **does not choose MAXSHOT production interpolation timing before hardware measurement**.
- `SpeedInstrumentInterpolationPolicy.disabled` is the ordinary production default.
- Production/unverified hardware therefore snaps to authoritative measurements.
- Explicit Simulator QA launch injects `SpeedInstrumentInterpolationPolicy.simulatorQA` to exercise the animation system.
- Simulator QA currently uses 50 ms minimum / 300 ms maximum-continuous interval / 0.8 observed-interval fraction. These are test presentation values only, not MAXSHOT claims.
- Real MAXSHOT interpolation remains disabled until notification cadence/latency/resolution is measured on hardware and a calibrated policy is explicitly injected.

## Phase 10 telemetry clock correction
- Simulator raw packet timestamps previously started near process uptime zero and advanced from simulated ride `elapsedSeconds`, while Dashboard rendering compares against real process monotonic uptime.
- That made a valid visual transition capable of appearing already expired at runtime and conflated ride-duration fixtures with packet-arrival evidence.
- `SimulatedScooterService` now timestamps raw samples with `DispatchTime.now().uptimeNanoseconds` and only adds the minimum monotonic increment if two packets land in one tick.
- Simulated `elapsedSeconds` advances ride distance/time evidence only; it never manufactures packet cadence.
- A regression test proves each emitted sample lies in the process-uptime window around its real emission.
- Deterministic 10 Hz benchmark math remains covered with explicitly timestamped synthetic samples instead of simulator ride duration.

## Phase 10 test + Simulator acceptance
Accepted implementation head before final memory-doc commits: `a816ddeb0997deceefe8713c479dfa91571128e7`.

Xcode 27 run `31061900280` / job `92491409069` on that head passed:
- `NembraCore`: **157/157** tests.
- `NembraAppTests`: **13/13** tests, 0 failures.
- `NembraUITests`: **5/5** tests, 0 failures.
- Real environment: GitHub `xcode-27` macOS runner, Xcode 27 beta / iOS 27 Simulator, iPhone 12 target preference.
- XCTest exported both `Dashboard Riding Landscape` and `Dashboard Stopped Landscape` attachments.

Visual review of the real iPhone 12 attachments:
- dominant center speed is clean and unclipped at riding `11 MPH` and stopped `0 MPH`.
- fixed-width center geometry remains stable across one/two-digit states.
- MPH remains subordinate and aligned without colliding with the numeral.
- accepted model/connection, battery/trip, and mode rails do not shift or compete with speed.
- stopped mode/Light/Lock controls remain clearly separated from the center instrument.
- moving state correctly removes state-changing controls and leaves only the subdued stopped-only hint.
- no safe-area clipping or landscape crowding was observed.
- static screenshots validate composition, not temporal frame pacing; temporal policy remains test/profiling-gated and real hardware calibration is still required.

## Current quality gate
1. Phase 10 code/runtime/visual acceptance is complete.
2. `DECISIONS.md`, `DESIGN_SYSTEM.md`, `docs/TELEMETRY.md`, and project memory now record the accepted truth/performance policy.
3. Wait only for the newest docs-head `xcode-27` run to confirm the final branch lineage remains green.
4. Mark PR #3 ready and merge after that newest-head gate passes.
5. Immediately branch from updated `main` and continue the next slice: **mode-responsive Dashboard / RideEngine application + persistence wiring**, using the existing `RideEngine` and persistence contracts rather than creating replacements.

## Real Xcode / Simulator proof
GitHub-hosted `xcode-27` is the authoritative remote Mac gate when direct interactive tooling is unavailable.
- Proven environment: macOS 26.5.2 / Xcode 27.0 beta build 27A5228h / iOS 27 Simulator.
- Explicit visual baseline: iPhone 12 / iOS 27.
- CI preserves `.xcresult` and exports XCTest screenshots/attachments on failure and success.
- Hosted-runner UI bootstrap can be slow; assertion waits remain tight while the outer UI test allowance tolerates cold runner startup.

## Important truth boundaries
- Interpolated/display speed is never telemetry or ride evidence.
- Motion-assisted estimates never masquerade as authoritative scooter/GPS speed.
- Simulator ride duration is not packet-arrival cadence.
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
- `docs/TELEMETRY.md`
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
