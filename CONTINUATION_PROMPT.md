# CONTINUATION PROMPT

Continue the **existing Nembra production iOS project**. Use GPT-5.6 Thinking/Sol High, @GitHub, @Build iOS Apps, current Apple documentation, Xcode 27, and iOS 27 Simulator. Do not create a new repository or new app and do not resurrect rejected prototype/UI work.

## Start here
1. Repository: public `jonathangana131-lab/Nembra`.
2. Read `PROJECT_STATE.md` first, then `DECISIONS.md`, `PROTOCOL_NOTES.md`, `DESIGN_SYSTEM.md`, and relevant docs under `docs/`.
3. Inspect recent commits/current branch and GitHub Actions before changing code.
4. Build/test the existing project first on the `xcode-27` GitHub Mac gate (or direct Xcode 27 tooling if available).
5. Preserve completed architecture; do not regenerate telemetry/ride/persistence work.

## Communication / recovery contract
- During long development, provide concise visible engineering updates every few meaningful tool operations or whenever a build, Simulator, screenshot, PR, checkpoint, or gate changes state.
- Do not expose hidden chain-of-thought; communicate only useful status: what is being worked on, what passed/failed, what is being fixed, and what gate comes next.
- Do not stop simply because a workflow started, a test finished, a screenshot was created, or one defect was fixed. Continue the active vertical slice until its full quality gate is accepted or a genuine external dependency blocks work.
- Before long/failure-prone chains, keep valid progress committed/pushed and make `PROJECT_STATE.md` + this continuation file current.
- If execution is physically blocked, leave an exact unfinished action and resume instruction; otherwise do not make the user type “continue” as routine workflow.

## Product truth
- Product: Nembra.
- First vehicle: MAXSHOT V1S Pro.
- Multi-scooter architecture is capability-based, but no random additional vehicles until MAXSHOT is excellent.
- Ordinary production launch is hardware-gated through `UnverifiedScooterService`; simulation is explicit QA only.
- Never invent Bluetooth writes, UUIDs, acknowledgements, VESC tuning, phase/battery current, field weakening, regen current, or telemetry.
- DP101/102/103 speed-limit slots remain independent until MAXSHOT-specific capture proves user-facing semantics/mode mapping.
- Device Trip is never labeled Today.

## Stable UI milestones
- Portrait Home is accepted and merged on `main`.
- Dedicated landscape Dashboard Phase 9 is accepted and merged at `51613a990eb058ee83741645d8c551082d4ef268` after real Xcode 27 / iPhone 12 / iOS 27 build, XCUITest, and screenshot review.
- Dashboard Phase 9 removes state-changing controls while moving and has no fake throttle/current/power gauge.

## QA rules
- `.github/workflows/xcode27-simulator.yml` runs on the real `xcode-27` Mac image, prefers iPhone 12/iOS 27, runs core/app/UI tests, and captures deterministic Simulator states.
- The workflow now uses per-branch concurrency with `cancel-in-progress: true`; obsolete new-style runs should not consume Mac capacity.
- Some older runs created before the concurrency change can still finish; use them as evidence if useful but accept only the newest code lineage.
- `NembraUITests` is a real UI-testing target in `Nembra.xcodeproj`/shared scheme.
- CI preserves `NembraTests.xcresult` and exports XCTest attachments on failure or success.
- Hosted-runner UI bootstrap can take ~40 seconds; total XCUITest allowance is 120 seconds while assertion waits remain tight.
- Never call a slice complete from source or compile alone: build → run → interact → screenshot → critique → fix → edge test → profile when relevant → tests → commit/push → memory docs.
- Show real Simulator screenshots; do not substitute generated mockups. User explicitly requested no image generation in this work stream.

## Preserve these architecture boundaries
- `ScooterService` / capability model separates SwiftUI from transport.
- one state-changing command at a time until real protocol proves concurrency safe.
- connection-generation token invalidates writes spanning disconnect/reconnect.
- `VehicleDataAvailability`: unavailable/live/retained; disconnect never fabricates zero telemetry.
- raw speed evidence is separate from render interpolation.
- motion assist cannot masquerade as authoritative speed.
- `SpeedDisplayInterpolator` outputs visual frames only and is non-predictive.
- `RollingNumberModel` uses fixed slots and correct carry/borrow direction; presentation only.
- automatic `RideEngine` preserves confirmed ride identity through disconnect.
- crash recovery uses a two-slot generation journal; never persist monotonic uptime across process lifetime.
- `completedPendingCommit` prevents ride loss between detector completion and history storage.
- history handoff is idempotent/readback-verified.
- ODO/GPS/live distance stay independent with explicit complete/partial/unknown coverage; never average them.
- live distance integrates one authoritative raw speed source and never integrates over oversized packet gaps.

