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
- Latest pushed implementation checkpoint recorded here: `1095f367c8d6ae7bc9f41b1bec4ede47fe055539`
- Recovery rule: after cloning, run `git rev-parse HEAD` and `git ls-remote origin refs/heads/product/capture-1-0-main-20260818`; if either differs from the SHA above, inspect newer commits and update this file before development.

The file cannot self-embed the SHA of the commit containing its own changed bytes. Therefore the SHA above names the latest pushed implementation checkpoint that this document has audited; the remote branch HEAD is the authority for any later continuity-only commit.

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

## Work in progress

The following local candidate is intentionally **not yet committed or pushed** while exact-head `1095f367…` Xcode 27 evidence is audited and the user-required Home hero correction is completed:

- `NembraApp/Features/Home/HomeView.swift`
  - standard Home hero remeasured toward the selected reference;
  - smaller standard header/control chrome, lifted/narrowed ES80 asset, widened battery body, retained hero clipping and gold grounding;
  - Dynamic Type-scaled battery number/percent through `@ScaledMetric`;
  - no change to telemetry authority, SOC fill meaning, or unavailable adaptive-range truth.
- `NembraUITests/NembraUITests.swift`
  - standard Home production accessibility audit;
  - explicit Accessibility XXXL Simulator-QA run with truth semantics, 44-point controls, scroll reachability, tab clearance, and top/bottom screenshots.
- `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityMetricLayoutSourceTests.swift`
  - source contracts for the measured Home geometry and runtime accessibility coverage.

This local geometry/accessibility batch is only a starting point. It does **not** yet implement the required battery microtexture/material depth, refined range typography, stronger approved ES80 render, complete non-occlusion proof, integrated floor lighting, or final native-glass response. Do not commit or call it visually complete in its present form.

Why uncommitted: the user explicitly rejected the current functional hero as the 1.0 visual target. The correction needs an asset-provenance decision and a measured implementation before it becomes a coherent remote candidate. Recovery if this task disappears before that push: start from pushed `1095f367…`, retain the runtime accessibility additions described above, and implement the full visual-acceptance list in this document; do not merely reproduce the current three-file geometry diff.

Local proportional checks already green for this candidate:

- `xcrun swiftc -frontend -parse` on all three changed Swift files.
- `git diff --check`.
- `swift test --package-path Packages/NembraCore --filter HomeAccessibilityMetricLayoutSourceTests` — 2/2 tests passed.

## Exact CI and retained evidence

All results below are scoped to exact checkpoint `1095f367c8d6ae7bc9f41b1bec4ede47fe055539` unless stated otherwise.

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

- Exact `45d020fa…` run `32275420710`, artifact `9378517919`, proved Core 1,353/1,353 and app/unit 76/76, but failed two Dashboard idle timeouts and one Ride Dynamic Type audit. Checkpoint `1095f367…` contains the bounded fixes. Ancestor evidence is not merge authority.

## Known blockers

### Code/CI work

- Fix exact run `32290421627` without weakening gates: stop/pause the Simulator stress source before post-measurement Dashboard exit, correct the noninteractive Ride timeline hit-region semantics, and restore at least 8 points of populated Home/tab clearance.
- Implement the complete Home visual correction above, including asset provenance, battery material/typography, zero occlusion, integrated grounding, and native functional-glass response.
- Compare the resulting fresh Home runtime screenshot beside `docs/design-reference/nembra-1.0-gold-glass/selected-home-gold-glass.png` at the same 390×844 logical viewport/state before visual acceptance.
- Push the coherent Home visual/accessibility candidate and rerun exact-head Xcode 27; its new runtime audits are not yet proven.
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

1. Fix the three proven exact-run defects from `32290421627`: bounded stress-fixture shutdown before Home exit, truthful noninteractive Ride timeline hit-region semantics, and populated Home continuation/tab clearance.
2. Preserve the passing battery-toggle, exact-scene entry/portrait restoration, Dynamic Type, Core, and app/unit contracts.
3. Use the current `ES80Side` only as a temporary truthful layout silhouette. Implement battery/layout/grounding independently; final visual acceptance remains blocked until the asset-rights requirement above is met. Preserve any new source/edit provenance and checksum in `docs/PRODUCTION_VISUAL_ASSET_PROVENANCE.md`.
4. Implement the focused Home hero correction in `NembraApp/Features/Home/HomeView.swift` and project assets. Keep SOC/range/currentness truth and the rest of Home unchanged.
5. Extend deterministic frame-intersection, state screenshot, Dynamic Type, and runtime accessibility evidence without substituting source-string tests for visual review.
5. Run:

   ```sh
   xcrun swiftc -frontend -parse \
     NembraApp/Features/Home/HomeView.swift \
     NembraUITests/NembraUITests.swift \
     Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityMetricLayoutSourceTests.swift
   git diff --check
   swift test --package-path Packages/NembraCore \
     --filter HomeAccessibilityMetricLayoutSourceTests
   ```

6. Create a same-viewport side-by-side comparison with the selected Home reference and inspect typography, battery texture/shell, approved scooter asset, non-occlusion, floor grounding, and native glass response together.
7. Update this file and PR #3675 with the exact result, commit only the coherent Home/continuity batch, push `product/capture-1-0-main-20260818`, and verify `git ls-remote` contains the commit.
8. Monitor the new exact-head Capture and main Xcode 27 workflows. Do not merge until every current-head acceptance gate is green and inspected.

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

- The `1095f367…` conditional Timeline/static branch is statically verified but still needs the exact Xcode 27 runtime to prove both prior idle timeouts are gone.
- The V4 pixel execution is no longer visual authority. Existing Drive/Nav/Explore screenshots can prove functionality and rejected traits only; a new production composition study/selection and later exact-head screenshots are required.
- Ride Window explicit row semantics still need the exact Xcode 27 Dynamic Type audit.
- The local Home hero measurements need a fresh same-state side-by-side screenshot comparison; source literals and parser tests are not visual acceptance.
- The current 500×500 `ES80Side` presentation asset is linked to AOVOPRO's official product page but is not production-cleared: the exact source/hash, retrieval date, masking steps, author/license, and written reproduction permission are missing. The user has also rejected its low-resolution grey/red treatment as final. A replacement needs a user-owned actual-scooter photo or written licensed high-resolution source, full provenance, truthful geometry, and visual review.
- Battery microtexture, dimensional shell/rim, adaptive typography/contrast, zero-copy-occlusion, integrated floor lighting, and richer native functional-glass response are not implemented or proven yet.
- The new standard and Accessibility XXXL Home audits need exact Xcode 27 execution after the candidate is pushed.
- Production numeric adaptive range remains unavailable because no accepted physical estimator/identity/evidence pipeline is wired. Do not synthesize the reference image's `8.4 mi`.
- Automatic capture is public-API best effort. Force-quit, restart-before-first-unlock, permissions, real ES80 restoration/reconnect, and background location behavior still require real-device evidence.
- Explore domain foundations do not select a road-graph provider or license. No road may be marked covered without accepted map-matched evidence.
