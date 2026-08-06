# CONTINUATION PROMPT

Continue the **existing Nembra production iOS project** in public repo `jonathangana131-lab/Nembra`. Do not restart, create a second app, or resurrect rejected prototype/UI work. Use @GitHub, current Build iOS Apps guidance, Xcode 27, and iOS 27 Simulator.

## Communication / execution contract
- Show concise engineering progress every few meaningful tool operations or whenever build/Simulator/screenshot/PR/checkpoint state changes.
- Do not expose hidden chain-of-thought; report only useful status, discoveries, failures, fixes, and next quality gate.
- Do not stop because a workflow started/finished, one screenshot was created, one error was fixed, or one commit landed. Continue the active vertical slice through build → run → interact → screenshot → critique/fix → edge tests → commit/push → memory docs, then immediately begin the next slice.
- Before long/failure-prone chains, keep valid work committed/pushed and keep `PROJECT_STATE.md` + this file current.
- User explicitly requested **no image generation** in this development stream. Use real Simulator screenshots only.

## Product truth
- Product: **Nembra**; first vehicle: **MAXSHOT V1S Pro**.
- Production launch is hardware-gated through `UnverifiedScooterService`; simulation is explicit QA only.
- Never invent BLE advertisement/GATT UUIDs, writes, acknowledgements, notification cadence, VESC-style tuning, phase/battery current, field weakening, regen current, or telemetry.
- DP101/102/103 limiter slots remain independent until MAXSHOT-specific hardware capture proves user-facing semantics/mode mapping.
- Device Trip is never labeled Today.
- Unknown values stay unknown. Disconnect never fabricates zero. Unknown speed is never treated as stopped for Lock.

## Accepted architecture — preserve
- Capability-based `VehicleProfile` / `ScooterService` boundary.
- One state-changing vehicle command at a time; connection-generation token invalidates writes spanning disconnect/reconnect.
- `VehicleDataAvailability`: unavailable/live/retained.
- Raw speed evidence is separate from render interpolation; motion assist can never masquerade as authoritative speed.
- `SpeedDisplayInterpolator` is presentation-only/non-predictive.
- `RollingNumberModel` reserves fixed slots and models correct upward/downward carry/borrow.
- Automatic `RideEngine`, crash-safe two-slot checkpoint journal/coordinator, `completedPendingCommit`, idempotent history handoff, and independent ODO/GPS/live-distance reconciliation already exist. Do not rebuild them.

## Portrait Home — accepted
The giant scooter-art direction is dead. Home is status-first: model + connection/lock → Battery/Trip/Mode → Light/Lock → Walk/Eco/Drive/Sport → vehicle details. Low battery is semantic, retained data is explicitly stale, moving Lock is disabled, `home.connection` exposes a stable confirmed accessibility value, and connected/unknown-speed Lock uses the compact disabled subtitle `No speed`.

## Phase 9 landscape Dashboard — ACCEPTED
Accepted tested code head: `28e92c7cda34d4a70e079aafa8b70d8e4183465c`.
Authoritative Xcode run: **`31064505473`**, job `92499843475`.
Result: project validation PASS; **158/158 core tests PASS**; app tests PASS; **7/7 XCUITests PASS**; Simulator capture PASS; artifact upload PASS.
Artifact: `nembra-xcode27-simulator-139-1`, ID `8953548324`.

Accepted composition:
- dedicated compact-height iPhone landscape cockpit; portrait remains Home
- top-left MAXSHOT identity + truthful connection
- top-right confirmed mode
- dominant centered confirmed speed
- one bottom instrument shelf with Battery + scooter Trip, then stopped controls or moving read-only state
- stopped: integrated W/E/D/S selector + compact Liquid Glass Light/Lock
- moving: no state-changing controls; confirmed Headlight/Lock read-only
- connected/unknown speed: `SPEED UNAVAILABLE`, no stopped controls
- no maps/navigation yet
- no fake throttle/current/watts/acceleration UI
- **Phase 9 does not use interpolation yet**

The earlier sparse three-column/debug-HUD composition was visually rejected. The accepted unified shelf composition was reviewed on real iPhone 12/iOS 27 screenshots in riding, stopped, and speed-unavailable states. `DESIGN_SYSTEM.md` v0.3 records this rule.

