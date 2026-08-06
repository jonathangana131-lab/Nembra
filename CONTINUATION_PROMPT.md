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
- Dashboard Phase 9 shows only confirmed speed; moving state removes state-changing controls; no fake throttle/current/power gauge exists.

## QA rules
- GitHub workflow `.github/workflows/xcode27-simulator.yml` runs on the real `xcode-27` Mac image, uses iPhone 12/iOS 27 where available, runs core/app/UI tests, and captures deterministic Simulator states.
- `NembraUITests` is a real UI-testing target in `Nembra.xcodeproj`/shared scheme. Extend it for critical future interactions.
- CI preserves `NembraTests.xcresult` and exports XCTest attachments so interaction/screenshot failures can be inspected even when `xcodebuild test` fails.
- The hosted runner may spend ~40 seconds establishing the first UI automation session. Total XCUITest allowance is 120 seconds while assertion-level waits remain tight.
- Never call a slice complete from source or compile alone: build → run → interact → screenshot → critique → fix → edge test → profile when relevant → tests → commit/push → memory docs.
- Show real Simulator screenshots; do not substitute generated mockups. User explicitly requested no image generation in this work stream.

## Preserve these architecture boundaries
- `ScooterService` / capability model separates SwiftUI from transport.
- One state-changing command at a time until real protocol proves concurrency safe.
- Connection-generation token invalidates writes spanning disconnect/reconnect.
- `VehicleDataAvailability`: unavailable/live/retained; disconnect never fabricates zero telemetry.
- Raw speed evidence is separate from render interpolation.
- Motion assist cannot masquerade as authoritative speed.
- `SpeedDisplayInterpolator` outputs visual frames only and is non-predictive.
- `RollingNumberModel` uses fixed slots and correct carry/borrow direction; presentation only.
- Automatic `RideEngine` preserves confirmed ride identity through disconnect.
- Crash recovery uses two-slot generation journal; never persist monotonic uptime across process lifetime.
- `completedPendingCommit` prevents ride loss between detector completion and history storage.
- History handoff is idempotent/readback-verified.
- ODO/GPS/live distance stay independent with explicit complete/partial/unknown coverage; never average them.
- Live distance integrates one injected authoritative raw speed source and never integrates over oversized packet gaps.

## Exact current milestone — Phase 10
- Active branch: `feature/speed-instrumentation-v2`.
- Start point: accepted Dashboard merge `51613a990eb058ee83741645d8c551082d4ef268`.
- Already pushed:
  - `VehicleStore.speedTelemetryUpdates()` raw evidence boundary.
  - `SpeedInstrumentModel.swift` around the existing core `SpeedDisplayInterpolator`.
  - `RollingSpeedValueView.swift` using existing `RollingNumberModel`.
  - App tests for confirmed-state fallback, authoritative-only interpolation, stale/motion-assist rejection, and long-gap duration bounding.
  - Updated `PROJECT_STATE.md` checkpoint.
- The visible Dashboard has **not** yet been changed in Phase 10.

### Phase 10 exact next actions
1. Wire `SpeedInstrumentModel.swift` and `RollingSpeedValueView.swift` into `Nembra.xcodeproj`.
2. Run the real Xcode 27 test gate before changing Dashboard UI. Fix compile/test failures without weakening truth boundaries.
3. Add a narrow Dashboard speed subtree that subscribes once to `VehicleStore.speedTelemetryUpdates()` and renders using `SpeedInstrumentModel`.
4. Use a local animation-cadence render mechanism only for the speed subtree; do not make global `VehicleState` update at display frequency.
5. Moving-state safety, ride engine, distance integration, history, stats and commands must remain based on confirmed/raw evidence, never visual interpolation.
6. Preserve exact accessibility value semantics: VoiceOver should announce a truthful speed value without describing interpolated frames as sensor measurements.
7. Run landscape XCUITest + screenshots, inspect iPhone 12 frames for digit jitter, clipping, width shifts, unit alignment and animation-induced layout changes.
8. Keep transition timing based on observed cadence and bounded presentation heuristics. Do not claim a production MAXSHOT BLE notification rate until real hardware captures exist.
9. Merge only after Mac build/test + Simulator visual review are green, then continue immediately into mode-responsive Dashboard / ride-engine app wiring.

## Hardware validation still outstanding
Real MAXSHOT advertisement identity, BLE services/characteristics, notification cadence/latency/resolution, packet framing/checksum, reads/writes/acks, DP101-103 semantics, and AccessorySetupKit descriptors. Separate APP COMPLETE from HARDWARE VALIDATION REQUIRED.

## Recovery requirement
After every significant milestone update `PROJECT_STATE.md`, `DECISIONS.md`, `PROTOCOL_NOTES.md` when relevant, `DESIGN_SYSTEM.md` when visual rules change, and this file. Keep enough information here that a fresh chat can locate the existing repo, build it before edits, inspect recent commits/screenshots, and continue the exact unfinished milestone without asking the user to re-explain the project.
