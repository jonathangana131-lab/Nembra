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
- Latest pushed implementation checkpoint recorded here: `245fb44a32a614119b133f1b5f16ffd8c138ad07`
- Latest pushed visual-authority/continuity checkpoint recorded here: `b3199bea8a7bde4c10da54d7444e4fb57eb86112`
- Recovery rule: after cloning, run `git rev-parse HEAD` and `git ls-remote origin refs/heads/product/capture-1-0-main-20260818`; if either is newer than the recorded checkpoints, inspect those commits and update this file before development.

The file cannot self-embed the SHA of the commit containing its own changed bytes. Therefore the SHAs above name the latest pushed implementation and meaningful continuity checkpoints this document has audited; the remote branch HEAD is the authority for any later continuity-only commit.

## Current focused aspect and production acceptance gate

The active goal is to finish two bounded aspects, merge them, and then hand off the next focused prompt:

1. **Nembra Capture 1.0 software checkpoint** — safe, fail-closed, one-time Bluetooth evidence utility. Software acceptance requires exact-head Capture source/provenance suites, standalone public/synthetic UI matrix, iPhone 12/iOS 27 visual evidence, artifact custody, and truthful nonphysical authority boundaries. Physical/private status remains **NO-GO** until the separate documented intended-account/intended-scooter field procedure has authorized prerequisites and a real device run.
2. **Portrait Home + current requirements-driven cockpit checkpoint** — selected Home composition, native functional glass, truthful telemetry/range/currentness, automatic-ride/durable-Today continuity, exact-scene orientation restoration, accessibility, idle animation shutdown, and Release performance evidence. Horizon V4 is requirements-only and visually rejected; no cockpit pixel target is currently selected. Acceptance requires a new internally studied/refined production direction plus exact-head Xcode 27, iPhone 12/iOS 27 functional/UI suites, screenshot comparison, accessibility audits, and validated Release clock/hitch metrics.

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

Checkpoint `245fb44a…` is the current pushed implementation. It closes the five exact Xcode 27 accessibility failures in run `32306810002` without weakening the audits:

- `NembraUITests/NembraUITests.swift` now launches Accessibility XXXL with UIKit's actual raw category identifier, `UICTContentSizeCategoryAccessibilityXXXL`; the prior expanded Swift-symbol spelling was read but did not activate the larger layout.
- `NembraApp/Features/Home/HomeView.swift` removes compounded numeric opacity, retains truthful stale/range de-emphasis, uses a higher-contrast semantic low-battery red, and adds one restrained specular boundary around the native-glass Vehicle Controls button.
- `NembraApp/App/AppRootView.swift` replaces the synthetic Ride timeline accessibility node with native scaling `Text` elements associated through `accessibilityLabeledPair`, while preserving `ViewThatFits`, timestamp truth, and the 72-point navigation-launcher clearance.
- Focused source regressions remain under `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityMetricLayoutSourceTests.swift` and `RideWindowNavigationClearanceSourceTests.swift`.
- `docs/design-reference/nembra-1.0-gold-glass/runtime-evidence/` retains the exact b319 selected-vs-runtime comparison and its explicit non-acceptance record so this visual diagnosis survives artifact expiry.

Local proportional evidence for `245fb44a…`: all five changed Swift files parse; `git diff --check` passes; Home source tests pass 5/5; Ride Window source test passes 1/1; a diagnostic generic-Simulator app build exits 0 under local Xcode 26.1; and an adversarial scope/secret audit is green. This local result is compile evidence only, not release authority.

## Work in progress

No intentional source, evidence, or documentation change is local-only at this checkpoint. The coherent code/evidence candidate is pushed and remote-verified as `245fb44a32a614119b133f1b5f16ffd8c138ad07`.

Hosted evidence is in progress and is not yet transferable:

- `Xcode 27 Simulator QA` run [`32310195339`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32310195339) is admitted/in progress for exact `245fb44a…`. This pull-request workflow uses the branch's product wrapper, including the separate Release performance scheme and fail-closed Hitch Time Ratio validator.
- `Capture V16 Standalone Exact-Head` run [`32310195334`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32310195334), `Capture Field Handoff Provenance` run [`32310195368`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32310195368), and `Capture Standalone Visual Evidence` run [`32310195430`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32310195430) are running/queued at the same exact SHA.
- `Capture TODAY Field Candidate Preflight QA` run [`32310195345`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32310195345) and `Capture TODAY Final GO QA` run [`32310195336`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32310195336) are green at exact `245fb44a…`; they remain nonphysical/non-authorizing contract evidence.

Do not call the Home correction visually accepted from source or local-build evidence. The first exact Xcode 27 runtime screenshots must be compared directly with the selected Home reference, and the current temporary ES80 asset still blocks final visual/provenance acceptance.

## Exact CI and retained evidence

