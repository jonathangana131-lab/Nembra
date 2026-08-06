# CONTINUATION PROMPT

Continue the **existing Nembra production iOS project**. Do not create a new repo/app and do not resurrect rejected prototype/UI work.

## Repository / current milestone
- Repository: public `jonathangana131-lab/Nembra`.
- Stable `main`: `9da973a4929e5408a14d38c919c6dbd2fd1004a3` or newer.
- Active branch: `feature/ride-application`.
- Portrait Home, Phase 9 landscape Dashboard, and Phase 10 measured-speed instrumentation are accepted and merged.
- Current subsystem: **RideEngine application + durable local history wiring**.

Read `PROJECT_STATE.md` first, then `DECISIONS.md`, `PROTOCOL_NOTES.md`, `DESIGN_SYSTEM.md`, and relevant source/tests. Inspect current branch/actions before edits.

## Communication / recovery contract
- Show concise engineering progress every few meaningful operations or whenever a build, failure, screenshot, PR, checkpoint, or quality gate changes state.
- Never dump hidden chain-of-thought.
- Do not stop because one tool run, commit, screenshot, or fix completed. Continue the active vertical slice until accepted or genuinely blocked.
- Before risky/long chains keep valid work committed/pushed and keep this file + `PROJECT_STATE.md` current.
- If platform execution becomes impossible, commit/push valid work and state the exact unfinished action. Otherwise do not require the user to type `continue` as normal workflow.

## Product truth
- Product: Nembra; first vehicle: MAXSHOT V1S Pro.
- Ordinary production launch is hardware-gated through `UnverifiedScooterService`; simulation is explicit QA only.
- Never invent BLE UUIDs/writes/acks, VESC tuning, phase/battery current, field weakening, regen current, wheel-diameter settings, telemetry, or scooter-safe routing.
- DP101/102/103 remain independent speed-limit slots until hardware capture proves user-facing mapping.
- Device Trip is never labeled Today.
- Exact GPS routes are private by default when route persistence arrives.

## Stable architecture — preserve it
- `ScooterService` / capability model separates transport from SwiftUI.
- one state-changing command at a time until real protocol proves concurrency safe.
- connection-generation invalidates writes spanning disconnect/reconnect.
- unavailable/live/retained vehicle data is explicit; disconnect never manufactures zero telemetry.
- raw speed evidence is independent from render-only interpolation.
- motion assist never masquerades as authoritative speed.
- `SpeedDisplayInterpolator` + `RollingNumberModel` are presentation only.
- `RideEngine` owns automatic ride state and preserves confirmed ride identity through disconnect.
- `RideCheckpointCoordinator` serializes engine mutation with a crash-safe two-slot journal.
- monotonic uptime is never persisted across process lifetime.
- `completedPendingCommit` prevents ride loss between detector completion and permanent history.
- `RideHistoryCommitCoordinator` commits history, exact-readback verifies, then clears recovery state.
- ODO/GPS/live-speed distance remain independent and reconciliation never averages sources merely to make a clean result.
- live distance integrates one authoritative raw speed source and never crosses oversized packet gaps.

## Current ride-application decision
Use **one shared `ScooterService` instance** for VehicleStore and ride processing. The simulated service supports multiple broadcast subscribers.

A dedicated serial ride runtime will merge:
- raw authoritative speed packets,
- connection changes,
- scooter ODO evidence,
- later quality-screened GPS/motion evidence.

State-only updates are not zero-speed measurements. For state/ODO events, include only a still-valid latest authoritative raw speed sample; otherwise speed is unknown. A disconnect is only a connection transition.

Core ride thresholds and checkpoint cadence intentionally have no MAXSHOT production defaults. Preserve that:
- unverified production automatic ride policy stays disabled/hardware-gated;
- explicit Simulator QA may inject documented QA-only values to exercise the full architecture;
- do not convert Simulator timing into MAXSHOT claims.

## Exact active work
1. Add a real durable local `RideHistoryStore` implementation, idempotent by session UUID and conflict/corruption safe, with core tests.
2. Add the serial ride application runtime around the **existing** `RideCheckpointCoordinator`; do not build a second detector/recovery architecture.
3. Refactor app bootstrap into shared dependencies so VehicleStore and ride runtime share one scooter service.
4. Recover journal state before accepting new observations. If startup has `completedPendingCommit`, commit/read-back/acknowledge it first.
5. Add explicit Simulator QA policy/script that drives the same runtime; never fake a SwiftUI ride state.
6. Expose a minimal trustworthy current-ride read model to Home/Dashboard only after runtime wiring works. Do not add placeholder Rides/Stats tabs.
7. Add core/app/UI tests for start, active ride, disconnect continuity, recovery/handoff, and false-start prevention.
8. Run the real GitHub `xcode-27` Mac gate on iPhone 12/iOS 27, inspect screenshots/interactions, fix, update memory, merge.
9. Immediately continue into the next master-directive subsystem after acceptance.

## Stable Phase 10 proof
Accepted Phase 10 implementation passed Xcode 27 run `31061900280` / job `92491409069`:
- NembraCore 157/157
- NembraAppTests 13/13
- NembraUITests 5/5
- real iPhone 12/iOS 27 Dashboard screenshots accepted.

Production MAXSHOT interpolation remains disabled until real hardware cadence/latency/resolution is measured. Simulator interpolation policy is QA-only.

## QA rules
- `.github/workflows/xcode27-simulator.yml` is the authoritative remote Mac gate when direct Mac tooling is unavailable.
- baseline: iPhone 12 / iOS 27.
- CI runs core/app/UI tests and preserves `.xcresult` + exported attachments.
- never accept a slice from compile or a good screenshot alone: build → run → interact → screenshot → critique → fix → edge-test/profile → commit/push → memory docs → merge.
- show real Simulator screenshots; do not use generated mockups in this work stream.

## Hardware validation still outstanding
MAXSHOT advertisement identity, BLE services/characteristics/properties, notification cadence/latency/resolution, packet framing/checksum, reads/writes/acks, DP101-103 semantics, AccessorySetupKit descriptors, and calibrated production ride/interpolation/checkpoint policies.
