# Acceleration timing evidence core

Date: 2026-08-06
Worker: `chat-p7w3k`
Lane: `acceleration-timing-core`
Primary hardware-validation target: **AOVOPRO ES80**

This slice adds a platform-independent timing core for future 0-to-target acceleration tests. It deliberately stops before app UI, run history, Core Motion fusion, or physical-scooter activation.

## Product requirement

Nembra eventually needs polished 0–10 / 15 / 20 / top-speed tests, but a displayed stopwatch value must not imply timing precision that the underlying speed samples cannot support.

A speed threshold is crossed **between** authoritative measurements. If one packet is below a threshold and the next packet is above it, software does not know the exact crossing instant unless a separately validated higher-rate measurement source proves it.

`AccelerationRunEvaluator` therefore reports timing **bounds** instead of fabricating a single exact crossing timestamp.

## Evidence model

The evaluator consumes `SpeedTelemetrySample` and accepts only `absoluteMeasurement` provenance.

- visual/interpolated Dashboard frames never enter the evaluator;
- `motionAssist` short-horizon estimates cannot arm or advance a run;
- a configured source can be required explicitly;
- if no source is required, the first eligible authoritative source becomes locked for that run and a later source change invalidates the trace;
- optional speed-accuracy gating is available for sources such as GPS;
- monotonic process uptime, not wall-clock time, defines ordering and timing.

No claim is made here about whether ES80 Bluetooth or GPS will be the accepted production acceleration source. That requires physical measurement of cadence, latency, jitter, resolution, and accuracy.

## Run semantics

A run begins from a verified stationary anchor.

- If the first eligible measurement is already moving above the stationary ceiling, the evaluator reports an invalid rolling start.
- Repeated stationary measurements refresh the most recent launch anchor.
- The first measurement above the stationary ceiling establishes a **launch crossing window** between the last stationary packet and that moving packet.
- The first measurement at or above the requested target establishes a **target crossing window** between the preceding below-target packet and the target-reaching packet.
- A completed result reports the narrowest elapsed lower/upper bounds that those two windows support.

Example:

- stationary packet at 1.0 s;
- first moving packet at 2.0 s;
- last below-target packet at 3.0 s;
- target-reaching packet at 4.0 s.

The launch happened somewhere in `[1.0, 2.0]` and the finish happened somewhere in `[3.0, 4.0]`. The truthful elapsed result is therefore **1.0–3.0 s**, not a fabricated `2.00 s`.

Future presentation may choose a concise estimate only if it also respects the measured uncertainty and accepted product policy. This core does not make that presentation decision.

## Invalidation behavior

An active trace fails closed when evidence continuity is no longer trustworthy:

- non-monotonic authoritative sample;
- measurement source changes mid-run;
- vehicle/app interruption explicitly reported by the caller;
- the scooter returns to stationary after launch;
- initial rolling start.

`reset()` discards the old trace and requires a fresh stationary anchor.

## Explicit non-goals

This slice does **not**:

- select the production ES80 speed source;
- infer threshold crossing from interpolated display values;
- use Core Motion as absolute speed;
- claim Bluetooth packet latency or GPS timing quality;
- add acceleration UI or history;
- persist acceleration records;
- infer throttle, torque, power, phase current, or motor output;
- send any scooter command or BLE write;
- activate acceleration testing on physical hardware.

## Software verification

A supplemental Swift 6.2.1 package harness using the exact core design passed 11 deterministic tests covering:

- rolling-start rejection;
- packet-bounded elapsed timing;
- sparse immediate target crossing;
- motion-estimate rejection;
- source-change invalidation;
- required-source and GPS-accuracy gating;
- non-monotonic evidence rejection;
- explicit interruption;
- return-to-stationary invalidation;
- reset behavior;
- invalid policy rejection.

Repository-wide exact-head NembraCore + Xcode 27 Simulator QA is still required on the final PR head through the `/xcode27` command gate.

## Hardware validation still required

Before production activation on the AOVOPRO ES80:

1. measure real ES80 Bluetooth speed cadence, latency, jitter, and resolution;
2. compare that evidence against quality-screened GPS timing on physical iPhone 12;
3. determine whether either source is sufficient alone or whether a carefully bounded multi-sensor presentation is justified;
4. choose stationary and target-crossing policy from measured traces rather than simulator convenience;
5. validate interruption/reconnect behavior on real rides;
6. decide user-facing precision from observed uncertainty instead of arbitrary decimal places.

Software correctness here is not physical ES80 validation.
