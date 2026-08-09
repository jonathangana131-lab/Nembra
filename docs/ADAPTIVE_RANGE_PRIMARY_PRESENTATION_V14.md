# Adaptive Range Primary Presentation — V14

## Purpose

This contract defines when Nembra may place a learned-range number in an **unqualified primary** battery/range readout.

It is presentation policy only. It does not decode battery transport, establish ES80 SoC semantics, choose distance evidence, train the range model, or create physical vehicle truth.

## V14 authority input

The policy consumes:

- `AdaptiveBatteryRangeLiveEstimate`
- the `BatteryEvidenceStreamValidator` that owns the accepted SoC receipt used to calculate that estimate.

It deliberately does **not** accept whole-vehicle `VehicleDataAvailability`, a caller-selected freshness enum, or a raw `AdaptiveBatteryRangeEstimate`.

The live estimate is bound to the exact accepted battery receipt. Before any primary numeric value is emitted, the policy rechecks `liveEstimate.isCurrent(in: validator)`.

Consequences:

- a marked evidence gap immediately demotes the old estimate;
- a newer accepted battery receipt immediately demotes the old estimate;
- reconnecting transport cannot make an old estimate look fresh;
- a newer receipt at the **same uptime tick** still demotes the old estimate because receipt identity, not wall/monotonic-clock inequality, owns currentness.

## Primary decision ladder

`nil` live estimate
→ `unavailable(.noEstimate)`

receipt no longer current
→ `unavailable(.retainedEstimateRequiresQualifier)`

current provisional seed
→ `learning(.provisionalSeed)`

current learned estimate below the low-confidence floor
→ `learning(.learningConfidence)`

current learned estimate at low confidence
→ `learning(.lowConfidenceRequiresQualifier)`

current learned estimate at normal/high confidence
→ `valueMeters(...)`

The policy never substitutes advertised range × battery percentage, trip distance, voltage-derived SoC, Wh/mi, or another invented numeric fallback.

## Why the V11 policy is not replayed verbatim

Historical presentation PR #83 used whole-vehicle availability as a conservative freshness gate because receipt-bound adaptive-range truth did not yet exist. That was appropriately fail-closed for its time, but it could not prove field-specific range currentness.

V14's `AdaptiveBatteryRangeLiveEstimate` carries the exact accepted SoC receipt identity. The primary presentation policy therefore consumes that stronger authority directly and removes the old caller-facing whole-vehicle freshness dependency.

## Accessibility / product integration boundary

This package policy chooses truth state only. A future Battery component should map the decision into concise visible and VoiceOver language:

- numeric learned range only for `.valueMeters`;
- explicit learning language for `.learning`;
- explicit unavailable/last-known treatment for `.unavailable` as appropriate to the detailed surface.

Battery fill must always continue to represent charge, even when the selected text mode is learned range.

No 60 Hz rendered intermediate may be written back into this policy, the model, persistence, ride records, or telemetry evidence.

## Current acceptance boundary

This V14 recovery is stacked on the receipt-bound adaptive-range authority candidate (#1421). It is package/domain work, not app-visible completion.

The parent currently has a separate integration finding: `AcceptedBatteryRangeLearningWindow` requires strictly increasing uptime even though receipt chronology permits distinct higher-sequence callbacks at equal uptime. That parent mismatch must be reconciled before the full battery-evidence → learning-window bridge is considered coherent.

No physical AOVOPRO ES80 battery source, scaling, cadence, current/power semantics, charging behavior, range result, or hardware behavior is established by this presentation policy.