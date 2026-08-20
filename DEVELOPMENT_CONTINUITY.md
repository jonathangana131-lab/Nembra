# Nembra 1.0 unified development continuity

Status: active canonical recovery authority. Update this file after every meaningful pushed checkpoint and before pausing, handing off, merging, or ending a development session.

## Resume protocol

Before changing code in a resumed task:

1. Read this file, `AGENTS.md`, `docs/NEMBRA_V2_PRODUCTION_FOUNDATION.md`, `docs/design-reference/horizon-v4-final/NEMBRA_HORIZON_V4_PRODUCTION_HANDOFF.md`, `docs/design-reference/nembra-1.0-gold-glass/NEMBRA_SELECTED_UI_HANDOFF.md`, `docs/CAPTURE_BLUETOOTH_CONTINUITY.md`, and `docs/ES80_PROTOCOL_MAP.md` completely.
2. Use the isolated unified worktree and branch below. Never continue product development in the original Capture checkout or either predecessor UI worktree.
3. Run `git status --short --branch`, `git log -5 --oneline --decorate`, `git fetch origin`, and compare local `HEAD` with the remote unified branch.
4. Inspect PRs #3675, #3676, and #3677 plus exact-head Actions. Ancestor, queued, skipped, admission-only, superseded, or cancelled results do not transfer to a newer SHA.
5. Continue the exact next action below. Do not restart planning, revive rejected V2/V3/V4 cockpit pixels, or duplicate work already preserved in a predecessor checkpoint.

This repository document is the recovery authority. Chat summaries are supplementary.

## Authoritative repository state

