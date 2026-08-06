# Speed telemetry quality gate

Date: 2026-08-06
Worker: `chat-p7w3k`
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
- maximum mean delivery latency;
- maximum empirical nonzero speed step.

There are no production defaults for cadence, jitter, latency, rejection rate, or resolution. An unconstrained policy requires only one accepted sample and does not silently demand metrics the caller never requested.

A future physical ES80 validation pass can populate feature-specific requirements from measured evidence. Simulator-friendly numbers must not become those requirements automatically.

## Missing evidence is different from passing evidence

When a caller requests a metric that the benchmark does not have, the assessment reports that absence explicitly.

Examples:

- a one-sample benchmark cannot satisfy a requested interval requirement and reports `missingIntervalEvidence`;
- BLE data without a source measurement timestamp cannot satisfy a requested latency requirement and reports `missingDeliveryLatencyEvidence`;
- a trace with no observed nonzero speed change cannot satisfy a requested resolution bound and reports `missingSpeedResolutionEvidence`.

The quality gate never substitutes zero, advertised specifications, a different source, or a display estimate for missing evidence.

## Complete failure reporting

`SpeedTelemetryQualityAssessment` accumulates independent failures in deterministic policy order rather than stopping at the first problem. A single benchmark can therefore report, for example:

- wrong source;
- insufficient sample count;
- excessive rejection fraction;
- missing interval evidence;
- missing latency evidence;
- missing resolution evidence.

That matters for field-validation tooling because fixing one evidence gap should not hide the others.

## Relationship to acceleration timing

The separate acceleration-timing worker can use this quality boundary later, after its required physical evidence exists. The two responsibilities remain separate:

- `TelemetryBenchmarkCollector` measures source behavior;
- `SpeedTelemetryQualityPolicy` evaluates measured behavior against explicit requirements;
- `AccelerationRunEvaluator` bounds a run using accepted authoritative speed measurements.

This lane does not make the acceleration worker depend on a guessed BLE cadence and does not wire either subsystem into production UI.

## Software verification

Deterministic repository tests cover:

- policy validation and absence of implicit hardware thresholds;
- a source satisfying explicit cadence/jitter/rejection/resolution requirements;
- insufficient samples plus missing interval evidence;
- source mismatch and rejected-sample fraction as separate failures;
- simultaneous mean/worst-interval/jitter failures;
- simultaneous missing latency and speed-resolution evidence;
- measured latency and empirical resolution independently exceeding policy;
- unconstrained policy remaining qualified without unrequested metrics.

A supplemental Swift 6.2.1 package harness using the same policy/assessment logic passed **5/5 focused tests**. Repository-wide NembraCore/Xcode 27 QA is still required before merge.

## Hardware validation still required

For the AOVOPRO ES80 and iPhone 12, capture real traces for the relevant operating conditions before setting production requirements. At minimum evaluate:

1. scooter BLE speed arrival cadence and worst gaps;
2. duplicate/value-resolution behavior;
3. delivery latency where a source timestamp actually exists;
4. GPS cadence, reported speed accuracy, and delivery latency;
5. screen-on/background/reconnect behavior where the feature expects continuity;
6. sustained ride conditions rather than one short stationary sample.

A policy passing Simulator data proves only that the simulated summary satisfies that policy. It does not verify the real scooter source.
