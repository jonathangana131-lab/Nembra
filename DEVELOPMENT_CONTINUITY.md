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
- Latest unified implementation checkpoint audited before this continuity update: `68b4eaa7a58483aa9ec660d1393f2960c8413aad`
- Source integration branch: `product/capture-1-0-main-20260818`
- Source integration PR: [#3675](https://github.com/jonathangana131-lab/Nembra/pull/3675), draft, base `main`
- Portrait predecessor PR: [#3677](https://github.com/jonathangana131-lab/Nembra/pull/3677), branch `agent/portrait-home-1-0-polish`, remote tip `0a418aef716fb9053cc9d67064fd56bd87f27677`
- Cockpit predecessor PR: [#3676](https://github.com/jonathangana131-lab/Nembra/pull/3676), branch `agent/cockpit-1-0-redesign`, remote tip `75edf0fcb231e28b3d9fbd7b7acc7592bdac1a48`
- Physical Capture status: **NO-GO**. Public CI, Simulator, source tests, signed-build tooling, and historical artifacts do not authorize a scooter session.

A commit cannot embed its own resulting SHA. The SHA above names the last remotely verified implementation checkpoint audited by this file; `git ls-remote origin refs/heads/release/nembra-1-0-unified` is authoritative for this continuity-only commit and any later checkpoint.

## Integrated provenance at the unified base

The unified branch begins at Capture continuity checkpoint `cb00ee46a…`, which contains:

- Capture typed/guided implementation `5c32d29d5327e4c54d0f3a70b548da6eeeb537a5`;
- Capture integration continuity `3f0814ac70211f68b7af1a6913c78c91a810f663`;
- shared accessibility/idleness checkpoint `0b7e3b27de5e9b547911558ae8ed4cb852becb59`;
- the truth, persistence, orientation, simulation, and UI foundation inherited from PR #3675.

The two predecessor UI branches were created before `5c32d29d…`. Their branch snapshots appear to delete the newer Capture files. Integrate their owned commits onto the unified branch; never merge or replace the unified tree with either older snapshot.

Portrait predecessor tip `0a418aef716fb9053cc9d67064fd56bd87f27677` is integrated by merge checkpoint `d4d8f6c882dac1c2eda634bbdff9121c218fefbb`. Cockpit predecessor commits through tip `75edf0fcb231e28b3d9fbd7b7acc7592bdac1a48` are integrated in audited order, with shared tests/contracts semantically combined, through unified implementation checkpoint `1847627d7c84b62e4f6a9633886d0e3dd756ddfc`.

The stopped Capture predecessor's final remote handoff `2a0e11e2be85d961386a058e0da0cf6f0ddf8189` is integrated in original commit order. Unified commits `0f8504ef8…` and `f9a6cea22…` carry the current-procedure signer/verifier/installer foundation; `92e58645d…` preserves the previously accepted Final-GO custody boundary; `07b0cab29…` records the source handoff. The production trust anchor remains deliberately nil, the installer still stops before device work, and this software checkpoint does not authorize physical Capture.

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

Current gate: unified source checkpoint `4faf337d42b2a02cf3f849f8814dc3d5ea4929d9` closes the three exact-tip contrast seams without weakening the audits; exact unified-head Xcode 27/iPhone 12 runtime proof is still required. Then perform a same-state side-by-side design QA loop. No Home visual acceptance exists until the battery, typography, approved scooter asset, zero copy occlusion, grounding/light, native glass, accessibility, first-fold/tab clearance, and runtime performance all pass.

### C. Landscape Cockpit / Drive / Navigation / Explore

Horizon V4 retains requirements only and is visually rejected. The selected Energy Chamber family supplies material/composition direction, not pixel authority. Drive must establish one-value battery, enormous rolling speed, truthful current/peak propulsion, durable facts, recording truth, exact-scene orientation, accessibility, and an idle-free high-frequency render island before Navigation or Explore widens.

Current gate: unified checkpoint `68b4eaa7a58483aa9ec660d1393f2960c8413aad` hardens source-bound NOW geometry, explicit non-overlapping speed/power bands, large-text rail labels, and single terminal test cleanup. Run exact unified-head Xcode 27/iPhone 12 landscape functional, accessibility, screenshot, and Release clock/Hitch Time Ratio evidence, compare the same-state runtime with the refined internal study, and iterate remaining P0/P1/P2 visual differences. Physical speed/power/odometer/range remain unavailable until verified upstream contracts exist.

## Completed work and exact paths

### Capture foundation already on the unified base

- `Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaStructuredApplicationEvidence.swift`
- `Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ES80GuidedCapturePlan.swift`
- focused tests beside those sources
- `docs/CAPTURE_BLUETOOTH_CONTINUITY.md`
- `docs/ES80_PROTOCOL_MAP.md`
- `.gitignore` private-evidence protections

Checkpoint `5c32d29d…` passed 33/33 focused Swift tests across the typed-event and guided-plan suites, parser/diff/secret checks, and a final adversarial review. These are software contracts only; every production ES80 semantic remains unknown.

The final predecessor authorization slice is also integrated. Exact paths are `AuthenticatedStationaryCaptureFieldAuthorization.swift` and tests, `TuyaFieldInstallerRetainedIPAAdmissionSourceTests.swift`, `es80_field_authorization_envelope.py`, `es80_signed_field_artifact_evidence.py`, their Python tests, `install_one_time_capture.command`, and the accepted-custody workflow pin. The compact Swift/Python contract binds procedure, exact build/runtime/evidence subjects, current-attempt challenge, expiry, and one replay-consumption request. It deliberately supplies no production public-key trust root and no app capability adapter.

### Integrated Portrait checkpoint

- Portrait implementation `72ba15f1844ef489fca64cecf5f9b207a2bef533` and continuity tip `0a418aef716fb9053cc9d67064fd56bd87f27677` are integrated at unified merge `d4d8f6c882dac1c2eda634bbdff9121c218fefbb`.
- Exact integrated paths include `NembraApp/Features/Home/HomeView.swift`, `NembraApp/Features/Home/VehicleHeroView.swift`, narrow `NembraApp/DesignSystem/NembraVisuals.swift` and `NembraApp/App/AppRootView.swift` changes, focused app/UI/source tests, `docs/continuity/PORTRAIT_EXPERIENCE.md`, `docs/design/PORTRAIT_DESIGN_SYSTEM.md`, and the non-runtime reference/provenance record under `docs/design/references/portrait-home/`.
- The merge was parser-clean for every changed Swift file, passed `git diff --cached --check`, and passed a staged secret/private-path scan. The two focused local SwiftPM source suites were still compiling under known local Xcode 26/resource contention at commit time; they are not claimed as results here.

### Integrated Cockpit checkpoint

- Cockpit authority/continuity commits `8671b285061f62983a590f6a27cd0fed725cb8a1` and `71fe1c4cb2bf0c8ed3a1476eab75970ee7ab49b6`, implementation `85dc4b70b7981502bd909dd6d7c628f7e8e4c700`, and predecessor handoff `75edf0fcb231e28b3d9fbd7b7acc7592bdac1a48` are integrated in order.
- Exact owned implementation paths are `NembraApp/App/AppBootstrap.swift`, `NembraApp/Features/Dashboard/DashboardView.swift`, `RollingSpeedValueView.swift`, `SpeedInstrumentModel.swift`, app/UI tests, and the Cockpit capability/feature/experience ledgers.
- Shared `NembraAppTests.swift`, `NembraUITests.swift`, and `docs/coordination/UI_CONTRACTS.md` preserve both Portrait and Cockpit contracts. Byte-identical duplicate study rasters were omitted after SHA-256 equality was verified; canonical assets remain under `docs/design-reference/horizon-post-v4-studies/`.
- Unified follow-up `1847627d7c84b62e4f6a9633886d0e3dd756ddfc` gates positive simulation parsing tests to Simulator and adds an explicit physical-device fail-closed assertion.

The integrated Cockpit Swift files parse cleanly and the integration diff check passes. Its predecessor branch passed 49/49 focused Core tests and a diagnostic strict local build, but the unified exact head has no Xcode 27 runtime acceptance yet.

### Unified pre-CI corrections

- `4faf337d42b2a02cf3f849f8814dc3d5ea4929d9` replaces the audited decorative text dot with a hidden shape, gives the Vehicle Controls glyph an opaque high-contrast inner backing while retaining native prominent glass, keeps range primary truth opaque, and renders the graphite copy well after charged-region ribs.
- `68b4eaa7a58483aa9ec660d1393f2960c8413aad` rejects a caller-supplied accepted-power NOW fraction that contradicts accepted watts and its admitted scale while preserving truthful above-envelope saturation; it replaces fractional speed/power centers with deterministic non-overlapping vertical regions, scales sighted rail microcopy for large text, and removes duplicate AX-test termination.
- Both batches pass Swift parser and diff checks. Local package/build diagnostics were still running when this continuity checkpoint was written; their eventual result must be recorded rather than inferred. GitHub-hosted Xcode 27 remains the runtime/release authority.

## Work in progress and recovery

- All three predecessor worktrees are clean and their final branches are remote-recoverable. The unified branch contains every reviewed predecessor checkpoint plus the Portrait/Cockpit pre-CI corrections through `68b4eaa7a…`.
- No intentional implementation is stranded only in a predecessor worktree. The unified local worktree should be clean after this continuity-only commit.
- Local Xcode 26 package/build diagnostics may still be running; they are diagnostic only and can be safely restarted from the exact commands below. Do not mistake process state for repository state or release evidence.

## Exact CI and evidence snapshot

- Capture `5c32d29d…`: TODAY Final GO `32321764453` green; TODAY Field Candidate Preflight `32321764641` green; Field Handoff Provenance `32321764666` green. V16 `32321764574`, visual `32321764568`, and product Xcode `32321764484` were cancelled by later branch movement after substantive early steps; they are not failures and not acceptance.
- Latest fully completed Capture baseline `3f0814ac…`: V16 `32315926223` green with artifact `9388386960`; visual `32315926201` green with artifact `9388184207`; field/TODAY lanes green. This remains software/Simulator evidence only.
- Portrait predecessor exact-tip Xcode 27 run [`32322459434`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32322459434) at `0a418aef…` is terminal red with artifact `nembra-xcode27-simulator-1369-1` (ID `9390586092`, SHA-256 `f0bcf0a3b498ab34b7401e9befb23aece14106efeb502aea18655e69a0d85a31`). Build/Core validation passed; app tests passed 78/78; Accessibility XXXL Home passed; Ride UI passed 5/5. Remaining Portrait failures are connected Home contrast on `slider.horizontal.3`, low-battery contrast on decorative `·`, and retained contrast on `Unavailable`. A separate Cockpit animation-idle timeout is not Portrait closure.
- Cockpit exact-head acceptance is pending. `85dc4b70…` has parse, 49/49 focused package tests, strict local compile/build-for-testing, and scope/secret checks only. It has no exact-tip Xcode 27 screenshot/accessibility/Release hitch evidence.
- Capture final remote handoff `2a0e11e2…`: TODAY preflight run `32327106843`, Final GO `32327106882`, and Field Handoff Provenance `32327106916` are green software/custody contracts. Product run `32327106874` is admission-only (its Mac job skipped). V16 `32327106929` and standalone visual `32327106847` were still running when recorded; inspect their terminal states. None grants physical authority.

## Known blockers

### Code / CI

- Prove the three Portrait contrast corrections on the combined exact head without weakening the hosted audits.
- The Capture authorization/retained-IPA schema foundation is integrated; production key review, atomic app capability consumption, exact install-manifest binding, typed private journal, bundle verifier, summary, and guided coordinator remain code/security work.
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

1. Push this combined implementation/continuity checkpoint and verify `origin/release/nembra-1-0-unified` contains it.
2. Create a new draft PR from `release/nembra-1-0-unified` to `main`, synchronize its checklist from this file, and explicitly dispatch `xcode27-simulator.yml` on the exact branch SHA. Do not treat automatic admission or the default-branch `/xcode27` wrapper as Release-performance authority.
3. Verify the dispatched run's exact `headSha`, Mac job, Xcode 27/iOS 27/iPhone 12 identity, complete artifact inventory, functional/accessibility results, deterministic screenshots, and separate Release three-sample Clock + Hitch Time Ratio validator output. Update this file with run and artifact IDs.
4. In parallel, finish Capture's atomic ThisDeviceOnly capability consumption/install-manifest seam without populating the trust root or contacting hardware; inspect the in-progress V16/visual runs and close compact-landscape reachability if still red.
5. Reassign three non-overlapping milestones from exact evidence: Capture authorization/journal, Home visual/accessibility closure, and Drive visual/performance closure. Navigation, Explore, and additional portrait tabs widen only after their vertical-slice gates pass.

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
- The predecessor implementations and unified corrections are source-integrated, but combined runtime correctness remains unproven until the exact-head build/test/runtime gate passes.
- The selected Home and Energy Chamber references are visual targets/directions only; same-state runtime comparisons have not passed.
- The temporary ES80 raster cannot close Home asset fidelity or rights.
- No current GitHub-safe physical packet fixture proves a production ES80 semantic. Every field in `docs/ES80_PROTOCOL_MAP.md` remains unknown except transport topology facts.
- Automatic capture remains public-API best effort; force-quit, first-unlock, restoration, real scooter reconnect, and background location still need physical-device evidence.
- Explore has no selected licensed road dataset or scalable accepted matcher/overlay implementation.
