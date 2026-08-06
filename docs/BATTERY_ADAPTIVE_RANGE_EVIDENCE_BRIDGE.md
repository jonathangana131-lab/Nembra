# Battery Evidence → Adaptive Range Bridge

Status: dependent software truth bridge. No physical AOVOPRO ES80 battery semantic is verified by this document or implementation.

## Purpose

Nembra now has two deliberately separate software domains under active development:

- the battery-evidence truth boundary, where normalized SoC/voltage/current/power/charging values retain an explicit evidence role;
- the adaptive percentage-based range model, which may learn only from authoritative measured SoC plus trustworthy distance windows.

This bridge is the narrow conversion boundary between them. It exists so higher layers cannot casually turn a plausible battery number into measured range-learning evidence.

## Dependency lineage

This worker lane is explicitly based on both exact parent heads:

- adaptive-range core PR #10 at `0a3a4c1a30ebcbe9abd2767b8aae3a01651ef088`;
- battery-evidence-domain PR #34 at `2d2f0b976f6cc2485b69918445a638aa89b43858`.

The branch contains those exact parent artifacts as a two-parent dependency composition. This document and the bridge source/tests are the worker-owned delta on top.

After either parent moves or lands, this lane must reconcile to the accepted parent head before final QA. It must not freeze stale copies of either domain.

## Accepted conversion

Only an observation whose role is `verifiedVehicleMeasurement` and whose semantic field is `stateOfChargePercent` may become a `BatterySOCReading` for the adaptive-range domain.

The conversion preserves:

- the normalized percentage exactly, including fractional values if a future verified source legitimately provides them;
- `.authoritativeMeasurement` provenance;
- process-local receipt uptime as the ordering timestamp.

Wall-clock `Date` remains correlation metadata and is not substituted for monotonic ordering.

## Evidence that is never promoted

The bridge returns `ignore` for SoC values whose roles are:

- `stockAppCorrelationAnchor`;
- `simulationFixture`;
- `derivedEstimate`;
- `presentationOnly`.

That remains true even if their numeric value looks plausible.

A stock Tuya screen showing `73%` is useful physical/app correlation evidence. It is not measured scooter SoC for adaptive range until the target ES80 raw source, scaling, semantics, and behavior are physically verified.

Likewise, a Simulator fixture can exercise software but never becomes physical ES80 efficiency history.

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

## Continuity is an action, not a forgotten boolean

The bridge emits `BatteryAdaptiveRangeEvidenceAction` rather than only returning an optional SoC reading.

Actions are:

- `ignore` — observation must not affect production adaptive-range learning;
- `resetContinuity` — verified battery evidence resumed after an unobserved interval, but this particular field is not SoC;
- `ingestSOC` — continuous verified SoC may enter the adaptive-range domain;
- `resetContinuityAndIngestSOC` — discard any in-flight range-learning span first, then accept the verified SoC as the new clean evidence point.

The explicit reset-only action matters because the first verified battery value after a process/observation gap might be voltage rather than SoC. If a bridge ignored that event solely because it was not SoC, a later apparently continuous SoC reading could accidentally close a range-learning window across an interval Nembra never observed.

## Non-authoritative gaps do not control production learning

An `afterUnobservedInterval` marker attached to stock-app correlation, simulation, derived, or presentation-only evidence does not reset production range learning.

Only physically verified vehicle measurements are allowed to influence the production adaptive-range evidence timeline. This prevents UI/simulation lifecycle artifacts from changing real learned history.

## Future learning-window integration

When the range-window assembler is accepted, a higher layer should apply bridge actions conservatively:

1. `ignore` → do nothing;
2. `resetContinuity` → reset/discard the in-flight battery-consumption span;
3. `ingestSOC(reading)` → offer the reading to the assembler/model path;
4. `resetContinuityAndIngestSOC(reading)` → reset first, then ingest the reading as the new clean anchor.

The higher layer still owns real-distance source classification, ride/session boundaries, transport-gap evidence, and policy selection. This bridge does not choose ODO versus GPS, does not infer distance coverage, and does not train the model directly.

## Hardware status

**IMPLEMENTED IN SOFTWARE ONLY.** The physical 2025-generation AOVOPRO ES80 still requires verification of its real battery SoC source, percentage resolution/cadence, voltage/current/power semantics, charging behavior, and continuity characteristics before any observation can legitimately use `verifiedVehicleMeasurement` in production.
