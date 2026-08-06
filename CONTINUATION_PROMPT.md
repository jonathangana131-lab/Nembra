# CONTINUATION PROMPT

Continue the **existing Nembra production iOS project**. Use GPT-5.6 Thinking/Sol High, @GitHub, @Build iOS Apps, current Apple documentation, Xcode 27, and iOS 27 Simulator. Do not create a new repository or app, do not restart architecture, and do not recreate accepted Home/Dashboard/telemetry/ride systems.

## Start here
1. Repository: `jonathangana131-lab/Nembra`.
2. Read `PROJECT_STATE.md` first, then this file, `DECISIONS.md`, `PROTOCOL_NOTES.md`, `DESIGN_SYSTEM.md`, and relevant docs under `docs/`.
3. Inspect current branches, recent commits, open PRs, and newest GitHub Actions runs before editing.
4. GitHub wins over stale milestone wording in older prompts.
5. Build/test the existing project before unnecessary architecture changes.
6. Continue autonomously through normal build/test/commit/PR steps. Do not stop because one tool call, screenshot, commit, or workflow finished.

## Continuous execution contract — permanent
A progress update is never a stopping point. While concrete Nembra work is available and tools remain usable, stay in the same assistant turn and immediately continue making tool calls after each meaningful status update.

Before every final response, perform this internal gate: **“Is there another concrete tool action I can perform right now that advances Nembra?”** If yes, do not finalize. Make the tool call and continue. Repeat until a genuine external dependency requires user input, available tools physically cannot perform the next required action, or the platform itself forcibly ends execution.

Operational rules:
- Never send a final response merely saying work is continuing, a build is running, a checkpoint was made, or the next inspection is planned. Those are status messages, not completion messages.
- Give concise visible updates only when something meaningful changes: implementation completed, build started/failed/passed, important bug found, Simulator screenshot inspected, QA gate passed, PR merged, or the next substantial vertical slice started.
- After every status update, immediately continue using tools in the same response. Never wait for the user to say “continue” because a progress update was sent.
- Git checkpoints protect progress; they do not end work. The sequence is `work → commit/push checkpoint → immediately continue working`.
- If Xcode GitHub Actions is queued or running, do not voluntarily stop when independent safe work exists. Inspect source, tests, prior Simulator artifacts, docs, or other safe parts of the same slice, then re-check CI. Never merge or accept a phase before its required exact-head gate passes.
- If the platform itself forcibly terminates a Thinking run, keep GitHub continuously recoverable. On the next turn, inspect the latest branch/head first, do not re-explain completed work, do not send a standalone continuation message, and immediately resume the exact unfinished action.
- The cadence is tool → tool → tool → meaningful status → tool → tool → tool. Do not interrupt execution merely to narrate.
- After one vertical slice is genuinely accepted and merged, immediately determine and begin the next planned substantial slice from fresh repository state unless a real dependency blocks it.

## Product / engineering truth
- Nembra is a premium native iOS 27 scooter companion platform.
- MAXSHOT V1S Pro is the first supported vehicle.
- Architecture is capability-based; do not scatter model-name conditionals or add random vehicles yet.
- SwiftUI does not own BLE protocol logic.
- Simulation and future real Bluetooth conform to the same production service/domain path.
- Simulation is explicit QA only; ordinary launch remains hardware-gated through `UnverifiedScooterService` until real MAXSHOT protocol identity is verified.
- Never invent telemetry, Bluetooth UUIDs, writes, acknowledgements, VESC tuning, phase current, throttle %, torque, range precision, battery precision, or mode-to-DP mappings.
- DP101/DP102/DP103 remain independent speed-limit slots until real MAXSHOT capture proves user-facing semantics.
- Device Trip is not Today mileage.

## Stable accepted work — preserve behavior, but do not confuse it with final visual quality
### Portrait Home
Functional system milestone accepted/merged. Preserve status-first hierarchy, typed failures, retained/live/unknown truth, low-battery priority, moving Lock safety, and confirmed controls.

### Phase 9 — dedicated landscape Dashboard
Functional system milestone accepted/merged. Dedicated cockpit, not portrait Home rotated. Preserve dominant speed, battery, Scooter Trip, mode, connection/model identity, stopped-only state-changing controls, moving-state safety, and no fake throttle/current/power gauge.

### Phase 10 — measured-speed instrumentation
Accepted/merged. Preserve raw authoritative speed separate from `VehicleState` and display frames; render-only/non-predictive interpolation; fixed rolling geometry; local high-frequency subtree; VoiceOver authoritative speed; production interpolation disabled until real MAXSHOT timing is measured; Simulator QA policy explicit only; real process monotonic receive timestamps.

