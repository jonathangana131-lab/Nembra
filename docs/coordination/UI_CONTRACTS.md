# Nembra cross-surface UI contracts

Status: shared coordination contract. Surface owners retain their own layout and
implementation files.

## Ownership

- Portrait owns Home, Rides, Vehicle, Settings, profile/secondary sheets, and
  portrait design tokens.
- Cockpit owns landscape Drive, Navigation, Explore, and cockpit-only
  geometry, motion, accessibility, and performance implementation.
- Capture/BLE owns hardware capture, raw evidence, confidence-rated protocol
  mappings/fixtures, and verified decoders.
- The unified release owner alone resolves shared root/bootstrap, persistence,
  workflow, project, test, and cross-surface contract changes.

Portrait does not edit `NembraApp/Features/Dashboard/` or
`DashboardSessionStore.swift`. Cockpit does not opportunistically refactor
portrait composition. Capture/BLE does not drive presentation with unverified
values. Shared-file changes require coordination before integration.

`NembraApp/App/AppRootView.swift` is shared by target membership, but
`RideHistoryDetailView.timelineRow` is portrait-owned. It deliberately exposes
one stacked pair of native semantic-font `Text` nodes and retains 72 points for
the Navigation launcher. Do not reintroduce duplicate `ViewThatFits` candidates,
combined nodes, or labeled-pair identities: exact Xcode 27 audited inactive
candidates and alternated Dynamic Type/hit-region failures.

## Product palette

Use the existing `NembraColor` values in
`NembraApp/DesignSystem/NembraVisuals.swift` without creating a competing
cockpit palette:

- gold `#EFBC58` for energy and active-route/discovery truth;
- active gold `#E5A83C` for restrained live illumination;
- deep gold `#9A5F18` for depth, not primary copy;
- graphite `#0B0B0A` and base black `#060706`;
- primary text `#F4F7FB`, secondary text `#8D98AA`;
- semantic system green only for healthy live connection and semantic red/yellow
  only for accepted warning/error policy.

Small text drawn over a variable energy material uses an opaque high-contrast
role; do not alpha-dim thin measurements.

## Battery contract split

- The physical fill always represents accepted state of charge.
- Portrait Home retains its selected simultaneous hierarchy: SOC is the primary
  percentage and accepted learned range may be shown as a separate qualified
  value. Unavailable remains explicit.
- Cockpit shows exactly one centered primary value inside one battery:
  percentage by default or accepted adaptive range after tap. It never shows
  simultaneous or detached range copy.
- Range unavailable, learning, retained, and currentness replace or qualify the
  applicable surface honestly; neither surface invents a number.
- The cockpit's engineered graphite/gold shell, inner rim, clipped micro-ribs,
  terminal, and state-aware copy inherit the selected Home material language in
  compact landscape geometry.
- VoiceOver announces current value, fill meaning, currentness, and the
  alternate action. Reduce Motion uses a static change/crossfade; haptics
  respect app and system preference.
- Neither surface may promote retained or Simulator battery evidence to current
  physical truth.

## Instrument typography

- Use licensed system SF typography only.
- Measurement digits share rounded/tabular SF DNA, deliberate optical spacing,
  and semantically scalable units/captions.
- Cockpit speed uses a stable fixed slot and a smaller decimal/unit on the same
  baseline without imitating proprietary Stark/Tesla typefaces.
- Telemetry captions use the same cool-grey hierarchy as portrait secondary
  information, with tracking reduced at large Dynamic Type sizes.

## Native material contract

- Native Liquid Glass belongs only to functional navigation/control chrome.
- Battery, speed, power, map, ledgers, and passive telemetry are content, not
  glass cards.
- Group neighboring glass controls in one `GlassEffectContainer`, keep 44-point
  targets and stable shapes/IDs, and use an opaque graphite Reduce Transparency
  fallback.

## Data boundary

Until Capture/BLE publishes a stable decoder/evidence contract, both surfaces
show unknown, unavailable, retained, or simulated values honestly and keep
dependent controls disabled. UI branches do not duplicate capture tools or
protocol inference.

## Portrait render isolation

- Home resolves connection and energy truth in narrow `@MainActor` Observation
  bridges, then hands plain Equatable snapshots to render leaves.
- The energy snapshot contains only authority-gated SOC/readout presentation,
  accepted adaptive-range decision, battery freshness, and the intentional
  persisted percentage/range emphasis. Speed, power, odometer, trip, vehicle
  ride/start mode, and commands must not enter it.
- The heavy battery/scooter/grounding renderer must not retain `VehicleStore`,
  `HorizonCockpitStore`, callbacks, `@State`, or a perpetual timeline.
- This boundary reduces passive hero redraws; it is not a claim that every Home
  section is isolated or that physical telemetry arrives at display cadence.
