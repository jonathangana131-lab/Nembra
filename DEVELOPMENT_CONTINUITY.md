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
- Latest pushed implementation checkpoint recorded here: `a381a30fd9c321120a6fd5998785d6ce2b1acc4b`
- Latest pushed visual-authority/continuity checkpoint recorded here: `188a9b260ed12f4fd34867c13984a55ea4a1f7ef`
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

Checkpoint `a381a30f…` is the current pushed Home/evidence candidate. It closes the three failures proven by exact run `32290421627` and implements the first focused Home energy-material correction without claiming visual acceptance:

- `NembraUITests/NembraUITests.swift` terminates the intentionally continuous render-stress fixture after its preserved 3×6-second measurement, post-update proof, QA screenshot, and metrics rather than waiting for impossible XCUI animation quiescence. Independent exact-scene portrait restoration coverage remains unchanged.
- `NembraApp/App/AppRootView.swift` gives the explicit read-only Ride timeline label/value node the full existing padded-row accessibility focus shape without adding a button trait or changing layout.
- `NembraApp/Features/Home/HomeView.swift` adds a synchronous, input-driven engineered battery Canvas with truthful SOC fill, SOC-clipped graphite copy well, gold/red dimensional fill, fine clipped ribs, metallic shell/rim/terminal, state-aware typography/contrast, early large-text reflow, a measured current-asset copy corridor, and separate blurred tire/deck/ambient/gold/floor grounding layers. It shortens the standard hero to restore populated-row/tab clearance and applies native glass only to the actionable saved-ride continuation.
- `NembraApp/DesignSystem/NembraVisuals.swift` uses a stable dark Nembra fallback and boundary under Reduce Transparency/Show Borders rather than an adaptive light surface that could erase white glyphs.
- `NembraUITests/NembraUITests.swift` adds standard accessibility auditing (including contrast), explicit Accessibility XXXL reachability/screenshots, and retained/low-battery contrast audits.
- Focused source contracts are updated under `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityControlLayoutSourceTests.swift`, `HomeAccessibilityMetricLayoutSourceTests.swift`, and `RideWindowNavigationClearanceSourceTests.swift`.

Local proportional evidence for `a381a30f…`: all seven changed Swift files parse; `git diff --check` passes; six focused Swift Testing source tests pass; and a diagnostic local Swift 6 strict-concurrency `build-for-testing` compiled the app, unit-test, and UI-test targets. This local Xcode 26.1 result is not release authority.

## Work in progress

No intentional source or documentation change is local-only at this checkpoint. The coherent code candidate is pushed as `a381a30fd9c321120a6fd5998785d6ce2b1acc4b`; continuity commit `188a9b260ed12f4fd34867c13984a55ea4a1f7ef` records it.

Hosted evidence is in progress and is not yet transferable:

- `Xcode 27 Simulator QA` run [`32306198999`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32306198999) is queued for exact `a381a30f…`.
- `Capture V16 Standalone Exact-Head` run [`32306199002`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32306199002), `Capture Field Build Provenance` run [`32306198992`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32306198992), and `Capture Standalone Visual Evidence` run [`32306199106`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32306199106) are running/queued at the same exact code SHA.
- `Capture TODAY Field Candidate Preflight QA` run [`32306199026`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32306199026) and `Capture TODAY Final GO QA` run [`32306199112`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32306199112) are green at exact `a381a30f…`; they remain nonphysical/non-authorizing contract evidence.

Do not call the Home correction visually accepted from source or local-build evidence. The first exact Xcode 27 runtime screenshots must be compared directly with the selected Home reference, and the current temporary ES80 asset still blocks final visual/provenance acceptance.

## Exact CI and retained evidence

The current implementation checkpoint is `a381a30fd9c321120a6fd5998785d6ce2b1acc4b`. Its exact-head main/Capture workflows are listed under Work in progress above. Only the two Ubuntu Capture contract lanes are currently green; the Xcode 27 product and standalone evidence lanes are pending and control acceptance.

The detailed results below are scoped to ancestor checkpoint `1095f367c8d6ae7bc9f41b1bec4ede47fe055539`. They are retained root-cause/baseline evidence only and do not transfer to `a381a30f…`.

- `Capture TODAY Field Candidate Preflight QA` run `32290421595` — **green**; non-authorizing prerequisite/custody validation only.
- `Capture TODAY Final GO QA` run `32290421666` — **green**; hardened authority-contract validation only, not physical GO.
- `Capture Standalone Visual Evidence` run `32290421585` — **green**.
  - Artifact `9381672370`, archive digest `sha256:a47241…c088`.
  - Exact iPhone 12/iOS 27; standard and AX XXXL PNG digests independently verified.
  - Empty private lock and physical/protocol authority false.
- `Capture V16 Standalone Exact-Head` run `32290421563` — **green**.
  - Artifact `9382139203`, archive digest `sha256:f6fcca…cc87b`.
  - Xcode 27.0 `(27A5228h)`, Swift 6.4, exact iPhone 12/iOS 27.
  - xcresult: 13/13 UI tests passed; 13 unique retained synthetic screenshots; no physical/Bluetooth/Tuya authority.
