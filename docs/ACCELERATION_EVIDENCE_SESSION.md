# Acceleration Evidence Session

## Purpose

`AccelerationRunEvaluator` records measurement-bounded 0-to-target observation evidence. `AccelerationEvidenceSession` closes the next truth gap: a completed timing result and the telemetry-quality evidence used to qualify it must come from the same selected-source attempt and, for final reporting, the same retained launch-to-target timing trace.

This is a software evidence layer. It does not make a speed source physically authoritative for AOVOPRO ES80 and it does not turn packet-receipt time into exact scooter threshold-crossing time.

## One explicit source

A reporting policy requires both `AccelerationRunPolicy.requiredSource` and `SpeedTelemetryQualityPolicy.requiredSource`, and they must be identical.

The session routes only that source into timing and benchmarking. Callbacks from another provider are explicitly ignored before either evidence consumer and counted diagnostically. This permits GPS and scooter BLE providers to coexist without accidentally mixing their evidence.

No `.motionAssist` source can become acceleration timing truth because the underlying run policy rejects it as an authoritative source.

## Required evidence dimensions

The policy chooses no ES80 numeric thresholds. Callers must supply them.

For every source, product-reporting policy requires:

- a maximum accepted timing-sample gap;
- at least three benchmark samples so jitter has more than one interval;
- rejected-sample fraction policy;
- mean and worst observed interval policy;
- jitter policy;
- empirical speed-resolution policy.

For GPS, policy additionally requires:

- maximum speed accuracy for timing evidence;
- nonzero delivery-latency coverage;
- maximum mean delivery latency.

These are evidence-shape requirements, not claims that any particular threshold is correct for real ES80 acceleration testing.

## Same-attempt and same-trace ownership

Every selected-source callback first enters an attempt-wide `TelemetryBenchmarkCollector` and then the exact same sample is passed to `AccelerationRunEvaluator`. The attempt-wide summary is diagnostic only because it can include packets the final timing trace does not retain.

A second constant-memory benchmark tracks only timing evidence retained by the evaluator:

- the first accepted stationary observation creates the candidate trace;
- each newer accepted stationary observation replaces the old anchor and resets the candidate benchmark;
- moving samples enter the trace only when they pass the timing accuracy policy and the evaluator remains valid;
- GPS samples rejected by the timing accuracy gate cannot contribute cadence, latency, or resolution evidence to the final run;
- superseded stationary anchors cannot contribute quality evidence to the final run;
- the final collector freezes when the evaluator completes.

This avoids retaining an unbounded raw sample array while still preventing pre-launch or timing-rejected packets from making a completed run look higher quality than the measurements actually used for timing.

The session becomes immutable when:

- timing completes;
- timing invalidates;
- a known observation interruption breaks an already observed attempt.

Later packets cannot improve the benchmark of an earlier result. There is deliberately no session reset operation; a new attempt requires a new session.

A known interruption after selected-source evidence begins freezes the attempt instead of joining quality statistics across missing observation time. Operator cancellation remains an explicit terminal evaluator state.

## Reporting readiness

`AccelerationEvidenceSessionSnapshot.readiness()` is green only when all of the following hold:

1. the run completed rather than remaining incomplete or invalidated;
2. the completed result source matches the selected source;
3. an exact retained timing-trace benchmark exists;
4. the run's retained timing-evidence sample count meets the telemetry policy's minimum accepted-sample depth;
5. no retained timing sample is rejected by the trace benchmark;
6. no known observation interruption broke the attempt;
7. the retained timing-trace benchmark satisfies the caller-supplied quality policy.

The retained timing-sample requirement is important. Repeated stationary packets or GPS packets rejected by timing accuracy policy can make attempt-wide stream statistics look deep while the final launch-to-target trace still contains only two accepted measurements. Such a run is not reporting-ready.

Likewise, a poor-accuracy GPS packet may appear to provide a fine empirical speed-resolution step in the raw attempt stream. If the timing evaluator rejects that packet, it is excluded from final trace quality and cannot make the run reportable.

A raw finite SI speed can also overflow the benchmark's required km/h representation. If that retained sample completes the timing evaluator while the trace benchmark rejects it, readiness fails closed rather than presenting the run.

## Truth boundary

A ready software result still means only:

- the selected source and retained evidence shape met the caller's policy;
- the reported elapsed value remains `receiveObservationUptime` evidence;
- launch and target fields remain observation windows;
- display interpolation is not measurement evidence.

It does **not** mean:

- the selected thresholds are validated for physical AOVOPRO ES80 hardware;
- the source cadence, latency, resolution, or accuracy is physically verified;
- the elapsed receive-clock interval is an exact 0-to-target physical acceleration time;
- an unsampled earlier target excursion was impossible;
- Simulator evidence proves scooter behavior.

## Product integration still required

Before user-facing acceleration results can be enabled in production, Nembra still needs:

1. a physically verified ES80 read-only speed source and its real cadence/latency/resolution behavior;
2. evidence-driven production quality thresholds;
3. a trusted application owner that creates one session per attempt and maps real source/lifecycle interruptions correctly;
4. deliberate app-target source visibility and UI wiring;
5. iPhone 12 / iOS 27 runtime and accessibility acceptance;
6. physical field validation before any wording implies real ES80 acceleration accuracy.

This layer is intentionally additive and does not alter Bluetooth commands, Dashboard interpolation, ride persistence, or vehicle-control behavior.
