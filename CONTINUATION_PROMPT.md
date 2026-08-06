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

## Phase 10 — accepted implementation, merge checkpoint
Active branch: `feature/speed-instrumentation-v2`.
PR: #3 `Add measured-speed Dashboard instrumentation`.

Phase 10 code/runtime/visual acceptance is complete. Do not redesign or replace it in a new chat.

Accepted behavior:
- `VehicleStore.speedTelemetryUpdates()` exposes raw speed evidence without publishing render frames to `VehicleState`.
- `SpeedInstrumentModel` wraps `SpeedDisplayInterpolator`, accepts authoritative samples only, rejects stale/motion-assist samples, and exposes render-only frames.
- before fresh raw telemetry arrives, confirmed `VehicleState` speed may initialize presentation without becoming a fake raw packet.
- `RollingSpeedValueView` uses fixed slots and a brief integer roll; it is not a second smoothing engine.
- `DashboardSpeedInstrumentView` owns raw-stream subscription and a local SwiftUI animation timeline capped at 60 Hz.
- the high-frequency timeline pauses outside an interpolation window and does not invalidate the whole Dashboard.
- Dashboard safety/moving-state decisions, controls, ride state, distance, history, and stats remain driven by confirmed/raw state, never interpolated frames.
- VoiceOver announces latest authoritative/confirmed speed, not an interpolated visual midpoint.
- long telemetry gaps snap instead of visually bridging missing evidence.

### Phase 10 timing truth
Do **not** choose MAXSHOT production interpolation timing before hardware measurement.
- `SpeedInstrumentInterpolationPolicy.disabled` is the production/default policy.
- ordinary/unverified production therefore snaps to authoritative measurements.
- explicit Simulator launch injects `.simulatorQA` only to exercise the visual system.
- Simulator QA values (50 ms minimum, 300 ms maximum-continuous interval, 0.8 interval fraction) are QA presentation settings only, not MAXSHOT claims.
- once real hardware notification cadence/latency/resolution is measured, introduce an explicit calibrated hardware policy; never silently reuse the Simulator profile.

### Simulator packet clock correction accepted during Phase 10
- raw `receivedAtUptimeNanoseconds` is packet-arrival evidence in the same process monotonic clock domain used by Dashboard rendering.
- `SimulatedScooterService` now timestamps raw samples using `DispatchTime.now().uptimeNanoseconds` with only a minimum monotonic increment for same-tick emissions.
- simulation `elapsedSeconds` advances ride distance/time fixtures only and never fabricates packet cadence.
- deterministic benchmark cadence remains tested with explicit synthetic sample timestamps.

### Phase 10 proof already accepted
Implementation head `a816ddeb0997deceefe8713c479dfa91571128e7` passed Xcode 27 run `31061900280` / job `92491409069`:
- NembraCore 157/157.
- NembraAppTests 13/13.
- NembraUITests 5/5.
- XCTest exported real iPhone 12/iOS 27 `Dashboard Riding Landscape` and `Dashboard Stopped Landscape` captures.
- visual inspection accepted center speed dominance, fixed width at `11` and `0`, MPH alignment, side-rail stability, stopped-control spacing, moving-control safety, and no clipping/crowding.
- still images do not prove temporal frame pacing; production timing remains hardware/profile gated.

## Exact immediate actions in a fresh chat
1. Inspect the current head and newest `xcode-27` run for `feature/speed-instrumentation-v2`. The project-memory documentation commits after `a816ddeb...` intentionally trigger one final branch-lineage gate.
2. If that newest docs-head run is green, mark PR #3 ready and merge it. Do not reopen Phase 10 design unless that final gate exposes a regression.
3. Confirm `main` contains the merge and project memory.
4. Create the next branch from updated `main` and continue **mode-responsive Dashboard / RideEngine application + persistence wiring**.
5. Before implementing that next slice, inspect the existing ride/persistence code (`RideEngine`, checkpoint coordinator/journal, completed-history commit contract, distance reconciliation/live-distance integration, current app bootstrap/store wiring). Do not create a second ride engine or duplicate persistence architecture.
6. Determine the smallest substantial application vertical slice that turns the already-built ride domain into real app behavior: automatic lifecycle wiring, crash-safe checkpoints/history handoff, and trustworthy UI consumption, with simulation exercising the exact production path.
7. Build/run/interact/screenshot/test that slice on iPhone 12/iOS 27 before accepting it.

## QA rules
- `.github/workflows/xcode27-simulator.yml` runs on the real `xcode-27` Mac image, prefers iPhone 12/iOS 27, runs core/app/UI tests, and captures deterministic Simulator states.
- per-branch concurrency uses `cancel-in-progress: true`; obsolete runs should not consume Mac capacity once newer lineage exists.
- `NembraUITests` is a real UI-testing target in `Nembra.xcodeproj`/shared scheme.
- CI preserves `NembraTests.xcresult` and exports XCTest attachments on failure or success.
- hosted-runner UI bootstrap can be slow; total XCUITest allowance accommodates cold startup while assertion waits remain tight.
- never call a slice complete from source or compile alone: build → run → interact → screenshot → critique → fix → edge test → profile when relevant → tests → commit/push → memory docs.
- show real Simulator screenshots; do not substitute generated mockups.

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

## Hardware validation still outstanding
Real MAXSHOT advertisement identity, BLE services/characteristics, notification cadence/latency/resolution, packet framing/checksum, reads/writes/acks, DP101-103 semantics, and AccessorySetupKit descriptors. Separate APP IMPLEMENTED from HARDWARE VALIDATION REQUIRED.

## Recovery requirement
After every significant milestone update `PROJECT_STATE.md`, `DECISIONS.md`, `PROTOCOL_NOTES.md` when relevant, `DESIGN_SYSTEM.md` when visual rules change, and this file. Keep enough information here that a fresh chat can locate the existing repo, build it before edits, inspect recent commits/screenshots, and continue the exact unfinished milestone without asking the user to re-explain the project.
