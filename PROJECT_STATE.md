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
- Phase 9 implementation/tested code head: `28e92c7cda34d4a70e079aafa8b70d8e4183465c`
- Active milestone: **Phase 9 — ACCEPTED, PR #2 ready to merge**
- Next milestone: **Phase 10 — measured-speed instrumentation / render-only interpolation**

## Portrait Home — accepted and merged
- The rejected giant scooter-art direction is dead. Home is status-first: vehicle identity + connection/lock → Battery/Trip/Mode → Light/Lock → Walk/Eco/Drive/Sport → vehicle details.
- Moving state disables Lock; locked state offers Unlock; low battery has semantic priority; retained values are explicitly last-known/read-only.
- `home.connection` exposes a stable confirmed accessibility value for reconnect QA.
- Speed-limit editing remains absent until DP101/102/103 user-facing semantics are verified.
- Real Home interaction gate passed on Xcode 27 before merge; PR #1 is merged.

## Phase 9 Dashboard — accepted
- Compact-height iPhone landscape routes to a dedicated `DashboardView`; portrait remains Home.
- Accepted composition deliberately rejects the earlier sparse three-rail/debug-HUD direction:
  - top-left model + truthful connection
  - top-right confirmed mode
  - dominant centered confirmed speed
  - one bottom instrument shelf containing Battery + scooter Trip and either stopped controls or moving read-only state
- Stopped controls use one integrated W/E/D/S selector plus compact native Liquid Glass Light/Lock controls.
- While moving, state-changing controls are absent and confirmed Headlight/Lock state remains read-only.
- Phase 9 does **not** inject render interpolation into the speed display.
- No maps/navigation, fake throttle gauge, current/watts gauge, acceleration display, or fabricated telemetry.
- Landscape XCUITests rotate the iPhone, exercise moving/stopped/unknown-speed states, confirm mode changes, and keep screenshots as XCTest attachments.

## Lock safety checkpoint
Commit `c70caceae48950d796c81c4cc23027b8fc8b5e3b` hardens the Lock boundary:
- Unknown speed is never treated as stationary.
- Lock requires a finite confirmed speed below 0.5 km/h before **and after** command acknowledgement.
- Unlock remains available even if speed is unknown.
- Home uses the compact disabled Lock subtitle `No speed` when unlocked speed is unknown.
- Dashboard shows `SPEED UNAVAILABLE` and does not expose stopped controls when speed is unknown.
- Two core regression tests prove unknown-speed Lock rejection/unlock availability and movement-during-ack rejection.
- Core package is **158/158 tests passing**.

## Connected unknown-speed QA
Commit `99695916b43700c02a91e044df62b19c68e9d3be` added explicit QA for the startup state where the vehicle connection and other DPs are known but speed has not arrived yet.
- Simulation scenario: `connected-speed-unknown`.
- Portrait XCUITest requires `home.connection == Connected`, finds Lock, and proves it is disabled with `No speed`.
- Landscape XCUITest requires `SPEED UNAVAILABLE` and proves Lock/Light/mode controls are absent.
- Landscape test retains `Dashboard Speed Unavailable Landscape`.
- Simulator capture harness records portrait `connected-speed-unknown` too.
- Phase 9 UI suite is **7 XCUITests**.

## Final real Xcode / Simulator proof
GitHub-hosted `xcode-27` is the authoritative remote Mac gate.
- Proven environment: macOS 26.5.2 / Xcode 27.0 beta build 27A5228h / iOS 27 Simulator / iPhone 12 baseline.
- Earlier green Phase 9 run `31058989306` at `f3394cac` was visually rejected because the layout was too sparse; Phase 9 remained open and was rebuilt.
- Final accepted run: **`31064505473`**, job `92499843475`, tested code head **`28e92c7cda34d4a70e079aafa8b70d8e4183465c`**.
- Final gate result: project validation PASS; **158/158 core tests PASS**; app tests PASS; **7/7 XCUITests PASS**; Simulator capture PASS; artifact upload PASS.
- Final artifact: `nembra-xcode27-simulator-139-1`, artifact ID `8953548324`.
- Visual acceptance reviewed real iPhone 12/iOS 27 frames for riding, stopped, and connected-speed-unknown. No clipping or orphaned control layout remains; the portrait safety subtitle now fits fully as `No speed`.
- `.github/workflows/xcode27-simulator.yml` has branch-scoped `cancel-in-progress` concurrency so superseded Mac runs are discarded.
- `DESIGN_SYSTEM.md` v0.3 records the accepted unified cockpit shelf rule and unknown-speed behavior.

## Phase 10 selective reuse plan
The old `feature/speed-instrumentation` branch diverged before accepted Home/Phase 9 and must **not** be merged wholesale.
After PR #2 merges, create a fresh branch from `main` and selectively reuse/reimplement only:
- narrow `VehicleStore.speedTelemetryUpdates()` service stream
- `SpeedInstrumentModel` concept/tests
- a rolling-digit SwiftUI presentation verified against the accepted `RollingNumberModel` carry/borrow direction

Core `SpeedTelemetry`, `TelemetryBenchmarkCollector`, `SpeedDisplayInterpolator`, and `RollingNumberModel` already live on the accepted lineage.
Important QA constraint: static `.riding` simulation is confirmed state only; raw speed samples are emitted only by simulation methods that explicitly generate packets. Phase 10 needs an explicit deterministic raw-telemetry-driving QA path rather than pretending a static riding state proves interpolation/cadence.

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
1. Update PR #2 with final run/artifact proof, mark it ready, and merge the accepted Phase 9 branch to `main`.
2. Create fresh `feature/measured-speed-instrumentation` from merged `main`; do not merge the old divergent speed branch.
3. Add deterministic raw-speed simulation QA and a narrow `VehicleStore` raw stream accessor.
4. Implement a presentation-only speed instrument that keeps confirmed-state fallback separate from fresh measured telemetry and visual interpolation.
5. Rebuild the rolling SwiftUI view so full-value transition direction drives carry/borrow behavior; keep high-frequency redraw local to the speed subtree.
6. Build/test on Xcode 27, benchmark the simulation stream explicitly as simulation-only, inspect real landscape Simulator behavior, fix, commit, merge, then continue the next master-directive slice.

## Visual QA acceptance criteria
A vertical slice is accepted only after latest-lineage Mac build/test success, real interaction coverage, representative Simulator screenshots, visual critique/fix, and truth/safety edge cases. A green compile or a clean screenshot alone is not completion.
