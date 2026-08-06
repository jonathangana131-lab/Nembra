# PROJECT STATE

Updated: 2026-08-06

## Product
- Product: **Nembra**
- First vehicle: **MAXSHOT V1S Pro**
- Repository: public `jonathangana131-lab/Nembra`
- Product stance: native iOS 27 scooter platform; MAXSHOT first; truthful telemetry and command confirmation; multi-vehicle architecture only after MAXSHOT quality is established.

## Current branch / milestone
- Active branch: `feature/ride-application`
- Stable branch: `main`
- Stable Home merge: `254b95a8d62d7d143df937cc0d8aa73f45548266`
- Stable Dashboard Phase 9 merge: `51613a990eb058ee83741645d8c551082d4ef268`
- Stable Phase 10 measured-speed merge: `9da973a4929e5408a14d38c919c6dbd2fd1004a3`
- Active milestone: **RideEngine application + durable local history wiring**.

## Stable accepted UI / telemetry
- Portrait Home is accepted and merged: status-first, no giant decorative scooter hero.
- Dedicated landscape Dashboard is accepted and merged.
- Phase 10 raw measured-speed → render-only interpolation → fixed-slot rolling digits is accepted and merged.
- Production MAXSHOT interpolation timing remains disabled until real hardware cadence/latency/resolution is measured; Simulator QA timing is test-only.
- Phase 10 accepted Xcode 27 proof: run `31061900280`, job `92491409069`, NembraCore 157/157, NembraAppTests 13/13, NembraUITests 5/5, real iPhone 12/iOS 27 landscape screenshots accepted.

## Active ride-application architecture decision
Do not create another ride detector, recovery journal, history handoff, or distance engine. The existing core contracts are the source of truth:
- `RideEngine` owns automatic ride candidate/active/disconnect/ending state.
- `RideCheckpointCoordinator` serializes engine mutation with the two-slot durable journal and persists significant transitions immediately.
- `completedPendingCommit` closes the crash window between ride end and permanent history.
- `RideHistoryCommitCoordinator` commits permanent history first, read-back verifies exact evidence, then clears recovery state.
- ODO/GPS/live-speed distance evidence remain independent; reconciliation never averages sources merely to make a clean number.

Application wiring will use **one shared `ScooterService` instance** for `VehicleStore` and ride processing. The service supports multiple broadcast subscribers. A dedicated serial ride runtime will merge:
- raw authoritative speed packets,
- connection state,
- scooter ODO evidence,
- later quality-screened GPS/motion evidence.

State-only updates must not be treated as a zero-speed measurement. When a state/connection/ODO event needs an engine observation, the runtime may include only a still-valid latest authoritative sample; otherwise speed is unknown. Disconnect itself remains a connection transition, never a zero measurement.

## Policy truth for the active slice
Core ride detection thresholds and checkpoint cadence intentionally have no MAXSHOT production defaults.
- ordinary unverified hardware must not silently inherit Simulator thresholds;
- explicit Simulator QA may inject a documented QA-only detection/cadence policy to exercise the full production architecture;
- real MAXSHOT production detection/cadence stays hardware-calibration gated until field traces justify values.

## Persistence goal for this slice
- keep the existing crash-safe two-slot checkpoint journal;
- add a real durable local implementation of `RideHistoryStore`, idempotent by session UUID and conflict-safe;
- wire startup recovery before new ride observations;
- if startup finds `completedPendingCommit`, commit/read-back/acknowledge it before accepting new ride input;
- expose trustworthy current ride state to SwiftUI only after the domain/runtime path is live;
- do not add placeholder Rides/Stats navigation yet.

## Current exact work sequence
1. Finish reading existing ride/history/distance/service APIs and tests.
2. Implement the concrete durable history store and tests.
3. Implement the serial ride application runtime using the existing coordinator and the shared scooter service.
4. Refactor app bootstrap into shared app dependencies so VehicleStore and ride runtime use the same service.
5. Add explicit Simulator QA policy/script that drives the same production ride path; never fake UI ride state.
6. Add minimal current-ride UI consumption only after the runtime is working.
7. Run full core/app/UI tests on the GitHub `xcode-27` Mac, capture iPhone 12/iOS 27 states, inspect/fix, then merge.
8. Continue immediately into the next master-directive subsystem after acceptance.

## Important truth boundaries
- Interpolated/display speed is never telemetry or ride evidence.
- Motion-assisted estimates never masquerade as authoritative scooter/GPS speed.
- Simulator ride duration is not packet-arrival cadence.
- Disconnect never fabricates a zero measurement.
- Device Trip is not labeled Today.
- DP101/102/103 are not mapped to ride modes without hardware proof.
- No VESC-style tuning, phase current, field weakening, regen current, or invented telemetry.
- Real BLE writes remain blocked until command meaning/transport/acknowledgment is verified.
- Exact GPS routes remain private by default when route persistence is added.

## Core systems already implemented
- capability-based `VehicleProfile` / `ScooterService` boundary.
- `SimulatedScooterService` + hardware-gated `UnverifiedScooterService`.
- typed connection failures and live/retained/unavailable data availability.
- serialized pending/confirmed commands + connection-generation invalidation.
- raw speed evidence + telemetry benchmark collector.
- render-only `SpeedDisplayInterpolator` + fixed-slot `RollingNumberModel`.
- automatic `RideEngine` with disconnect continuity.
- crash-safe two-slot ride journal + `completedPendingCommit` handoff.
- idempotent completed-history commit contract.
- independent ODO/GPS/live-distance reconciliation.
- process-local authoritative live-distance segment integration.

## Hardware validation still required
- BLE advertisement identity.
- services/characteristics/properties.
- notification cadence, speed latency/jitter/resolution.
- read/write/ack behavior and packet framing/checksum.
- MAXSHOT-specific DP101/102/103 semantics.
- AccessorySetupKit descriptors from observed identity.
- calibrated production ride-detection/checkpoint/interpolation policies.

## Real Xcode / Simulator gate
GitHub-hosted `xcode-27` remains authoritative when direct Mac tooling is unavailable.
- baseline: iPhone 12 / iOS 27.
- CI runs core/app/UI tests and preserves `.xcresult` + exported attachments.
- do not accept a vertical slice from compile or screenshots alone.

## Key files
- `CONTINUATION_PROMPT.md`
- `DECISIONS.md`
- `DESIGN_SYSTEM.md`
- `PROTOCOL_NOTES.md`
- `NembraApp/App/AppBootstrap.swift`
- `NembraApp/App/NembraApp.swift`
- `NembraApp/App/VehicleStore.swift`
- `Packages/NembraCore/Sources/NembraCore/RideEngine.swift`
- `Packages/NembraCore/Sources/NembraCore/RideCheckpointPersistence.swift`
- `Packages/NembraCore/Sources/NembraCore/RideCheckpointCoordinator.swift`
- `Packages/NembraCore/Sources/NembraCore/RideHistoryCommit.swift`
- `Packages/NembraCore/Sources/NembraCore/RideDistanceReconciliation.swift`
- `Packages/NembraCore/Sources/NembraCore/LiveDistanceIntegration.swift`

## Acceptance rule
One subsystem at a time: research → implement → build → run → interact → screenshot → critique → fix → edge-test/profile when relevant → commit/push → memory docs → merge → immediately continue to the next required slice.
