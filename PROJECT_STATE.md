# PROJECT STATE

Updated: 2026-08-06

## Product
- Product: **Nembra**.
- First supported vehicle: **MAXSHOT V1S Pro**.
- Repository: public `jonathangana131-lab/Nembra`.
- Product stance: premium native iOS 27 scooter platform; MAXSHOT first; capability-based architecture; truthful telemetry; pessimistic/confirmed commands; simulation and real hardware share production UI through the same service boundary.

## Current branch / milestone
- Stable branch: `main`.
- Stable Phase 10 merge: `9da973a4929e5408a14d38c919c6dbd2fd1004a3`.
- Active branch: `feature/dashboard-mode-personality`.
- Active milestone: **Phase 11 — confirmed-mode Dashboard personality**.
- PR: **#4 — Add confirmed-mode Dashboard personality**.
- Phase 11 code/runtime/visual acceptance is complete on implementation head `a622d22b91106917c3a2fc9d1b3abc81a5785ab6`.
- Remaining Phase 11 work: commit project-memory/design decision updates, let the newest docs-head `xcode-27` gate pass, mark PR #4 ready, merge, then branch from the updated `main`.

## Stable UI milestones
### Portrait Home
- Accepted and merged.
- Status-first vehicle console with honest unknown/retained/live presentation.
- Moving-state Lock safety, typed connection failures, low-battery priority, and confirmed controls are preserved.

### Phase 9 — dedicated landscape Dashboard
- Accepted and merged.
- Dedicated cockpit rather than portrait Home rotated.
- Dominant speed, battery, Scooter Trip, ride mode, connection/model identity.
- Stopped-only mode/Light/Lock controls; state-changing controls disappear while moving.
- No fake throttle/current/power gauge.

### Phase 10 — measured-speed instrumentation
- Accepted and merged at `9da973a4929e5408a14d38c919c6dbd2fd1004a3`.
- Raw authoritative speed evidence is separate from `VehicleState` and separate from display frames.
- `SpeedInstrumentModel` wraps render-only `SpeedDisplayInterpolator` and rejects stale/motion-assist samples.
- `RollingSpeedValueView` reserves fixed digit geometry; rolling is presentation only.
- `DashboardSpeedInstrumentView` is the only 60 Hz-capable subtree and pauses its animation timeline outside active interpolation.
- Production interpolation remains disabled until real MAXSHOT cadence/latency/resolution is measured; explicit Simulator QA injects a presentation-only policy.
- VoiceOver announces authoritative/confirmed speed, never an interpolation midpoint.
- Simulator packet timestamps use real process monotonic arrival time; simulated ride duration never manufactures packet cadence.

## Phase 11 accepted implementation
`DashboardModePersonality` is a pure presentation model derived only from the scooter-confirmed `RideMode?`.

Accepted behavior:
- Walk, Eco, Drive, and Sport subtly change cockpit visual energy through center ambient intensity, speed-instrument scale, mode emphasis/marker, and status emphasis.
- Unknown mode has its own quiet neutral presentation.
- The treatment is restrained and monochrome; no RGB theme, fake carbon, fake performance gauge, or Sport warning-red decoration.
- Confirmed mode is the source of truth. A tap does not permanently change the personality until the service confirms the new ride mode.
- The accepted Phase 10 speed truth path is unchanged.
- Side rails, speed geometry, stopped controls, moving-state safety, ride state, telemetry, distance, history, and persistence semantics are unchanged.
- Phase 11 does **not** create or imply a MAXSHOT DP101/DP102/DP103 mapping.
- Phase 11 does **not** claim changes in measured power, torque, throttle, acceleration, range, efficiency, or speed limit.
- Reduce Motion disables the spatial/snappy mode-personality animation while preserving the confirmed state change.

## Phase 11 Xcode / Simulator acceptance
Implementation head: `a622d22b91106917c3a2fc9d1b3abc81a5785ab6`.

GitHub Actions:
- workflow: **Xcode 27 Simulator QA**
- run: `31063560164`
- job: `92496459298`
- conclusion: **success**
- runner label: `xcode-27`
- project validation: passed
- core package validation: passed
- Xcode build/test/Simulator capture stage: passed
- artifact upload: passed

Test evidence from the exported `.xcresult` / log artifact:
- `NembraAppTests`: **14/14**, 0 failures.
- `NembraUITests`: **5/5**, 0 failures.
- Phase 11 UI test drives the real stopped Dashboard through confirmed **Sport → Walk → Eco → Drive → Sport** transitions.
- It preserves real XCTest attachments for each confirmed personality.
- The moving Dashboard test preserves a real riding landscape attachment and verifies state-changing controls remain unavailable while moving.

Kept iPhone 12/iOS 27 Dashboard attachments inspected:
- `Dashboard Walk Landscape`
- `Dashboard Eco Landscape`
- `Dashboard Drive Landscape`
- `Dashboard Sport Landscape`
- `Dashboard Sport Confirmed Landscape`
- `Dashboard Riding Landscape`

