# Battery Evidence Domain

Status: software truth-boundary foundation. No physical AOVOPRO ES80 BLE/Tuya battery semantic, callback grouping, or receipt cadence is verified by this document or implementation.

## Purpose

Nembra needs one strict boundary between a plausible battery-looking number and a value that is actually allowed to become measured scooter telemetry. The stock newer-generation ES80 app visibly exposes battery percentage, voltage, current, and power, but those visible values remain correlation anchors until raw transport fields, scaling, signedness, cadence, derivation, and target-hardware behavior are physically verified.

`BatteryEvidenceObservation` keeps four independent concepts separate:

1. a validated normalized semantic value such as SoC %, volts, amps, watts, or charging state;
2. the truth role of that value;
3. process-local raw-callback receipt identity, when the observation came through a trusted live acquisition path;
4. receipt uptime / wall-clock metadata / continuity.

A plausible value, a recent-looking timestamp, or a receipt sequence is not enough to promote evidence authority.

## Truth roles

- `verifiedVehicleMeasurement` — reserved for a target-vehicle field whose raw source, semantics, and scaling have been physically verified. Only this role may cross the authoritative measurement gate.
- `stockAppCorrelationAnchor` — a value observed in the stock app. Useful for passive-capture correlation, never automatically measured Nembra telemetry.
- `simulationFixture` — deterministic software/Simulator evidence. Useful for QA, never physical ES80 proof.
- `derivedEstimate` — calculated/estimated evidence. It remains an estimate and must not be persisted as measured telemetry.
- `presentationOnly` — display-only/intermediate state such as animated progression. It never becomes telemetry evidence.

## Receipt identity is callback identity, not authority

`BatteryEvidenceReceiptIdentity` is an opaque process-local pair:

- `acquisitionEpoch: UUID` identifies one live acquisition lifetime;
- `sequenceNumber: UInt64` strictly orders raw callbacks within that epoch.

The identity must be minted at the serialized raw acquisition boundary **before** semantic decoding/normalization fans out. Every semantic field derived from one callback receives the same identity. Two distinct callbacks receive distinct increasing sequence numbers even when `receivedAtUptimeNanoseconds` is equal.

Receipt identity does **not** mean the field is physically verified. A simulation or stock-app correlation value can be well ordered and still remain non-authoritative. The verified role and the receipt/order proof are separate gates.

The package-scoped `BatteryEvidenceReceiptSequencer` is a small synchronous reference object intended for one serialized trusted callback owner. It starts at sequence 1 and fails closed before `UInt64` wrap. Reference semantics are deliberate: copying a mutable value sequencer could fork its counter and mint duplicate `(epoch, sequence)` identities, while aliasing one reference keeps one shared counter. The sequencer is intentionally not `Sendable`; the trusted acquisition owner stamps receipts synchronously on its already-serialized callback path before immutable identities fan out into async normalization.

There is intentionally no public receipt initializer. Under a real Swift-package build, package-scoped construction supports package tests and a future trusted acquisition target in the **same Swift package**. Under direct app-source compilation, the initializer remains file-scoped. Ordinary app/package clients may read a receipt identity carried by a projection, but cannot mint one through this API.

This does not elevate the separate public research `NembraBluetoothCapture` recorder into a production authority source. Its session/sequence is useful correlation/order evidence, but public/synthetic research capture remains non-authoritative. A future physical ES80 producer must preserve the sealed verified-role boundary as well as the receipt-order boundary.

## Authority construction is sealed for both build graphs

The lowest-level role-selecting `BatteryEvidenceObservation` initializer is **file-scoped**, not merely module-internal.

That distinction is required by Nembra's current build graph. The production iOS target does not currently link the `NembraCore` package product; it manually compiles selected files from `Packages/NembraCore/Sources/NembraCore` directly into the `Nembra` app target. If the raw verified initializer were plain `internal`, a future Dashboard/service file in that same app module could call it and self-assert `verifiedVehicleMeasurement`.

The source therefore has two deliberately different compilation paths:

- **direct app-source compilation:** raw verified observation construction and receipt construction remain file-scoped, so unrelated app/service/view source cannot manufacture authority or live callback identity;
- **real Swift-package compilation (`SWIFT_PACKAGE`):** NembraCore exposes package-scoped deterministic construction to package tests and future trusted sibling targets inside the same Swift package. External package clients cannot call it.

Verified package construction additionally requires a nonnil receipt identity. A verified-looking observation without a live receipt fails `missingReceiptIdentity`.

