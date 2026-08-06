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
- Current quality gate: first full Xcode 27 compile/test of the wired app runtime.

## Stable accepted UI / telemetry
- Portrait Home is accepted and merged: status-first, no giant decorative scooter hero.
- Dedicated landscape Dashboard is accepted and merged.
- Phase 10 raw measured-speed → render-only interpolation → fixed-slot rolling digits is accepted and merged.
- Production MAXSHOT interpolation timing remains disabled until real hardware cadence/latency/resolution is measured; Simulator QA timing is test-only.
- Phase 10 accepted Xcode 27 proof: run `31061900280`, job `92491409069`, NembraCore 157/157, NembraAppTests 13/13, NembraUITests 5/5, real iPhone 12/iOS 27 landscape screenshots accepted.

## Ride-application implementation checkpoint
The active branch now contains and has pushed:
- `AtomicRideHistoryStore`: per-session atomic JSON history, exact read-back, idempotent equivalent inserts, UUID conflict protection, corrupt-record preservation.
- core tests for history insertion/read-back/idempotency/conflict/corruption/missing record.
- `RideApplicationRuntime`: one serial actor merging raw authoritative speed + connection/ODO state into the existing `RideCheckpointCoordinator` and `RideHistoryCommitCoordinator`.
- runtime tests for: cached state speed cannot start a ride, raw speed starts/journals a ride, disconnect/reconnect preserves UUID, completed ride hands off to permanent history before journal clear, startup flushes `completedPendingCommit` before new observations.
- `RideStore`: observable app read model over the runtime; no separate detector or fake UI ride state.
- `NembraRuntime`: one shared `ScooterService` instance for `VehicleStore` and ride processing; ride recovery starts before vehicle auto-connect or QA movement.
- explicit Simulator QA-only ride policy/cadence and optional raw-packet QA script. Ordinary unverified production ride tracking remains disabled/hardware-calibration gated.

## Xcode project wiring
The one-shot GitHub helper is complete and removed itself.
- bot commit: `5c673858ce85351bc755f70befd39d2e534ec497`
- `RideStore.swift`, `RideHistoryPersistence.swift`, and `RideApplicationRuntime.swift` are now wired into `Nembra.xcodeproj` and the app Sources phase.
- Ubuntu helper reference validation passed after fixing the helper's false file-reference check.
- the next connector-authored checkpoint triggers the authoritative Xcode 27 Mac gate on this fully wired target.

## Active architecture truth
Do not create another ride detector, recovery journal, history handoff, or distance engine. Existing core contracts remain authoritative:
- `RideEngine` owns automatic candidate/active/disconnect/ending state.
- `RideCheckpointCoordinator` serializes engine mutation with the two-slot durable journal.
- `completedPendingCommit` closes the crash window between ride end and permanent history.
- `RideHistoryCommitCoordinator` commits permanent history first, exact-readback verifies it, then clears recovery state.
- ODO/GPS/live-speed distance evidence remain independent; reconciliation never averages sources merely to make a clean number.

Application wiring uses **one shared `ScooterService` instance**. State-only updates are not zero-speed measurements. The runtime may carry only an authoritative cached raw speed sample subject to the RideEngine freshness policy; otherwise speed is unknown. Disconnect is a connection transition, never a speed reading.

## Policy truth
Core ride-detection thresholds and checkpoint cadence intentionally have no MAXSHOT production defaults.
- ordinary unverified hardware does not inherit Simulator thresholds;
- explicit Simulator QA injects documented QA-only detection/cadence values only to exercise the production architecture;
- real MAXSHOT production detection/cadence remains hardware-calibration gated until field traces justify it.

## Current exact work sequence
1. Let the wired Xcode 27 gate compile/run all core + app + UI tests; fix exact Swift 6/Xcode 27 failures, never skip them.
2. Add app bootstrap tests proving production RideStore disabled vs explicit Simulator RideStore enabled.
3. Once runtime is green, add minimal truthful current-ride Home consumption only for active/reconnecting/finishing/saving/blocked states; no placeholder Rides/Stats tabs.
4. Add a real XCUITest that launches Simulator QA with `NEMBRA_RIDE_QA_SCRIPT=active`, waits for `home.currentRide`, and captures the iPhone 12 screenshot.
5. Inspect/fix the actual screenshot and interaction state.
6. Add/verify disconnect continuity and persistence/handoff coverage at the appropriate core/app levels.
7. Update decisions/memory, open PR, merge only after latest-lineage Mac build/tests + real Simulator review are accepted.
8. Continue immediately to the next master-directive subsystem.

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
- durable local completed-history store + exact history handoff verification.
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
- `NembraApp/App/RideStore.swift`
- `Packages/NembraCore/Sources/NembraCore/RideApplicationRuntime.swift`
- `Packages/NembraCore/Sources/NembraCore/RideHistoryPersistence.swift`
- `Packages/NembraCore/Sources/NembraCore/RideEngine.swift`
- `Packages/NembraCore/Sources/NembraCore/RideCheckpointPersistence.swift`
- `Packages/NembraCore/Sources/NembraCore/RideCheckpointCoordinator.swift`
- `Packages/NembraCore/Sources/NembraCore/RideHistoryCommit.swift`
- `Packages/NembraCore/Sources/NembraCore/RideDistanceReconciliation.swift`
- `Packages/NembraCore/Sources/NembraCore/LiveDistanceIntegration.swift`

## Acceptance rule
One subsystem at a time: research → implement → build → run → interact → screenshot → critique → fix → edge-test/profile when relevant → commit/push → memory docs → merge → immediately continue to the next required slice.