### Phase 11 — confirmed-mode Dashboard personality
Accepted/merged on `main` at `e102595e2a85c4857c093ccfacea39ba9ff06307`.
Preserve confirmed-mode-only visual personality, restrained monochrome hierarchy, no RGB/gamer theme, no fake performance implications, no DP101/102/103 mapping, Reduce Motion support, fixed center geometry, and moving-state safety.

**Permanent visual-quality clarification:** all current Home/Dashboard screenshots and layouts are intermediate functional baselines. Their acceptance means the current system slice is coherent and regression-free. It does **not** mean Nembra has reached final product-level visual quality.

## Phase 12 — accepted functional implementation, final merge checkpoint
Active branch: `feature/ride-application-persistence`.
PR: **#5 — Wire automatic ride recovery and local history**.

Functional implementation/runtime/visual acceptance is complete on:
`2da5843312b27732888984f64e64ec58c52a32d7`

### Accepted application/persistence behavior
- root `AppRuntime` owns one shared scooter service plus `VehicleStore` and `RideApplicationStore` outside SwiftUI screen lifetime.
- `RideApplicationStore` reuses the existing `RideEngine`, `RideCheckpointCoordinator`, two-slot recovery journal, `completedPendingCommit`, and `RideHistoryCommitCoordinator`; do not replace these with parallel systems.
- both state and raw-speed streams are registered before ride-store startup returns.
- only fresh raw authoritative speed packets may fill `RideObservation.speedSample`.
- cached `VehicleState.speedKilometersPerHour` is never promoted to fresh ride evidence.
- mode/light/lock/general state acknowledgements cannot replay a previous speed packet or manufacture a zero-speed sample.
- state-only ride observations are limited to meaningful connection transitions or real odometer advancement.
- if an authoritative packet reaches the app while the independent state stream still reports connecting/reconnecting, only the newest **unconsumed** packet may be held; it is consumed exactly once after confirmed connected state catches up, cleared on disconnect, and remains subject to `RideEngine` freshness policy.
- unchanged `status`, `activeSessionID`, `continuity`, and error values are not reassigned on every high-frequency packet, limiting unnecessary Observation invalidation.
- SwiftData is the concrete local completed-history adapter. It stores the exact validated core ride record, enforces session-ID uniqueness, verifies exact readback, returns idempotent success for an equivalent duplicate, rejects same-ID conflicting evidence, and rejects a stored payload whose session identity disagrees with its row.
- simulation recovery/history has an isolated namespace and cannot silently contaminate future production ride data.
- ordinary unverified production launch keeps automatic ride detection disabled until real MAXSHOT cadence/latency/reconnect behavior is measured.
- Simulator thresholds are QA fixtures only and must never be promoted into hardware defaults without evidence.
- portrait Home exposes only a restrained transient ride-status strip for meaningful application ride state.

### Exact Phase 12 Xcode 27 proof
Implementation head: `2da5843312b27732888984f64e64ec58c52a32d7`.

GitHub Actions:
- run: `31067831584`
- job: `92509801452`
- runner: `xcode-27`
- conclusion: **success**
- project validation: passed
- core package validation: passed
- full Xcode/iOS 27 Simulator app/UI stage: passed
- artifact upload: passed

Exported result:
- `NembraAppTests`: **20/20**, zero failures.
- `NembraUITests`: **6/6**, zero failures.

Phase 12 app coverage includes:
- SwiftData durable reopen/idempotency/conflict semantics.
- payload/session corruption rejection.
- one raw speed packet cannot be replayed by state-only acknowledgements.
- deterministic cross-stream race where raw speed arrives before connected state and is consumed once only when state catches up.
- same durable session identity after coordinator/process recreation, fresh reconnect evidence, completion, history commit, and recovery-journal acknowledgement.
- production/default runtime automatic ride detection remains disabled.

The UI suite includes a real terminate/relaunch flow with an isolated simulation storage namespace. Kept iPhone 12/iOS 27 attachments inspected:
- `Automatic Ride Active Home`
- `Automatic Ride Recovered Home`

The recovered screenshot returns as `Ride resumed`; it does not present a fake new ride. No safe-area clipping, crowding, or hierarchy regression was observed. This is functional systems-slice visual acceptance only, not final-product visual acceptance.

### Phase 12 performance/truth audit
- high-frequency Dashboard rendering remains isolated by Phase 10.
- packet ingestion does not repeatedly republish unchanged ride application presentation fields.
- no code-first evidence justifies replacing the current architecture before physical-device profiling.
- hosted Simulator evidence is not physical iPhone 12 profiling and not MAXSHOT BLE validation.
- the only accepted-run warnings were Xcode AppIntents metadata skips because there is no AppIntents framework dependency; they are not Phase 12 failures.

