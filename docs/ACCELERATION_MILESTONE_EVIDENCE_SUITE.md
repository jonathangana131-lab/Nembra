# Acceleration Milestone Evidence Suite

Worker: `chat-q7m4`  
Lane: `acceleration-milestone-evidence`

## Product gap

Nembra already has a deliberately conservative `AccelerationEvidenceSession` for one configured target. Product experiences such as an observed 0→10 / 0→15 / 0→20-style benchmark need several targets from the same attempt, but independently constructing several sessions in app code makes it easy to drift source, cadence, accuracy, continuity, or telemetry-quality policy between displayed milestones.

`AccelerationMilestoneEvidenceSuite` provides one additive NembraCore composition for that use case. It does not create a new timing algorithm. Each target delegates to the existing accepted acceleration evaluator/evidence session, while the suite guarantees that every target receives the exact same callbacks and interruptions under one common evidence policy.

## Truth contract

- Targets are explicit SI speeds and must be nonempty and strictly increasing.
- Every target uses the same authoritative speed source, stationary threshold, sample-gap ceiling, accuracy requirement, and telemetry-quality policy.
- Every target sees the exact same measurement callbacks in the exact same order.
- Motion-assisted/display-estimated speed is rejected by the delegated acceleration run policy and cannot become milestone evidence.
- Display-interpolated speed never becomes acceleration evidence because the delegated evaluator still requires authoritative absolute speed measurements.
- A completed lower milestone is immutable. If a later gap or continuity interruption occurs, already-sealed lower-target evidence may remain reportable while unfinished higher targets fail closed.
- Missing evidence is never bridged to finish a higher target.
- Results remain receive-observation-clock evidence. They are not renamed into exact physical launch/crossing times or continuous-time maxima.
- No target value is hard-coded as an ES80 capability. Product code may configure targets such as 10/15/20 mph only after converting them to SI and deciding that those milestones make sense for the current product experience.

## Why separate milestone sessions are intentional

Lower milestones complete before higher milestones. Their retained timing traces therefore end at different accepted target observations, which is useful: each milestone's telemetry-quality assessment describes the evidence actually used for that milestone rather than later packets that arrived after it was already sealed.

All sessions still share the same launch-side evidence contract. Because their only policy difference is target speed and they consume the same stream, callers cannot silently qualify one target from Bluetooth and another from GPS, or apply a looser gap policy only to a higher target.

## Failure behavior

Examples:

- `0 → 2 m/s` completes, then the selected speed stream has a measurement gap before `4 m/s`: the 2 m/s result can remain ready, while unfinished 4 m/s and higher milestones invalidate for the gap.
- `0 → 2 m/s` completes, then vehicle connection continuity is lost: the completed result remains sealed; unfinished milestones invalidate for the interruption and retain the interruption evidence in readiness.
- A caller supplies duplicate or descending targets: policy construction fails instead of producing ambiguous milestone identity/order.
- The telemetry-quality source disagrees with the run source: policy construction fails through the existing `AccelerationEvidenceSessionPolicy` source gate.
- A caller attempts to use `.motionAssist` as the required run source: construction fails through the existing acceleration run authority gate.

## Product boundary

This slice is package/domain composition only. It does not add an acceleration UI, persist benchmark history, select ES80-specific thresholds, or wire production speed telemetry. Future app integration must still:

1. use a physically/production-qualified authoritative speed source;
2. choose evidence-backed cadence, accuracy, jitter, resolution, and latency thresholds;
3. present receive-clock observation timing honestly rather than implying perfect physical crossing time;
4. keep milestone results separate from propulsion power/current evidence;
5. reject interrupted/ambiguous attempts instead of filling gaps with visual interpolation;
6. run iPhone 12 / iOS 27 Simulator visual/accessibility acceptance for any product surface, followed by real-device/physical-source validation before claiming ES80 acceleration performance.

## Hardware status

**SOFTWARE EVIDENCE COMPOSITION ONLY — NOT PHYSICAL AOVOPRO ES80 ACCELERATION VERIFICATION.** No physical ES80 speed source/cadence/latency/resolution, 0→target performance, top speed, Bluetooth/Tuya field, or scooter behavior is established by this slice.
