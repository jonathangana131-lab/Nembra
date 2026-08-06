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

A missing/invalid display SoC uses a neutral unknown icon rather than `battery.0percent`. The empty-battery symbol is reserved for a legitimate validated low/zero charge reading, so unknown charge is not visually relabeled as 0%.

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

PR #45 co-locates its battery display-transition planner append-only in that same source file. Its transition types are self-contained, so this project wiring does not create a hidden extra app-target source dependency. That is build visibility only; #57 does not consume those transition frames yet.

## Deterministic UI coverage

The Dashboard UI suite includes focused coverage for:

- normal connected `92%` percentage presentation;
- a tap to estimated-range mode producing unavailable rather than synthetic mileage;
- restoration to percentage mode despite persistent `AppStorage` preference;
- a minimum 44 pt battery control target;
- the `scooter-unavailable` retained `71%` fixture announcing last-known provenance in both percentage and range modes;
- the `cold-disconnected` no-SoC fixture leaving the battery readout disabled and explicitly unavailable regardless of the persisted presentation preference;
- the `low-battery` 14% fixture exposing `low battery` to accessibility in both percentage and unavailable-range modes and preserving a low-battery range screenshot.

The unavailable-range screenshots remain required in the exact-head Simulator gate so sighted `RANGE —`, low-battery presentation, and the no-SoC unknown icon can be judged directly rather than inferred from accessibility assertions alone.

## Future adaptive-range bridge contract

The recovered adaptive-range model deliberately carries more truth than `BatteryEstimatedRangeDisplay.valueMeters` can currently represent. `AdaptiveBatteryRangeEstimate` contains:

- `presentedRemainingMeters`;
- `basis`, which distinguishes `.provisionalSeed` from `.learned`;
- `confidence`, with `.learning`, `.low`, `.normal`, and `.high`;
- `socProvenance`, which distinguishes an authoritative measurement from an estimated SoC;
- whether low-SoC conservatism was applied.

The estimator may legitimately return a numeric range before any scooter-specific history exists by using a conservative `.provisionalSeed`, and it may also produce estimates while confidence is still `.learning` or `.low`. It also accepts an estimated SoC for presentation while preserving that provenance.

The adaptive-range model does not own the app's live-vs-retained vehicle availability. A mathematically valid estimate can therefore still be contextually stale if the SoC supplied by the app belongs to retained disconnected state. The future presentation bridge must carry that freshness distinction separately rather than treating any non-nil estimate as current.

Therefore the future app bridge **must not** simply do this for every non-nil model result:

`AdaptiveBatteryRangeEstimate.presentedRemainingMeters -> BatteryEstimatedRangeDisplay.valueMeters`

That conversion would erase basis, confidence, SoC provenance, and live-vs-retained availability and could make a cold-start seed, weak estimate, estimated-SoC result, or stale disconnected estimate look indistinguishable from a better-supported current learned range.

Before numeric range is wired into this Dashboard, an accepted presentation policy must deliberately preserve those qualifiers. Acceptable integration shapes include extending the presentation domain so a provisional/low-confidence/stale numeric estimate carries an explicit user-facing qualifier, retaining a previously shown range as explicitly last-known, or mapping insufficiently supported states to an explicit learning/provisional/unavailable presentation until the product can show the number without overstating certainty. The exact policy belongs to the adaptive-range/readout integration lane, not this UI checkpoint.

At minimum the bridge must preserve these invariants:

1. `nil` estimator output remains `.unavailable`.
2. A `.provisionalSeed` is never relabeled as learned or typical scooter range.
3. `.learning` / `.low` confidence is not silently presented with the same certainty treatment as stronger learned evidence.
4. Estimated SoC provenance is not promoted into authoritative battery evidence merely because it was used to calculate a display estimate.
5. Retained/disconnected charge does not silently produce a fresh-looking range; any retained numeric range needs explicit last-known/stale semantics or must fail closed.
6. `presentedRemainingMeters`, not raw internal range, is the presentation candidate once a truthful policy allows a numeric value.
7. Low-SoC conservatism remains a model/presentation fact; the UI must not reverse-engineer or recreate it from battery percentage.
8. No presentation range value is allowed to train the model, alter ride evidence, or become decoded scooter telemetry.

This seam is intentionally documented now because the present `RANGE —` implementation is safer than prematurely flattening the adaptive model's uncertainty into a polished-looking number.

## Deferred integration

This slice intentionally does not modify Home or live-ride surfaces and does not claim cross-surface completion. Those surfaces can adopt the same stored preference after overlap and final visual-system decisions are reconciled.

A numeric range remains dependent on an accepted authoritative adaptive-range output **and** an accepted presentation mapping that preserves basis/confidence/provenance/freshness as described above. The future bridge should replace only the Dashboard's current `.unavailable` range input; it must not bypass `BatteryPrimaryReadoutState` or promote presentation values into evidence.

## Hardware status

Software presentation integration only. This work does not verify AOVOPRO ES80 battery source, percentage resolution/cadence, voltage/current/power semantics, charging behavior, or physical range behavior.
