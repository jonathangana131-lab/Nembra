# Nembra 1.0 cockpit experience continuity

Status: active cockpit workstream recovery authority. Update after every
meaningful pushed checkpoint and before pausing or handing off.

## Resume protocol

1. Work only in a dedicated worktree for branch
   `agent/cockpit-1-0-redesign`; never edit the integration or portrait
   worktrees directly.
2. Read `AGENTS.md`, `DEVELOPMENT_CONTINUITY.md`, this file,
   `docs/NEMBRA_V2_PRODUCTION_FOUNDATION.md`,
   `docs/design-reference/horizon-v4-final/NEMBRA_HORIZON_V4_PRODUCTION_HANDOFF.md`,
   and `docs/design/references/COCKPIT_DRIVE_STUDIES.md` completely.
3. Fetch `origin/product/capture-1-0-main-20260818`; inspect branch divergence,
   the cockpit PR, integration PR #3675, and exact-head CI before editing.
4. Continue the exact next action below. Do not revive V2/V3/V4 geometry or
   duplicate Capture/BLE protocol discovery.

## GitHub state

- Repository: `jonathangana131-lab/Nembra`
- Cockpit branch: `agent/cockpit-1-0-redesign`
- Integration target: `product/capture-1-0-main-20260818`
- Integration PR: [#3675](https://github.com/jonathangana131-lab/Nembra/pull/3675)
- Branch base at worktree creation: `cf817a8b1c1f74640055af317671497a202e4f74`
- Latest pushed cockpit checkpoint recorded here:
  `8671b285061f62983a590f6a27cd0fed725cb8a1`
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

## Work in progress

- Native Drive recomposition has not started. The audit/design inputs are
  remotely recoverable at `8671b285…`. This continuity-only synchronization is
  the sole local change before the next push.

## Validation and CI truth

No cockpit-branch build/test has run yet. Local Xcode 26 is not release authority.

The base integration head `cf817a8b…` has green Capture software lanes but a red
main product run `32310434323`. That failure belongs to the shared base: portrait
contrast/Ride accessibility plus a Dashboard pre-tap animation-idleness timeout.
It is baseline evidence only and does not validate this branch. Artifact:
`9386781377` (`a51913e14e2ce7ed62bc4606be15819d894046e222e0cfad8544d6b8cbecc519`).

## Known blockers

### Code work

- Current Dashboard composition must be replaced while preserving stable public
  accessibility identifiers and slow/high-frequency observation separation.
- The Simulator-only power adapter currently has no production physical power
  source; physical UI must remain unavailable until the Capture lane publishes a
  verified typed source.
- Current battery UI duplicates detached adaptive-range copy and uses a generic
  silver fill; it violates the new one-value Home-derived contract.
- The base Drive test can wait indefinitely for SwiftUI animation quiescence;
  the new render slice must prove its animation schedule unmounts at steady state.

### External / evidence

- GitHub-hosted Xcode 27 runner capacity and exact-head screenshot/performance
  evidence are required for acceptance.
- Physical BLE/background/reconnect claims require the separate Capture lane and
  real-device evidence. Simulator results are never physical authority.
- No licensed/versioned road-graph provider is selected, so Explore cannot claim
  city coverage from MapKit presentation geometry.

## Exact next executable action

1. Replace the current Drive slow layer and power geometry in
   `NembraApp/Features/Dashboard/DashboardView.swift`,
   `SpeedInstrumentModel.swift`, and `RollingSpeedValueView.swift` while retaining
   typed truth boundaries and the narrow render island.
2. Update focused app/UI/source tests for one-value battery semantics, zero/NOW/
   peak power clarity, geometry bounds, idle timeline shutdown, and rejection of
   detached range/fantasy scale.
3. Run parsers, focused SwiftPM/app tests, `git diff --check`, and a scope/secret
   audit; commit/push/verify, then request the exact-head Xcode 27 workflow.
4. Inspect the retained iPhone 12 landscape screenshots and Release metrics before
   widening into Navigation.

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
