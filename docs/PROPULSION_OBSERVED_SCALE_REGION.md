# Propulsion Observed-Scale Region Presentation

## Purpose

Nembra's future live cockpit needs a restrained way to emphasize when the newest **accepted** propulsion-power measurement is genuinely near the edge of the learned observed-power gauge scale. That emphasis must never be driven by render interpolation and must never be mislabeled as throttle position or a certified/rated hardware maximum.

`PropulsionObservedScaleRegionSnapshot` is the product-presentation bridge for that state. It is deliberately additive and package-only so it does not race active Dashboard/project-file owners.

## Accepted measurement, never display interpolation

The region projection consumes `PropulsionGaugeDisplayModel.accessibilitySnapshot(...)`, not `PropulsionGaugeFrame.displayWatts` or `normalizedPropulsion`.

That means:
- a newly accepted high-power sample can enter the near-edge region immediately even while the visual gauge is still smoothly catching up;
- a newly accepted low-power sample leaves the near-edge region immediately even if the animated gauge is visually falling from an earlier high value;
- calling the projection at 60 Hz cannot manufacture repeated power observations or change the semantic region between accepted measurements;
- the projection cannot become telemetry, peak evidence, range/battery evidence, persistence, acceleration evidence, or protocol truth.

## Region states

The projection exposes five explicit states:
- `unavailable`: the propulsion source/presentation is unavailable or render chronology is invalid;
- `retained`: the last accepted power is preserved but no longer current;
- `observedScaleUnavailable`: live accepted power exists, but no compatible learned/simulator scale is available;
- `normal`: current accepted power is below the caller's near-edge presentation threshold;
- `nearObservedScaleEdge`: current accepted power is at or above that threshold on a compatible observed presentation scale.

Retained or unavailable evidence never remains in the near-edge state.

## Threshold policy

`PropulsionObservedScaleRegionPolicy` requires an explicit finite `nearEdgeFraction` in `(0, 1]`. NembraCore deliberately supplies no production default because selecting that threshold is product presentation policy, not physical scooter truth.

The fraction is measured against the compatible **gauge scale**, which may include the canonical observed-envelope headroom. It is not a percentage of rated motor power, controller capacity, throttle travel, or any certified maximum.

## Authority and identity

Scale admission is not duplicated here. The projection reuses the accepted-only accessibility snapshot, which itself reuses `PropulsionGaugeDisplayModel`'s exact vehicle/mode/authority compatibility checks.

Therefore:
- Simulator power can use only a Simulator scale;
- verified vehicle power can use only a verified observed-envelope scale;
- cross-vehicle and cross-mode scales fail closed;
- retained/unavailable evidence exposes no observed-scale fraction;
- render interpolation cannot create the region.

## Product wording

A future cockpit may use this state for restrained visual emphasis or wording such as **Near observed max** once the underlying verified observed-envelope path is production-wired. It must not use **Full throttle**, **100% throttle**, **rated max**, or equivalent language from this state.

The code intentionally does not provide a `fullPower` or `throttle` enum case.

## Integration status

This slice does not modify `DashboardView.swift`, `Nembra.xcodeproj/project.pbxproj`, BLE/Tuya acquisition, observed-envelope learning/persistence, rides, battery/range, navigation, or commands.

The production iOS target does not yet directly compile the propulsion presentation stack. App/source visibility and actual SwiftUI wiring remain later integration work after active high-contention owners clear and after verified ES80 read-only power semantics exist.

## Truth boundary

**SOFTWARE / PRESENTATION SEMANTICS ONLY — NOT PHYSICAL AOVOPRO ES80 PROOF.**

No ES80 power/current/voltage DP, GATT characteristic, units, scaling, signedness, cadence, rated maximum, throttle position, regen behavior, battery/thermal state, or physical full-power ceiling is established here. Simulator remains Simulator evidence. Learned observed scale remains presentation calibration, not a certified hardware maximum.
