# CONTINUATION PROMPT

Continue the **existing Nembra production iOS project**. Use GPT-5.6 Thinking/Sol High, @GitHub, @Build iOS Apps, current Apple documentation, Xcode 27, and iOS 27 Simulator. Do not create a new repository or app, do not restart architecture, and do not recreate accepted Home/Dashboard/telemetry/ride systems.

## Start here
1. Repository: `jonathangana131-lab/Nembra`.
2. Read `PROJECT_STATE.md` first, then this file, `DECISIONS.md`, `PROTOCOL_NOTES.md`, `DESIGN_SYSTEM.md`, and relevant docs under `docs/`.
3. Inspect current branches, recent commits, open PRs, and newest GitHub Actions runs before editing.
4. GitHub wins over stale milestone wording in older prompts.
5. Build/test the existing project before unnecessary architecture changes.
6. Continue autonomously through normal build/test/commit/PR steps. Do not stop because one tool call, screenshot, commit, or workflow finished.

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

## Active Phase 12 — ride application + persistence
Active branch: `feature/ride-application-persistence`.
PR: **#5** (draft while acceptance gates run).

The next work is not a new ride engine. It is application ownership and concrete persistence around the already-accepted ride domain.

### Existing implementation direction
- root `AppRuntime` owns `VehicleStore` and `RideApplicationStore`.
- both consume the same scooter service instance.
- `RideApplicationStore` bridges confirmed application evidence into existing `RideCheckpointCoordinator` / history handoff.
- SwiftData stores exact completed `RideHistoryRecord` payloads with session-ID uniqueness and idempotent conflict checks.
- Simulator persistence is namespaced separately from future production history.
- a transient portrait Home ride-status strip exposes real ride application state.
- app tests cover durable history reopen/idempotency, same-session recovery/completion, and raw-speed freshness semantics.
- UI test terminates/relaunches the process with a unique simulation storage namespace and requires the recovered ride state to return.

### Truth boundary discovered during Phase 12 audit
Only a **fresh raw authoritative speed packet** may populate `RideObservation.speedSample`.
- cached `VehicleState.speedKilometersPerHour` is never promoted into raw ride evidence.
- a previous raw speed packet is never replayed when a mode/light/lock/general state publication arrives.
- state-only observations are meaningful for real connection transitions and real odometer advancement, not arbitrary control acknowledgements.
- disconnect/reconnect remains ride continuity evidence but never fabricates a zero-speed measurement.
- evidence streams are registered before ride-store startup returns so the first QA packet cannot race past the subscriber.

### Production-vs-QA policy
- Simulator ride detection thresholds exist only to exercise the production application path deterministically.
- production automatic ride detection remains disabled until real MAXSHOT speed cadence/latency/reconnect timing is measured.
- do not silently promote Simulator thresholds into hardware defaults.

### Immediate execution contract
1. Inspect the newest workflow run for the **exact current Phase 12 head** after memory updates.
2. Require project validation + core package + Xcode app tests + UI tests + artifact upload to pass.
3. Inspect the real iPhone 12/iOS 27 XCTest attachments, especially automatic ride active/recovered relaunch states, and confirm existing Home/Dashboard visuals did not regress.
4. If a failure appears, patch only the proven issue, add/regress tests where useful, and run a new exact-head gate.
5. When implementation/runtime/screenshots are accepted, update project memory with exact run/job/count evidence.
6. Run one final docs-head gate, mark PR #5 ready, squash merge with the exact expected head, and verify `main`.
7. Continue to the next substantial system slice from fresh `main`; do not restart or prematurely jump into the final visual overhaul until its required data foundations exist.

## MANDATORY FUTURE MILESTONE — Production Visual Overhaul / Final Product Design Pass
This is a permanent master-directive requirement and a release gate. It must not be dropped, treated as optional polish, or postponed indefinitely.

### When it begins
Continue current systems work now. Start the dedicated major design phase once the UI has enough truthful foundational state, especially:
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
During long work, give concise visible status updates when builds/gates/screenshots/PR state meaningfully change. Do not reveal hidden chain-of-thought. Do not stop merely because one test, screenshot, commit, or workflow finished. Keep working until the active vertical slice is accepted or a genuine external dependency blocks execution.

Before context loss or long failure-prone operations, commit/push valid work and update `PROJECT_STATE.md` plus this continuation file so a fresh chat can continue from GitHub without asking the user to restate the project.
