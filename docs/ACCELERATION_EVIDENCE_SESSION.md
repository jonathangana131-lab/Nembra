# Acceleration Evidence Session

## Purpose

`AccelerationRunEvaluator` records measurement-bounded 0-to-target observation evidence. `AccelerationEvidenceSession` closes the next truth gap: a completed timing result and the telemetry-quality evidence used to qualify it must come from the same selected source and the same final retained launch-to-target timing trace.

This is a software evidence layer. It does not make a speed source physically authoritative for AOVOPRO ES80 and it does not turn packet-receipt time into exact scooter threshold-crossing time.

## One explicit source

A reporting policy requires both `AccelerationRunPolicy.requiredSource` and `SpeedTelemetryQualityPolicy.requiredSource`, and they must be identical.

Callbacks from another provider are explicitly ignored before timing evidence is consumed and counted diagnostically. This permits GPS and scooter BLE providers to coexist without accidentally mixing their evidence.

No `.motionAssist` source can become acceleration timing truth because the underlying run policy rejects it as an authoritative source.

## Required evidence dimensions

The policy chooses no ES80 numeric thresholds. Callers must supply them.

For every source, product-reporting policy requires:

- a maximum accepted timing-sample gap;
- at least three retained benchmark samples so jitter has more than one interval;
- rejected-sample fraction policy;
- mean and worst observed interval policy;
- jitter policy;
- empirical speed-resolution policy.

For GPS, policy additionally requires:

- maximum speed accuracy for timing evidence;
- nonzero delivery-latency coverage;
- maximum mean delivery latency.

These are evidence-shape requirements, not claims that any particular threshold is correct for real ES80 acceleration testing.

## Exact retained-trace ownership

The session maintains one constant-memory benchmark for the timing evidence retained by the evaluator:

- the first accepted stationary observation creates the candidate trace;
- each newer accepted stationary observation replaces the old anchor and resets the benchmark;
- moving samples enter the trace only when they pass the timing accuracy policy and the evaluator remains valid;
- GPS samples rejected by the timing accuracy gate cannot contribute cadence, latency, or resolution evidence to the final run;
- superseded stationary anchors and long idle time before the final anchor cannot contribute quality evidence to the final run;
- the final collector freezes when the evaluator completes.

The session intentionally does **not** expose a broader attempt-wide benchmark. Source-characterization tooling can run its own `TelemetryBenchmarkCollector`, but acceleration product code receives only the quality evidence that belongs to the retained timing trace. This makes the truthful reporting path the easiest API path and avoids accidentally qualifying a result with measurements the evaluator did not retain.

The session becomes immutable when:

- timing completes;
- timing invalidates;
- a known observation interruption breaks an already observed attempt.

Later packets cannot improve the benchmark of an earlier result. There is deliberately no session reset operation; a new attempt requires a new session.

A known interruption after selected-source evidence begins freezes the attempt instead of joining evidence across missing observation time. Operator cancellation remains an explicit terminal evaluator state.

## Reporting readiness

`AccelerationEvidenceSessionSnapshot.readiness()` is green only when all of the following hold:

1. the run completed rather than remaining incomplete or invalidated;
2. the completed result source matches the selected source;
3. an exact retained timing-trace benchmark exists;
4. the run's retained timing-evidence sample count meets the telemetry policy's minimum accepted-sample depth;
5. no retained timing sample is rejected by the trace benchmark;
6. no known observation interruption broke the attempt;
7. the retained timing-trace benchmark satisfies the caller-supplied quality policy.

`telemetryQuality` is optional and is produced only for a completed run with a retained-trace benchmark. Incomplete or invalidated attempts do not receive a synthetic quality assessment from unrelated/pre-launch traffic.

Repeated stationary packets cannot make a shallow launch-to-target trace look deep because only the final stationary anchor remains in the trace. Likewise, a poor-accuracy GPS packet cannot provide an attractive resolution or latency statistic if the timing evaluator rejected that packet.

A raw finite SI speed can overflow the benchmark's required km/h representation. If that retained sample completes the timing evaluator while the trace benchmark rejects it, readiness fails closed rather than presenting the run.

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

## Application attempt ownership

`AccelerationAttemptOwner` adds the software application boundary above one evidence session without selecting any ES80 policy values.

Each new attempt receives a monotonically increasing generation token. Raw speed callbacks and connection/lifecycle interruptions must carry that token back to the owner. A callback retained by an older async task is therefore rejected instead of being allowed to mutate a replacement attempt.

The owner also records a process-local monotonic start fence. A raw sample received at or before that fence is ignored, because a callback at the exact boundary is ambiguous with traffic already queued when the attempt began. The first usable observation must be strictly newer than the attempt boundary.

An active mutable attempt cannot be silently replaced. Completed, invalidated, and continuity-broken attempts are terminal and remain inspectable until the caller explicitly begins a newer attempt. Attempt start fences themselves must advance monotonically within one owner.

This closes the reusable software ownership primitive only. It does **not** mean Nembra currently starts acceleration attempts from production UI, has a verified ES80 speed source, has validated physical quality thresholds, or maps every real app/Bluetooth lifecycle edge into this owner yet.

## Product integration still required

Before user-facing acceleration results can be enabled in production, Nembra still needs:

1. a physically verified ES80 read-only speed source and its real cadence/latency/resolution behavior;
2. evidence-driven production quality thresholds;
3. app-root wiring that creates/owns `AccelerationAttemptOwner`, feeds it only raw authoritative `SpeedTelemetrySample` evidence, and maps real connection/application lifecycle interruptions with the correct generation;
4. deliberate app-target source visibility and UI wiring;
5. iPhone 12 / iOS 27 runtime and accessibility acceptance;
6. physical field validation before any wording implies real ES80 acceleration accuracy.

The current owner/session layers are intentionally additive and do not alter Bluetooth commands, Dashboard interpolation, ride persistence, or vehicle-control behavior.
