# PROJECT STATE

Updated: 2026-08-06

## Product
- Product: **Nembra**
- First vehicle: **MAXSHOT V1S Pro**
- Repository: public `jonathangana131-lab/Nembra`
- Product stance: native iOS 27 scooter platform; MAXSHOT first; truthful telemetry and command confirmation; multi-vehicle architecture only after MAXSHOT quality is established.

## Current branch / milestone
- Active branch: `feature/landscape-dashboard`
- Stable branch: `main`
- Stable portrait Home merge: `254b95a8d62d7d143df937cc0d8aa73f45548266`
- Active milestone: **Phase 9 — dedicated landscape Dashboard Mode, final safety + Simulator gate**
- Next milestone: **Phase 10 — measured-speed instrumentation / render-only interpolation**

## Portrait Home — accepted and merged
- The rejected giant scooter-art direction is dead. Home is status-first: vehicle identity + connection/lock → Battery/Trip/Mode → Light/Lock → Walk/Eco/Drive/Sport → vehicle details.
- Moving state disables Lock; locked state offers Unlock; low battery has semantic priority; retained values are explicitly last-known/read-only.
- `home.connection` now exposes a stable confirmed accessibility value for reconnect QA.
- Speed-limit editing remains absent until DP101/102/103 user-facing semantics are verified.
- Real Home interaction gate passed on Xcode 27 before merge; PR #1 is merged.

## Phase 9 Dashboard implementation
- Compact-height iPhone landscape routes to a dedicated `DashboardView`; portrait remains Home.
- Current refined composition avoids the rejected sparse three-rail/debug-HUD look:
  - top-left model + truthful connection
  - top-right confirmed mode
  - dominant centered confirmed speed
  - one bottom instrument shelf containing Battery + scooter Trip and either stopped controls or moving read-only state
- Stopped controls use one integrated W/E/D/S selector plus compact native Liquid Glass Light/Lock controls.
- While moving, state-changing controls are absent and confirmed Headlight/Lock state remains read-only.
- Phase 9 still does **not** inject render interpolation into the speed display.
- No maps/navigation, fake throttle gauge, current/watts gauge, acceleration display, or fabricated telemetry.
- Landscape XCUITests rotate the iPhone, exercise moving/stopped state, confirm mode changes, and keep screenshots as XCTest attachments.

## Lock safety checkpoint
Commit `c70caceae48950d796c81c4cc23027b8fc8b5e3b` hardens the Lock boundary:
- Unknown speed is never treated as stationary.
- Lock requires a finite confirmed speed below 0.5 km/h before **and after** command acknowledgement.
- Unlock remains available even if speed is unknown.
- Home shows `Speed unavailable` and disables Lock when unlocked speed is unknown.
- Dashboard shows `SPEED UNAVAILABLE` and does not expose stopped controls when speed is unknown.
- Two new core regression tests prove unknown-speed Lock rejection/unlock availability and movement-during-ack rejection.
- Core package is now **158/158 tests passing** on Ubuntu validation before the final Mac gate.

## Real Xcode / Simulator proof
GitHub-hosted `xcode-27` is the authoritative remote Mac gate.
- Proven environment: macOS 26.5.2 / Xcode 27.0 beta build 27A5228h / iOS 27 Simulator / iPhone 12 baseline.
- Earlier Phase 9 run `31058989306` at `f3394cac` was fully green, but its sparse composition was visually rejected and rebuilt.
- Refined stopped cockpit screenshot from later Xcode output was visually accepted: speed hierarchy, top model/mode balance, and the unified bottom shelf are materially better.
- A later failed run exposed unrelated QA defects rather than Dashboard compile failures: reconnect used a brittle text query and riding expected Headlight Off although the deterministic riding fixture is Headlight On. Both tests are corrected.
- `.github/workflows/xcode27-simulator.yml` now has branch-scoped `cancel-in-progress` concurrency so future superseded Mac runs are discarded.
- **Do not merge PR #2 until the exact post-safety lineage is green on Xcode 27 and both named landscape screenshots are inspected.**

## Phase 10 selective reuse plan
The old `feature/speed-instrumentation` branch diverged before accepted Home/Phase 9 and must **not** be merged wholesale.
After Phase 9 merges, create a fresh branch from `main` and selectively reuse only:
- narrow `VehicleStore.speedTelemetryUpdates()` service stream
- `SpeedInstrumentModel` concept/tests
- a rolling-digit SwiftUI presentation rewritten/verified to honor the accepted `RollingNumberModel` carry/borrow direction

Core `SpeedTelemetry`, `TelemetryBenchmarkCollector`, `SpeedDisplayInterpolator`, and `RollingNumberModel` already live on the accepted lineage.
Important QA constraint: static `.riding` simulation is confirmed state only; raw speed samples are emitted only by `simulateRide(...)`. Phase 10 therefore needs an explicit deterministic QA telemetry-driving path rather than pretending a static riding state proves interpolation/cadence.

## Core architecture already implemented
- Capability-based `VehicleProfile` / `ScooterService` boundary.
- `SimulatedScooterService` + hardware-gated `UnverifiedScooterService`; production never silently launches simulation.
- Typed connection failures and unavailable/live/retained data availability.
- Serialized confirmed commands and connection-generation invalidation.
- Raw speed evidence + cadence/jitter/resolution/latency benchmark collector.
- Render-only `SpeedDisplayInterpolator` and fixed-slot directional `RollingNumberModel`.
- Automatic `RideEngine`, crash-safe checkpoint journal/coordinator, `completedPendingCommit`, idempotent history handoff, and independent ODO/GPS/live-distance reconciliation.

## Important truth boundaries
- Interpolated/display speed is never telemetry or ride evidence.
- Motion-assisted estimates never masquerade as authoritative scooter/GPS speed.
- Disconnect never fabricates zero.
- Unknown speed never means stopped for a safety-sensitive Lock operation.
- Device Trip is not labeled Today.
- DP101/102/103 remain independent until hardware proof maps them to user-facing semantics.
- No invented BLE writes/UUIDs/acks or VESC-style tuning.

## Hardware validation still required
Real MAXSHOT advertisement identity, services/characteristics, notification cadence/latency/resolution, reads/writes/acks, packet framing/checksum, DP101–103 semantics, and AccessorySetupKit descriptors.

## Next exact actions
1. Trigger/follow the Xcode 27 run on the post-safety branch head (the bot safety commit itself does not trigger downstream workflows).
2. Require project validation + **158/158 core tests** + app tests + all five XCUITests to pass.
3. Download/export and inspect `Dashboard Riding Landscape` and `Dashboard Stopped Landscape` at the iPhone 12/iOS 27 baseline.
4. If visually accepted, update `DESIGN_SYSTEM.md` with the unified cockpit shelf rule, update this file + `CONTINUATION_PROMPT.md` with the green run, mark PR #2 ready, and merge.
5. Immediately create a fresh Phase 10 branch from merged `main` and implement deterministic raw-speed QA + render-only interpolation/rolling digits.
6. Continue autonomously through the remaining master-directive vertical slices after each quality gate.

## Visual QA acceptance criteria
A vertical slice is accepted only after latest-lineage Mac build/test success, real interaction coverage, representative Simulator screenshots, visual critique/fix, and truth/safety edge cases. A green compile or a clean screenshot alone is not completion.