External callers may construct ordinary evidence only through `BatteryEvidenceObservation.nonAuthoritative(...)`, which rejects `verifiedVehicleMeasurement` and deliberately creates a receipt-unbound observation. This preserves research/simulation import without allowing generic callers to claim that data is a current raw callback.

At the current project state there is intentionally no production API that maps a physical ES80 field into verified battery evidence because the physical source/semantics remain unverified. A future verified adapter must preserve this construction boundary; it must not widen raw constructors merely because app wiring needs them.

## Generic Codable transports neither authority nor live receipt identity

Generic `BatteryEvidenceObservation` Codable is deliberately limited to non-authoritative, receipt-unbound evidence:

- encoding a `verifiedVehicleMeasurement` observation fails;
- decoding a payload that claims `verifiedVehicleMeasurement` fails;
- `receiptIdentity` is not part of the generic coding keys;
- a bound non-authoritative package fixture encodes without its receipt identity and decodes receipt-unbound;
- a payload that injects a `receiptIdentity` object cannot restore it through this decoder;
- ordinary unbound stock-app/simulation/derived/presentation observations remain round-trippable and revalidated.

A serialized string saying `verifiedVehicleMeasurement`, or a copied epoch/sequence pair, therefore cannot become physical proof or live currentness on import.

If Nembra later needs durable measured battery telemetry, that requires a separate explicit verified persistence design with vehicle identity, schema, provenance, and process/receipt semantics. It must not silently reuse this generic observation codec as a trust channel.

## Semantic values

`BatterySemanticValue` normalizes only basic shape invariants:

- SoC must be finite and within `0...100`.
- Voltage must be finite and nonnegative.
- Current and power must be finite, but sign is deliberately unconstrained because real ES80 signedness/direction conventions remain physical-verification work.
- Charging state is boolean.

The domain deliberately does **not** hard-code an ES80 pack voltage curve, cutoff voltage, current direction, regen semantics, power derivation, or percentage resolution. Fractional normalized SoC remains representable; the stock app displaying an integer does not prove the raw source is integer-resolution.

## Adaptive range boundary

`isAdaptiveRangeSOCEvidence` is true only for an SoC observation whose role is `verifiedVehicleMeasurement`. Verified construction also requires live receipt identity, but that property means only that the individual anchor is eligible to enter the adaptive-range chain.

It does **not** make a learning window valid. The range layer must still reject incomplete distance coverage, continuity gaps, insufficient battery consumption, tiny/noisy windows, outliers, replay, and source mismatch. Receipt identity must survive far enough downstream to bind derived range to the current accepted SoC, while uptime remains the freshness-age clock.

Stock-app percentages, simulation values, estimates, presentation frames, and generic imported observations cannot train the real-scooter model through this boundary.

## Electrical telemetry boundary

`isVerifiedElectricalTelemetry` is true only for verified vehicle measurements of voltage, current, power, or charging state. The stock-app detail screen showing those values does not satisfy this gate. Before Nembra uses them as production telemetry, physical capture must establish raw source, units/scaling, cadence, signedness, and derivation semantics. A visible stock-app watt number does not justify Wh/mi.

## Continuity

Every observation records whether it follows continuous evidence or arrives after an unobserved interval. `afterUnobservedInterval` is an explicit boundary. The stream validator additionally requires a strictly newer receipt to satisfy a caller-marked gap; replaying the same/older receipt cannot reopen continuity even when uptime is equal.

A higher layer must never bridge an unknown interval into one battery-consumption window. This remains compatible with adaptive range's requirement that reconnect/coverage gaps do not teach efficiency.

## Raw transport relationship

This type is above raw passive capture. Raw BLE/GATT/Tuya bytes, advertisements, characteristics, descriptors, and callback cadence remain research evidence in passive tooling.

A future verified vehicle adapter may map a proven raw field into `BatterySemanticValue` and cross the sealed verified construction boundary only after physical verification. Candidate DP IDs, public Tuya family behavior, timing similarity, stock-app correlation, imported JSON, or research recorder sequence alone do not authorize that promotion.

## Scope deliberately not included

This slice does not:

- decode ES80 BLE/Tuya packets;
- assign DP IDs;
- declare battery percentage resolution/cadence;
- establish physical callback grouping;
- convert voltage to SoC;
- infer watts from volts × amps;
- integrate Wh/mi;
- persist verified measured battery observations or process-local receipt identity;
- persist learned range state;
- decide display smoothing/interpolation;
- wire Home/Dashboard/live ride;
- enable any motorized-hardware write.

Those remain separate evidence-gated lanes.
