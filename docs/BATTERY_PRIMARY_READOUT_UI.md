# Dashboard primary battery readout integration

Date: 2026-08-06
Protocol context: V11 feature cell `battery-truth-range-dashboard`

## Scope

This slice wires the already-landed `BatteryPrimaryReadoutState` presentation boundary into the landscape Dashboard battery instrument.

The Dashboard battery metric becomes a normal-tap control whose presentation preference toggles between battery percentage and estimated remaining range. The preference uses the app-wide `nembra.primaryBatteryReadoutMode` `AppStorage` key so other product surfaces can adopt the same preference later without creating a second state model.

## Current truth boundary

`BatteryPrimaryReadoutState` remains the authority for presentation-mode semantics. At this checkpoint the Dashboard supplies:

- `VehicleState.batteryPercent` only as legacy/unqualified display-layer charge data;
- `.unavailable` for estimated range.

`VehicleState` does not currently carry field-specific battery freshness/authority. Connection state, whole-vehicle `dataAvailability`, a changed/equal percentage, and the state's generic `lastUpdated` timestamp are therefore **not** accepted proof that the charge field is fresh. A reconnect can preserve a non-nil cached percentage while the whole vehicle becomes `.connected`/`.live` before any fresh battery observation arrives.

For that reason, every non-nil `VehicleState.batteryPercent` shown by this slice is conservatively presented as **LAST KNOWN CHARGE**, including connected Simulator fixtures. That qualifier is removed only when a future accepted app bridge can supply field-specific authoritative live SoC truth. This is intentionally conservative; it prevents cached battery from being promoted into live telemetry merely because transport state changed.

The Dashboard deliberately does **not** calculate range from battery percentage, advertised range, trip distance, or invented energy values. Until an accepted adaptive-range integration supplies a legitimate estimate through an explicit presentation policy, switching to range mode displays an unavailable value rather than fabricated distance.

The visible eyebrow is mode-aware: percentage mode says `BATTERY`, while estimated-range mode says `RANGE`. A compact `LAST KNOWN CHARGE` qualifier remains visible whenever a charge value exists. The battery icon and low-battery warning remain charge-oriented in either mode. Toggling changes presentation preference only; it does not mutate scooter telemetry, battery evidence, range learning, ride evidence, persisted measurements, or motorized-hardware state.

A missing or invalid display SoC uses a neutral unknown icon rather than `battery.0percent`. The empty-battery symbol is reserved for a legitimate validated low/zero charge reading so unknown charge is never visually relabeled as 0%.

## Accessibility and currentness

The existing `dashboard.battery` accessibility identifier remains stable.

Accessibility exposes the current presentation meaning rather than a visual transition frame. Percentage values are announced as percentages, estimated range is explicitly identified as estimated, and unavailable range remains unavailable. Whenever charge exists at this legacy boundary, percentage mode announces `last known vehicle data` and range mode separately says the battery charge is last known. This qualification no longer depends on whole-vehicle `VehicleState.dataAvailability`.

The same validated display-charge threshold that drives the sighted low-battery treatment also appends `low battery` to the accessibility value, so range mode cannot hide the warning. Because the preceding charge qualifier is always present at this boundary, the warning cannot silently imply that a cached charge became a fresh packet.

The control uses a selection haptic when the stored presentation preference changes. It is disabled when no legitimate display SoC exists, avoiding a meaningless toggle between two unavailable states. In that state its accessibility hint says battery data is unavailable. With charge present, the hint explicitly says Nembra is showing the last known charge before describing the toggle action.

## Why whole-vehicle availability is insufficient

The V11 battery feature cell found a concrete reconnect counterexample: the simulator/service can retain a non-nil battery value across a transport gap and later switch the connection back to `.connected` without proving that a new battery observation was received. A whole-state `.live` classification therefore cannot establish battery-field currentness.

The battery evidence chain under development has the correct target shape:

