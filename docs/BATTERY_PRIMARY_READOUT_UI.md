# Dashboard primary battery readout integration

Date: 2026-08-06

## Scope

This slice wires the already-accepted `BatteryPrimaryReadoutState` presentation boundary into the landscape Dashboard battery instrument.

The Dashboard battery metric is now a normal-tap control whose presentation preference toggles between battery percentage and estimated remaining range. The preference uses the app-wide `nembra.primaryBatteryReadoutMode` `AppStorage` key so other product surfaces can adopt the same preference later without creating a second state model.

## Current truth boundary

`BatteryPrimaryReadoutState` remains the authority for presentation-mode semantics. The Dashboard supplies:

- `VehicleState.batteryPercent` only as the current display-layer percentage input;
- `.unavailable` for estimated range at this integration checkpoint.

The Dashboard deliberately does **not** calculate range from battery percentage, advertised range, trip distance, or any invented energy value. Until an accepted adaptive-range integration supplies a legitimate estimate, switching to range mode displays an unavailable value rather than a fabricated distance.

The visible eyebrow is mode-aware: percentage mode says `BATTERY`, while estimated-range mode says `RANGE`. This keeps a fail-closed `RANGE —` state visually distinct from an unknown battery reading. The battery icon and low-battery warning remain charge-oriented in either readout mode. Toggling changes presentation preference only; it does not mutate scooter telemetry, battery evidence, adaptive-range learning, ride evidence, persistence of measured data, or any motorized-hardware state.

## Accessibility and retained data

The existing `dashboard.battery` accessibility identifier remains stable.

VoiceOver exposes the current authoritative presentation meaning instead of reading a visual transition frame. It identifies percentage values as percentages, range values as estimated range, and unavailable range as unavailable. The same validated charge threshold that turns the sighted battery treatment red also appends `low battery` to the accessibility value, so range mode never hides that warning from VoiceOver merely because the primary number is no longer a percentage.

When `VehicleState.dataAvailability` is `.retained`, a retained percentage is explicitly announced as last-known vehicle data. In range mode, the accessibility value explicitly says that the battery charge is last-known vehicle data while preserving the range result's own unavailable/learning/value classification. A retained `71%` therefore remains useful read-only context without sounding like a fresh live packet.

The control uses a selection haptic when the stored presentation preference changes. It is disabled when no legitimate display SoC exists, avoiding a no-op interaction between two unavailable states. In that disabled state its accessibility hint says battery data is unavailable rather than incorrectly instructing the user to double-tap a control that cannot activate.

## Motion boundary

This slice deliberately does not claim the final `% ↔ range` or integer battery-roll animation. The earlier orphaned numeric content-transition modifier was removed rather than implying a complete motion implementation without an explicit animation transaction or the dedicated battery-transition planner.

The battery-presentation-transition lane owns truthful integer presentation frames, and the Production Visual + Performance Overhaul owns final motion choreography and Reduce Motion acceptance. When that work is integrated, VoiceOver must remain anchored to the authoritative/current readout target, presentation intermediates must never enter telemetry/range evidence, and Reduce Motion must avoid spatial integer traversal.

## Xcode target wiring

The app target manually includes selected NembraCore sources. `BatteryPrimaryReadoutState.swift` is therefore added explicitly to the app target and Core project group. The package source itself is unchanged.

## Deterministic UI coverage

The Dashboard UI suite includes focused coverage for:

- normal connected `92%` percentage presentation;
- a tap to estimated-range mode producing unavailable rather than synthetic mileage;
- restoration to percentage mode despite persistent `AppStorage` preference;
- a minimum 44 pt battery control target;
- the `scooter-unavailable` retained `71%` fixture announcing last-known provenance in both percentage and range modes;
- the `cold-disconnected` no-SoC fixture leaving the battery readout disabled and explicitly unavailable regardless of the persisted presentation preference;
- the `low-battery` 14% fixture exposing `low battery` to accessibility in both percentage and unavailable-range modes and preserving a low-battery range screenshot.

The unavailable-range screenshots remain required in the exact-head Simulator gate so sighted `RANGE —` and low-battery presentation can be judged directly rather than inferred from accessibility assertions alone.

## Deferred integration

This slice intentionally does not modify Home or live-ride surfaces and does not claim cross-surface completion. Those surfaces can adopt the same stored preference after overlap and final visual-system decisions are reconciled.

A numeric range remains dependent on an accepted authoritative adaptive-range output. The future bridge should replace only the Dashboard's current `.unavailable` range input; it must not bypass `BatteryPrimaryReadoutState` or promote presentation values into evidence.

## Hardware status

Software presentation integration only. This work does not verify AOVOPRO ES80 battery source, percentage resolution/cadence, voltage/current/power semantics, charging behavior, or physical range behavior.
