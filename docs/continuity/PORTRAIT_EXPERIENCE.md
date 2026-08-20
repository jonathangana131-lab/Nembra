# Portrait experience continuity

Updated: 2026-08-19

## Recovery authority

- Remote repository: `jonathangana131-lab/Nembra`
- Integration target: `product/capture-1-0-main-20260818`
- Portrait branch: `agent/portrait-home-1-0-polish`
- Isolated worktree directory name used by this task:
  `Nembra-portrait-home-1-0` (local path intentionally not committed).
- Rebased integration head:
  `3f0814ac70211f68b7af1a6913c78c91a810f663` (contains implementation
  checkpoint `0b7e3b27de5e9b547911558ae8ed4cb852becb59`).
- Latest pushed portrait implementation checkpoint:
  `15aff85c4a98abd5c37dfb12a677a1a8555de4df` (remote-verified).
- Latest remote branch tip verified before this continuity update:
  `15aff85c4a98abd5c37dfb12a677a1a8555de4df`.
- Draft portrait PR: [#3677](https://github.com/jonathangana131-lab/Nembra/pull/3677).

This file is the portrait workstream recovery authority. The root
`DEVELOPMENT_CONTINUITY.md` remains the integration-wide authority.

## Current focus and acceptance gate

Focus: finish the vertical Home page at production 1.0 quality before widening
to Rides, Vehicle, Settings, profile, or secondary sheets.

Current gate:

1. the unchanged connected, retained, low-battery, and Accessibility XXXL
   audits pass on exact-head GitHub Xcode 27 / iPhone 12 / iOS 27;
2. truthful Home connected/disconnected/loading/error/low/retained/ride states
   remain functional;
3. deterministic screenshots are compared at one viewport against the selected
   Home authority;
4. no scooter/text intersection, tab obstruction, fabricated range, or
   simulator-to-physical promotion occurs;
5. final visual acceptance remains blocked while the temporary ES80 raster is
   not high-resolution and production-cleared.

## Completed on the integration baseline

- Home projects authority-gated battery/range, durable Today, automatic ride
  state, confirmed vehicle commands, and durable latest ride.
- Native portrait shell and four tabs exist.
- Input-driven battery and grounding canvases have no perpetual idle timeline.
- Integration commit `0b7e3b27…` already removed the failing Ride Window
  labeled-pair accessibility nodes and strengthened retained/range contrast.
  Do not duplicate or cherry-pick those hunks.
- Exact cf817 failure/evidence details are retained in
  `docs/design/audits/HOME_VISUAL_GAP_AUDIT_2026-08-19.md`.

## Completed and pushed in the first portrait checkpoint

Implementation commit `1149ea9babb7a49fd52cb927826b4a0a59c12820` is
pushed and verified on `origin/agent/portrait-home-1-0-polish`:

- `NembraApp/DesignSystem/NembraVisuals.swift`: opaque portrait instrument copy
  and warning tokens;
- `NembraApp/Features/Home/HomeView.swift`: canonical icon-only `Label` for the
  Vehicle Controls glass button, token adoption, a deeper standard copy well,
  and a large-text reflow that moves unscaled range copy below the battery
  instead of allowing it to cross the gold fill;
- `NembraUITests/NembraUITests.swift`: the existing Accessibility XXXL fixture
  now runs unchanged contrast and text-clipping audits on the reflowed state;
- `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityMetricLayoutSourceTests.swift`:
  source regressions for those semantics;
- `docs/design/`, `docs/coordination/`, and this continuity record: preserved
  selected source, authority, explicit visual gaps, design system, and workstream
  boundaries.

## Completed and pushed in the render-isolation checkpoint

Implementation commit `15aff85c4a98abd5c37dfb12a677a1a8555de4df` is
pushed and verified on `origin/agent/portrait-home-1-0-polish`:

- `NembraApp/Features/Home/HomeView.swift`: replaces inline header/energy
  implementations with two narrow Observation bridges;
- `NembraApp/Features/Home/VehicleHeroView.swift`: removes the rejected unused
  generated/vector scooter implementation and now owns narrow Observation
  bridges, value-only header/energy snapshots, and Equatable render leaves;
- `NembraAppTests/NembraAppTests.swift`: adds tests asserting that
  speed/power/odometer/timestamp changes do not change the energy snapshot,
  while battery/readout mode and connection truth do;
- `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityMetricLayoutSourceTests.swift`:
  routes existing source contracts to their exact files and forbids stores,
  `@State`, or a perpetual timeline in the expensive renderer;
- this file, `docs/PRODUCTION_VISUAL_ASSET_PROVENANCE.md`, and
  `docs/coordination/UI_CONTRACTS.md`: recovery/provenance/coordination updates.

Recovery: checkout remote `agent/portrait-home-1-0-polish` at
`15aff85c4…`. No implementation change from this slice remains local-only. Do
not restore the removed legacy vector scooter code; it was rejected, unused,
and is not evidence of an ES80.

## Tests and CI

Latest completed baseline run:

- GitHub `Xcode 27 Simulator QA` run `32310434323`, exact cf817, artifact
  `9386781377`, digest
  `a51913e14e2ce7ed62bc4606be15819d894046e222e0cfad8544d6b8cbecc519`.
- Core 1,355/1,355 and app/unit 76/76 passed.
- Portrait failures: Vehicle Controls contrast, low-range qualifier contrast,
  retained percent contrast, and Ride `Ended` Dynamic Type. Integration 0b7
  owns all except the canonical Vehicle Controls semantics; exact-current-head
  evidence is still required.

Current render-isolation evidence: all four touched Swift files parse;
`git diff --check` passes; focused Home source tests pass 5/5; the
secret/private-path scan is clean; and a fresh diagnostic generic-Simulator
strict-concurrency `build-for-testing` completed with exit 0 for the app, unit,
and UI-test targets. The two new snapshot XCTest methods were compiled but were
not executed locally; exact-head hosted Xcode 27 must execute them. Local Xcode
26 is never release authority.

Exact-head hosted Xcode 27 workflow run
[`32318006928`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32318006928)
is terminal **failure** at remote tip `bec498463…`. It genuinely ran on Xcode
27.0 / iOS 27.0 / iPhone 12: Core passed 1,355/1,355; app unit passed 76/76;
UI passed 17/22. Portrait failures were Vehicle Controls contrast, low-battery
separator contrast, retained `%` contrast, and Ride timestamp Dynamic Type; the
fifth failure is cockpit-owned animation quiescence. Artifact
`nembra-xcode27-simulator-1365-1` is ID `9389149291`, digest
`aef19246aa9d9d782a343c138ab77c1a03a7a8560f282c707b4d3f5782063ff8`.
The run validates the first checkpoint only, not pushed isolation checkpoint
`15aff85c4…`, and it is not portrait acceptance.

## Blockers

- **Code/CI:** the four portrait-owned failures from run `32318006928` require
  code fixes and an exact-head rerun. Xcode 27 must also prove XXXL reflow,
  first-fold geometry, retained truth, snapshots, and render-island behavior.
- **User/asset rights:** final Home needs a user-owned/commissioned high-resolution
  actual ES80 side photo or written AOVOPRO permission with full provenance.
- **Capture/BLE:** physical fields remain unavailable until the Capture/BLE
  workstream publishes verified decoders. This does not block honest unavailable
  portrait states.
- **GitHub:** custom Xcode 27 capacity may queue. Queue delay is not failure.

## Exact next executable action

1. Fix the four portrait-owned failures from run `32318006928` against the
   current render-isolated implementation without weakening any audit. Run:

   ```sh
   xcrun swiftc -frontend -parse NembraApp/Features/Home/HomeView.swift NembraApp/Features/Home/VehicleHeroView.swift NembraAppTests/NembraAppTests.swift
   swift test --package-path Packages/NembraCore --filter HomeAccessibility
   xcodebuild -quiet -project Nembra.xcodeproj -scheme Nembra -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=26.0 SWIFT_STRICT_CONCURRENCY=complete build-for-testing
   git diff --check
   ```

2. Commit/push the focused accessibility correction, verify the remote SHA,
   update both continuity files and PR body, then dispatch exact-head
   `xcode27-simulator.yml` on the portrait branch.
3. The new run must execute the two snapshot unit tests and the unchanged
   Home/Ride production audits. Do not transfer ancestor run `32318006928` to
   the new SHA.

## Rejected approaches

- Do not revive V2/V3/V4 cockpit pixels in portrait; cockpit visuals are a
  separate workstream and V4 is requirements-only.
- Do not restore the removed legacy generated/vector scooter implementation;
  `VehicleHeroView.swift` now contains narrow Observation bridges and
  value-only Home render leaves, not an alternative hardware asset.
- Do not recolor or AI-upscale the temporary ES80 raster into invented hardware.
- Do not use custom blur stacks, glass-coat passive telemetry, or restore the
  doubled top-control ring.
- Do not derive range from SOC × advertised distance or put fixture values into
  production.
- Do not duplicate Capture/BLE work.

## Unverified assumptions and evidence required

- The canonical icon-only `Label` did not eliminate the hosted
  `slider.horizontal.3` contrast failure; the production control treatment
  needs a stronger pixel-level correction without hiding the audit node.
- The opaque instrument token and deeper copy well did not close every hosted
  state: low battery still fails on a separator and retained battery on `%`.
- Production adaptive range remains unwired; `Unavailable` is currently correct.
- The render-isolation slice is intended to keep battery/grounding Canvases
  unchanged across speed/power-only receipts. Source tests are green and the
  snapshot unit tests compile, but hosted execution/performance evidence is
  pending; do not claim whole-screen invalidation is solved because
  Today/controls/readiness remain broader.
