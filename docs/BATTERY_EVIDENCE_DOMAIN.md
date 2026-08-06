# Battery Evidence Domain

Status: software truth-boundary foundation. No physical AOVOPRO ES80 BLE/Tuya battery semantic is verified by this document or implementation.

## Purpose

Nembra needs one strict boundary between a plausible battery-looking number and a value that is actually allowed to become measured scooter telemetry. The stock 2025-generation ES80 app visibly exposes battery percentage, voltage, current, and power, but those visible values are still correlation anchors until raw transport fields, scaling, signedness, cadence, derivation, and target-hardware behavior are verified.

`BatteryEvidenceObservation` therefore keeps two independent concepts separate:

1. a validated normalized semantic value such as SoC %, volts, amps, watts, or charging state;
2. the truth role of that value.

A plausible normalized value is not enough to promote its role.

## Truth roles

- `verifiedVehicleMeasurement` — reserved for a target-vehicle field whose raw source, semantics, and scaling have been physically verified. Only this role may cross the authoritative measurement gate.
- `stockAppCorrelationAnchor` — a value directly observed in the stock app. Useful for passive capture correlation, never automatically measured Nembra telemetry.
- `simulationFixture` — deterministic software/Simulator evidence. Useful for QA, never physical ES80 proof.
- `derivedEstimate` — a calculated/estimated value. It remains an estimate and must not be persisted as measured telemetry.
- `presentationOnly` — display-only/intermediate state such as animated progression. It never becomes telemetry evidence.

## Authority construction is sealed

The raw `BatteryEvidenceObservation` initializer is module-internal.

External modules may construct an observation only through `BatteryEvidenceObservation.nonAuthoritative(...)`, which rejects `verifiedVehicleMeasurement`. This keeps a normal app/view/service caller from promoting a plausible number into verified scooter telemetry merely by choosing an enum case.

The future physically verified vehicle adapter may use the internal trusted construction boundary only when the real target field has actually been proven. At the current project state, no external production API exists for manufacturing verified ES80 battery observations because the physical ES80 semantics are still unverified.

NembraCore's `@testable` tests can use the internal initializer to exercise future verified-path behavior; test access is not a production authority path.

## Generic Codable does not serialize authority

Generic `BatteryEvidenceObservation` Codable is deliberately limited to non-authoritative evidence:

- encoding a `verifiedVehicleMeasurement` observation fails;
- decoding a payload that claims `verifiedVehicleMeasurement` fails;
- non-authoritative stock-app/simulation/derived/presentation observations remain round-trippable and revalidated.

A serialized string saying `verifiedVehicleMeasurement` therefore cannot become physical proof on import.

If Nembra later needs durable measured battery telemetry, that requires a separate explicit verified persistence design with its own vehicle identity, schema, provenance, and process/uptime semantics. It must not silently reuse the generic observation codec as a trust channel.

This is also consistent with receipt uptime being process-local ordering evidence rather than a durable cross-process clock.

## Semantic values

`BatterySemanticValue` normalizes only basic shape invariants:

- SoC must be finite and within `0...100`.
- Voltage must be finite and nonnegative.
- Current and power must be finite, but their sign is deliberately not constrained because real ES80 signedness/direction conventions remain physical-verification work.
- Charging state is boolean.

The domain deliberately does **not** hard-code an ES80 pack voltage curve, cutoff voltage, current direction, regen semantics, power derivation, or percentage resolution. Those require evidence.

Fractional normalized SoC remains representable. This avoids assuming that the physical ES80 is truly limited to integer percentage resolution simply because the stock app currently displays an integer percentage.

## Adaptive range boundary

`isAdaptiveRangeSOCEvidence` is true only for a SoC observation whose role is `verifiedVehicleMeasurement`.

That property means only that the individual anchor is eligible to enter the adaptive-range layer. It does **not** declare a learning window valid. The adaptive-range model must still reject incomplete distance coverage, transport/reconnect gaps, insufficient consumption, tiny/noisy windows, outliers, and other policy failures.

Stock-app percentages, simulation values, estimates, presentation frames, and generic imported observations cannot train the real-scooter range model through this boundary.

## Electrical telemetry boundary

`isVerifiedElectricalTelemetry` is true only for verified vehicle measurements of:

- voltage;
- current;
- power;
- charging state.

The stock-app detail screen showing those values does not satisfy this gate. Before Nembra uses them as production electrical telemetry, field capture must establish their actual raw source, units/scaling, cadence, signedness, and derivation semantics.

A visible stock-app watt number does not justify Wh/mi.

## Continuity

Every observation records whether it follows continuous evidence or arrives after an unobserved interval.

`afterUnobservedInterval` is an explicit boundary. The observation itself may still be a valid new authoritative anchor only when it came through the trusted verified construction boundary; a higher layer must never silently bridge the unknown interval into one continuous battery-consumption window.

This is intentionally compatible with the adaptive-range rule that reconnect/coverage gaps must not teach efficiency.

## Raw transport relationship

This type is above raw passive capture. Raw BLE/GATT/Tuya bytes, advertisement evidence, characteristics, descriptors, and callback cadence remain immutable research evidence in the passive capture tooling.

The future verified vehicle adapter may map a proven raw field into `BatterySemanticValue` and use the trusted internal verified construction path only after physical verification. Candidate DP IDs, public Tuya family behavior, timing similarity, stock-app correlation, or imported JSON alone do not authorize that promotion.

## Scope deliberately not included

This slice does not:

- decode ES80 BLE/Tuya packets;
- assign DP IDs;
- declare battery percentage resolution/cadence;
- convert voltage to SoC;
- infer watts from volts × amps;
- integrate Wh/mi;
- persist verified measured battery observations;
- persist learned range state;
- decide display smoothing/interpolation;
- wire Home/Dashboard/live ride;
- enable any motorized-hardware write.

Those remain separate lanes with their own evidence gates.