The current implementation checkpoint is `245fb44a32a614119b133f1b5f16ffd8c138ad07`. Its exact-head main/Capture workflows are listed under Work in progress above. Only the two Ubuntu Capture contract lanes are currently green; Xcode 27 product and standalone evidence remain pending and control acceptance.

The latest completed exact-head baseline is `b3199bea8a7bde4c10da54d7444e4fb57eb86112`; its evidence is root-cause context only and does not transfer to `245fb44a…`:

- Capture software lanes were all **green** at b319: TODAY preflight `32306490943` (53/53), Final GO contracts `32306490976` (73/73), field provenance `32306490925` (12 Python + 39 Swift), visual `32306490938` (artifact `9385041433`, digest `ae584486dd348d6813b6f7fc32c575690529e2789439c97905a2d4524e84bda2`), and V16 `32306490991` (84 Swift + 9 Python + 13/13 UI; artifact `9385365288`, digest `8acbea444f343bd8160911be8f2e6cc6d8abb7efb940823030d309e5a8a2aab4`). These remain simulator/public contract evidence; they do not authorize physical/private Capture.
- Draft-safe exact-head main run [`32306810002`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32306810002) was **red** at b319.
  - Exact Xcode 27/iOS 27/iPhone 12 environment; Core 1,355/1,355 and app/unit 76/76 passed; UI 17/22 passed.
  - Failures: invalid Accessibility XXXL raw category left the header horizontal; standard Vehicle Controls glass boundary contrast; low-battery `14` contrast; retained `%` contrast; and synthetic Ride `Ended` Dynamic Type support.
  - Sustained Debug render evidence collected clock samples `[5.926993292, 6.003017419, 5.906703171]`, but the base-main issue-comment workflow invoked the legacy producer and emitted no Hitch Time Ratio. Release performance did not run, so no performance acceptance exists.
  - Artifact `9385491719`, archive digest `bd9683af92fee36fec45651c525bc70e48ea3f02047a1a18b47122ae5125efa4`.
  - The deterministic functional Home screenshot and selected reference are preserved together at `docs/design-reference/nembra-1.0-gold-glass/runtime-evidence/home-b319-functional-not-accepted-reference-comparison.png`. It is explicitly not a visual-acceptance target.

## Known blockers

### Code/CI work

- Validate exact `245fb44a…` on GitHub-hosted Xcode 27. Only the new runtime can prove Accessibility XXXL reflow, standard/retained/low-battery contrast, native Ride timeline Dynamic Type/VoiceOver behavior, populated Home/tab clearance, and real Release clock/Hitch Time Ratio samples.
- Inspect every new exact-head Home screenshot beside `docs/design-reference/nembra-1.0-gold-glass/selected-home-gold-glass.png` on one same-viewport comparison canvas. The retained b319 comparison proves open visual gaps; it is not acceptance.
- Continue the Home correction only from visible runtime mismatches. The current battery/material/typography/grounding implementation is a candidate, not a final image.
- Replace the temporary 500×500 grey/red ES80 source only after the user supplies a user-owned/commissioned high-resolution actual-scooter side photo or written AOVOPRO permission for a specific high-resolution source. Update `docs/PRODUCTION_VISUAL_ASSET_PROVENANCE.md` with exact custody before shipping it.
- Keep PR description/checklist synchronized with this file after each pushed checkpoint.

### GitHub/external

- Hosted `xcode-27` capacity can queue for roughly 30–90+ minutes. Queue delay is not a product failure.
- PR remains draft. It requires a final exact-current-head ready-for-review rerun before merge.

### User/physical Capture

- Physical Capture remains **NO-GO** without private Tuya provisioning/signing material, intended iPhone, intended SmartLife account, intended stationary charger-disconnected ES80, explicit current-attempt target confirmation, and execution of `ES80-AUTHENTICATED-STATIONARY-v1` by the authorized field operator.
- Do not commit private credentials, raw sensitive Capture output, device identifiers, or field artifacts.

### User/asset-rights

- Final Home 1.0 scooter artwork requires either a user-owned/commissioned high-resolution side photograph of the actual ES80 configuration or written AOVOPRO media/license permission for a specific high-resolution source. The existing 500×500 raster is useful for temporary layout but its exact original URL, transformation chain, license, and permission are not retained; do not AI-generate or upscale invented hardware detail.

## Exact next executable action

