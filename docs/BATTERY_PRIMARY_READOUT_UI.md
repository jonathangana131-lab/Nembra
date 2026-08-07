# Dashboard primary battery readout integration

Date: 2026-08-06
Protocol context: V10 recovery

## Scope

This slice wires the already-landed `BatteryPrimaryReadoutState` presentation boundary into the landscape Dashboard battery instrument.

The Dashboard battery metric becomes a normal-tap control whose presentation preference toggles between battery percentage and estimated remaining range. The preference uses the app-wide `nembra.primaryBatteryReadoutMode` `AppStorage` key so other product surfaces can adopt the same preference later without creating a second state model.

## Current truth boundary

`BatteryPrimaryReadoutState` remains the authority for presentation-mode semantics. At this checkpoint the Dashboard supplies:

- `VehicleState.batteryPercent` only as the current display-layer percentage input;
- `.unavailable` for estimated range.

The Dashboard deliberately does **not** calculate range from battery percentage, advertised range, trip distance, or invented energy values. Until an accepted adaptive-range integration supplies a legitimate estimate through an explicit presentation policy, switching to range mode displays an unavailable value rather than fabricated distance.

The visible eyebrow is mode-aware: percentage mode says `BATTERY`, while estimated-range mode says `RANGE`. The battery icon and low-battery warning remain charge-oriented in either mode. Toggling changes presentation preference only; it does not mutate scooter telemetry, battery evidence, range learning, ride evidence, persisted measurements, or motorized-hardware state.

A missing or invalid display SoC uses a neutral unknown icon rather than `battery.0percent`. The empty-battery symbol is reserved for a legitimate validated low/zero charge reading so unknown charge is never visually relabeled as 0%.

## Accessibility and retained data

The existing `dashboard.battery` accessibility identifier remains stable.

Accessibility exposes the current presentation meaning rather than a visual transition frame. Percentage values are announced as percentages, estimated range is explicitly identified as estimated, and unavailable range remains unavailable. The same validated charge threshold that drives the sighted low-battery treatment also appends `low battery` to the accessibility value, so range mode cannot hide the warning.

When `VehicleState.dataAvailability` is `.retained`, a retained percentage is explicitly announced as last-known vehicle data. In range mode, the accessibility value separately states that battery charge is last-known while preserving the range result's unavailable/learning/value classification. Retained charge remains useful read-only context without sounding like a fresh packet.

The control uses a selection haptic when the stored presentation preference changes. It is disabled when no legitimate display SoC exists, avoiding a meaningless toggle between two unavailable states. In that state its accessibility hint says battery data is unavailable.

## Motion boundary

This slice does not claim final `% ↔ range` or integer battery-roll animation. Presentation interpolation must never become telemetry or range evidence. Final motion choreography, Reduce Motion behavior, and any rolling battery transition remain separate product work.

## Xcode target wiring

The Nembra app target manually compiles selected NembraCore sources. `BatteryPrimaryReadoutState.swift` is therefore added explicitly to the app target and Core project group. The package source itself is unchanged by this recovery.

At V10 recovery head, the landed `BatteryPrimaryReadoutState.swift` source is self-contained for this Dashboard integration. No unmerged transition-planner or adaptive-range implementation is treated as an app-build dependency.

## Deterministic UI coverage

The Dashboard UI suite includes focused coverage for:

- connected `92%` percentage presentation;
- a tap to range mode producing unavailable rather than synthetic mileage;
- persistence of the user-facing mode across app relaunch;
- restoration to percentage mode for deterministic following tests;
- a minimum 44 pt battery control target;
- the `scooter-unavailable` retained `71%` fixture announcing last-known provenance in both modes;
- the `cold-disconnected` no-SoC fixture leaving the control disabled and explicitly unavailable;
- the `low-battery` 14% fixture exposing `low battery` in both modes and preserving a low-battery range screenshot.

The exact-head Simulator gate must still inspect screenshots. Passing XCUI assertions alone does not prove visual quality, and Simulator evidence is not physical-device evidence.

## Future adaptive-range bridge contract

A future accepted range model may carry substantially more truth than a bare numeric distance: confidence, learning/provisional status, SoC provenance, freshness/currentness, low-SoC conservatism, and other evidence qualifications. This UI seam must not flatten those distinctions merely to show a polished number.

Before numeric range is wired into this Dashboard, the accepted bridge must preserve at least these invariants:

1. Missing range output remains unavailable.
2. Provisional or cold-start output is not relabeled as learned or typical scooter range.
3. Weak/learning confidence is not silently presented with the same certainty as stronger evidence.
4. Estimated SoC provenance is not promoted into authoritative battery evidence because it contributed to a display estimate.
5. Retained/disconnected charge does not silently produce a fresh-looking range; retained numeric range needs explicit stale/last-known semantics or must fail closed.
6. Low-SoC conservatism remains a model/presentation fact; the UI must not recreate it from battery percentage.
7. No presented range value may train the model, alter ride evidence, or become decoded scooter telemetry.
8. If a future authoritative bridge can legitimately provide useful range while direct display SoC is unavailable, the temporary disabled-toggle rule must be reconsidered deliberately rather than inherited accidentally.

The present `RANGE —` behavior is intentionally conservative until that bridge exists in accepted app integration.

## Deferred integration

This slice intentionally does not modify Home or live-ride surfaces and does not claim cross-surface completion. Those surfaces can adopt the same stored preference after overlap and final visual-system decisions are reconciled.

A numeric range remains dependent on accepted authoritative range output **and** an accepted presentation mapping that preserves evidence quality and freshness. That future bridge should replace only the Dashboard's current `.unavailable` range input; it must not bypass `BatteryPrimaryReadoutState` or promote presentation values into evidence.

## Hardware status

Software presentation integration only. This work does not verify AOVOPRO ES80 battery source, percentage resolution/cadence, voltage/current/power semantics, charging behavior, or physical range behavior.
