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

The battery icon and low-battery warning remain charge-oriented in either readout mode. Toggling changes presentation preference only; it does not mutate scooter telemetry, battery evidence, adaptive-range learning, ride evidence, persistence of measured data, or any motorized-hardware state.

## Accessibility and interaction

The existing `dashboard.battery` accessibility identifier remains stable.

VoiceOver exposes the current authoritative presentation meaning instead of reading a visual transition frame. It identifies percentage values as percentages, range values as estimated range, and unavailable range as unavailable. The accessibility hint describes the alternate value reached by a normal activation.

The control uses a selection haptic when the stored presentation preference changes. It is disabled when no legitimate display SoC exists, avoiding a no-op interaction between two unavailable states.

## Xcode target wiring

The app target manually includes selected NembraCore sources. `BatteryPrimaryReadoutState.swift` is therefore added explicitly to the app target and Core project group. The package source itself is unchanged.

## Deferred integration

This slice intentionally does not modify Home or live-ride surfaces and does not claim cross-surface completion. Those surfaces can adopt the same stored preference after overlap and final visual-system decisions are reconciled.

A numeric range remains dependent on an accepted authoritative adaptive-range output. The future bridge should replace only the Dashboard's current `.unavailable` range input; it must not bypass `BatteryPrimaryReadoutState` or promote presentation values into evidence.

## Hardware status

Software presentation integration only. This work does not verify AOVOPRO ES80 battery source, percentage resolution/cadence, voltage/current/power semantics, charging behavior, or physical range behavior.
