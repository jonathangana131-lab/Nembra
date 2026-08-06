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

## Current Home design rule
The rejected giant scooter-art Home direction is dead. Portrait Home is status-first:
vehicle identity + connection/lock → Battery/Trip/Mode → Light/Lock → Walk/Eco/Drive/Sport → vehicle details/ride context. A large scooter render is optional and must never displace useful information. Future exact graphics require verified physical references and a clear product purpose.

Home moving-state Lock must remain disabled with `Stop to lock`; service/domain rejection remains authoritative. Low battery receives semantic priority. Retained values remain explicitly last-known/read-only.

## QA rules
- GitHub workflow `.github/workflows/xcode27-simulator.yml` runs on the real `xcode-27` Mac image, uses iPhone 12/iOS 27 where available, runs core/app/UI tests, and captures deterministic Simulator states.
- `NembraUITests` is a real UI-testing target in `Nembra.xcodeproj`/shared scheme. Extend it for critical future interactions.
- CI preserves `NembraTests.xcresult` and exports XCTest attachments so interaction/screenshot failures can be inspected even when `xcodebuild test` fails.
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

## Exact current milestone
- `main` contains the accepted portrait Home merge `254b95a8d62d7d143df937cc0d8aa73f45548266`.
- Active branch: `feature/landscape-dashboard`.
- PR #2 remains draft until the final Phase 9 lineage is green and visually accepted.
- Phase 9 implementation exists: dedicated compact-height landscape `DashboardView`, portrait Home preserved, dominant confirmed speed, battery/trip/mode/connection, stopped-only compact controls, hidden state-changing controls while moving, stable accessibility identifiers, and landscape XCUITests with kept screenshots.
- Xcode 27 run `31058989306` at `f3394cac` was fully **green** and exported real `Dashboard Riding Landscape` + `Dashboard Stopped Landscape` attachments.
- Visual review accepted the stopped composition but found wasted dead space in the riding right rail.
- Final polish commits `cfb0f9fc` and `75fd6622` replace the old `Controls available when stopped` sentence with truthful read-only Headlight + Lock status while moving, and the XCUITest now asserts those values while still proving Light/Lock buttons are absent.
- Latest final-polish Xcode run at this checkpoint: `31059807152`, head `75fd662222f344e4323554c6763a034cd0e775ae`; it was queued when the memory checkpoint was written. Check this/newer head first.

### Phase 9 Dashboard acceptance gate
- enormous confirmed speed with safe iPhone 12 landscape fit
- mode, battery, scooter Trip, connection/model identity
- stopped-only compact Light/Lock and ride-mode controls
- no state-changing controls while moving; read-only confirmed Headlight/Lock state may remain visible
- no map/navigation yet
- no fake throttle/current/power gauge
- no interpolation presented as measured telemetry yet
- real XCUITest orientation coverage passes
- exported `Dashboard Riding Landscape` and `Dashboard Stopped Landscape` attachments are visually inspected
- fix any clipping, cramped rails, weak hierarchy, inaccessible controls, or orientation defects before merge

## Phase 10 reuse rule
The old `feature/speed-instrumentation` branch diverged before the accepted Home/Phase 9 work. **Do not merge or rebase that branch wholesale.** After Phase 9 merges, create a fresh Phase 10 branch from merged `main` and selectively transplant only valid narrow pieces:
- `VehicleStore.speedTelemetryUpdates()`
- `SpeedInstrumentModel`
- `RollingSpeedValueView`
- targeted app tests for confirmed fallback / measured / visually interpolated / stale / motion-estimated behavior

Core `SpeedDisplayInterpolator` and `RollingNumberModel` are already on the accepted lineage. Their tests cover first-sample snap, accel/decel no-overshoot, mid-transition interruption continuity, truth-boundary separation, stale/out-of-order rejection, motion-estimate rejection, fixed slots, 9→10, 19→20, 20→19, 99→100, and invalid values.

### Phase 10 execution
Wire the dedicated raw speed stream into the render-only interpolation/rolling-digit system. Keep high-frequency rendering local to the speed instrument rather than globally mutating `VehicleState`. Benchmark simulated cadence separately from render rate. Do not choose MAXSHOT production interpolation timing until real hardware notification cadence/latency/resolution is measured; Simulator timing can be an injected QA profile only. Re-run Xcode 27 and inspect real landscape screenshots/interaction after the speed layer is wired.

Then continue autonomously through mode-responsive Dashboard, ride engine app/persistence wiring, background Bluetooth, background location/route capture, MapKit rides, Dashboard navigation transformation, history/stats, acceleration tests, BLE diagnostics/protocol validation, real scooter validation, cloud/accounts, leaderboard, Live Activities/widgets/App Intents, accessibility/performance/error hardening, end-to-end/release prep. Do not stop after a single screen or ask whether to continue.

## Hardware validation still outstanding
Real MAXSHOT advertisement identity, BLE services/characteristics, notification cadence/latency/resolution, packet framing/checksum, reads/writes/acks, DP101-103 semantics, and AccessorySetupKit descriptors. Separate APP COMPLETE from HARDWARE VALIDATION REQUIRED.

## Recovery requirement
After every significant milestone update `PROJECT_STATE.md`, `DECISIONS.md`, `PROTOCOL_NOTES.md` when relevant, `DESIGN_SYSTEM.md` when visual rules change, and this file. Keep enough information here that a fresh chat can locate the existing repo, build it before edits, inspect recent commits/screenshots, and continue the exact unfinished milestone without asking the user to re-explain the project.