- Repository: `jonathangana131-lab/Nembra`
- Unified release branch: `release/nembra-1-0-unified`
- Unified isolated worktree: local directory `Nembra-unified-1-0`
- Latest remotely verified unified branch checkpoint before this continuity update: `cb00ee46a0fe3ecc53b7143fb61939615102919b`
- Source integration branch: `product/capture-1-0-main-20260818`
- Source integration PR: [#3675](https://github.com/jonathangana131-lab/Nembra/pull/3675), draft, base `main`
- Portrait predecessor PR: [#3677](https://github.com/jonathangana131-lab/Nembra/pull/3677), branch `agent/portrait-home-1-0-polish`, remote tip `0a418aef716fb9053cc9d67064fd56bd87f27677`
- Cockpit predecessor PR: [#3676](https://github.com/jonathangana131-lab/Nembra/pull/3676), branch `agent/cockpit-1-0-redesign`, remote tip `75edf0fcb231e28b3d9fbd7b7acc7592bdac1a48`
- Physical Capture status: **NO-GO**. Public CI, Simulator, source tests, signed-build tooling, and historical artifacts do not authorize a scooter session.

A commit cannot embed its own resulting SHA. The SHA above names the last remotely verified predecessor/base checkpoint audited by this file; `git ls-remote origin refs/heads/release/nembra-1-0-unified` is authoritative for any later continuity-only commit.

## Integrated provenance at the unified base

The unified branch begins at Capture continuity checkpoint `cb00ee46a…`, which contains:

- Capture typed/guided implementation `5c32d29d5327e4c54d0f3a70b548da6eeeb537a5`;
- Capture integration continuity `3f0814ac70211f68b7af1a6913c78c91a810f663`;
- shared accessibility/idleness checkpoint `0b7e3b27de5e9b547911558ae8ed4cb852becb59`;
- the truth, persistence, orientation, simulation, and UI foundation inherited from PR #3675.

The two predecessor UI branches were created before `5c32d29d…`. Their branch snapshots appear to delete the newer Capture files. Integrate their owned commits onto the unified branch; never merge or replace the unified tree with either older snapshot.

## Workstream ownership matrix

The durable matrix is `docs/coordination/UNIFIED_WORKSTREAM_OWNERSHIP.md`.

1. **Capture/BLE truth** owns `Packages/NembraBluetoothCapture/`, the standalone Capture entry/runtime, field scripts, Capture tests, and Capture/protocol ledgers. It may publish typed verified decoder contracts but never presentation guesses.
2. **Portrait** owns Home, Rides, Vehicle, Settings, portrait design tokens, and portrait-only secondary views. It consumes only stable shared truth contracts.
3. **Cockpit** owns Dashboard/Drive and later Navigation/Explore presentation, high-frequency instrument rendering, cockpit accessibility, and cockpit performance evidence.
4. **Unified parent** is the only authority for shared bootstrap/root wiring, shared app/unit/UI test files, persistence contracts, project/workflow integration, conflict resolution, canonical continuity, PR synchronization, and final acceptance.

No two writers may edit the same shared file concurrently. Lane commits return to the unified parent for review and integration.

## Current focused aspects and production acceptance gates

### A. Capture + ES80 Bluetooth truth

Deliver the smallest reliable one-time companion that guides one stationary session, preserves lossless evidence, exports/imports a versioned private bundle plus human summary, and produces a confidence-rated protocol map. Only `verified` mappings may enter production decoders. Unknown writes, DP queries, controls, unbind/reset, and firmware/OTA remain forbidden.

Current gate: close the independently signed, short-lived, single-use `ES80-AUTHENTICATED-STATIONARY-v1` authorization and exact retained-IPA installer chain; then wire typed real `dpsUpdate` evidence into private durable custody and a cross-verified guided bundle. Physical execution still requires the intended account, private Tuya inputs, intended iPhone 12/iOS 27, intended stationary charger-disconnected scooter, and explicit current-attempt authority.

### B. Portrait Home and menus

Finish Home before widening. Preserve truthful battery/range, durable Today, confirmed controls, automatic-recording readiness, recovery states, and narrow render invalidation. The visual authority is the selected portrait source plus gold handoff; the temporary 500×500 grey/red ES80 raster is not production-cleared.

Current gate: integrate predecessor checkpoint `0a418aef…`, run exact-head Xcode 27/iPhone 12 audits and screenshots for connected, retained, low, error, ride, and Accessibility XXXL states, then perform a same-state side-by-side design QA loop. No Home visual acceptance exists until the battery, typography, approved scooter asset, zero copy occlusion, grounding/light, native glass, accessibility, first-fold/tab clearance, and runtime performance all pass.

### C. Landscape Cockpit / Drive / Navigation / Explore

Horizon V4 retains requirements only and is visually rejected. The selected Energy Chamber family supplies material/composition direction, not pixel authority. Drive must establish one-value battery, enormous rolling speed, truthful current/peak propulsion, durable facts, recording truth, exact-scene orientation, accessibility, and an idle-free high-frequency render island before Navigation or Explore widens.

Current gate: integrate predecessor checkpoint `75edf0fc…`, run exact-head Xcode 27/iPhone 12 landscape functional, accessibility, screenshot, and Release clock/Hitch Time Ratio evidence, compare the same-state runtime with the refined internal study, and iterate remaining P0/P1/P2 visual differences. Physical speed/power/odometer/range remain unavailable until verified upstream contracts exist.

## Completed work and exact paths

### Capture foundation already on the unified base

- `Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaStructuredApplicationEvidence.swift`
- `Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ES80GuidedCapturePlan.swift`
- focused tests beside those sources
- `docs/CAPTURE_BLUETOOTH_CONTINUITY.md`
- `docs/ES80_PROTOCOL_MAP.md`
- `.gitignore` private-evidence protections

Checkpoint `5c32d29d…` passed 33/33 focused Swift tests across the typed-event and guided-plan suites, parser/diff/secret checks, and a final adversarial review. These are software contracts only; every production ES80 semantic remains unknown.

### Predecessor checkpoints awaiting deliberate integration

- Portrait implementation: `72ba15f1844ef489fca64cecf5f9b207a2bef533`; continuity tip `0a418aef…`. Owned paths include `HomeView.swift`, `VehicleHeroView.swift`, narrow `NembraVisuals.swift`/`AppRootView.swift` changes, focused app/UI/source tests, and portrait authority/continuity docs.
- Cockpit implementation: `85dc4b70b7981502bd909dd6d7c628f7e8e4c700`; continuity tip `75edf0fc…`. Owned paths include `DashboardView.swift`, `RollingSpeedValueView.swift`, `SpeedInstrumentModel.swift`, narrow `AppBootstrap.swift`, focused app/UI tests, and cockpit authority/capability/continuity docs.

Neither predecessor checkpoint is integrated into the unified branch yet. Their local/remote refs are clean and equal at the SHAs above.

## Work in progress and recovery

- Unified worktree: clean at `cb00ee46…` before this documentation checkpoint; no unified implementation is local-only.
- Original Capture worktree: one bounded installer/evidence slice is local-only while being finalized on `product/capture-1-0-main-20260818`:
  - `scripts/field/install_one_time_capture.command`
  - `Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerRetainedIPAAdmissionSourceTests.swift`
  - `scripts/ci/es80_signed_field_artifact_evidence.py`
  The Capture owner must run focused checks, update both continuity ledgers, commit explicit paths, push, and return a remote SHA before unified integration. Do not delete or overwrite this worktree.
- Portrait and Cockpit predecessor worktrees are clean and remote-recoverable. Their review agents are read-only.

## Exact CI and evidence snapshot

- Capture `5c32d29d…`: TODAY Final GO `32321764453` green; TODAY Field Candidate Preflight `32321764641` green; Field Handoff Provenance `32321764666` green. V16 `32321764574`, visual `32321764568`, and product Xcode `32321764484` were cancelled by later branch movement after substantive early steps; they are not failures and not acceptance.
- Latest fully completed Capture baseline `3f0814ac…`: V16 `32315926223` green with artifact `9388386960`; visual `32315926201` green with artifact `9388184207`; field/TODAY lanes green. This remains software/Simulator evidence only.
- Portrait exact-head acceptance is pending. Run `32318006928` validated ancestor `bec498463…` and failed four portrait accessibility issues plus one cockpit issue; later `72ba15f18…` claims narrow fixes but has no authoritative terminal exact-tip run yet.
- Cockpit exact-head acceptance is pending. `85dc4b70…` has parse, 49/49 focused package tests, strict local compile/build-for-testing, and scope/secret checks only. It has no exact-tip Xcode 27 screenshot/accessibility/Release hitch evidence.

## Known blockers

### Code / CI

- Integrate both predecessor lanes commit-by-commit without deleting the newer Capture foundation or weakening shared tests.
- Close current Capture field authorization, exact retained-IPA admission, typed private journal, bundle verifier, summary, and guided coordinator.
- Obtain exact unified-head Xcode 27 functional, UI, accessibility, screenshot, and Release performance evidence after each meaningful integration checkpoint.
- Production adaptive range has no accepted physical runtime producer; numeric range remains unavailable.
- Production automatic BLE ride capture, Navigation, and Explore lack verified hardware/provider/runtime wiring and must remain honest/degraded.

### User / physical Capture

- Real Capture needs private Tuya provisioning/signing inputs, the intended SmartLife account and scooter membership, the intended iPhone 12/iOS 27, a stationary charger-disconnected scooter, and an explicitly authorized current attempt. No physical run is authorized yet.

### User / asset rights

- Final Home needs a user-owned/commissioned high-resolution side photograph of the actual ES80 configuration or written AOVOPRO media permission for a specific source with complete provenance. Do not AI-upscale or invent hardware detail.

### External/provider

- Explore needs a selected, licensed, versioned road graph and matcher policy. MapKit-rendered roads cannot become coverage evidence.
- GitHub `xcode-27` capacity may queue. Queue delay is not a code failure.

## Exact next executable action

1. Commit and push this unified coordination checkpoint on `release/nembra-1-0-unified`; verify the remote ref.
2. Review the returned Portrait and Cockpit audit reports, then cherry-pick their owned commits in chronological order while keeping this canonical continuity file and the newer Capture files. Resolve shared `NembraAppTests.swift`, `NembraUITests.swift`, `AppRootView.swift`, `NembraVisuals.swift`, and UI-contract docs semantically.
3. When the Capture owner returns a pushed SHA, inspect and cherry-pick that atomic installer/evidence checkpoint.
4. Run Swift parsers on every changed Swift file, focused Capture/Core suites, `git diff --check`, secret/private-artifact scan, and diagnostic strict build-for-testing where practical. Commit and push the coherent unified baseline.
5. Trigger the exact unified-head Xcode 27 workflow. Inspect the actual xcresults, screenshots, accessibility issues, and Release metrics; record run IDs/artifacts and update this file before the next code batch.
6. Reassign three non-overlapping implementation milestones from that evidence: Capture authorization/journal, Home exact visual/accessibility closure, and Drive exact visual/performance closure. Navigation, Explore, and additional portrait tabs widen only after their vertical-slice gates pass.

## Rejected designs and approaches

- Horizon V2 Orbit/Vector/Apex and all V3/V4 cockpit visual execution are rejected. Do not resurrect their geometry, typography, cards, arcs, maps, battery pill, range duplication, mega-pill, or control layout.
- The Energy Chamber family is a selected direction only. Its generated signed/fantasy power scales, ambiguous NOW marker, and generic typography are rejected.
- Cockpit battery shows exactly one centered value: percentage by default or accepted range after tap. SOC fill always means charge. Simultaneous/detached range is forbidden.
- Portrait Home retains its selected separate SOC/range hierarchy, but no range is fabricated.
- Do not make Capture a second consumer app, send unknown/destructive writes, call SDK application values raw FD50 bytes, or let receipt hashes masquerade as signatures.
- Do not glass-coat passive telemetry/content or build custom blur stacks. Native Liquid Glass belongs to functional chrome.
- Do not fabricate BLE facts, power, speed, odometer, route progress, Today totals, or road coverage. Simulator fixtures remain visibly disclosed and never become physical truth.
- Do not use local Xcode 26 as release authority, force-push predecessor branches, squash away required provenance, or merge a failing checkpoint.

## Unverified assumptions and evidence still required

- Portrait and Cockpit local strict builds/tests are not substitutes for exact unified-head Xcode 27 behavior.
- The predecessor implementations may conflict in shared tests/root wiring; integration correctness is unproven until the combined build/test/runtime gate passes.
- The selected Home and Energy Chamber references are visual targets/directions only; same-state runtime comparisons have not passed.
- The temporary ES80 raster cannot close Home asset fidelity or rights.
- No current GitHub-safe physical packet fixture proves a production ES80 semantic. Every field in `docs/ES80_PROTOCOL_MAP.md` remains unknown except transport topology facts.
- Automatic capture remains public-API best effort; force-quit, first-unlock, restoration, real scooter reconnect, and background location still need physical-device evidence.
- Explore has no selected licensed road dataset or scalable accepted matcher/overlay implementation.
