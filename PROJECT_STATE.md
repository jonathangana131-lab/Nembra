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
- Current quality gate: latest-lineage Xcode 27 app/UI acceptance with real active-ride Home interaction + screenshot.

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

## Startup reliability finding / fix
A real integration bug was found by the runtime tests: `RideApplicationRuntime.start()` originally spawned subscriber tasks and returned before the scooter-service raw-speed continuation was guaranteed registered. First post-launch movement packets could therefore be lost.

Fix commit: `cec751e145efc30e2de076c999c4e36a065f189f`.
- state and raw-speed `AsyncStream`s are now created/registered before `start()` returns;
- consumer tasks start only after both subscriptions exist;
- the first movement packets cannot fall into a startup race window.

Authoritative Mac proof for that fix:
- run `31066478164`, job `92505136306`: **PASS**.
- project syntax/reference validation: PASS.
- NembraCore: **167/167 PASS**.
- app compile/AppTests/existing UI tests/Simulator capture/artifact upload: PASS.

## Xcode project wiring
The one-shot GitHub helper is complete and removed itself.
- initial wiring bot commit: `5c673858ce85351bc755f70befd39d2e534ec497`.
- `RideStore.swift`, `RideHistoryPersistence.swift`, and `RideApplicationRuntime.swift` are wired into `Nembra.xcodeproj` and the app Sources phase.
- the first generated PBX lists had three missing commas; the malformed project was caught by the Xcode 27 `plutil` gate before Swift compiled.
- an isolated one-shot repair fixed only those delimiters; project syntax/reference validation is now proven green on the hosted Mac.

## Current Home / app acceptance changes
The branch now also includes:
- two AppBootstrap truth tests:
  - ordinary unverified launch keeps `rideStore.isEnabled == false`;
  - explicit Simulator QA enables the real ride runtime.
- Home consumes `RideStore` only when its domain presentation is visible.
- `home.currentRide` appears only for active/reconnecting/finishing/saving/blocked states.
- visible Home ride copy is evidence-limited: no fake distance, duration, route, or “Today” mileage.
- active state: `Ride active` / `Tracking automatically`.
- reconnecting state: `Ride continuing` / `Reconnecting to scooter`.
- finishing state: `Checking ride end` / `Waiting for confirmed stop`.
- saving state: `Saving ride` / `Securing ride history`.
- blocked state: `Ride tracking paused` / `Ride data is preserved`.
- existing connected-stopped UI test asserts no current-ride surface while idle.
- new XCUITest launches explicit QA with `NEMBRA_RIDE_QA_SCRIPT=active`, waits for `home.currentRide` after real RideEngine confirmation, verifies the accessibility label, and retains `Home Active Ride` screenshot.

Current Home bot commit: `7e9a10a9465b70444d62443f01ddc9e441e7daed`.
This Project State commit is the connector-authored trigger for the full latest-lineage Xcode 27 acceptance run.

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
1. Run the latest-lineage Xcode 27 gate containing the new AppBootstrap tests, Home current-ride UI and active-ride XCUITest.
2. Fix exact Swift 6/AppTest/XCUITest failures rather than disabling or weakening coverage.
3. Download the `.xcresult`/attachment artifact and inspect the real iPhone 12/iOS 27 `Home Active Ride` screenshot; adjust layout/copy only if real evidence calls for it.
4. Add a recovery/reconnect Home interaction state if needed after active screenshot acceptance; do not add placeholder ride-history navigation.
5. Update `DECISIONS.md`, `PROJECT_STATE.md`, `CONTINUATION_PROMPT.md`, open PR, and merge only after latest-lineage Mac build/tests + real Simulator review are accepted.
6. Continue immediately to the next master-directive subsystem after merge.

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
- `NembraApp/Features/Home/HomeView.swift`
- `NembraUITests/NembraUITests.swift`
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
