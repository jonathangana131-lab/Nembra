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
- Unknown values stay unknown. Disconnect never fabricates zero.

## Accepted architecture — preserve
- Capability-based `VehicleProfile` / `ScooterService` boundary.
- One state-changing vehicle command at a time; connection-generation token invalidates writes spanning disconnect/reconnect.
- `VehicleDataAvailability`: unavailable/live/retained.
- Raw speed evidence is separate from render interpolation; motion assist can never masquerade as authoritative speed.
- `SpeedDisplayInterpolator` is presentation-only/non-predictive.
- `RollingNumberModel` reserves fixed slots and models correct upward/downward carry/borrow.
- Automatic `RideEngine`, crash-safe two-slot checkpoint journal/coordinator, `completedPendingCommit`, idempotent history handoff, and independent ODO/GPS/live-distance reconciliation already exist. Do not rebuild them.

## Portrait Home — accepted and merged
`main` contains Home merge `254b95a8d62d7d143df937cc0d8aa73f45548266`.
The rejected giant scooter-art Home direction is dead. Home is status-first: model + connection/lock → Battery/Trip/Mode → Light/Lock → Walk/Eco/Drive/Sport → vehicle details. Low battery is semantic, retained data is explicitly stale, moving Lock is disabled, and `home.connection` exposes a stable confirmed accessibility value.

## Exact current milestone — Phase 9 landscape Dashboard
Active branch: `feature/landscape-dashboard`.
PR #2 remains draft until the **post-safety latest lineage** is green and both landscape screenshots are visually accepted.

Current Dashboard composition:
- dedicated compact-height iPhone landscape cockpit; portrait remains Home
- black instrument surface
- top-left MAXSHOT identity + connection
- top-right confirmed mode
- dominant centered confirmed speed
- one bottom instrument shelf with Battery + scooter Trip, then stopped controls or moving read-only state
- stopped controls: integrated W/E/D/S selector + compact Liquid Glass Light/Lock
- moving: no state-changing controls; confirmed Headlight/Lock read-only
- no maps/navigation yet
- no fake throttle/current/watts/acceleration UI
- **Phase 9 does not use interpolation yet**

The earlier sparse three-column/debug-HUD composition was visually rejected. The refined unified cockpit/shelf composition is materially better; stopped screenshot has already been visually accepted. The final named riding/stopped screenshots still must come from the latest green lineage before merge.

## Latest safety checkpoint
Atomic core/UI safety commit: `c70caceae48950d796c81c4cc23027b8fc8b5e3b`.
It fixes a real boundary where unknown speed had been treated like zero/stopped:
- Lock requires a finite confirmed speed <0.5 km/h before and after acknowledgement.
- Unlock remains allowed when speed is unknown.
- If movement begins during command acknowledgement, Lock is rejected before commit.
- Home unlocked/unknown-speed state says `Speed unavailable` and disables Lock.
- Dashboard connected/unknown-speed state says `SPEED UNAVAILABLE` and exposes no stopped controls.
- Core regression suite is now **158/158 passing**.

XCUITest corrections already on branch:
- reconnect waits on `home.connection == Connected` rather than brittle arbitrary text
- deterministic `.riding` fixture expects Headlight `On` and Lock `Unlocked`

CI workflow now has:
```yaml
concurrency:
  group: xcode27-simulator-${{ github.ref }}
  cancel-in-progress: true
```
Preserve this so stale Mac runs do not queue indefinitely.

### Phase 9 final acceptance gate — do this first
1. Find the newest `Xcode 27 Simulator QA` run on the branch **after the latest connector-authored docs checkpoint** (bot commits do not trigger downstream workflows by themselves).
2. Require project validation + **158/158 core tests** + app tests + all five XCUITests.
3. Download the run artifact; inspect the named `Dashboard Riding Landscape` and `Dashboard Stopped Landscape` attachments on iPhone 12/iOS 27.
4. Reject/fix any clipping, weak hierarchy, bad orientation, inaccessible controls, false state, or safety regression.
5. If accepted, update `DESIGN_SYSTEM.md` with the unified cockpit shelf rule; update `PROJECT_STATE.md` + this file with exact green run/head; update PR #2; mark ready; merge to `main`.
6. Immediately create a **fresh Phase 10 branch from merged main**. Do not merge/rebase the old divergent speed branch wholesale.

## Phase 10 — measured-speed instrumentation
Core pieces already on accepted lineage:
- `SpeedTelemetrySample`: source/provenance, monotonic arrival time, optional source timestamp/accuracy; BLE/GPS absolute, motionAssist estimate only.
- `TelemetryBenchmarkCollector`: effective Hz, interval min/mean/max/jitter, duplicate values, empirical speed step, source latency.
- `SpeedDisplayInterpolator`: authoritative samples only, out-of-order rejection, interruption continuity, no overshoot, display frames never telemetry.
- `RollingNumberModel`: fixed slots, global up/down direction, per-slot wrap steps, leading visibility, carry/borrow tests.

Old `feature/speed-instrumentation` is reference-only. Selectively reimplement/transplant:
- narrow `VehicleStore.speedTelemetryUpdates()` accessor
- `SpeedInstrumentModel` concept/tests for confirmed fallback → raw measured → visual interpolation
- rolling-digit SwiftUI presentation, but do **not** blindly copy the old view; ensure direction follows the full rolling model so 9→10 / 19→20 / 20→19 are correct.

Important simulation truth: static `.riding` only seeds confirmed `VehicleState`; the raw speed stream intentionally does not replay cached speed. Raw BLE samples appear only after `simulateRide(...)`. Therefore Phase 10 must add an explicit deterministic QA telemetry-driving path and benchmark that simulation separately. Never treat Simulator cadence as the proven MAXSHOT production cadence. Production interpolation timing remains hardware-validation-gated until real notification frequency/latency/resolution are measured.

Keep high-frequency redraw local to the speed subtree (e.g. animation timeline), never publish interpolated frames back into `VehicleState`, ride history, stats, distance, or protocol diagnostics. Re-run Xcode 27 and inspect real landscape behavior after wiring.

## Continue after Phase 10
Continue autonomously through mode-responsive cockpit, ride persistence/app wiring, background Bluetooth/location, maps/navigation, history/stats, acceleration testing, BLE diagnostics and real MAXSHOT validation, cloud/accounts/leaderboard, Live Activities/widgets/App Intents, accessibility/performance/error hardening, end-to-end/release prep. One subsystem at a time, deeply finished before advancing.

## Hardware validation still outstanding
Real MAXSHOT advertisement identity, BLE services/characteristics, notification cadence/latency/resolution, packet framing/checksum, reads/writes/acks, DP101–103 semantics, and AccessorySetupKit descriptors. Keep **APP COMPLETE** separate from **HARDWARE VALIDATION REQUIRED**.
