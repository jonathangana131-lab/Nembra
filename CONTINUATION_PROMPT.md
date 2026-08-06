# CONTINUATION PROMPT

Continue the **existing Nembra production iOS project**. Use GPT-5.6 Thinking/Sol High, @GitHub, @Build iOS Apps, current Apple documentation, Xcode 27, and iOS 27 Simulator. Do not create a new repository or app, do not restart architecture, and do not recreate accepted Home/Dashboard/telemetry/ride systems.

## Start here
1. Repository: `jonathangana131-lab/Nembra`.
2. Read `PROJECT_STATE.md` first, then this file, `DECISIONS.md`, `PROTOCOL_NOTES.md`, `DESIGN_SYSTEM.md`, and relevant docs under `docs/`.
3. Inspect current branches, recent commits, open PRs, and newest GitHub Actions runs before editing.
4. GitHub wins over stale milestone wording in older prompts.
5. Build/test the existing project before unnecessary architecture changes.

## Product / engineering truth
- Nembra is a premium native iOS 27 scooter companion platform.
- MAXSHOT V1S Pro is the first supported vehicle.
- Architecture is capability-based; do not scatter model-name conditionals or add random vehicles yet.
- SwiftUI does not own BLE protocol logic.
- Simulation and future real Bluetooth conform to the same production service/domain path.
- Simulation is explicit QA only; ordinary launch remains hardware-gated through `UnverifiedScooterService` until real MAXSHOT protocol identity is verified.
- Never invent telemetry, Bluetooth UUIDs, writes, acknowledgements, VESC tuning, phase current, throttle %, torque, or mode-to-DP mappings.
- DP101/DP102/DP103 remain independent speed-limit slots until real MAXSHOT capture proves user-facing semantics.
- Device Trip is not Today mileage.

## Stable accepted work — do not rebuild
### Portrait Home
Accepted/merged. Preserve its status-first hierarchy, typed failures, retained/live/unknown truth, low-battery priority, moving Lock safety, and confirmed controls.

### Phase 9 — dedicated landscape Dashboard
Accepted/merged. It is a dedicated cockpit, not portrait Home rotated. It preserves dominant speed, battery, Scooter Trip, mode, connection/model identity, stopped-only state-changing controls, and moving-state safety. It has no fake throttle/current/power gauge.

### Phase 10 — measured-speed instrumentation
Accepted and merged to `main` at `9da973a4929e5408a14d38c919c6dbd2fd1004a3`.

Preserve:
- raw authoritative speed evidence separate from `VehicleState` and display frames.
- render-only/non-predictive `SpeedDisplayInterpolator`.
- `SpeedInstrumentModel` accepting authoritative samples only.
- fixed-slot `RollingNumberModel` / `RollingSpeedValueView` geometry.
- local 60 Hz-capable Dashboard speed subtree that pauses outside active interpolation.
- VoiceOver announcing authoritative/confirmed speed, not interpolated midpoint.
- no interpolation feedback into ride evidence, history, ODO, distance, benchmarks, or acceleration tests.
- production interpolation disabled until real MAXSHOT speed cadence/latency/resolution is measured.
- explicit Simulator QA presentation policy only for exercising animation.
- raw sample receive timestamps in real process monotonic clock time; simulator ride duration never manufactures packet cadence.

## Phase 11 — accepted implementation, final merge checkpoint
Active branch: `feature/dashboard-mode-personality`.
PR: **#4 — Add confirmed-mode Dashboard personality**.

Implementation/runtime/visual acceptance is complete on head:
`a622d22b91106917c3a2fc9d1b3abc81a5785ab6`

### Accepted Phase 11 behavior
`DashboardModePersonality` is pure presentation state resolved from the scooter-confirmed `RideMode?`.

Walk/Eco/Drive/Sport alter only restrained cockpit visual energy:
- center ambient intensity
- speed-instrument scale
- mode readout scale/marker
- secondary status emphasis

Truth/safety rules:
- confirmed mode drives the personality; a tap alone is never accepted as state.
- no telemetry, speed, ride evidence, command semantics, speed limit, distance, history, or persistence behavior changes.
- no MAXSHOT DP101/DP102/DP103 mapping is introduced or implied.
- no mode claims about measured power, torque, throttle, acceleration, range, or efficiency.
- treatment remains monochrome/semantic rather than RGB/gamer styling.
- Reduce Motion disables the spatial/snappy mode-personality animation while preserving confirmed state.
- Phase 10 speed instrumentation and fixed center geometry remain intact.
- stopped-only controls and moving-state safety remain intact.

### Phase 11 real Mac / Simulator proof
GitHub Actions run `31063560164`, job `92496459298`, on implementation head `a622d22b...` completed successfully on the `xcode-27` runner.

The exported artifact confirms:
- `NembraAppTests`: **14/14**, 0 failures.
- `NembraUITests`: **5/5**, 0 failures.
- project validation, core package validation, Xcode build/test/Simulator capture, and artifact upload all passed.

The mode UI test uses the real command-confirmation path and captures:
- Sport initial
- Walk confirmed
- Eco confirmed
- Drive confirmed
- Sport confirmed

