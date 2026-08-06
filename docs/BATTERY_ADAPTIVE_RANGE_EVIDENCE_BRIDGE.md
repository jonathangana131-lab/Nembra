# Battery Evidence → Adaptive Range Bridge

Status: dependent software truth bridge. No physical AOVOPRO ES80 battery semantic is verified by this document or implementation.

## Purpose

Nembra now has two deliberately separate software domains under active development:

- the battery-evidence truth boundary, where normalized SoC/voltage/current/power/charging values retain explicit role, continuity, and process-local ordering evidence;
- the adaptive percentage-based range model, which may learn only from authoritative measured SoC plus trustworthy distance windows.

This bridge is the narrow conversion boundary between them. It exists so higher layers cannot casually turn a plausible battery number into measured range-learning evidence or accidentally learn across a known observation gap.

## Dependency lineage

This worker lane depends on:

- adaptive-range core PR #10;
- battery-evidence-domain PR #34, including its `BatteryEvidenceStreamValidator` ordering/continuity contract.

The branch is composed from exact parent heads before this worker's source/tests/doc are applied. If either parent moves or lands, this lane must reconcile to the accepted parent head before final QA. It must not freeze stale copies of either domain.

## Accepted conversion

Only an observation whose role is `verifiedVehicleMeasurement` and whose semantic field is `stateOfChargePercent` may become a `BatterySOCReading` for the adaptive-range domain.

The conversion preserves:

- the normalized percentage exactly, including fractional values if a future verified source legitimately provides them;
- `.authoritativeMeasurement` provenance;
- process-local receipt uptime as the ordering timestamp.

Wall-clock `Date` remains correlation metadata and is not substituted for monotonic ordering.

## Evidence that is never promoted

Continuous SoC values whose roles are the following remain outside production range learning:

- `stockAppCorrelationAnchor`;
- `simulationFixture`;
- `derivedEstimate`;
- `presentationOnly`.

A stock Tuya screen showing `73%` is useful physical/app correlation evidence. It is not measured scooter SoC for adaptive range until the target ES80 raw source, scaling, semantics, and behavior are physically verified.

Likewise, a Simulator fixture can exercise software but never becomes physical ES80 efficiency history.

## Continuity truth is independent of value authority

An explicit `afterUnobservedInterval` marker is factual evidence that Nembra missed part of the battery-evidence stream. The bridge therefore resets any in-flight range-learning span for **every** such marker, even when the attached value is stock-app, simulated, derived, presentation-only, or a verified non-SoC electrical field.

That reset does **not** promote the attached number. A non-authoritative SoC still cannot become `BatterySOCReading`, and voltage/current/power/charging still cannot teach percentage-based efficiency.

This distinction is necessary because the first normalized battery observation after a real gap may not be authoritative SoC. If the bridge ignored the continuity boundary solely because the attached numeric value was non-authoritative, a later continuous verified SoC could accidentally close a learning window across an interval Nembra already knows it did not observe.

## Non-SoC electrical fields

Verified voltage, current, power, or charging-state observations do not become percentage-based range samples.

This bridge performs no:

- voltage→SoC conversion;
- current integration;
- power integration;
- watt-hour calculation;
- Wh/mi calculation;
- battery-health inference.

A future energy model may use physically verified electrical telemetry through a separate evidence-backed design. This bridge does not pre-empt that work.

## Actions instead of a lossy optional value

The bridge emits `BatteryAdaptiveRangeEvidenceAction` rather than only returning an optional SoC reading.

Actions are:

- `ignore` — a continuous observation does not affect production adaptive-range learning;
- `resetContinuity` — discard any in-flight battery-consumption span because a known unobserved interval ended here, while not promoting this value to SoC;
- `ingestSOC` — continuous verified SoC may enter the adaptive-range domain;
- `resetContinuityAndIngestSOC` — discard the old span first, then accept verified SoC as the new clean evidence point.

## Stateful stream validation

`BatteryAdaptiveRangeEvidenceBridge` wraps the parent's `BatteryEvidenceStreamValidator` and should be preferred when consuming an ordered sequence.

It preserves the parent contract:

- process-local uptime is the ordering authority;
- equal uptimes are legitimate because one callback may produce several normalized battery fields;
- uptime regression inside one observed epoch fails closed;
- after a higher layer calls `markUnobservedInterval()`, the next observation must carry `afterUnobservedInterval`;
- the first explicit post-gap boundary may establish a fresh uptime epoch even when its numeric uptime is lower than the prior process/boot epoch.

Stream validation and bridge action advance atomically. If ordering/continuity validation fails, the accepted-stream baseline is not advanced and no range-ingest action is returned.

## Future learning-window integration

When the range-window assembler is accepted, a higher layer should apply bridge actions conservatively:

1. `ignore` → do nothing;
2. `resetContinuity` → reset/discard the in-flight battery-consumption span;
3. `ingestSOC(reading)` → offer the reading to the assembler/model path;
4. `resetContinuityAndIngestSOC(reading)` → reset first, then ingest the reading as the new clean anchor.

The higher layer still owns real-distance source classification, ride/session boundaries, transport-gap evidence, and policy selection. This bridge does not choose ODO versus GPS, does not infer distance coverage, and does not train the model directly.

## Hardware status

**IMPLEMENTED IN SOFTWARE ONLY.** The physical 2025-generation AOVOPRO ES80 still requires verification of its real battery SoC source, percentage resolution/cadence, voltage/current/power semantics, charging behavior, and continuity characteristics before any observation can legitimately use `verifiedVehicleMeasurement` in production.
