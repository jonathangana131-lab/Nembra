# Observed Power Envelope Persistence

This is a **dependent persistence layer** above the `ObservedPowerEnvelope` domain owned by authoritative PR #225. It does not decode ES80 telemetry, establish watts semantics, change the live learner, or wire the Dashboard.

## Persisted state

A checkpoint stores only validated calibration facts:

- exact opaque vehicle identity key;
- optional confirmed-mode key;
- identity/evidence authority class;
- exact software learning policy;
- learned observed ceiling watts;
- learning/support counts required to validate that calibration.

The gauge scale is re-derived from the retained observed ceiling and exact headroom policy instead of persisting a second redundant floating-point truth.

## Deliberately not persisted

A checkpoint never stores:

- observation scope objects as reusable evidence tokens;
- receipt sequence or process uptime chronology;
- the learner's rolling eligible-power window;
- individual physical measurements;
- display-interpolated frames;
- throttle, regen, rated maximum, battery/thermal state, or any unverified ES80 protocol meaning.

A new process/session must start new observation chronology and a new learning window. Old callback ordering cannot become fresh evidence after relaunch.

## Restore boundary

Decode is fail-closed. Schema, identity strings, authority pairing, learning policy, learned ceiling, sample count, support count, and derived scale must validate.

Restore additionally requires the caller to supply the exact current `ObservedPowerEnvelopeScope` and policy. Verified-physical snapshot/restore entry points remain package-sealed, matching #225's authority boundary; public clients can exercise only Simulator/runtime-QA persistence.

The count invariants mirror #225's bounded rolling-window semantics: `learningSampleCount` is the current eligible window count and cannot exceed `windowCapacity`; `upperBandSupportCount` comes from that same window and cannot exceed the sample count.

## Relaunch floor and upward hysteresis

A validated retained calibration is a presentation **floor** for the same scope + policy. Lower current-session output cannot silently shrink an already learned observed full-power region.

A fresh learner starts without the retained calibration, so its first newly established scale must not bypass #225's scale-stability policy merely because it is a little higher. Reconciliation therefore reapplies the exact retained policy's `upwardHysteresisFraction` across the process boundary. The current-session calibration replaces the retained one only when:

`current scale > retained scale × (1 + upward hysteresis)`

If that threshold overflows or the current scale does not strictly exceed it, the retained calibration remains authoritative. This mirrors #225's in-session upward-adaptation rule and prevents small restart-to-restart scale jitter.

The selected result carries explicit provenance:

- `retainedCheckpoint`, or
- `currentSession`.

That is calibration provenance, not telemetry evidence.

## Persistence-write reconciliation

The floor and hysteresis rule apply on writes too. Once a durable checkpoint exists, callers must not create a lower or merely marginally higher fresh checkpoint and overwrite it directly.

Use:

- `reconciledSimulatorQACheckpoint(with:)` for Simulator/runtime QA;
- package-sealed `reconciledVerifiedVehicleMeasurementCheckpoint(with:)` for trusted production integration.

These validate exact retained scope/policy/authority against the current learner first. Uncalibrated, lower/equal, or sub-hysteresis increases return the retained checkpoint unchanged. Only a qualified increase above the retained hysteresis threshold produces a replacement.

One-shot snapshot constructors are for initial checkpoint creation when no retained checkpoint exists.

## Current #225 compatibility

This branch is based directly on blocker-fixed #225 head `e9e2520bf847b16f56e2a1853aa21df82888d166`.

Current #225 mechanically binds each observation to an exact calibration scope before chronology/window mutation and separately carries strict source-owned `receiptSequenceNumber` plus monotonic uptime. Persistence stores neither chronology field and requires the current trusted scope again when restoring.

The regression suite creates observations with the learner's exact scope, exercises equal uptime ticks with strictly increasing receipt sequence, persists the established calibration, and verifies that old observation chronology is absent from durable state. Separate cross-launch hysteresis regressions prove a small fresh-session increase cannot advance effective or durable calibration while a qualified increase can.

## Hardware status

**NOT VERIFIED ON PHYSICAL AOVOPRO ES80.** No physical ES80 power/current field, DP, characteristic, scale, cadence, throttle signal, regen semantic, battery/thermal condition, or actual full-power ceiling is claimed by this persistence work.
