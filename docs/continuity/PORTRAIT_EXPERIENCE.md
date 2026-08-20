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
  `1149ea9babb7a49fd52cb927826b4a0a59c12820` (remote-verified).

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

No intentional source, reference, or design-contract change is local-only after
that implementation commit. This continuity-only update follows it; recover by
checking out the remote portrait branch, then compare its current HEAD with the
implementation SHA above.

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

Current proportional local evidence: all three touched Swift files parse;
`git diff --check` passes; focused Home source tests pass 5/5; inherited Ride
Window source test passes 1/1; the reference hash is exact; the secret/private
path scan is clean; and a diagnostic generic-Simulator strict-concurrency
`build-for-testing` completed with exit 0 after the final large-text reflow.
Local Xcode 26 is never release authority.

No exact-head hosted Xcode 27 evidence exists for `1149ea9b…` yet. The cf817
artifact below remains baseline/root-cause evidence only.

## Blockers

- **Code/CI:** exact-head Xcode 27 must prove contrast, XXXL reflow, first-fold
  geometry, retained truth, Ride accessibility, and screenshots.
- **User/asset rights:** final Home needs a user-owned/commissioned high-resolution
  actual ES80 side photo or written AOVOPRO permission with full provenance.
- **Capture/BLE:** physical fields remain unavailable until the Capture/BLE
  workstream publishes verified decoders. This does not block honest unavailable
  portrait states.
- **GitHub:** custom Xcode 27 capacity may queue. Queue delay is not failure.

## Exact next executable action

1. Open/update the draft portrait PR targeting
   `product/capture-1-0-main-20260818` and synchronize its body with this file.
2. Dispatch the branch-local `xcode27-simulator.yml` workflow at exact
   `1149ea9b…`; verify the Mac job actually runs rather than accepting a
   classifier-only green shell.
3. For local recovery or preflight, run:

   ```sh
   xcrun swiftc -frontend -parse NembraApp/DesignSystem/NembraVisuals.swift
   xcrun swiftc -frontend -parse NembraApp/Features/Home/HomeView.swift NembraUITests/NembraUITests.swift
   swift test --package-path Packages/NembraCore --filter HomeAccessibilityMetricLayoutSourceTests
   git diff --check
   ```

4. While hosted evidence runs, extract the Home energy/status leaf views to
   narrow Observation invalidation without changing truth contracts.

## Rejected approaches

- Do not revive V2/V3/V4 cockpit pixels in portrait; cockpit visuals are a
  separate workstream and V4 is requirements-only.
- Do not use `VehicleHeroView.swift`'s legacy generated/vector scooter as the
  selected Home foundation.
- Do not recolor or AI-upscale the temporary ES80 raster into invented hardware.
- Do not use custom blur stacks, glass-coat passive telemetry, or restore the
  doubled top-control ring.
- Do not derive range from SOC × advertised distance or put fixture values into
  production.
- Do not duplicate Capture/BLE work.

## Unverified assumptions and evidence required

- The canonical icon-only `Label` is expected to eliminate the SF-symbol-named
  audit node; only Xcode 27 can confirm it.
- The opaque instrument token and deeper copy well are expected to preserve
  contrast on all SOC fills; visual and accessibility evidence is pending.
- Production adaptive range remains unwired; `Unavailable` is currently correct.
- The current Home may still invalidate too broadly on live VehicleStore state;
  a value-input leaf extraction and hosted performance evidence remain pending.
