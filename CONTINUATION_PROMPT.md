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
- PR #2 is draft and must remain unmerged until the landscape gate is green and visually accepted.
- Phase 9 implementation already exists: dedicated compact-height landscape `DashboardView`, portrait Home preserved, dominant confirmed speed, battery/trip/mode/connection, stopped-only compact controls, moving-state control removal, stable accessibility identifiers, and landscape XCUITests with kept screenshots.
- Xcode run `31057841472` failed only because a `@MainActor tearDown()` override had actor isolation incompatible with XCTest. The Dashboard application target compiled. That test-target defect has already been fixed by removing the actor-isolated override pattern; the latest branch commit after that fix is `6dae8c8bbd383507d714911a4aa70ded0e512ceb` or newer.
- Continue by watching the newest Xcode 27 run on `feature/landscape-dashboard`, not by re-investigating the old `tearDown()` failure.

### Phase 9 Dashboard acceptance gate
- enormous confirmed speed with safe iPhone 12 landscape fit
- mode, battery, scooter Trip, connection/model identity
- stopped-only compact Light/Lock and ride-mode controls
- no state-changing controls while moving
- no map/navigation yet
- no fake throttle/current/power gauge
- no interpolation presented as measured telemetry yet
- real XCUITest orientation coverage passes
- exported `Dashboard Riding Landscape` and `Dashboard Stopped Landscape` attachments are visually inspected
- fix any clipping, cramped rails, weak hierarchy, inaccessible controls, or orientation defects before merge

### Phase 10 immediately afterward
Wire existing raw speed telemetry into the render-only interpolation/rolling-digit system. Benchmark real/simulated cadence separately from render rate. Keep measured speed and displayed interpolated frames explicitly distinct. Do not choose MAXSHOT production interpolation timing until hardware cadence is measured; Simulator timing can be an injected QA profile only.

Then continue autonomously through mode-responsive Dashboard, ride engine app/persistence wiring, background Bluetooth, background location/route capture, MapKit rides, Dashboard navigation transformation, history/stats, acceleration tests, BLE diagnostics/protocol validation, real scooter validation, cloud/accounts, leaderboard, Live Activities/widgets/App Intents, accessibility/performance/error hardening, end-to-end/release prep. Do not stop after a single screen or ask whether to continue.

## Hardware validation still outstanding
Real MAXSHOT advertisement identity, BLE services/characteristics, notification cadence/latency/resolution, packet framing/checksum, reads/writes/acks, DP101-103 semantics, and AccessorySetupKit descriptors. Separate APP COMPLETE from HARDWARE VALIDATION REQUIRED.

## Recovery requirement
After every significant milestone update `PROJECT_STATE.md`, `DECISIONS.md`, `PROTOCOL_NOTES.md` when relevant, `DESIGN_SYSTEM.md` when visual rules change, and this file. Keep enough information here that a fresh chat can locate the existing repo, build it before edits, inspect recent commits/screenshots, and continue the exact unfinished milestone without asking the user to re-explain the project.
