# Nembra 1.0 cockpit experience continuity

Status: integrated Cockpit scope recovery authority under the unified release
owner. Update after every meaningful pushed Cockpit checkpoint and before
pausing or handing off.

## Resume protocol

1. Resume in the dedicated unified worktree on branch
   `release/nembra-1-0-unified`. The predecessor
   `agent/cockpit-1-0-redesign` branch is preserved as provenance, not an active
   implementation branch.
2. Read `AGENTS.md`, `DEVELOPMENT_CONTINUITY.md`, this file,
   `docs/NEMBRA_V2_PRODUCTION_FOUNDATION.md`,
   `docs/design-reference/horizon-v4-final/NEMBRA_HORIZON_V4_PRODUCTION_HANDOFF.md`,
   and `docs/design/references/COCKPIT_DRIVE_STUDIES.md` completely.
3. Fetch `origin/release/nembra-1-0-unified`; inspect the unified draft PR,
   predecessor PRs #3675/#3676/#3677, and exact-head CI before editing.
4. Continue the exact next action below. Do not revive V2/V3/V4 geometry or
   duplicate Capture/BLE protocol discovery.

## GitHub state

- Repository: `jonathangana131-lab/Nembra`
- Active unified branch: `release/nembra-1-0-unified`
- Preserved predecessor branch: `agent/cockpit-1-0-redesign`
- Integration target: `main`
- Integration PR: [#3675](https://github.com/jonathangana131-lab/Nembra/pull/3675)
- Branch base at worktree creation: `cf817a8b1c1f74640055af317671497a202e4f74`
- Latest pushed cockpit design/continuity checkpoint recorded here:
  `71fe1c4cb2bf0c8ed3a1476eab75970ee7ab49b6`
- Latest pushed cockpit implementation checkpoint recorded here:
  `85dc4b70b7981502bd909dd6d7c628f7e8e4c700`. Local and remote branch refs
  were verified equal after push.
- Latest unified implementation containing this checkpoint and its pre-CI
  hardening: `68b4eaa7a58483aa9ec660d1393f2960c8413aad`.
- Cockpit PR: [#3676](https://github.com/jonathangana131-lab/Nembra/pull/3676)

A Git commit cannot embed its own SHA without changing that SHA. This file
records the latest pushed coherent implementation checkpoint it has audited;
the remote branch ref is the final authority for a later continuation-only
commit.

## Ownership and coordination

This branch owns the landscape phone-mount Cockpit/Drive, later Navigation and
Explore transformations, their presentation/data seams, tests, evidence, and
truthful feature lab. It may make narrowly necessary shared visual-contract or
entry wiring changes, but it does not own portrait Home, Rides, Vehicle, or
Settings.

The original Nembra task remains the sole Capture/BLE discovery workstream. This
branch consumes only typed, evidence-backed interfaces and fixtures it publishes.
It must not infer or promote physical speed, power, battery, odometer, mode,
light, lock, error, characteristic, DP, unit, scale, cadence, or signedness.
Unknown and stale states stay explicit.

## Current focused aspect and acceptance gate

Active aspect: a complete Drive vertical slice based on the internal refined
Energy Chamber composition, with a one-value battery, giant rolling speed,
unmistakable accepted-power NOW locator, durable ride facts, automatic-recording
truth, native control glass, narrow render invalidation, accessibility, and
performance evidence.

Drive is not accepted until an exact pushed head passes on GitHub-hosted Xcode
27/iPhone 12/iOS 27 and retained evidence proves:

- one engineered battery displays percentage by default or accepted range after
  tap, never both; SOC alone controls fill;
- speed uses accepted currentness/provenance and display-only interpolation with
  no invented sensor cadence or precision;
- power shows accepted watts only, explicit currentness, zero origin, positive
  propulsion direction, a non-color-only NOW position, restrained active segment,
  and a distinct accepted peak; no fantasy signed/rated/throttle/regen scale;
- Today, ride duration, odometer, connection, and automatic recording remain
  typed, qualified, and durable or explicitly unavailable;
- every visible/empty/retained/reconnecting/error state fits real landscape safe
  areas and has 44-point controls, VoiceOver, increased-contrast, Reduce Motion,
  and Reduce Transparency behavior;
- the high-frequency speed/power island does not invalidate slow chrome/ledger,
  stops all idle timelines, and passes the Release clock/Hitch Time Ratio gate;
- a same-state implementation screenshot is placed beside the current internal
  lead and reviewed; the first runnable layout is not completion.

Navigation and Explore remain blocked from implementation widening until Drive
meets this gate.

## Completed work

- Created an isolated worktree from exact integration head `cf817a8b1…` on
  `agent/cockpit-1-0-redesign`.
- Inspected the selected Home language, user-named promising Drive image, rejected
  V4 navigation screenshot, exact current Xcode 27 Drive runtime attachment, and
  current Dashboard/Speed/Energy Rail source.
- Copied four 1844 x 853 internal Drive studies into
  `docs/design/references/` and recorded SHA-256 provenance, rejection boundaries,
  comparison, and the refined Energy Chamber as the current internal lead in
  `docs/design/references/COCKPIT_DRIVE_STUDIES.md`.
- Completed a repository-grounded telemetry and product-wiring audit in
  `docs/continuity/COCKPIT_CAPABILITY_MATRIX.md`. Ordinary production remains
  deliberately fail-closed; positive scooter telemetry currently exists only
  behind explicit Simulator QA seams.
- Classified Navigation, Explore, auto-recording, route replay/export,
  analytics, range, parking, maintenance, Live Activities, coverage, and
  unsupported health/theft/crash claims in
  `docs/continuity/COCKPIT_FEATURE_LAB.md`, including exact input, confidence,
  privacy, energy, failure, and fabrication boundaries.
- Audited the SwiftUI architecture and retained the exact-scene orientation
  authority, package truth domains, one-value battery state, accepted-value
  interpolation, slow snapshot bridge, and isolated fast instrument surface.
  The V4 composition, detached range, capsule battery, extreme 32-tick arc,
  nested digit animations, and ambiguous Simulator power rendering are marked
  for replacement.
- Pushed the complete post-V4 study/provenance, capability, feature-lab,
  cross-surface contract, and recovery checkpoint as `8671b285…`; verified the
  remote branch ref matched exactly and opened draft PR #3676 against the
  integration branch.
- Confirmed the current app is still structurally V4: detached adaptive-range
  copy, generic silver capsule battery, extreme raised 32-tick arc, uppercase
  metric strip, and ambiguous rail marker. Its truthful state and render-island
  foundations are reusable; its composition is not.
- Replaced that inherited V4 Drive composition in the working tree with the
  first post-V4 vertical slice while preserving the exact-scene session owner,
  slow snapshot bridge, typed evidence domains, and stable public identifiers:
  - `NembraApp/Features/Dashboard/DashboardView.swift` now provides a deep
    black/floor field, quiet top chrome, one Home-derived engineered battery,
    no detached range readout, honest recording/ledger language, and native
    grouped Liquid Glass only for the Home/Navigate controls.
  - The battery renders exactly one value (percentage by default, accepted
    range/learning/unavailable after tap), keeps SOC as the sole fill meaning,
    uses a graphite shell/rim/terminal, clipped gold or semantic-low ribs, a
    dual-contrast label at the true SOC edge, persisted mode, Reduce Motion,
    app-controlled haptics, VoiceOver alternate action, and normal/high accepted
    range confidence without inventing the reference image's `8.4 mi`.
  - `SpeedInstrumentModel.swift` now separates accepted NOW position from local
    illumination settling and accepted recent peak, with an explicit zero,
    positive direction, non-color-only diamond locator, hollow distinct peak,
    source-bound accepted watts, and visibly synthetic `QA SCALE · 650 W` only
    under the sealed Simulator authority. Retained/unavailable states expose no
    live position or inferred zero.
  - `RollingSpeedValueView.swift` uses licensed system SF, tabular rolling digits,
    2/3-digit capacity, unit-independent canonical presentation bounds, and no
    nested per-digit animation. Unit preference/locale are resolved outside the
    render timeline. The high-frequency timeline is mounted only while accepted
    speed or power presentation is settling and disappears at steady state.
  - `AppBootstrap.swift` now compile-gates positive simulation selection to an
    iOS Simulator runtime, including explicit launch arguments/environment;
    Release Simulator performance fixtures remain possible while physical
    iPhones cannot select synthetic vehicle authority.
  - `NembraAppTests.swift` and `NembraUITests.swift` add source-to-store power
    receipt custody, one-value battery, confidence, peak-visibility, retained/
    unavailable, speed capacity/unit, bounded geometry, idle schedule, truth-
    claim rejection, iPhone landscape frame, Accessibility XXXL, audit, screenshot,
    and existing Release hitch-path coverage. Historical V4 XCTest selector names
    remain only as workflow ABI and explicitly test the post-V4 implementation.
  - The final precommit hardening adds a bounded `99:59:59` Drive duration
    formatter, rejects huge/NaN/infinite values without integer conversion,
    retires both speed and accepted-power Timeline windows under test, proves a
    real Store `live -> retained` power transition removes every live locator,
    gives Accessibility XXXL a genuine two-band footer, maintains an audit-safe
    secondary-text contrast floor, and asserts identity/speed/power/ledger frame
    separation at the real landscape accessibility size.

## Work in progress

The Drive implementation above is integrated and remote-recoverable at unified
checkpoint `1847627d7c84b62e4f6a9633886d0e3dd756ddfc`. Its owned source/test scope
is:

- `NembraApp/App/AppBootstrap.swift`
- `NembraApp/Features/Dashboard/DashboardView.swift`
- `NembraApp/Features/Dashboard/RollingSpeedValueView.swift`
- `NembraApp/Features/Dashboard/SpeedInstrumentModel.swift`
- `NembraAppTests/NembraAppTests.swift`
- `NembraUITests/NembraUITests.swift`
- `docs/continuity/COCKPIT_EXPERIENCE.md`
- `DEVELOPMENT_CONTINUITY.md`

The unified integration preserved Portrait and Capture work, semantically
combined shared app/UI tests and UI contracts, omitted only byte-identical
duplicate study rasters, and added a physical-device fail-closed test guard for
Simulator launch parsing. No production telemetry authority was widened.

Unified pre-CI commit `68b4eaa7a58483aa9ec660d1393f2960c8413aad`
then closes four review risks without widening Cockpit scope:

- accepted watts and admitted scale now determine the sole accepted NOW
  fraction within a narrow numeric tolerance; above-envelope accepted watts
  remain exact and saturate the marker at one;
- speed and Energy Rail use explicit non-overlapping vertical regions that
  reserve the top identity and bottom durable ledger at standard and
  Accessibility XXXL iPhone 12 landscape sizes;
- sighted Energy Rail value/microcopy responds to Dynamic Type within bounded
  mounted-display geometry while the full combined VoiceOver value remains
  authoritative;
- the Accessibility XXXL UI test has one failure-safe terminal cleanup rather
  than issuing a duplicate termination after its kept screenshot.

Swift parser and diff checks pass. Local diagnostic build/tests were running at
this continuity write; only their terminal result may be claimed later. Exact
Xcode 27 runtime, screenshot, accessibility, and Release performance evidence
remain required.

## Validation and CI truth

Current working-tree static evidence:

- `xcrun swiftc -frontend -parse` passes for all six changed Swift files;
- `git diff --check` passes;
- focused NembraCore battery, propulsion, rolling-number, speed telemetry, and
  interpolation tests passed 49/49 across five suites with zero failures;
- local Xcode 26.1 generic-Simulator app build exited 0 under
  `SWIFT_STRICT_CONCURRENCY=complete` and the iOS 26 deployment override;
- a fresh strict `build-for-testing` against the unchanged six-file source/test
  candidate diff
  `c291e740a274b2deb5ab4c97fe719fbe961cb3ef4e2c36110543fb9b25e63458`
  exited 0 and compiled the app, `NembraAppTests`, and `NembraUITests` with no
  Swift or strict-concurrency warnings/errors;
- focused app-test execution did not run: local iOS 26.1 is below Nembra's iOS
  27 deployment target and `test-without-building` exited 70 before test-body
  execution. This is an environment limitation, not a passing test claim.

Local Xcode 26 is diagnostic compile evidence only and is never release authority.
No exact implementation-head Xcode 27 build, landscape screenshot, accessibility
audit, or Release clock/Hitch Time Ratio evidence exists yet.

The base integration head `cf817a8b…` has green Capture software lanes but a red
main product run `32310434323`. That failure belongs to the shared base: portrait
contrast/Ride accessibility plus a Dashboard pre-tap animation-idleness timeout.
It is baseline evidence only and does not validate this branch. Artifact:
`9386781377` (`a51913e14e2ce7ed62bc4606be15819d894046e222e0cfad8544d6b8cbecc519`).

## Known blockers

### Code work

- A future physical `.scooterBluetooth` or `.gps` speed source must not be enabled
  merely because it carries an absolute sample. It first needs a typed,
  source-specific and tested plausibility/accuracy/latency/precision policy. The
  current `999.94 km/h` bound is display capacity only, not vehicle validation.
- A future numeric adaptive-range runtime must bind its live estimate and the SOC
  fill to the same accepted/current battery owner (or define and test an explicit
  value-with-fill-unavailable state). Root currently injects `nil`, so production
  is safely unavailable.
- The two/three micro-tick confidence treatment is typed and non-color-only but
  its sighted glanceability is unaccepted until a hosted screenshot/audit proves
  it; revise from visual evidence rather than adding an unexplained caption now.
- The Simulator-only power adapter still has no production physical power source;
  physical UI remains unavailable until Capture publishes a verified typed source,
  source scale/envelope, receipt cadence, and currentness contract.
- The power rail's tiny sighted microcopy is intentionally secondary and its full
  meaning exists in one scalable accessibility value, but the exact hosted
  Accessibility XXXL screenshot/audit must still prove that the simplified visual
  hierarchy remains legible. Do not weaken frame/contrast/dynamic-type assertions
  if it does not.

### External / evidence

- GitHub-hosted Xcode 27 runner capacity and exact-head screenshot/performance
  evidence are required for acceptance.
- Physical BLE/background/reconnect claims require the separate Capture lane and
  real-device evidence. Simulator results are never physical authority.
- No licensed/versioned road-graph provider is selected, so Explore cannot claim
  city coverage from MapKit presentation geometry.

## Exact next executable action

1. Finish the unified static/focused checks and any reviewed P0/P1 preflight
   fix; push and update both this scope ledger and root continuity.
2. Create the unified draft PR to `main`, then explicitly dispatch
   `xcode27-simulator.yml` at the exact final unified SHA. Do not use the current
   default-branch `/xcode27` wrapper as Release-performance authority.
3. Download the exact-head artifact and verify source SHA,
   Xcode 27/iOS 27/iPhone 12 identity, Core/app/UI results, Accessibility XXXL,
   one-value battery interaction, landscape frame containment, three sustained
   render intervals, actual Release clock + Hitch Time Ratio samples, and
   retained post-V4 screenshots.
4. Put the same-state runtime Drive screenshot beside the refined internal study
   in one comparison canvas, record visible mismatches, and iterate Drive. Do not
   widen into Navigation or Explore until the Drive acceptance gate is met.

## Rejected designs and approaches

- Horizon V2, V3, and V4 PNGs are requirements/history evidence only. Never
  restore their cards, giant navigation overlay, silver battery pill, detached
  range, clipped arc, mega-pill ledger, small mode segment, or map/gauge collision.
- `cockpit-drive-energy-chamber-study.png` is promising visual input, not a pixel
  authority. Its `-18 / 18 kW`, `7.2 kW`, and `12.4 kW` values are rejected and
  unsupported.
- No first runnable composition is a 1.0 completion claim.
- Do not glass-coat telemetry, put passive metrics in decorative cards, add fake
  throttle/regen controls, or animate/store display interpolation as evidence.
- Do not duplicate Capture/BLE discovery or use Simulator fixtures as physical
  truth.

## Unverified assumptions and required evidence

- The refined Energy Chamber remains only the strongest internal skeleton; real
  Xcode 27 screenshots may require spacing, type, contrast, and control changes.
- The current accepted speed and propulsion presentation domains appear reusable,
  but their app integration and idle behavior require branch-specific tests and
  hosted profiling.
- Production battery range is unavailable until the accepted adaptive-range
  runtime has real physical identity/evidence/currentness; reference `8.4 mi`
  cannot be injected into production.
- Production odometer, power, city coverage, mode, and automatic background
  restoration remain unavailable or qualified wherever upstream authority is
  absent.
- Navigation/Explore MapKit contracts exist, but no production overlay provider,
  licensed road dataset, route session, or scalable road renderer is yet wired.
