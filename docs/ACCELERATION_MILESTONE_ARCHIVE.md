# Acceleration Milestone Archive

Worker: `chat-q7m4`  
Lane: `acceleration-result-archive`

## Product gap

Nembra can now evaluate several acceleration milestones from one shared authoritative speed stream, but a qualified result still needs a safe durable representation before future history/statistics UI can retain it across launches.

`AccelerationMilestoneAttemptArchive` is that domain boundary. It archives only product-reportable milestone evidence from a terminal snapshot; it is deliberately not a serialized live session and cannot resume an acceleration attempt.

## Truth contract

- only milestones whose existing `AccelerationEvidenceReadiness` is ready are archived;
- the complete requested target list is retained separately from qualified results, so a partial attempt is never presented as a complete one;
- every archived milestone must belong to the requested set and remain strictly increasing;
- the exact source and caller-supplied cadence/accuracy/jitter/resolution/latency thresholds that qualified the attempt are stored as historical policy facts;
- those historical thresholds are not promoted into current ES80 hardware truth when decoded later;
- source authority remains fail-closed: motion-assisted/display-estimated speed cannot become archived acceleration evidence;
- the timing basis remains explicitly `receiveObservationUptime`, preserving that elapsed values came from accepted app receipt observations rather than an exact physical threshold-crossing clock;
- each milestone retains the quality diagnostics for the exact timing trace that qualified it;
- result sample count and retained benchmark sample count must agree;
- observed benchmark duration and stationary-to-target receive-clock duration must agree within a narrow floating-point tolerance;
- no display-interpolated frames are persisted.

## Why raw uptime anchors are not persisted

Process uptime is useful while one attempt is live because it gives strict monotonic ordering and interval measurement. Absolute uptime numbers are not meaningful durable timestamps across app launches, device restarts, or later decoding.

The archive therefore retains:

- observed elapsed duration;
- launch observation-window width;
- target-transition observation-window width;
- timing evidence sample count;
- source and quality diagnostics.

It deliberately does **not** retain `receivedAtUptimeNanoseconds`, `earliestUptimeNanoseconds`, or `latestUptimeNanoseconds`. A decoded archive cannot be fed back into the live evaluator as continuity evidence.

## Partial attempts

A run may legitimately produce a trustworthy lower milestone and then lose evidence before reaching a higher target. For example, a qualified 0→10-style observation can remain immutable even if a later gap invalidates 0→15 and 0→20-style targets.

The archive records both:

- `requestedTargetsMetersPerSecond` — what this attempt intended to observe;
- `qualifiedMilestones` — only what actually satisfied the evidence policy.

`isComplete` is true only when every requested target has a qualified archived milestone. `highestQualifiedTargetMetersPerSecond` is a convenience for history presentation and does not imply anything about an unobserved physical maximum.

## Corruption / schema handling

Top-level decoding is custom and revalidates the record instead of trusting synthesized stored-property assignment. It rejects, among other cases:

- unsupported schema versions;
- non-finite dates or target values;
- empty, duplicate, or descending requested targets;
- invalid historical policy shape;
- motion-assist authority;
- empty qualified evidence;
- qualified targets absent from the requested attempt;
- duplicate/descending qualified milestones;
- source disagreement with the archived policy;
- impossible quality-summary structure;
- result/benchmark sample-count mismatch;
- result/benchmark duration mismatch.

This is corruption resistance for archived evidence, not a claim that arbitrary external JSON is trusted telemetry.

## Integration boundary

This slice defines the durable domain record only. It does not modify shared persistence factories, ride-history stores, AppRuntime, Home, Dashboard, or statistics UI. Those are higher-contention integration surfaces and should consume this record only when a safe owning lane is available.

A future persistence layer should treat archives as immutable history entries keyed by `attemptID`; replacement/upsert semantics must not silently rewrite previously accepted evidence. Product UI should label results as observed acceleration evidence and preserve the receive-clock limitation rather than presenting them as laboratory-grade physical crossing times.

## Hardware status

**SOFTWARE ARCHIVAL BOUNDARY ONLY — NOT PHYSICAL AOVOPRO ES80 ACCELERATION VERIFICATION.**

This work does not establish ES80 speed source identity, cadence, latency, resolution, acceleration performance, top speed, Bluetooth/Tuya field semantics, or any other scooter behavior. Physical thresholds still require real ES80 evidence before production qualification.