### Phase 9 safety proof
Commit `c70caceae48950d796c81c4cc23027b8fc8b5e3b`:
- Lock requires finite confirmed speed <0.5 km/h before and after acknowledgement.
- Unlock remains allowed when speed is unknown.
- Movement beginning during acknowledgement rejects Lock before commit.
- Home unknown-speed Lock is disabled; Dashboard unknown speed suppresses stopped controls.
Connected unknown-speed simulation QA was added in `99695916b43700c02a91e044df62b19c68e9d3be`.

CI preserves branch-scoped cancellation:
```yaml
concurrency:
  group: xcode27-simulator-${{ github.ref }}
  cancel-in-progress: true
```

## Immediate handoff
PR #2 should be marked ready and merged to `main` now. The docs-only acceptance commits use `[skip ci]`; the tested app code is the exact `28e92c7` lineage above. After merge, create **fresh** `feature/measured-speed-instrumentation` from merged `main`. Do not merge/rebase the old divergent speed branch wholesale.

## Phase 10 — measured-speed instrumentation
Core pieces already on accepted lineage:
- `SpeedTelemetrySample`: source/provenance, monotonic arrival time, optional source timestamp/accuracy; BLE/GPS absolute, motionAssist estimate only.
- `TelemetryBenchmarkCollector`: effective Hz, interval min/mean/max/jitter, duplicate values, empirical speed step, source latency.
- `SpeedDisplayInterpolator`: authoritative samples only, out-of-order rejection, interruption continuity, no overshoot, display frames never telemetry.
- `RollingNumberModel`: fixed slots, global up/down direction, per-slot wrap steps, leading visibility, carry/borrow tests.

Old `feature/speed-instrumentation` is **reference-only**. Selectively reimplement:
1. narrow `VehicleStore.speedTelemetryUpdates()` accessor
2. app-side `SpeedInstrumentModel` with confirmed-state fallback → fresh authoritative raw sample → render-only interpolation
3. rolling-digit SwiftUI view whose transition direction is driven by the **full-value** `RollingNumberModel`, preserving 9→10, 19→20, 20→19 and fixed geometry
4. keep high-frequency redraw local to the speed subtree (e.g. `TimelineView(.animation)`), never mutate whole `VehicleStore` at display cadence

### Deterministic Phase 10 QA requirement
Static `.riding` only seeds confirmed `VehicleState`; it deliberately does not replay a cached raw speed packet. Phase 10 must add an explicit simulation-only raw-speed driver after the Dashboard subscriber exists. Suggested architecture:
- simulation-only service method that emits an authoritative simulated Bluetooth speed sample with an explicit local monotonic receipt timestamp and updates confirmed simulation state
- app bootstrap/store knows whether a deterministic telemetry QA script is configured
- Dashboard subscribes first, then the simulation-only driver runs a finite repeatable ramp
- app unit tests prove fallback/measured/interpolated origin, stale sample rejection, motion-assist rejection, interruption continuity, and no write-back to vehicle state
- XCUITest proves raw speed path becomes live; Simulator/video/screenshots verify digit geometry and cockpit stability
- benchmark the generated stream and label results **simulation-only**

Do not derive production MAXSHOT packet cadence from this simulation. Production interpolation timing remains hardware-validation-gated until real notification frequency/latency/resolution are observed. Runtime timing may adapt to measured packet intervals, but do not document a fictional scooter Hz.

## Continue after Phase 10
Continue autonomously through mode-responsive cockpit, ride persistence/app wiring, background Bluetooth/location, maps/navigation, history/stats, acceleration testing, BLE diagnostics and real MAXSHOT validation, cloud/accounts/leaderboard, Live Activities/widgets/App Intents, accessibility/performance/error hardening, end-to-end/release prep. One subsystem at a time, deeply finished before advancing.

## Hardware validation still outstanding
Real MAXSHOT advertisement identity, BLE services/characteristics, notification cadence/latency/resolution, packet framing/checksum, reads/writes/acks, DP101–103 semantics, and AccessorySetupKit descriptors. Keep **APP COMPLETE** separate from **HARDWARE VALIDATION REQUIRED**.