1. Monitor exact `245fb44a…` `Xcode 27 Simulator QA` run `32310195339` through terminal status. Download its artifact and verify source SHA, Xcode/iOS/iPhone 12 identity, Core/app/unit/UI results, Release clock + Hitch Time Ratio samples, direct screenshot matrix, retained attachments, and any accessibility issue element.
2. Monitor exact `245fb44a…` Capture runs `32310195334`, `32310195368`, and `32310195430`. Treat queue/cancellation separately from test failure and preserve the physical/private NO-GO boundary.
3. If the product run is green, place its unscrolled deterministic `Selected Portrait Home - Simulator QA Only` screenshot beside `docs/design-reference/nembra-1.0-gold-glass/selected-home-gold-glass.png` on one 390×844 logical comparison canvas. Inspect battery ribs/shell/copy-well contrast, scooter/text intersections, grounding, functional glass, populated-row/tab clearance, and all state screenshots. Record visible mismatches; do not infer fidelity from source.
4. If the product run is red, apply only the narrow evidenced fix in the files named by the failure. Preserve the passing battery-toggle, exact-scene portrait restoration, telemetry truth, daily continuity, and performance gates.
5. Before every new checkpoint, run parsers, `git diff --check`, the three focused source suites, and a secret/scope audit; commit/push intentionally, verify the remote branch SHA, then update this file and PR #3675 again.
6. Do not merge until every exact-current-head gate is green and inspected. Home remains visually unfinished while the temporary unlicensed/low-resolution ES80 asset is present even if functional CI turns green.
7. After this bounded truth/CI checkpoint is stable, start the next deep product aspect with multiple internal iPhone 12 landscape cockpit studies from the retained requirements and selected Home language. V4 remains requirements-only/rejected visually, and the cockpit battery remains one value inside one instrument: percentage by default, tap to range, tap back, with SOC fill unchanged.

## Rejected designs and approaches

- Horizon V2 Orbit/Vector/Apex and the V2 Option 2 execution are rejected. Do not merge, polish, or use their geometry, typography, thin roads, debug labels, or metric strips.
- Every Horizon V3 cockpit image/layout is rejected prototype history. Do not resurrect its clipped/crooked arc, map collisions, card structure, typography, or styling.
- Horizon V4 retains requirements authority only. Its PNGs and current runtime visual execution are rejected pixel targets; `docs/design-reference/horizon-v4-final/V4_COCKPIT_VISUAL_REJECTED.md` is the durable rejection record.
- The selected portrait package under `docs/design-reference/nembra-1.0-gold-glass/` is the sole Home/Rides/Vehicle/Settings composition authority.
- The next cockpit visual direction must be developed through several internal iPhone 12 landscape studies from retained requirements and the selected Home language. Do not present the first runnable layout as complete.
- Cockpit battery is one unified in-instrument value: percentage by default, tap to range, tap back. SOC fill always means charge; simultaneous/detached range is forbidden.
- Do not convert Capture into a second product app or let hardware waiting freeze main-app work.
- Do not fabricate BLE facts, range, route progress, ride totals, or road coverage. Simulator fixtures stay Debug+iOS-Simulator-only and visibly disclosed.
- Do not glass-coat telemetry/content or use independent blur stacks; use native Liquid Glass only for functional chrome and grouped glass containers where required.
- Do not use local Xcode 26 as release authority. GitHub-hosted Xcode 27/iPhone 12/iOS 27 evidence controls acceptance.
- Do not squash-merge PR #3675; the planned integration uses a merge commit after final exact-head approval.

## Unverified assumptions and evidence still required

- The `245fb44a…` accessibility fixes and previously pushed stress-fixture termination are statically/locally verified, but exact Xcode 27 must prove the full audits and the Release metric validator receives real clock and Hitch Time Ratio samples.
- The V4 pixel execution is no longer visual authority. Existing Drive/Nav/Explore screenshots can prove functionality and rejected traits only; a new production composition study/selection and later exact-head screenshots are required.
- Native Ride Window label/content pairs still need the exact Xcode 27 Dynamic Type and VoiceOver audit.
- The retained b319 screenshot proves default 92%/unavailable copy is not visibly occluded, but it is not state-parallel with the selected 73%/learned-range reference and cannot prove other states, larger text, or populated-row clearance.
- The current 500×500 `ES80Side` presentation asset is linked to AOVOPRO's official product page but is not production-cleared: the exact source/hash, retrieval date, masking steps, author/license, and written reproduction permission are missing. The user has also rejected its low-resolution grey/red treatment as final. A replacement needs a user-owned actual-scooter photo or written licensed high-resolution source, full provenance, truthful geometry, and visual review.
- Battery microtexture, dimensional shell/rim, adaptive typography/contrast, SOC-clipped copy well, floor/contact lighting, and actionable continuation glass remain visually unfinished. The b319 comparison specifically records the overly bright double rim, wide copy well, uniform ribs, weak floor/contact grounding, temporary grey/red scooter, and flatter glass response.
- The standard, retained, low-battery, and Accessibility XXXL Home audits need exact Xcode 27 execution at `245fb44a…`.
- Production numeric adaptive range remains unavailable because no accepted physical estimator/identity/evidence pipeline is wired. Do not synthesize the reference image's `8.4 mi`.
- Automatic capture is public-API best effort. Force-quit, restart-before-first-unlock, permissions, real ES80 restoration/reconnect, and background location behavior still require real-device evidence.
- Explore domain foundations do not select a road-graph provider or license. No road may be marked covered without accepted map-matched evidence.