The moving Dashboard test also keeps a real riding landscape capture and verifies state-changing controls are hidden/unavailable while moving.

Actual iPhone 12/iOS 27 attachments were visually inspected and accepted:
- Walk is calmer without looking disabled.
- Eco is incrementally stronger.
- Drive is the balanced baseline.
- Sport is more energetic without warning/RGB/gamer styling.
- speed remains dominant and unclipped.
- side rails remain stable.
- stopped controls remain separated from center speed.
- moving hierarchy/safety remain intact.
- no excessive glow, crowding, or safe-area clipping was observed.

## Exact immediate actions in a fresh/resumed chat
1. Inspect current PR #4 head. The next commit after `a622d22b...` should be the Phase 11 memory/design acceptance commit.
2. Inspect the newest `xcode-27` run for that exact documentation head.
3. If the newest docs-head gate is green, mark PR #4 ready for review and merge it with `expected_head_sha` set to that exact head. Do not reopen accepted Phase 11 design unless the final gate exposes a regression.
4. Confirm `main` contains the merge and updated project memory.
5. Create a new feature branch from the updated `main` for the next substantial ride application/persistence slice.
6. Before writing next-slice code, inspect the existing ride/persistence application path. Do not create a second ride engine or duplicate storage architecture.

## Next slice — ride application + persistence wiring
The ride domain is already substantial. The next job is to make that existing domain drive real application lifecycle behavior.

Inspect at minimum:
- `RideEngine`
- `RideCheckpointCoordinator`
- the two-slot recovery journal
- `completedPendingCommit`
- `RideHistoryCommitCoordinator`
- completed history store protocol/adapters
- distance reconciliation and explicit coverage
- `LiveDistanceSegmentAccumulator`
- `VehicleStore`
- `AppBootstrap`
- app lifecycle ownership/background hooks
- current simulation scenario plumbing

Do not replace these accepted contracts merely because application wiring is incomplete.

### Desired vertical-slice outcome
Choose the smallest substantial slice that proves the production application path end-to-end, likely including:
- root-owned automatic ride application coordinator/state outside SwiftUI view lifetime.
- confirmed scooter evidence feeding the existing `RideEngine`.
- checkpoint writes driven by real app state transitions/cadence.
- same durable ride identity surviving ordinary app navigation and recoverable relaunch/crash scenarios.
- completed ride going through `completedPendingCommit` and idempotent verified history handoff.
- concrete production persistence adapter where the existing contract still lacks one.
- simulation exercising exactly the same application coordinator/store/UI path.
- truthful UI consumption of current ride state without inventing measurements.

Acceptance must include build → run → interact → background/relaunch/recovery scenario where possible → screenshot → inspect → edge test → tests → commit/push → memory update.

## Ride architecture boundaries already accepted
- automatic `RideEngine` owns ride continuity outside SwiftUI.
- disconnect alone never ends a confirmed ride.
- motion is candidate evidence only; authoritative BLE/GPS/ODO evidence confirms truth according to injected policy.
- evidence freshness limits are injected; no MAXSHOT cadence constant before hardware measurement.
- two-slot generation journal checkpoints confirmed ride state.
- monotonic uptime never persists across process lifetime.
- recovered ride resumes conservatively with historical uptime unknown.
- `completedPendingCommit` blocks evidence loss between detector completion and history commit.
- history handoff is idempotent/readback verified; same UUID + conflicting evidence is a conflict, not overwrite.
- ODO/GPS/live-integrated distance remain independent with complete/partial/unknown coverage and are never blindly averaged.
- live distance integrates one authoritative raw speed source only and never integrates across oversized packet gaps.

## QA / performance rules
- `xcode-27` hosted runner is the authoritative remote Mac gate when direct interactive Xcode tooling is unavailable.
- iPhone 12/iOS 27 is the primary Simulator visual baseline.
- `.xcresult`, logs, Simulator screenshots, and XCTest attachments are preserved.
- passing hosted Simulator QA is real iOS runtime evidence, but not physical MAXSHOT hardware validation or physical iPhone 12 performance profiling.
- keep high-frequency animation local.
- use Observation/structured concurrency/current SwiftUI patterns already established in the project.
- respect VoiceOver, Reduce Motion, hit targets, contrast, and orientation behavior.
- do not accept a slice from compile success or a source-code review alone.

## Hardware validation still outstanding
Real MAXSHOT advertisement identity, services/characteristics/properties, notification cadence/latency/jitter/resolution, packet framing/checksum, reads/writes/acks, DP101-103 semantics, and AccessorySetupKit descriptors.

Keep **APP IMPLEMENTED** separate from **VERIFIED ON REAL MAXSHOT HARDWARE**.

## Communication / recovery contract
During long work, give concise visible status updates when builds/gates/screenshots/PR state meaningfully change. Do not reveal hidden chain-of-thought. Do not stop merely because one test, screenshot, commit, or workflow finished. Keep working until the active vertical slice is accepted or a genuine external dependency blocks execution.

Before context loss or long failure-prone operations, commit/push valid work and update `PROJECT_STATE.md` plus this continuation file so a fresh chat can continue from GitHub without asking the user to restate the project.
