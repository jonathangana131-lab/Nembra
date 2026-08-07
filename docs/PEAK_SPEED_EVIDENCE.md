# Observed peak-speed evidence

Date: 2026-08-07
Current recovery worker: `chat-t6v9m`
Lane: `recover-peak-speed-evidence`
Primary hardware-validation target: **AOVOPRO ES80**

This slice establishes a truthful NembraCore boundary for future peak-speed displays, completed-ride evidence, statistics, and performance features.

The product rule is intentionally narrow:

> Nembra may know the highest authoritative speed measurement it accepted. That is not automatically the scooter's exact continuous-time physical top speed.

## Terminology

This subsystem deliberately uses **observed peak speed** rather than "true top speed".

A sampled source can miss a short physical peak between measurements. Packet gaps, application interruptions, rejected low-quality samples, or connection loss make that limitation stronger. The software preserves those distinctions instead of presenting a sampled maximum as perfect continuous measurement.

## One source per accumulator

`PeakSpeedPolicy` selects exactly one authoritative `SpeedTelemetrySource`.

- `.motionAssist` is forbidden because it is short-horizon estimate evidence, not an absolute speed measurement.
- BLE and GPS measurements are never mixed into one maximum.
- foreign authoritative traffic is rejected before it can advance the selected source's ordering clock.
- a caller may optionally require a maximum speed-accuracy value; that requirement is injected rather than guessed.

No production ES80 source, cadence requirement, GPS-accuracy ceiling, or top-speed threshold is chosen in this slice.

## Highest accepted measurement

`PeakSpeedEvidenceAccumulator` keeps the highest accepted measurement from the selected source.

- the first accepted sample establishes a peak;
- a strictly higher later measurement replaces it;
- lower measurements do not replace it;
- an equal-speed measurement does not replace it, so the earliest observation of that maximum remains stable;
- stale/non-increasing selected-source timestamps are rejected;
- the stored measurement retains source, measured meters/second, monotonic receipt uptime, and source accuracy metadata when present.

Wall-clock time is not used to order peak observations.

## Rejected selected-source evidence still matters

A selected-source callback can be unusable as peak evidence while still being real chronological evidence. The accumulator therefore advances its selected-source observation-order anchor before derived-speed and optional accuracy gating.

Examples include:

- missing required GPS speed accuracy;
- GPS speed accuracy worse than the caller-injected ceiling;
- a finite raw SI speed whose required km/h conversion overflows.

If such a callback arrives at uptime 300, a later callback stamped uptime 200 cannot become fresh merely because the callback at 300 was rejected.

Wrong-source and non-authoritative estimate traffic remains outside this selected-source ordering stream.

## Derived-unit overflow fails closed

`SpeedTelemetrySample` stores a finite SI speed in meters/second. A mathematically finite raw `Double` can still overflow when multiplied by 3.6 for the product-facing km/h representation.

`PeakSpeedEvidenceAccumulator` rejects that callback as `.nonFiniteDerivedSpeed` before it can become the session maximum. The rejection:

- increments selected-source quality-rejection evidence;
- preserves the callback as chronological ordering evidence;
- leaves an existing valid peak unchanged;
- allows later monotonic valid evidence to establish or update the peak;
- does **not** invent an arbitrary maximum scooter speed to make the value fit.

Every published `PeakSpeedMeasurement.kilometersPerHour` is therefore finite.

## Continuity is separate from the numeric peak

A known observation interruption does not erase a speed measurement that was genuinely observed. Instead, the result becomes partial selected-source evidence.

`PeakSpeedEvidence` carries:

- the highest accepted measurement;
- accepted sample count;
- quality-rejected selected-source sample count;
- known interruption count;
- `PeakSpeedObservationContinuity`.

The public continuity cases intentionally describe only **recorded selected-source evidence loss**:

- `.noRecordedSelectedSourceEvidenceLoss` means no selected-source quality rejection or explicit interruption was recorded in this accumulator. It still does **not** claim continuous physical sampling between packets.
- `.partialSelectedSourceEvidence` means at least one selected-source quality rejection or explicit observation interruption was recorded. The retained peak remains a truthful observed value, but Nembra must not imply complete observation coverage.

An interruption recorded before the first accepted peak is retained. `evidence` remains unavailable until a peak exists, and when later valid evidence arrives its continuity is correctly partial.

## Relationship to telemetry quality

The separate telemetry benchmark/quality subsystem evaluates source cadence, jitter, latency, rejected fraction, and empirical speed resolution against caller-supplied requirements.

That boundary remains separate:

- telemetry benchmarking answers how a source behaved;
- telemetry quality policy answers whether that evidence meets a feature's requirements;
- peak-speed evidence answers what the highest accepted selected-source measurement was and whether known selected-source evidence loss was recorded.

A future user-facing peak-speed feature must combine these boundaries. A clean numeric maximum alone must not silently qualify weak or poorly observed telemetry.

## No durable ride-schema change yet

`CompletedRideEvidence` currently persists ride identity, wall-clock lifecycle dates, ODO/GPS distance evidence, and process continuity. It does not persist peak speed.

This slice deliberately does not modify completed-ride/checkpoint/history/statistics schemas. A later integration must mechanically bind peak evidence and its source-quality provenance to the same ride session, preserve legacy records with no peak evidence, and avoid promoting an unqualified number into history merely because it is available in memory.

## Software verification

Repository tests cover:

- motion-assist policy rejection and invalid accuracy policy;
- first accepted measurement establishing peak;
- strictly higher updates plus stable equal-speed tie behavior;
- foreign-source value and ordering isolation;
- motion-estimate rejection;
- GPS accuracy missing/exceeded handling;
- rejected-quality observations preventing older timestamps from becoming fresh;
- stale-timestamp rejection;
- interruption preserving a measured peak while marking selected-source evidence partial;
- an interruption before the first peak remaining visible when later evidence arrives;
- finite raw SI speed whose km/h conversion overflows being rejected transactionally;
- a very large but representable conversion remaining accepted;
- ordinary m/s -> km/h conversion behavior;
- reset clearing prior peak/evidence-loss state.

A focused Swift 6.2.1 harness using the production peak implementation plus the current `SpeedTelemetry` contract passed **13/13 checks in debug and 13/13 in release with warnings treated as errors** on this recovery iteration. That is package/domain evidence only, not physical iPhone or ES80 proof. Repository exact-head QA is requested separately for the final recovery SHA.

## Hardware validation still required

Before Nembra presents an ES80 value as a meaningful peak-speed result:

1. measure the selected source's physical cadence, jitter, resolution, latency, and gaps;
2. compare BLE and quality-screened GPS on a physical iPhone 12;
3. decide feature-specific telemetry-quality requirements from real traces;
4. verify reconnect/background behavior for any ride spanning interruptions;
5. bind the peak/quality evidence to the correct ride session before persistence or statistics integration;
6. choose whether UI says "Observed peak", "Peak speed", or stronger wording based on actual evidence quality;
7. never infer a physical peak between measurements from Dashboard interpolation.

Software/Simulator success is not physical AOVOPRO ES80 top-speed verification.