- a validated current evidence segment;
- per-field freshness classification with no guessed ES80 age defaults;
- a live-truth projection that distinguishes unavailable, freshness-unclassified, stale, fresh non-authoritative, and verified-live evidence.

That chain is not yet accepted for app consumption and currently has its own receipt-identity continuity blocker. This Dashboard does not copy or approximate those semantics locally. Until that dependency is accepted, legacy `VehicleState` charge remains last-known.

## Promotion rule for the future live-truth bridge

Removing `LAST KNOWN CHARGE` is a positive truth claim and therefore needs an explicit field-specific promotion rule. The future bridge must satisfy all of these before the Dashboard treats SoC as live:

1. the observation is for `.stateOfChargePercent`;
2. evidence authority is an accepted verified-vehicle measurement, not simulation, stock-app correlation, derived, retained, or presentation-only data;
3. continuity belongs to the currently valid evidence segment;
4. field freshness is classified from accepted receipt/uptime evidence under an explicit policy rather than inferred from connection state or wall clock;
5. the resulting field state is the battery live-truth domain's verified-live case;
6. disconnect/reconnect invalidates live currentness until a valid post-gap battery receipt is accepted, even if the percentage happens to be numerically unchanged.

A future app adapter should map that accepted field state into a small presentation currentness input. The Dashboard should not ingest raw BLE/Tuya bytes or duplicate the evidence validator.

## Motion boundary

This slice does not claim final `% ↔ range` or integer battery-roll animation. Presentation interpolation must never become telemetry or range evidence. Final motion choreography, Reduce Motion behavior, and any rolling battery transition remain separate product work.

## Xcode target wiring

The Nembra app target manually compiles selected NembraCore sources. `BatteryPrimaryReadoutState.swift` is therefore added explicitly to the app target and Core project group. The package source itself is unchanged by this recovery.

At the current recovery head, the landed `BatteryPrimaryReadoutState.swift` source is self-contained for this Dashboard integration. No unmerged transition-planner, adaptive-range, battery-evidence, freshness, or live-truth implementation is treated as an app-build dependency.

## Deterministic UI coverage

The Dashboard UI suite includes focused coverage for:

- connected `92%` legacy charge remaining explicitly last-known rather than being promoted by connection state;
- a tap to range mode producing unavailable rather than synthetic mileage while retaining the last-known charge qualifier;
- persistence of the user-facing mode across app relaunch without changing currentness semantics;
- restoration to percentage mode for deterministic following tests;
- a minimum 44 pt battery control target;
- the `scooter-unavailable` retained `71%` fixture announcing last-known provenance in both modes;
- the `cold-disconnected` no-SoC fixture leaving the control disabled and explicitly unavailable;
- the `low-battery` 14% fixture exposing both the last-known qualification and `low battery` in both modes while preserving a low-battery range screenshot.

The exact-head Simulator gate must still inspect screenshots, including the visible `LAST KNOWN CHARGE` treatment. Passing XCUI assertions alone does not prove visual quality, and Simulator evidence is not physical-device evidence.

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
9. A live-looking range must not be paired with an unqualified stale battery fill; range currentness and charge currentness need explicit, independently truthful presentation semantics.

The present `RANGE —` behavior is intentionally conservative until that bridge exists in accepted app integration.

## Deferred integration

This slice intentionally does not modify Home or live-ride surfaces and does not claim cross-surface completion. Those surfaces can adopt the same stored preference after overlap and final visual-system decisions are reconciled inside the V11 feature cell.

A numeric range remains dependent on accepted authoritative range output **and** an accepted presentation mapping that preserves evidence quality and freshness. That future bridge should replace only the Dashboard's current `.unavailable` range input; it must not bypass `BatteryPrimaryReadoutState` or promote presentation values into evidence.

## Hardware status

Software presentation integration only. This work does not verify AOVOPRO ES80 battery source, percentage resolution/cadence, voltage/current/power semantics, charging behavior, freshness thresholds, reconnect packet behavior, or physical range behavior.
