# Speed telemetry quality gate

Date: 2026-08-06
Original worker: `chat-p7w3k`
Recovery worker: `chat-b6q2y` (Swarm OS v7 epoch 2)
Lane: `telemetry-quality-gate`
Primary hardware-validation target: **AOVOPRO ES80**

This slice adds a policy-driven quality gate on top of Nembra's existing `TelemetryBenchmarkSummary`. It answers a deliberately narrow question:

> Does this measured source satisfy the evidence requirements chosen for this feature?

It does **not** choose those requirements, rank a source as universally "best", or convert a Simulator result into physical scooter truth.

## Why this boundary exists

Nembra already measures useful speed-source properties:

- accepted and rejected sample counts;
- arrival interval count and effective sample rate;
- mean/minimum/maximum arrival interval;
- interval jitter standard deviation;
- duplicate speed values and empirical minimum nonzero speed step;
- delivery latency when a source provides a meaningful measurement timestamp.

Those measurements are evidence. They are not themselves a product decision. Acceleration timing, live distance, dashboard presentation, ride detection, and future navigation may legitimately require different source quality.

`SpeedTelemetryQualityPolicy` keeps that distinction explicit by making every threshold caller supplied.

## No hidden ES80 constants

The policy can optionally require:

- a specific `SpeedTelemetrySource`;
- a minimum number of accepted samples;
- a maximum rejected-sample fraction;
- maximum mean sample interval;
- maximum observed sample interval;
- maximum interval-jitter standard deviation;
- a minimum fraction of accepted samples that actually carry delivery-latency evidence;
- maximum mean delivery latency;
- maximum empirical nonzero speed step.

There are no production defaults for cadence, jitter, latency, latency coverage, rejection rate, or resolution. An unconstrained policy requires only one accepted sample and does not silently demand metrics the caller never requested.

An explicitly supplied `minimumDeliveryLatencySampleFraction` of `0` means exactly **no minimum coverage requirement**. It does not create a hidden demand for timestamped latency evidence.

A future physical ES80 validation pass can populate feature-specific requirements from measured evidence. Simulator-friendly numbers must not become those requirements automatically.

## Missing evidence is different from passing evidence

When a caller requests a metric that the benchmark does not have, the assessment reports that absence explicitly.

Examples:

- a one-sample benchmark cannot satisfy a requested interval requirement and reports `missingIntervalEvidence`;
- BLE data without a source measurement timestamp cannot satisfy a positive requested latency-coverage or mean-latency requirement and reports `missingDeliveryLatencyEvidence`;
- a trace with no observed nonzero speed change cannot satisfy a requested resolution bound and reports `missingSpeedResolutionEvidence`.

The quality gate never substitutes zero, advertised specifications, a different source, or a display estimate for missing evidence.

## Representative latency evidence

A good mean latency from a tiny timestamped subset must not automatically qualify an otherwise unmeasured stream. `minimumDeliveryLatencySampleFraction` lets a feature require representative timestamp coverage independently of the maximum allowed mean latency.

For example, if four GPS samples are accepted but only one has a usable source measurement timestamp, the measured latency fraction is `0.25`. A caller requiring `0.75` latency coverage fails with `deliveryLatencySampleFractionBelowMinimum` even if that single observed latency happens to be excellent.

If zero accepted samples carry latency evidence and a **positive** latency coverage or mean-latency requirement was requested, the assessment reports `missingDeliveryLatencyEvidence`; if a positive minimum coverage fraction was also requested, it additionally reports the unmet `0.0` coverage fraction. This preserves both facts instead of collapsing them into one vague failure.

## Complete failure reporting

`SpeedTelemetryQualityAssessment` accumulates independent failures in deterministic policy order rather than stopping at the first problem. A single benchmark can therefore report, for example:

- wrong source;
- insufficient sample count;
- excessive rejection fraction;
- missing interval evidence;
- missing latency evidence;
- insufficient latency-evidence coverage;
- missing resolution evidence.

That matters for field-validation tooling because fixing one evidence gap should not hide the others.

## Relationship to acceleration timing and peak speed

The separate acceleration-timing and peak-speed workers can use this quality boundary later, after their required physical evidence exists. The responsibilities remain separate:

- `TelemetryBenchmarkCollector` measures source behavior;
- `SpeedTelemetryQualityPolicy` evaluates measured behavior against explicit requirements;
- `AccelerationRunEvaluator` bounds a run using accepted authoritative speed measurements;
- `PeakSpeedEvidenceAccumulator` preserves the highest accepted measurement and observation continuity.

This lane does not make those workers depend on a guessed BLE cadence and does not wire any subsystem into production UI.

## Software verification

Deterministic repository tests cover:

- policy validation and absence of implicit hardware thresholds;
- a source satisfying explicit cadence/jitter/rejection/resolution requirements;
- insufficient samples plus missing interval evidence;
- source mismatch and rejected-sample fraction as separate failures;
- simultaneous mean/worst-interval/jitter failures;
- simultaneous missing latency and speed-resolution evidence;
- sparse latency timestamps failing requested representative coverage even when observed mean latency looks good;
- zero latency samples reporting both missing evidence and unmet positive requested coverage;
- zero minimum latency coverage imposing no hidden timestamp requirement;
- measured latency and empirical resolution independently exceeding policy;
- unconstrained policy remaining qualified without unrequested metrics.

The pre-v7 worker reported a focused Swift 6.2.1 harness passing **11/11 tests** on the predecessor slice. That is supporting evidence, not final repository acceptance. The later exact-head Xcode 27 run `31131216556` on predecessor head `8aa9d328b80f5b783ab91f2468877c2de583009a` passed immutable checkout/project validation but failed during `Validate core package`; the preserved GitHub annotations expose only exit code 1, so the exact historical failing assertion is not claimed.

During v7 recovery, source review independently proved that one inherited test compared a Foundation `Date`-derived 50 ms latency using exact `== 50`. Swift 6.2.1 evaluates that construction at approximately `49.999952316` ms, so the test now uses the same tight `0.001 ms` tolerance pattern already present in `TelemetryBenchmarkTests`. That is test hardening only and does not change production quality-policy semantics.

Repository-wide NembraCore/Xcode 27 QA on the exact final recovery SHA is still required before merge.

## Hardware validation still required

For the AOVOPRO ES80 and iPhone 12, capture real traces for the relevant operating conditions before setting production requirements. At minimum evaluate:

1. scooter BLE speed arrival cadence and worst gaps;
2. duplicate/value-resolution behavior;
3. delivery latency **and timestamp coverage** where a source timestamp actually exists;
4. GPS cadence, reported speed accuracy, delivery latency, and source timestamp availability;
5. screen-on/background/reconnect behavior where the feature expects continuity;
6. sustained ride conditions rather than one short stationary sample.

A policy passing Simulator data proves only that the simulated summary satisfies that policy. It does not verify the real scooter source.