Visual acceptance:
- Walk is visibly calmer without looking disabled.
- Eco is slightly stronger than Walk while remaining quiet.
- Drive reads as the neutral/balanced baseline.
- Sport is more energetic without becoming gamer UI or warning UI.
- Mode differences remain subtle enough that speed/battery/connection hierarchy is unchanged.
- Fixed center speed geometry remains stable and unclipped.
- Side rails remain fixed; stopped controls remain separated from the speed instrument.
- Moving Drive retains the accepted moving-state safety hierarchy and subdued stopped-only hint.
- No safe-area clipping, landscape crowding, or excessive glow was observed in the accepted captures.

## Current quality gate
1. Phase 11 implementation/runtime/visual acceptance is complete on `a622d22b...`.
2. Commit this acceptance into `PROJECT_STATE.md`, `CONTINUATION_PROMPT.md`, `DECISIONS.md`, and `DESIGN_SYSTEM.md`.
3. The documentation commit intentionally creates one newest-head `xcode-27` run.
4. Do not reopen Phase 11 design unless that exact final lineage gate exposes a regression.
5. When the newest docs-head run is green, mark PR #4 ready and merge it using the exact expected head SHA.
6. Confirm the merge on `main`.
7. Create the next feature branch from updated `main` and continue the **ride application + persistence vertical slice** using the existing ride architecture rather than creating replacements.

## Next slice after Phase 11 merge
The next substantial slice should turn the already-built ride domain into real application behavior.

Inspect before editing:
- `RideEngine`
- `RideCheckpointCoordinator`
- two-slot ride recovery journal
- `completedPendingCommit`
- `RideHistoryCommitCoordinator`
- distance reconciliation / source coverage
- `LiveDistanceSegmentAccumulator`
- `AppBootstrap`
- `VehicleStore`
- current persistence adapters / app lifecycle wiring

Likely acceptance target:
- automatic ride engine is owned outside SwiftUI views.
- app lifecycle feeds confirmed vehicle evidence into the existing ride engine.
- crash-safe checkpoints are actually driven by app behavior.
- completed rides hand off idempotently into the concrete app history store.
- relaunch/recovery resumes the same durable ride identity where legitimate.
- simulation exercises the exact production application path.
- UI consumes real ride application state without inventing data.
- build/run/interact/relaunch/screenshot/test on iPhone 12/iOS 27 before accepting.

Do not create a second ride engine, alternate checkpoint journal, or duplicate history pipeline.

## Important truth boundaries
- Interpolated/display speed is never telemetry or ride evidence.
- Motion-assisted estimates never masquerade as authoritative scooter/GPS speed.
- Simulator ride duration is not packet-arrival cadence.
- Disconnect never fabricates a zero measurement.
- Device Trip is not labeled Today.
- Dashboard mode personality is presentation only and follows confirmed ride mode.
- DP101/DP102/DP103 remain unmapped to Walk/Eco/Drive/Sport until hardware evidence proves semantics.
- No VESC-style tuning, phase current, field weakening, regen current, or invented telemetry.
- Real BLE writes remain blocked until command meaning/transport/acknowledgement is verified sufficiently.

## Core systems already implemented
- capability-based `VehicleProfile` / `ScooterService` boundary.
- `SimulatedScooterService` + hardware-gated `UnverifiedScooterService`.
- typed connection failures and live/retained/unavailable data availability.
- serialized pending/confirmed commands + connection-generation invalidation.
- raw speed evidence + telemetry benchmark collector.
- render-only `SpeedDisplayInterpolator` + fixed-slot `RollingNumberModel`.
- confirmed-mode visual Dashboard personality.
- automatic `RideEngine` with disconnect continuity.
- crash-safe two-slot ride journal + `completedPendingCommit` handoff.
- idempotent completed-history commit contract.
- independent ODO/GPS/live-distance reconciliation.
- process-local authoritative live-distance segment integration.

## Hardware validation still required
- real MAXSHOT advertisement identity.
- BLE services/characteristics/properties.
- notification cadence and speed latency/jitter/resolution.
- read/write/ack behavior and packet framing/checksum.
- MAXSHOT-specific DP101/DP102/DP103 semantics.
- AccessorySetupKit descriptors based on observed identity.

## Real Xcode / Simulator proof
GitHub-hosted `xcode-27` is the authoritative remote Mac gate when direct interactive Xcode tooling is unavailable.
- iPhone 12 / iOS 27 remains the explicit visual baseline.
- CI preserves `.xcresult`, logs, Simulator screenshots, and XCTest attachments on success/failure.
- Hosted Simulator proof is real iOS runtime evidence but is not physical MAXSHOT BLE validation or physical iPhone 12 performance profiling.

## Acceptance rule
A vertical slice is accepted only after latest-lineage Mac build/test success, representative real Simulator interaction/screenshots, visual self-critique, relevant edge/failure/moving-state coverage, performance audit when relevant, tests, commit/push, and current project memory. A compile or one attractive screenshot is not completion.