## Exact current milestone — Phase 10
- Active branch: `feature/speed-instrumentation-v2`.
- Draft PR: #3 `Add measured-speed Dashboard instrumentation`.
- Base: accepted Dashboard merge `51613a990eb058ee83741645d8c551082d4ef268`.
- Visible Dashboard **has now been changed** only at the center speed subtree; accepted side rails/controls remain intact.

### Phase 10 code already pushed
- `VehicleStore.speedTelemetryUpdates()` exposes raw speed evidence without publishing render frames to `VehicleState`.
- `SpeedInstrumentModel` wraps the core `SpeedDisplayInterpolator`, accepts authoritative samples only, rejects stale/motion-assist samples, and exposes render-only frames.
- `RollingSpeedValueView` uses fixed slots and a brief integer roll; it is not a second smoothing engine.
- `DashboardSpeedInstrumentView` owns the raw stream subscription and uses a local SwiftUI animation timeline capped at 60 Hz.
- the animation timeline pauses outside a real interpolation window.
- Dashboard safety/moving-state decisions, commands, ride state, distance, history and stats remain driven by confirmed/raw state, never interpolated frames.
- VoiceOver announces the latest authoritative/confirmed speed, not an interpolated visual midpoint.
- long telemetry gaps snap to the new measurement rather than visually bridging missing data.
- both Phase 10 source files are wired into the real Nembra Xcode target.

### CRITICAL timing rule
Do **not** choose MAXSHOT production interpolation timing before hardware measurement.
- `SpeedInstrumentInterpolationPolicy.disabled` is the production/default policy.
- ordinary/unverified production launch therefore snaps to authoritative measurements.
- explicit Simulator launch injects `.simulatorQA` to exercise the visual system.
- `.simulatorQA` values (50 ms minimum, 300 ms maximum-continuous interval, 0.8 interval fraction) are QA presentation settings only, not MAXSHOT claims.
- once real hardware notification cadence/latency/resolution is measured, introduce an explicit calibrated hardware policy; never silently reuse the Simulator profile.

### Phase 10 tests already pushed
- confirmed VehicleState fallback before fresh raw evidence.
- production/default model snaps even across close measurements.
- ordinary launch policy is disabled.
- explicit Simulator launch policy is `.simulatorQA`.
- QA profile interpolates only close authoritative measurements.
- stale + motion-assist samples do not move presentation state.
- QA profile snaps across long telemetry gaps.

### Exact next actions
1. Watch the newest `feature/speed-instrumentation-v2` Xcode 27 run. Older pre-concurrency jobs may still be occupying the runner; do not mistake queueing for a code failure.
2. If the latest lineage fails, fetch its Mac logs/artifact and fix the exact Swift 6/Xcode/UI-test issue without weakening the timing/truth boundaries above.
3. If green, download the latest artifact and inspect the real iPhone 12 `Dashboard Riding Landscape` and `Dashboard Stopped Landscape` attachments/screenshots.
4. Check digit geometry, leading-slot width, unit baseline, clipping, center dominance, rail movement, moving-control safety, and dark appearance.
5. Static screenshots cannot prove temporal smoothness; combine them with model tests and later device profiling. Do not pretend a still image measured frame rate.
6. Update `DECISIONS.md` and `DESIGN_SYSTEM.md` with the accepted local/pause/hardware-gated instrumentation rules.
7. Mark PR #3 ready and merge only after latest-lineage Mac + visual gate pass.
8. Immediately continue to the next master-directive slice: mode-responsive Dashboard / ride-engine application and persistence wiring. Do not stop after the merge.

## Hardware validation still outstanding
Real MAXSHOT advertisement identity, BLE services/characteristics, notification cadence/latency/resolution, packet framing/checksum, reads/writes/acks, DP101-103 semantics, and AccessorySetupKit descriptors. Separate APP COMPLETE from HARDWARE VALIDATION REQUIRED.

## Recovery requirement
After every significant milestone update `PROJECT_STATE.md`, `DECISIONS.md`, `PROTOCOL_NOTES.md` when relevant, `DESIGN_SYSTEM.md` when visual rules change, and this file. Keep enough information here that a fresh chat can locate the existing repo, build it before edits, inspect recent commits/screenshots, and continue the exact unfinished milestone without asking the user to re-explain the project.
