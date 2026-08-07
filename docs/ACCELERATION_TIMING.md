# Acceleration timing evidence core

Date: 2026-08-06  
Original worker: `chat-p7w3k`  
V7 recovery/hardening: `chat-l2p6q`  
Lane: `recover-acceleration-timing-core`  
Primary hardware-validation target: **AOVOPRO ES80**

This slice adds a platform-independent evidence core for future 0-to-target acceleration work. It deliberately stops before app UI, run history, Core Motion fusion, or physical-scooter activation.

## Product requirement

Nembra eventually needs polished 0–10 / 15 / 20 / top-speed tests, but the product must not present a stopwatch number as physical acceleration truth unless the underlying source evidence actually supports that claim.

Two separate limits matter:

1. **sampling limit** — accepted below-target packets do not prove the scooter never reached target and fell back between packets;
2. **clock/latency limit** — `SpeedTelemetrySample.receivedAtUptimeNanoseconds` is the app's monotonic packet-receipt clock, not necessarily the physical source-measurement or threshold-crossing clock.

The current evaluator therefore produces **receive-observation evidence**, not a physical 0-to-target time and not a first-reach bound.

## Evidence model

The evaluator consumes `SpeedTelemetrySample` and accepts only evidence that can legitimately act as an authoritative absolute speed measurement for this slice.

- visual/interpolated Dashboard frames never enter the evaluator;
- `motionAssist` short-horizon estimates cannot arm or advance a trace;
- `requiredSource: .motionAssist` is rejected at policy construction;
- the evaluator independently rejects `.motionAssist` regardless of decoded provenance as defense in depth, so a malformed imported sample cannot become timing evidence even if it crosses a permissive persistence/import boundary;
- when this recovery finding was identified, the upstream synthesized `Codable` boundary could deserialize an impossible source/provenance pair without invoking the validating initializer; upstream PR #99 separately owns revalidation of decoded `SpeedTelemetrySample` values through that initializer;
- the acceleration regression is intentionally compatible with both safe states: a hardened decoder may reject the malformed pair before the evaluator sees it, while an older permissive decoder must still be contained by the evaluator's `.motionAssist` guard;
- this defense does not claim the normal live telemetry path emits malformed samples, and the evaluator guard remains safe redundancy after upstream decoding is hardened;
- a configured authoritative source can be required explicitly;
- if no source is required, the first usable authoritative source becomes locked for that trace and a later source change invalidates it;
- optional speed-accuracy gating is available for sources such as GPS;
- an optional maximum accepted sample interval can reject a trace when usable measurement cadence becomes too sparse for the requested evidence quality;
- that interval is injected policy, not a guessed ES80 constant; leaving it unset makes no cadence claim;
- monotonic process uptime, not wall-clock time, defines observation ordering and receive-interval calculations.

No claim is made here about whether ES80 Bluetooth or GPS will be the accepted production acceleration source. That requires physical measurement of cadence, latency, jitter, resolution, and accuracy.

## Stationary policy has no hardware-default value

`stationaryMaximumMetersPerSecond` is required when constructing `AccelerationRunPolicy`.

There is intentionally **no public default** such as `0.5 m/s`, because that threshold changes real behavior:

- whether the first accepted sample is a valid stationary anchor or a rolling start;
- when a launch observation begins;
- whether a moving trace later invalidates as returned to stationary.

Until physical ES80/iPhone evidence establishes a production threshold, callers must make that policy choice explicitly. Deterministic tests use `0.5 m/s` only as a labeled synthetic fixture value; it is not an ES80 fact and must not silently become one through an initializer default.

## Receive-observation timing basis

Every completed result declares:

`timingBasis == .receiveObservationUptime`

That basis means:

- window endpoints are `receivedAtUptimeNanoseconds` values;
- the app knows the accepted observations arrived in that monotonic order;
- the result does **not** compensate for source-to-app delivery latency;
- optional `measurementDate` and derived delivery latency are not silently converted into a monotonic physical timing clock;
- receive-time windows must not be labeled as physical scooter crossing windows.

For example, a source measurement may physically occur at 1.0 s and arrive at the app at 1.5 s. A later measurement may physically occur at 2.0 s and arrive at 2.1 s. The receive interval `[1.5, 2.1]` is truthful about app observations, but it does not prove a physical threshold crossing happened inside that receive interval.

A future physical timing basis would need stronger evidence, such as a validated source-side monotonic timestamp and/or a measured latency envelope that can be propagated conservatively.

