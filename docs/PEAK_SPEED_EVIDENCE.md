# Observed peak-speed evidence

Date: 2026-08-06
Worker: `chat-p7w3k`
Lane: `peak-speed-evidence`
Primary hardware-validation target: **AOVOPRO ES80**

This slice establishes a truthful core boundary for future top-speed displays, ride details, and performance tests.

The key product rule is simple:

> Nembra may know the highest authoritative speed measurement it accepted. That is not automatically the scooter's exact continuous-time physical top speed.

## Terminology

This subsystem deliberately uses **observed peak speed** rather than "true top speed".

A sampled source can miss a short physical peak between measurements. Packet gaps, application interruptions, rejected low-quality GPS samples, or connection loss make that limitation stronger. The software must preserve those distinctions instead of presenting a sampled maximum as perfect continuous measurement.

## One source per accumulator

`PeakSpeedPolicy` selects exactly one authoritative `SpeedTelemetrySource`.

- `.motionAssist` is forbidden as a peak-speed source because it is short-horizon estimate evidence, not an absolute measurement.
- BLE and GPS measurements are never mixed into one maximum.
- a foreign authoritative source is rejected without contaminating the selected-source stream.
- a caller may optionally require a maximum speed-accuracy value; this is useful for GPS and remains an injected requirement rather than a product default.

No production ES80 source or GPS-accuracy ceiling is chosen in this slice.

## Highest accepted measurement

`PeakSpeedEvidenceAccumulator` keeps the highest accepted measurement from the selected source.

- the first accepted sample establishes a peak;
- a strictly higher later measurement replaces it;
- lower measurements do not replace it;
- an equal-speed measurement does not replace it, so the earliest observation of that maximum remains stable;
- stale/non-increasing selected-source timestamps are rejected transactionally.

The stored `PeakSpeedMeasurement` keeps source, measured meters/second, monotonic receipt uptime, and source accuracy metadata when present. It intentionally does not rely on wall-clock time to order observations.

### Rejected quality is still ordering evidence

A selected-source sample may be rejected because GPS speed accuracy is missing or exceeds the injected ceiling. That sample is still a real callback with a monotonic receipt timestamp.

The accumulator therefore advances its selected-source **observation-order anchor before accuracy gating**. Example:

1. good GPS sample arrives at uptime 100;
2. inaccurate GPS sample arrives at uptime 300 and is rejected for quality;
3. a later call supplies a supposedly good GPS sample stamped uptime 200.

Step 3 is rejected as non-increasing. Nembra must not erase the real callback at 300 merely because it was low quality and then allow older evidence at 200 to masquerade as fresh.

Wrong-source and non-authoritative estimate traffic remains outside this selected-source ordering stream.

## Continuity is separate from the numeric peak

A known observation interruption does not erase a speed measurement that was genuinely observed. Instead, the result becomes partial observation coverage.

`PeakSpeedEvidence` therefore carries:

- the highest accepted measurement;
- accepted sample count;
- quality-rejected selected-source sample count;
- known interruption count;
- `PeakSpeedObservationContinuity`.

`uninterruptedAcceptedObservations` means no selected-source quality rejection or explicit interruption was recorded in this accumulator. It still does **not** claim continuous physical sampling between packets.

`partialAcceptedObservations` means at least one selected-source quality rejection or explicit observation interruption occurred. The retained peak remains a truthful observed value, but Nembra must not imply complete observation coverage for the session.

## Quality rejection behavior

When the policy requests speed accuracy:

- missing accuracy is rejected and marks accepted-observation continuity partial once evidence exists;
- accuracy worse than the injected ceiling is rejected and marks continuity partial;
- the rejected observation still advances selected-source ordering evidence;
- a later monotonic good sample can still establish/update observed peak evidence.

A wrong-source sample is different: it was never part of the selected source's evidence stream, so it is rejected without incrementing the selected-source quality-rejection count or advancing the selected-source ordering anchor.

## Relationship to telemetry quality

The separate telemetry-quality-gate worker evaluates measured source cadence, jitter, latency, timestamp coverage, rejected fraction, and empirical speed resolution against caller-supplied requirements.

That is intentionally separate from this accumulator:

- telemetry benchmarking answers how the source behaved;
- telemetry quality policy answers whether that behavior meets a feature's requirements;
- peak-speed evidence answers what the highest accepted measurement was and whether known observation continuity was lost.

A future top-speed feature should combine these boundaries rather than hiding weak cadence inside a single impressive number.

## No durable ride-schema change yet

`CompletedRideEvidence` does not currently persist peak speed. This slice does not modify that durable schema, checkpoint journal, SwiftData history, or statistics model.

That is deliberate. First establish and validate the evidence semantics; only then should a separate migration/persistence slice decide whether observed peak belongs in completed ride history and how legacy records represent its absence.

## Software verification

Repository tests cover:

- motion-assist policy rejection and invalid accuracy policy;
- first accepted measurement establishing peak;
- strictly higher updates plus stable equal-speed tie behavior;
- foreign source isolation;
- motion-estimate rejection;
- GPS accuracy missing/exceeded handling;
- rejected-quality observations still preventing older timestamps from becoming fresh;
- transactional stale-timestamp rejection;
- interruption preserving the measured peak while marking continuity partial;
- reset clearing prior peak/continuity state.

The revised focused Swift 6.2.1 package using the same core semantics passed **7/7 grouped tests** after the rejected-quality ordering hardening. Repository-wide exact-head NembraCore/Xcode 27 QA is still required before merge.

## Hardware validation still required

Before Nembra presents an ES80 value as a meaningful top-speed result:

1. measure the selected source's real cadence, jitter, resolution, and gaps;
2. compare BLE and quality-screened GPS on physical iPhone 12;
3. decide the feature-specific quality policy from those traces;
4. verify reconnect/background behavior for any session spanning interruptions;
5. choose whether UI says "Observed peak", "Peak speed", or stronger wording based on the actual evidence quality;
6. never infer a physical peak between measurements from dashboard interpolation.

Software/Simulator success is not physical top-speed verification.
