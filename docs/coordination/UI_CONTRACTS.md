# UI workstream contracts

## Ownership

- `agent/portrait-home-1-0-polish`: portrait Home, Rides, Vehicle, Settings,
  profile/secondary sheets, and portrait design tokens.
- Cockpit workstream: landscape Drive, Navigation, Explore, and cockpit-only
  geometry/motion/performance implementation.
- Capture/BLE workstream: hardware capture, raw evidence, confidence-rated
  protocol mappings/fixtures, and verified decoders.

Portrait does not edit `NembraApp/Features/Dashboard/` or
`DashboardSessionStore.swift`. Capture/BLE does not drive presentation with
unverified values. Shared files require a note here or in the PR before edits.

## Shared visual semantics

- Common palette: deep black, graphite, warm white, cool secondary neutrals,
  selective warm gold, confirmed-health green, semantic warning red.
- Small text drawn over a variable energy material uses an opaque
  high-contrast role; do not alpha-dim thin measurements.
- Native Liquid Glass is interactive chrome only. Passive telemetry remains
  opaque/static.
- Measurement digits share rounded/tabular SF DNA, with optically separate
  units and semantic Dynamic Type behavior.

## Battery contract split

- Portrait Home retains its selected simultaneous hierarchy: SOC remains the
  truthful fill and primary percentage; accepted learned range may be shown as
  a separate qualified value. Unavailable remains explicit.
- Landscape cockpit uses one value inside one battery instrument: percentage by
  default, tap to range, tap back. Its fill always remains SOC.
- Neither workstream may synthesize range or promote retained/Simulator battery
  evidence to current physical truth.

## Data boundary

Until Capture/BLE publishes a stable decoder/evidence contract, portrait shows
unknown, unavailable, or retained values honestly and keeps dependent controls
disabled. This branch does not duplicate capture tools or protocol inference.

## Portrait render isolation

- Home resolves connection and energy truth in narrow `@MainActor` Observation
  bridges, then hands plain Equatable snapshots to render leaves.
- The energy snapshot contains only authority-gated SOC/readout presentation,
  accepted adaptive-range decision, and battery freshness. Speed, power,
  odometer, trip, vehicle ride/start mode, and vehicle commands must not enter
  it. The persisted percentage/range emphasis is an intentional energy input.
- The heavy battery/scooter/grounding renderer must not retain `VehicleStore`,
  `HorizonCockpitStore`, callbacks, `@State`, or a perpetual timeline.
- This boundary reduces passive hero redraws; it is not a claim that every Home
  section is isolated or that physical telemetry arrives at display cadence.