## Two monotonic anchors: observed vs accepted

Once a source is locked—or when policy explicitly requires one source—the evaluator keeps two separate monotonic concepts.

### Observed-source ordering

Every authoritative callback from the locked/required source advances `lastObservedUptimeNanoseconds` before optional accuracy screening. A low-quality GPS sample is still a real callback with chronology.

If a GPS sample at uptime 300 fails the accuracy ceiling and a later call supplies a supposedly good sample stamped uptime 200, the trace invalidates as non-monotonic. Quality rejection cannot erase the callback at 300 and let older evidence masquerade as fresh.

When no source is explicitly required and no usable source has been selected yet, low-quality provider traffic does not choose or poison the future trace source.

### Accepted timing evidence

`lastAcceptedUptimeNanoseconds` advances only when a measurement passes the source/accuracy gates and is usable by the state machine.

The optional `maximumSampleIntervalNanoseconds` is evidence-critical only when the latest stationary anchor transitions to movement and while a trace is already moving. Long idle time while the scooter remains stationary does not weaken a future attempt: a newer accepted stationary sample simply replaces the older launch anchor.

Therefore:

- stationary observation at 1 s, another stationary observation at 10 s, then movement observed at 11 s can remain valid with a `[10 s, 11 s]` launch **observation** window even under a 1.5 s gap ceiling;
- stationary observation at 10 s followed by first movement observation at 12 s fails that same 1.5 s ceiling;
- a rejected GPS callback between accepted measurements does **not** reset the usable-measurement gap timer.

This separation lets chronology stay truthful without pretending rejected data improves timing quality or that a parked scooter needs continuous high-rate measurements before an attempt begins.

## Observation semantics

A trace requires a verified stationary observation anchor under the caller-supplied stationary policy.

- If the first eligible measurement is already moving above the supplied stationary ceiling, the evaluator reports an invalid rolling start.
- Repeated stationary measurements refresh the most recent launch anchor, even after a long idle interval.
- The first measurement above the stationary ceiling creates `launchObservationWindow`, spanning the last accepted stationary receipt and the first accepted moving receipt.
- The first accepted measurement at or above the requested target creates `targetTransitionObservationWindow`, spanning the immediately preceding accepted below-target receipt and that target-reaching receipt.
- `targetTransitionObservationWindow` describes the final observed below→at/above pair. It does **not** prove that pair contains the scooter's first physical target reach.
- `stationaryToTargetObservationElapsedSeconds` is only the monotonic receive-clock interval from the latest stationary packet receipt to the first accepted at/above-target packet receipt.

Timing-window construction is evaluator-owned. Callers receive immutable observation evidence but cannot publicly construct contradictory/reversed windows and trigger a precondition through the public API.

## Why there is no first-reach bound API

Conventional 0-to-target timing means the **first** time the scooter physically reaches the target after physical launch.

Consider accepted samples for a 10 m/s target:

- stationary at receive uptime 0;
- 2 m/s at 1 s;
- 9 m/s at 2 s;
- 8 m/s at 3 s;
- 10 m/s at 4 s.

The final observed below→at-target pair is `[3 s, 4 s]`. But the accepted samples do not rule out an unsampled excursion above 10 m/s between 1 s and 2 s followed by a drop back below target before the 2 s observation.

A positive first-reach lower bound derived from the last sampled below-target packet would therefore be fabricated precision. A receive-span “upper bound” would also invite a stronger physical-time interpretation than variable delivery latency supports.

For that reason the public result intentionally exposes **no first-reach lower/upper bound fields at all**. It exposes only the two observation windows and the directly measured app-timeline interval `stationaryToTargetObservationElapsedSeconds`.

That interval is not a physical acceleration time, not a physical upper bound, and not proof of first reach. A future physical timing result must use a separately validated evidence contract capable of addressing both unsampled excursions and source-to-app latency.

## Cancellation and interruption semantics

An operator cancelling an attempt is a deliberate terminal action even if the evaluator is still waiting for its first stationary anchor. `.operatorCancelled` therefore invalidates every nonterminal attempt state:

- `.waitingForStandstill`;
- `.armed`;
- `.running`.

Later samples cannot resurrect that cancelled attempt. The caller must explicitly `reset()` to begin a new one.

Connection loss and application lifecycle interruption remain evidence invalidators only once a trace is armed/running. If no evidence exists yet and the evaluator is merely waiting for standstill, those non-operator interruptions do not manufacture a failed timing trace.

## Retained timing-evidence sample count

