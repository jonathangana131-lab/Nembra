# Observed Power Envelope Persistence

This is a **dependent persistence layer** above the `ObservedPowerEnvelope` domain owned by authoritative PR #225. It does not decode ES80 telemetry, establish watts semantics, change the live learner, or wire the Dashboard.

## Construction authority stays sealed

PR #225 intentionally seals `ObservedPowerEnvelopeCalibration` construction:

- `package` under SwiftPM;
- `fileprivate` when selected Core sources are compiled directly into the app target.

Persistence must not reopen that boundary just to make old state resemble freshly minted live-domain calibration.

Therefore durable restore returns `ObservedPowerEnvelopeRestoredCalibration`, a separate read-only value containing the validated retained scope, authority, observed ceiling, derived gauge scale, and validation counts. It cannot be inserted into `ObservedPowerEnvelopeLearner` as fresh evidence or forged into the parent domain calibration through this layer.

The current-session path can copy fields **out of** an already-qualified live `ObservedPowerEnvelopeCalibration` into this read-only representation; it never invokes the parent's sealed initializer.

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

A new process/session starts new observation chronology and a new learning window. Old callback ordering cannot become fresh evidence after relaunch.

## Restore boundary

Decode is fail-closed. Schema, identity strings, authority pairing, learning policy, learned ceiling, sample count, support count, and derived scale must validate.

Restore additionally requires the caller to supply the exact current `ObservedPowerEnvelopeScope` and policy. Verified-physical snapshot/restore entry points remain package-sealed in SwiftPM and file-local in direct-source builds, matching #225's authority boundary; public clients can exercise only Simulator/runtime-QA persistence.

The count invariants mirror #225's bounded rolling-window semantics: `learningSampleCount` is the current eligible window count and cannot exceed `windowCapacity`; `upperBandSupportCount` comes from that same window and cannot exceed the sample count.

## Relaunch floor and upward hysteresis

A validated retained calibration is a presentation **floor** for the same scope + policy. Lower current-session output cannot silently shrink an already learned observed full-power region.

A fresh learner starts without the retained calibration, so its first newly established scale must not bypass #225's scale-stability policy merely because it is slightly higher. Reconciliation reapplies the exact retained policy's `upwardHysteresisFraction` across the process boundary:

`current scale > retained scale × (1 + upward hysteresis)`

Lower/equal, uncalibrated, non-finite-threshold, and sub-hysteresis cases keep the retained value. Only a strictly qualified same-scope/same-policy/same-authority increase may advance the effective calibration.

The selected result carries explicit provenance:

- `retainedCheckpoint`, or
- `currentSession`.

That is calibration provenance, not telemetry evidence.

## Persistence-write reconciliation

The floor and hysteresis rule apply on writes too. Once a durable checkpoint exists, callers must not create a lower or merely marginally higher fresh checkpoint and overwrite it directly.

Use:

- `reconciledSimulatorQACheckpoint(with:)` for Simulator/runtime QA;
- package-sealed `reconciledVerifiedVehicleMeasurementCheckpoint(with:)` for trusted production integration.

Uncalibrated, lower/equal, or sub-hysteresis sessions return the retained checkpoint unchanged. Only a qualified increase produces a replacement. One-shot snapshot constructors are for initial checkpoint creation when no retained checkpoint exists.

## Current #225 compatibility

This branch is based directly on #225 head `d973452f6c34e9b055236aac61f8a7e29b67c10e`, which includes:

- exact observation scope binding before chronology/window mutation;
- strict source-owned receipt sequence separated from monotonic uptime;
- sealed `ObservedPowerEnvelopeCalibration` construction in both SwiftPM and direct-source app build modes.

The tests construct observations using the learner's exact scope and explicit receipt order, exercise equal uptime ticks with increasing receipt sequence, and verify restored durable state is the separate retained-calibration value rather than a newly minted live calibration.

## Hardware status

**NOT VERIFIED ON PHYSICAL AOVOPRO ES80.** No physical ES80 power/current field, DP, characteristic, scale, cadence, throttle signal, regen semantic, battery/thermal condition, or actual full-power ceiling is claimed by this persistence work.