- `Capture Field Handoff Provenance` run `32290421648` — **green**. Canonical procedure/native grep and public-handoff checks passed; 12 Python + 39 Swift tests passed. `PRIVATE_REVIEW_AUTHORITY` remained unset; no private pods, device build/install, Bluetooth, or physical authority ran.
- `Xcode 27 Simulator QA` run `32290421627` — **red**.
  - Artifact `9382766126`, digest `sha256:faad966b7aa56e1b360ed29b7e88d26d2ff0436e03681b6517f455a4aef7e750`.
  - Exact environment: checkpoint `1095f367…`, Xcode 27/iOS 27/iPhone 12.
  - Core 1,353/1,353 and app/unit 76/76 passed; xcresult total 93 passed / 3 failed.
  - Battery-toggle and Drive entry/portrait-restoration tests passed. The sustained render test collected three Debug clock samples (5.911647, 5.925257, 5.954871 seconds), then its post-measurement Home tap waited 60 seconds for ongoing stress-animation quiescence and exceeded the 120-second test allowance. This is a fixture shutdown/idleness defect, not a proven hitch-threshold failure.
  - Ride accessibility Dynamic Type now passes; the audit fails `.hitRegion` on the read-only 266×18-point Started/date timeline node. It needs appropriate noninteractive accessibility grouping/semantics, not a fake 44-point control.
  - The populated Home continuation row ends at y=772.667 while the native tab begins at y=761, overlapping by 11.667 points and missing the required 8-point breathing room by 19.667 points. The populated screenshot was correctly withheld.
  - Release performance did not run. There are no real Hitch Time Ratio samples, direct screenshot matrix, Release xcresult/log, or dashboard performance evidence; validator self-test fixtures are not runtime evidence.

Historical evidence useful for root cause only:

- Exact `45d020fa…` run `32275420710`, artifact `9378517919`, proved Core 1,353/1,353 and app/unit 76/76, but failed two Dashboard idle timeouts and one Ride Dynamic Type audit. Its `Selected Portrait Home - Simulator QA Only` attachment is the functional screenshot that exposed the flat battery, temporary grey/red scooter, copy occlusion, weak grounding, and shallow material response. It is explicitly not the Home 1.0 visual-acceptance image. Checkpoint `1095f367…` contains the bounded runtime fixes; `a381a30f…` contains the subsequent Home/evidence correction. Ancestor evidence is not merge authority.

## Known blockers

### Code/CI work

- Validate exact `a381a30f…` on GitHub-hosted Xcode 27. Source work for all three failures in run `32290421627` is pushed, but only the new runtime can prove stress-fixture shutdown, the Ride read-only hit region, populated Home/tab clearance, standard/retained/low-battery contrast, and Accessibility XXXL reachability.
- Inspect the exact-head Home screenshots beside `docs/design-reference/nembra-1.0-gold-glass/selected-home-gold-glass.png` on one same-viewport comparison canvas. Source geometry is not visual acceptance.
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

1. Monitor exact `a381a30f…` `Xcode 27 Simulator QA` run `32306198999` through terminal status. Download its artifact and verify source SHA, Xcode/iOS/iPhone 12 identity, Core/app/unit/UI results, Release clock + Hitch Time Ratio samples, direct screenshot matrix, retained attachments, and any accessibility issue element.
2. Monitor the three exact `a381a30f…` Capture Xcode lanes listed above. Treat queue/cancellation separately from test failure and preserve the physical/private NO-GO boundary.
3. If the product run is green, place its unscrolled deterministic `Selected Portrait Home - Simulator QA Only` screenshot beside `docs/design-reference/nembra-1.0-gold-glass/selected-home-gold-glass.png` on one 390×844 logical comparison canvas. Inspect battery ribs/shell/copy-well contrast, scooter/text intersections, grounding, functional glass, populated-row/tab clearance, and all state screenshots. Record visible mismatches; do not infer fidelity from source.
4. If the product run is red, apply only the narrow evidenced fix in the files named by the failure. Preserve the passing battery-toggle, exact-scene portrait restoration, telemetry truth, daily continuity, and performance gates.
5. Before every new checkpoint, run parsers, `git diff --check`, the three focused source suites, and a secret/scope audit; commit/push intentionally, verify the remote branch SHA, then update this file and PR #3675 again.
6. Do not merge until every exact-current-head gate is green and inspected. Home remains visually unfinished while the temporary unlicensed/low-resolution ES80 asset is present even if functional CI turns green.

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

- The `a381a30f…` stress-fixture termination is statically verified and preserves measurement evidence, but exact Xcode 27 must prove the sustained test exits within allowance and the Release metric validator receives real samples.
- The V4 pixel execution is no longer visual authority. Existing Drive/Nav/Explore screenshots can prove functionality and rejected traits only; a new production composition study/selection and later exact-head screenshots are required.
- Ride Window explicit row semantics and full padded accessibility shape still need the exact Xcode 27 audit.
- The pushed Home hero measurements support a conservative >20-point copy corridor for the current temporary asset at the default iPhone 12 state, but only fresh same-state screenshots and hosted accessibility audits can prove real non-occlusion/contrast. Source literals and parser tests are not visual acceptance.
- The current 500×500 `ES80Side` presentation asset is linked to AOVOPRO's official product page but is not production-cleared: the exact source/hash, retrieval date, masking steps, author/license, and written reproduction permission are missing. The user has also rejected its low-resolution grey/red treatment as final. A replacement needs a user-owned actual-scooter photo or written licensed high-resolution source, full provenance, truthful geometry, and visual review.
- Battery microtexture, dimensional shell/rim, adaptive typography/contrast, SOC-clipped copy well, floor/contact lighting, and actionable continuation glass are implemented as the `a381a30f…` candidate but are not visually or performance accepted until exact Xcode 27 screenshots/audits are inspected.
- The new standard, retained, low-battery, and Accessibility XXXL Home audits need exact Xcode 27 execution at the current implementation SHA.
- Production numeric adaptive range remains unavailable because no accepted physical estimator/identity/evidence pipeline is wired. Do not synthesize the reference image's `8.4 mi`.
- Automatic capture is public-API best effort. Force-quit, restart-before-first-unlock, permissions, real ES80 restoration/reconnect, and background location behavior still require real-device evidence.
- Explore domain foundations do not select a road-graph provider or license. No road may be marked covered without accepted map-matched evidence.