`AccelerationRunResult.timingEvidenceSampleCount` counts accepted measurements retained by the final evidence trace:

- the newest stationary measurement that forms the launch observation window;
- the first moving measurement;
- each accepted post-launch measurement through the first accepted at/above-target observation.

Earlier stationary measurements that were superseded by a newer stationary launch anchor are real observations, but they are not part of the final retained trace and therefore are not counted.

Example: stationary samples at 1.0 s and 2.0 s, first movement at 3.0 s, and first accepted target-reaching sample at 4.0 s produce a launch observation window `[2.0, 3.0]` and a retained timing-evidence count of **3**, not 4.

## Invalidation behavior

An active trace fails closed when evidence continuity is no longer trustworthy:

- non-monotonic locked/required-source observation;
- configured maximum accepted-measurement interval exceeded on the launch transition or during a moving trace;
- measurement source changes mid-trace;
- vehicle/app interruption after the trace is armed;
- explicit operator cancellation in any nonterminal attempt state;
- the scooter returns to stationary after launch observation;
- initial rolling start.

`reset()` discards the old trace and requires a fresh stationary anchor.

## Explicit non-goals

This slice does **not**:

- produce a physical 0-to-target acceleration time;
- expose a first-reach acceleration lower/upper bound;
- claim packet receive timestamps equal source measurement timestamps;
- compensate for variable source-to-app delivery latency;
- prove the final observed below→target pair contains the first physical target reach;
- provide a verified production ES80 stationary threshold;
- select the production ES80 speed source;
- infer threshold crossing from interpolated display values;
- use Core Motion as absolute speed;
- hard-code an unverified ES80 sample cadence;
- require continuous high-rate sampling while the scooter simply remains parked;
- claim Bluetooth packet latency or GPS timing quality;
- add acceleration UI or history;
- persist acceleration records;
- infer throttle, torque, power, phase current, or motor output;
- send any scooter command or BLE write;
- activate acceleration testing on physical hardware.

## Deterministic software verification

The focused test matrix contains **21 deterministic tests across 2 suites** covering:

- rolling-start rejection;
- explicit receive-observation timing basis;
- direct stationary-receipt → target-receipt observation interval;
- regression for a decreasing-but-still-moving sampled sequence where an earlier unsampled target excursion cannot be ruled out;
- regression proving `measurementDate` / delivery latency does not silently become the timing basis;
- launch and target-transition observation windows;
- retained timing-evidence count excluding superseded stationary anchors;
- sparse immediate target observation;
- ordinary motion-estimate rejection;
- malformed `.motionAssist + .absoluteMeasurement` evidence rejected either by a hardened imported-sample decoder or, on an older permissive boundary, by the evaluator's defense-in-depth guard;
- source-change invalidation;
- required-source and GPS-accuracy gating;
- impossible `.motionAssist` authoritative required-source policy rejection;
- quality-rejected locked-source observations still protecting monotonic ordering;
- non-monotonic evidence rejection;
- configurable long accepted-measurement gap rejection;
- rejected-quality callbacks not hiding an overlong usable-measurement gap;
- long stationary idle refreshing the launch anchor without false gap invalidation;
- movement still failing when it arrives too long after that newest stationary anchor;
- connection interruption after launch evidence exists;
- operator cancellation while still waiting and no resurrection before reset;
- return-to-stationary invalidation;
- reset and malformed-policy behavior.

The tests use an explicit synthetic `0.5 m/s` stationary fixture threshold only to exercise software state transitions. They do not claim that threshold is appropriate for the physical ES80.

Repository-wide exact-head NembraCore + Xcode 27 Simulator QA remains required on the final PR head. Deterministic tests are software evidence only until that exact head reports a passing run.

## Hardware validation still required

Before production acceleration timing can make a physical-time claim on the AOVOPRO ES80:

1. measure real ES80 Bluetooth speed cadence, latency, jitter, and resolution;
2. compare that evidence against quality-screened GPS timing on a physical iPhone 12;
3. determine whether either source supplies a trustworthy source-side timing basis;
4. quantify source-to-app latency and its variability rather than assuming packet receipt equals measurement time;
5. determine what evidence, if any, can rule out earlier unsampled target excursions;
6. choose the actual stationary, maximum-gap, and target policies from measured traces rather than Simulator/test convenience;
7. validate interruption/reconnect behavior on real rides;
8. decide user-facing precision from observed uncertainty instead of arbitrary decimal places.

Software correctness here is not physical ES80 validation.