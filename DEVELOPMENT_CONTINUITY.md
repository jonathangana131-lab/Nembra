# Nembra development continuity

Status: active recovery authority. Update this file after every meaningful checkpoint and before pausing, handing off, merging, or ending a development session.

## Resume protocol

Before changing code in a resumed task:

1. Read this file completely.
2. Read `docs/design-reference/horizon-v4-final/NEMBRA_HORIZON_V4_PRODUCTION_HANDOFF.md` and `docs/NEMBRA_V2_PRODUCTION_FOUNDATION.md` completely.
3. Run `git status --short`, `git log -5 --oneline --decorate`, `git fetch origin`, and compare `HEAD` with the branch and PR head below.
4. Inspect the current PR and exact-head Actions results. Evidence from an ancestor SHA does not transfer to a newer head.
5. Continue the exact next action recorded below. Do not restart planning or revive rejected V2/V3 cockpit work.

This repository file is the recovery authority. Chat/task summaries are supplementary.

## Authoritative GitHub state

- Repository: `jonathangana131-lab/Nembra`
- Branch: `product/capture-1-0-main-20260818`
- Pull request: [#3675 — Finish Capture checkpoint and production Nembra surfaces](https://github.com/jonathangana131-lab/Nembra/pull/3675)
- PR base: `main`
- PR state: draft until all exact-current-head acceptance gates below are green and inspected
- Latest pushed implementation/design checkpoint recorded here: `0b7e3b27de5e9b547911558ae8ed4cb852becb59`
- Latest pushed continuity checkpoint preceding this update: `cf817a8b1c1f74640055af317671497a202e4f74`
- Recovery rule: after cloning, run `git rev-parse HEAD` and `git ls-remote origin refs/heads/product/capture-1-0-main-20260818`; if either is newer than the recorded checkpoints, inspect those commits and update this file before development.

The file cannot self-embed the SHA of the commit containing its own changed bytes. Therefore the SHAs above name the latest pushed implementation and meaningful continuity checkpoints this document has audited; the remote branch HEAD is the authority for any later continuity-only commit.

## Current focused aspect and production acceptance gate

The integration branch still carries the complete Nembra 1.0 objective, but implementation ownership is now deliberately split:

1. **Nembra Capture 1.0 software checkpoint** — safe, fail-closed, one-time Bluetooth evidence utility. Software acceptance requires exact-head Capture source/provenance suites, standalone public/synthetic UI matrix, iPhone 12/iOS 27 visual evidence, artifact custody, and truthful nonphysical authority boundaries. Physical/private status remains **NO-GO** until the separate documented intended-account/intended-scooter field procedure has authorized prerequisites and a real device run.
2. **Portrait Home and menus** — owned by the isolated Codex task `01a01c57-b619-7262-8971-ba9044659a29`. The root branch does not duplicate that implementation. Its PR is an integration input and must preserve the selected Home truth/accessibility/performance contracts.
3. **Landscape cockpit and feature lab** — owned by the isolated Codex task `01a01c57-590f-7c21-8071-39e8bfdd78e8`. Horizon V4 remains requirements-only and visually rejected. The user-approved post-V4 direction is the Energy Chamber family recorded under `docs/design-reference/horizon-post-v4-studies/`; its live-power gauge and typography still require redesign and exact Xcode 27 proof.

The root task is now the dedicated **Capture + Bluetooth truth** workstream and integration owner. It must finish the smallest reliable one-time companion capture, preserve raw evidence without guessing, produce a versioned machine-readable export plus human summary/protocol map, integrate only high-confidence mappings into production decoding, and notify both sibling branches through repository docs/PR notes when stable contracts or fixtures are available.

### Parallel portrait recovery record

- Branch: `agent/portrait-home-1-0-polish`
- Latest pushed implementation checkpoint:
  `1149ea9babb7a49fd52cb927826b4a0a59c12820`
- Scope recovery authority: `docs/continuity/PORTRAIT_EXPERIENCE.md`
- Current focus: finish Home connected/disconnected/loading/error/retained/low
  states and selected composition before widening into Rides, Vehicle, Settings,
  profile, or secondary sheets.
- First checkpoint paths: `NembraApp/Features/Home/HomeView.swift`,
  `NembraApp/DesignSystem/NembraVisuals.swift`, `NembraUITests/NembraUITests.swift`,
  focused Home source tests, `docs/design/`, `docs/coordination/UI_CONTRACTS.md`,
  and portrait continuity/provenance records.
- Local evidence: Swift parse passes; focused Home source tests pass 5/5;
  inherited Ride source test passes 1/1; strict-concurrency generic Simulator
  build-for-testing exits 0 under diagnostic local Xcode 26; secret/path and
  diff checks pass.
- Hosted acceptance: not yet run for `1149ea9b…`. Exact Xcode 27 / iPhone 12 /
  iOS 27 accessibility, screenshot, and performance evidence remains required.
- External blocker: final Home artwork still requires a high-resolution,
  production-cleared truthful ES80 source. The 500×500 temporary raster cannot
  close visual acceptance.
- Next executable action: open the portrait draft PR against the integration
  branch, manually dispatch branch-local `xcode27-simulator.yml`, inspect the
  exact-head Mac job/artifacts, then continue the value-input Home leaf
  extraction while hosted evidence runs.

This parallel record does not authorize the root task to edit portrait files.
Capture/BLE publishes only stable typed contracts/fixtures for the portrait
branch to consume; unknown or stale values remain unavailable/retained in UI.

The current Home screenshot is a functional checkpoint only and is explicitly **not visually accepted**. Home visual acceptance additionally requires one fresh exact-head Xcode 27 iPhone 12 screenshot placed side-by-side with `docs/design-reference/nembra-1.0-gold-glass/selected-home-gold-glass.png` and proving all of the following together:

- a dimensional battery instrument with fine SOC-clipped ribs/micro-lines, gold gradient/highlight, deep graphite empty region, metallic rim/inner depth, and terminal detail;
- refined SF battery/range typography with state-appropriate contrast and hierarchy for learned, unavailable, low, reconnecting, and retained/stale states;
- a provenance-documented, high-resolution, truthful ES80 side render with premium graphite material/lighting and no invented/counterfeit geometry;
- zero intersection between the scooter and percentage, range/unavailable copy, status text, or accessibility content in every deterministic state;
- separate tire contact shadows, a longer deck shadow, ambient occlusion, restrained warm under-deck light, and a believable floor/reflection plane;
- native Liquid Glass depth/specular/environmental response on actual interactive controls/actions and the system floating tab bar, without glass-coating telemetry or passive content;
- one integrated lighting scene: warm energy light may influence the scooter, floor, contact shadows, and nearby functional glass edges while primary information stays white, secondary information cool grey, connection health green, and energy/active state gold.

Do not merge PR #3675 or claim either aspect complete until the latest remote head—not an ancestor—meets these gates.

## Completed and pushed work

The current pushed implementation checkpoint includes:

- Capture authority, provenance, immutable artifact sealing/validation, recoverable sharing, public/synthetic UI, field handoff and exact-head workflows under `NembraApp/App/NembraCaptureEntrypoint.swift`, `Packages/NembraBluetoothCapture/`, `NembraCaptureUITests/`, `Scripts/`, `.github/workflows/`, and the canonical Capture docs.
- Selected portrait Home/Rides/Vehicle/Settings implementation under `NembraApp/Features/Home/`, `NembraApp/App/AppRootView.swift`, and `NembraApp/Features/Settings/`, with selected references under `docs/design-reference/nembra-1.0-gold-glass/`.
- Existing cockpit functional implementation, exact-scene orientation ownership, idle animation shutdown, and product performance harness under `NembraApp/Features/Dashboard/`, `NembraApp/App/DashboardSessionStore.swift`, `NembraUITests/`, `scripts/ci/xcode27_product_simulator_capture.sh`, `scripts/ci/validate_xcode27_dashboard_performance.py`, and `.github/workflows/xcode27-simulator.yml`. Its current visuals are not 1.0 acceptance.
- Automatic-capture readiness/candidate journal, crash-safe daily ride segments, ride history/route persistence, and road-exploration provenance foundations under `Packages/NembraCore/Sources/NembraCore/` and their focused tests.
- Horizon functional/state requirements under `docs/design-reference/horizon-v4-final/NEMBRA_HORIZON_V4_PRODUCTION_HANDOFF.md`; V2/V3/V4 cockpit PNGs are rejection/history evidence only.

Checkpoint `0b7e3b27…` closes the exact `cf817a8b…` integration failures without beginning new portrait or cockpit feature work:

- `NembraApp/Features/Home/HomeView.swift` removes compounded dimming from retained percentage and adaptive-range qualifier text while preserving explicit retained/currentness semantics.
- `NembraApp/App/AppRootView.swift` removes shared labeled-pair identities from both `ViewThatFits` timeline alternatives so Xcode audits the visible native semantic-font `Text` nodes in title-then-timestamp order.
- `NembraUITests/NembraUITests.swift` makes the deterministic landscape screenshot terminal in its fixture, then strengthens the separately passing battery-hitch test to prove the real Home control restores portrait and removes the cockpit. This avoids the evidenced hosted-XCUI post-screenshot animation-idle deadlock without disabling motion, raising timeouts, or weakening product assertions.
- Focused source contracts are updated under `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityMetricLayoutSourceTests.swift` and `RideWindowNavigationClearanceSourceTests.swift`.
- `docs/design-reference/horizon-post-v4-studies/` preserves four original `1844 × 853` studies with hashes and generation provenance. The user selected the Energy Chamber material/composition family; its ambiguous/fabricated live-power scale, NOW locator, and generic typography are explicitly rejected pending redesign. The one-value battery contract remains percentage **or** range inside the same battery while SOC fill always means charge.

Proportional local evidence for `0b7e3b27…`: all five changed Swift files parse; `git diff --check` passes; focused Home/Ride source tests pass 4/4; secret/path scan is clean; and a diagnostic local generic-iOS-Simulator `build-for-testing` exits 0 for app, unit-test, and UI-test targets. Local Xcode 26.1 is compile evidence only, never release authority.

Checkpoint `1095f367…` specifically fixes the steady-state Dashboard animation/idleness timeout and Ride-window timeline accessibility semantics:

- `NembraApp/Features/Dashboard/SpeedInstrumentModel.swift`
- `NembraUITests/NembraUITests.swift`
- `NembraApp/App/AppRootView.swift`
- `Packages/NembraCore/Tests/NembraCoreTests/RideWindowNavigationClearanceSourceTests.swift`

Checkpoint `a381a30f…` implements the first focused Home energy-material correction without claiming visual acceptance:

- `NembraUITests/NembraUITests.swift` terminates the intentionally continuous render-stress fixture after its preserved 3×6-second measurement, post-update proof, QA screenshot, and metrics rather than waiting for impossible XCUI animation quiescence. Independent exact-scene portrait restoration coverage remains unchanged.
- `NembraApp/App/AppRootView.swift` gives the explicit read-only Ride timeline label/value node the full existing padded-row accessibility focus shape without adding a button trait or changing layout.
- `NembraApp/Features/Home/HomeView.swift` adds a synchronous, input-driven engineered battery Canvas with truthful SOC fill, SOC-clipped graphite copy well, gold/red dimensional fill, fine clipped ribs, metallic shell/rim/terminal, state-aware typography/contrast, early large-text reflow, a measured current-asset copy corridor, and separate blurred tire/deck/ambient/gold/floor grounding layers. It shortens the standard hero to restore populated-row/tab clearance and applies native glass only to the actionable saved-ride continuation.
- `NembraApp/DesignSystem/NembraVisuals.swift` uses a stable dark Nembra fallback and boundary under Reduce Transparency/Show Borders rather than an adaptive light surface that could erase white glyphs.
- `NembraUITests/NembraUITests.swift` adds standard accessibility auditing (including contrast), explicit Accessibility XXXL reachability/screenshots, and retained/low-battery contrast audits.
- Focused source contracts are updated under `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityControlLayoutSourceTests.swift`, `HomeAccessibilityMetricLayoutSourceTests.swift`, and `RideWindowNavigationClearanceSourceTests.swift`.

Historical checkpoint `245fb44a…` closed the five exact Xcode 27 accessibility failures in run `32306810002` without weakening the audits. Its labeled-pair timeline approach was later superseded by `0b7e3b27…` after exact Xcode 27 exposed an inactive-candidate audit failure:

- `NembraUITests/NembraUITests.swift` now launches Accessibility XXXL with UIKit's actual raw category identifier, `UICTContentSizeCategoryAccessibilityXXXL`; the prior expanded Swift-symbol spelling was read but did not activate the larger layout.
- `NembraApp/Features/Home/HomeView.swift` removes compounded numeric opacity, retains truthful stale/range de-emphasis, uses a higher-contrast semantic low-battery red, and adds one restrained specular boundary around the native-glass Vehicle Controls button.
- `NembraApp/App/AppRootView.swift` replaces the synthetic Ride timeline accessibility node with native scaling `Text` elements associated through `accessibilityLabeledPair`, while preserving `ViewThatFits`, timestamp truth, and the 72-point navigation-launcher clearance.
- Focused source regressions remain under `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityMetricLayoutSourceTests.swift` and `RideWindowNavigationClearanceSourceTests.swift`.
- `docs/design-reference/nembra-1.0-gold-glass/runtime-evidence/` retains the exact b319 selected-vs-runtime comparison and its explicit non-acceptance record so this visual diagnosis survives artifact expiry.

Local proportional evidence for `245fb44a…`: all five changed Swift files parse; `git diff --check` passes; Home source tests pass 5/5; Ride Window source test passes 1/1; a diagnostic generic-Simulator app build exits 0 under local Xcode 26.1; and an adversarial scope/secret audit is green. This local result is compile evidence only, not release authority.

## Work in progress

No intentional source, study, or evidence change is local-only after implementation commit `0b7e3b27de5e9b547911558ae8ed4cb852becb59`; it is pushed and remote-verified. This document is published as a continuity-only checkpoint immediately after that implementation commit; because it cannot contain its own commit SHA, the remote branch HEAD is the recovery authority as described above.

Exact-head hosted evidence for `0b7e3b27…` started automatically:

- [`Xcode 27 Simulator QA` run `32315523013`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315523013) is in progress and controls functional/accessibility/Release-performance acceptance.
- [`Capture V16 Standalone Exact-Head` run `32315522994`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315522994) and [`Capture Standalone Visual Evidence` run `32315523022`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315523022) are in progress.
- [`Capture Field Handoff Provenance` run `32315522998`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315522998), [`Capture TODAY Field Candidate Preflight QA` run `32315522997`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315522997), and [`Capture TODAY Final GO QA` run `32315523032`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315523032) are green. These remain nonphysical/non-authorizing contract evidence.

After this continuity push, root work resumes only in Capture/Bluetooth truth. The next code batch begins with a read-only capability/export/protocol-map audit; it does not modify Home or cockpit implementation.

## Exact CI and retained evidence

The current implementation checkpoint is `0b7e3b27de5e9b547911558ae8ed4cb852becb59`; its exact-head workflows are listed above and remain pending.

The latest completed baseline is exact `cf817a8b1c1f74640055af317671497a202e4f74`; its evidence is root-cause context only and does not transfer to `0b7e3b27…`:

- All five Capture lanes were **green**: TODAY preflight `32310420811` (53/53), Final GO contracts `32310421001` (73/73), field provenance `32310420850` (12 Python + 39 Swift), standalone visual `32310420920` (artifact `9386365261`, digest `1f83a866c52bf7ff74def59728805c2a0ade8f04e86dc9236d4e6729d1ab93c2`), and V16 `32310420859` (84 Swift + 9 Python + 13/13 UI; artifact `9386603633`, digest `0265b7884a329610ce7fcd4c8e6297ba3f0943662fa5fb2c187fe6bdbfa6afea`). These prove software/simulator contracts only and do not authorize physical/private Capture.
- [`Xcode 27 Simulator QA` run `32310434323`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32310434323) was a genuine exact-head **red** run: Core 1,355/1,355 and app/unit 76/76 passed; UI 17/22 passed.
- Its five final failures were connected-Home contrast, low-battery qualifier contrast, retained percent contrast, Ride timeline Dynamic Type, and one Dashboard post-screenshot animation-idle timeout. The sustained Debug render test passed three approximately six-second clock samples, but no Hitch Time Ratio was emitted; Debug red prevented direct screenshots and the separate Release performance lane.
- Artifact `9386781377`, digest `a51913e14e2ce7ed62bc4606be15819d894046e222e0cfad8544d6b8cbecc519`.

## Known blockers

### Code/CI work

- Validate exact `0b7e3b27…` on GitHub-hosted Xcode 27. Only that runtime can prove the three Home contrast fixes, native Ride timeline Dynamic Type behavior, terminal screenshot fixture, active Home restoration, and real Release clock/Hitch Time Ratio samples.
- Audit the current Capture/Bluetooth code against the new one-time evidence outcome before editing. In particular, prove or identify gaps in guided action sequencing, service/characteristic/property enumeration, notify/indicate/read capture, monotonic raw packet metadata, reconnect/relaunch recovery, lossless export/import, human summary, and evidence-backed protocol mapping.
- Create one dedicated Capture/Bluetooth continuity handoff after the audit. It must inventory only GitHub-safe captured sessions/fixtures; private identifiers and raw sensitive field artifacts remain excluded.
- Keep PR description/checklist synchronized with this file after each pushed checkpoint.
- Portrait Home/menu and cockpit implementation are owned by their two isolated tasks. Root must not overwrite those branches; integrate their PRs only after reviewing contracts, checks, and merge conflicts.

### GitHub/external

- Hosted `xcode-27` capacity can queue for roughly 30–90+ minutes. Queue delay is not a product failure.
- PR remains draft. It requires a final exact-current-head ready-for-review rerun before merge.

### User/physical Capture

- Physical Capture remains **NO-GO** without private Tuya provisioning/signing material, intended iPhone, intended SmartLife account, intended stationary charger-disconnected ES80, explicit current-attempt target confirmation, and execution of `ES80-AUTHENTICATED-STATIONARY-v1` by the authorized field operator.
- Do not commit private credentials, raw sensitive Capture output, device identifiers, or field artifacts.

### User/asset-rights

- Final Home 1.0 scooter artwork requires either a user-owned/commissioned high-resolution side photograph of the actual ES80 configuration or written AOVOPRO media/license permission for a specific high-resolution source. The existing 500×500 raster is useful for temporary layout but its exact original URL, transformation chain, license, and permission are not retained; do not AI-generate or upscale invented hardware detail.

## Exact next executable action

1. Monitor exact `0b7e3b27…` product run `32315523013` and Capture runs `32315522994` and `32315523022`. Inspect the already-green field/TODAY lanes, treat queue/cancellation separately from a genuine failure, and preserve the physical/private NO-GO boundary.
2. Begin a read-only Capture/Bluetooth truth audit from `CAPTURE_HARD_FREEZE_ACTIVE.md`, `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`, the current Capture docs, `Packages/NembraBluetoothCapture/`, `NembraApp/App/NembraCaptureEntrypoint.swift`, `NembraCaptureUITests/`, and retained GitHub-safe fixtures/artifact manifests.
3. Create `docs/CAPTURE_BLUETOOTH_CONTINUITY.md` with branch/SHA/checks, safe session inventory, verified mappings, contradictions/unknowns, import/export instructions, and the shortest exact physical ES80 action still required. Do not copy private artifacts or device identifiers into Git.
4. Implement only the smallest missing Capture batch evidenced by that audit; run package tests, parser/static checks, and exact-head Xcode 27. Push a coherent commit and update both continuity records before widening.
5. When a BLE mapping or fixture is stable and production-consumable, document the typed contract and notify portrait task `01a01c57-b619-7262-8971-ba9044659a29` and cockpit task `01a01c57-590f-7c21-8071-39e8bfdd78e8` through repository docs/PR notes.
6. Do not merge PR #3675 until current-head Capture evidence, the integrated sibling PRs, and final product gates are green and inspected. Use a merge commit, not squash.

## Rejected designs and approaches

- Horizon V2 Orbit/Vector/Apex and the V2 Option 2 execution are rejected. Do not merge, polish, or use their geometry, typography, thin roads, debug labels, or metric strips.
- Every Horizon V3 cockpit image/layout is rejected prototype history. Do not resurrect its clipped/crooked arc, map collisions, card structure, typography, or styling.
- Horizon V4 retains requirements authority only. Its PNGs and current runtime visual execution are rejected pixel targets; `docs/design-reference/horizon-v4-final/V4_COCKPIT_VISUAL_REJECTED.md` is the durable rejection record.
- The selected portrait package under `docs/design-reference/nembra-1.0-gold-glass/` is the sole Home/Rides/Vehicle/Settings composition authority.
- The Energy Chamber family is the selected post-V4 material/composition direction, not a pixel-final screenshot. Its original `-18/18 kW` scale, ambiguous NOW locator, unreadable direction/intensity, and generic typography are rejected and must not ship.
- Cockpit battery is one unified in-instrument value: percentage by default, tap to range, tap back. SOC fill always means charge; simultaneous/detached range is forbidden.
- Do not convert Capture into a second product app or let hardware waiting freeze main-app work.
- Do not fabricate BLE facts, range, route progress, ride totals, or road coverage. Simulator fixtures stay Debug+iOS-Simulator-only and visibly disclosed.
- Do not glass-coat telemetry/content or use independent blur stacks; use native Liquid Glass only for functional chrome and grouped glass containers where required.
- Do not use local Xcode 26 as release authority. GitHub-hosted Xcode 27/iPhone 12/iOS 27 evidence controls acceptance.
- Do not squash-merge PR #3675; the planned integration uses a merge commit after final exact-head approval.

## Unverified assumptions and evidence still required

- The `0b7e3b27…` accessibility/test-harness fixes are statically and locally compile-verified, but exact Xcode 27 must prove the full audits and that the Release metric validator receives real clock and Hitch Time Ratio samples.
- The Energy Chamber material/composition direction is user-approved, but its live-power visualization and typography are explicitly unfinished. The isolated cockpit task owns that implementation and must prove it with later exact-head screenshots/performance.
- Native Ride Window title/timestamp Text nodes still need the exact Xcode 27 Dynamic Type and VoiceOver audit.
- The retained b319 screenshot proves default 92%/unavailable copy is not visibly occluded, but it is not state-parallel with the selected 73%/learned-range reference and cannot prove other states, larger text, or populated-row clearance.
- The current 500×500 `ES80Side` presentation asset is linked to AOVOPRO's official product page but is not production-cleared: the exact source/hash, retrieval date, masking steps, author/license, and written reproduction permission are missing. The user has also rejected its low-resolution grey/red treatment as final. A replacement needs a user-owned actual-scooter photo or written licensed high-resolution source, full provenance, truthful geometry, and visual review.
- Battery microtexture, dimensional shell/rim, adaptive typography/contrast, SOC-clipped copy well, floor/contact lighting, and actionable continuation glass remain visually unfinished. The b319 comparison specifically records the overly bright double rim, wide copy well, uniform ribs, weak floor/contact grounding, temporary grey/red scooter, and flatter glass response.
- The standard, retained, low-battery, and Accessibility XXXL Home audits need exact Xcode 27 execution at `0b7e3b27…`; later portrait work belongs to the isolated Home task.
- No current GitHub-safe artifact proves a production ES80 packet mapping. CI proves software contracts and simulator fixtures, not physical BLE semantics. The upcoming Capture audit must classify every existing field/byte claim as observed fact, inference, hypothesis, contradiction, or unknown before any decoder integration.
- Production numeric adaptive range remains unavailable because no accepted physical estimator/identity/evidence pipeline is wired. Do not synthesize the reference image's `8.4 mi`.
- Automatic capture is public-API best effort. Force-quit, restart-before-first-unlock, permissions, real ES80 restoration/reconnect, and background location behavior still require real-device evidence.
- Explore domain foundations do not select a road-graph provider or license. No road may be marked covered without accepted map-matched evidence.