## Exact immediate actions in a fresh/resumed chat
1. Inspect the current `feature/ride-application-persistence` head. The commit after `2da58433...` should be the Phase 12 project-memory acceptance commit.
2. Inspect the newest `xcode-27` workflow for that **exact docs head**.
3. Freeze the branch while it runs. Do not reopen accepted Phase 12 architecture unless the exact final gate reveals a real regression.
4. If green, mark PR #5 ready and **squash merge** using `expected_head_sha` set to that exact docs head.
5. Confirm the resulting `main` head and re-read `PROJECT_STATE.md`, `CONTINUATION_PROMPT.md`, branches, PRs, commits, and latest Actions from fresh `main`.
6. Determine the next substantial vertical slice from repository state and create its feature branch from the updated `main`. Do not guess the next phase from an older prompt.
7. Continue autonomously.

## MANDATORY FUTURE MILESTONE — Production Visual Overhaul / Final Product Design Pass
This is a permanent master-directive requirement and a release gate. It must not be dropped, treated as optional polish, or postponed indefinitely.

### When it begins
Continue systems work until the UI has enough truthful foundational state, especially:
- battery telemetry / SoC and any legitimate range inputs.
- automatic ride state and live trip data.
- maps/navigation and route state.
- persisted/completed rides.
- relevant vehicle, charging, connection, and error state.

Do not redesign prematurely around placeholders, but do not call the current intermediate UI final either.

### Final landscape Dashboard quality bar
Pursue the original master vision as a quality bar, not a pixel-for-pixel layout:
- world-class native iOS 27 appearance.
- premium modern EV instrumentation.
- Stark/Tesla-level cockpit polish without copying either.
- huge beautiful rolling MPH.
- Tesla-quality real-time battery presentation with 1% behavior only where legitimately supported by actual telemetry.
- elegant range/trip/duration information from real evidence.
- deeply integrated navigation that dynamically rearranges the cockpit.
- polished live ride information.
- restrained but meaningful Eco/Drive/Sport personalities.
- original premium scooter-aware graphics where useful.
- beautiful native materials/Liquid Glass used with restraint.
- excellent typography, spacing, depth, animation, haptics, accessibility, and interaction.
- minimal wasted space.
- no developer-dashboard aesthetic, giant empty black regions, generic cards, prototype rails, or placeholder-looking surfaces.

### Required screen-by-screen overhaul loop
For every major surface before visual completion:
1. current **real Simulator screenshot**.
2. critique against the master product vision and truthful available data.
3. redesign.
4. implement in production SwiftUI/domain state.
5. run/interact on iPhone 12/iOS 27.
6. screenshot.
7. critique again.
8. repeat until product-level quality is reached.

Must cover:
- portrait Home.
- landscape Dashboard without navigation.
- landscape Dashboard with navigation and dynamic layout changes.
- live ride states.
- battery / charging / low-battery states where supported.
- completed rides/maps.
- history/stats.
- leaderboard when implemented.
- controls/settings.
- major connection, permission, unsupported-hardware, persistence, and recovery error states.

A technically correct screen that looks mediocre is **not final**. Clean constraints, no clipping, and passing screenshots are engineering necessities, not final visual acceptance.

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
- the application bridge never treats control acknowledgements as ride telemetry and never replays one raw packet as multiple measurements.

## QA / performance rules
- `xcode-27` hosted runner is the authoritative remote Mac gate when direct interactive Xcode tooling is unavailable.
- iPhone 12/iOS 27 is the primary Simulator visual baseline.
- `.xcresult`, logs, Simulator screenshots, and XCTest attachments are preserved.
- passing hosted Simulator QA is real iOS runtime evidence, but not physical MAXSHOT hardware validation or physical iPhone 12 performance profiling.
- keep high-frequency animation local.
- use Observation/structured concurrency/current SwiftUI patterns already established in the project.
- respect VoiceOver, Reduce Motion, hit targets, contrast, and orientation behavior.
- do not accept a slice from compile success or source-code review alone.
- system-phase screenshot acceptance does not waive the future Production Visual Overhaul milestone.

## Hardware validation still outstanding
Real MAXSHOT advertisement identity, services/characteristics/properties, notification cadence/latency/jitter/resolution, packet framing/checksum, reads/writes/acks, DP101-103 semantics, and AccessorySetupKit descriptors.

Keep **APP IMPLEMENTED** separate from **VERIFIED ON REAL MAXSHOT HARDWARE**.

## Communication / recovery contract
During long work, give concise visible status updates when builds/gates/screenshots/PR state meaningfully change. Do not reveal hidden chain-of-thought. A progress update is never a completion event. After every update, immediately resume tool execution while actionable Nembra work remains.

Before context loss or long failure-prone operations, commit/push valid work and update `PROJECT_STATE.md` plus this continuation file so a fresh chat can continue from GitHub without asking the user to restate the project.
