# Adaptive Range Primary Presentation

Status: dependent software truth/presentation policy. Physical AOVOPRO ES80 behavior remains unverified.

## Purpose

The recovered adaptive-range model carries more truth than the current battery instrument can visibly qualify. In particular, an `AdaptiveBatteryRangeEstimate` distinguishes:

- provisional cold-start seed vs learned history;
- learning / low / normal / high confidence;
- authoritative measured SoC vs estimated SoC;
- raw range vs the model's smoothed/deadband presentation range;
- optional evidence-backed low-SoC conservatism.

The current `BatteryEstimatedRangeDisplay` intentionally has only three simple states: numeric meters, learning, or unavailable. It has no visible qualifier for "provisional", "low confidence", "estimated SoC", or "last known while disconnected".

This lane prevents integration code from flattening every non-nil range estimate into an authoritative-looking mileage number.

## Policy

`AdaptiveBatteryRangePrimaryPresentationPolicy` allows an unqualified numeric primary range only when all of these are true:

1. vehicle data is live rather than retained/offline;
2. an adaptive estimate exists;
3. `presentedRemainingMeters` is finite and non-negative;
4. estimate basis is `.learned`, not `.provisionalSeed`;
5. SoC provenance is `.authoritativeMeasurement`, not `.estimate`;
6. confidence is `.normal` or `.high`.

The output preserves a detailed withholding reason while separately projecting into the existing `BatteryEstimatedRangeDisplay` contract.

### Current fail-closed mapping

| Input state | Detailed decision | Existing primary readout |
| --- | --- | --- |
| learned + normal/high + authoritative SoC + live | numeric value | numeric value |
| provisional seed | learning | learning |
| learning confidence | learning | learning |
| low confidence | learning | learning |
| estimated SoC | unavailable until qualified | unavailable |
| retained vehicle data | unavailable until qualified | unavailable |
| vehicle data unavailable | unavailable | unavailable |
| missing/invalid range | unavailable | unavailable |

This is deliberately conservative. A future detailed battery surface may choose to present provisional, retained, estimated-SoC, or low-confidence values with explicit labels. That richer UX must not weaken the truth classification of the underlying evidence.

## Why `presentedRemainingMeters`

The adaptive model already owns range deadband/smoothing and evidence-backed low-SoC conservatism. This policy consumes its `presentedRemainingMeters`; it does not recompute efficiency or introduce a second smoothing model.

The policy never uses:

- advertised range × battery percentage;
- fabricated current, watts, watt-hours, or Wh/mi;
- Dashboard interpolation frames;
- battery display-animation intermediate values;
- route distance as a substitute for the range model.

## Ownership / dependency boundary

Worker: `chat-n5z2k`

Lane: `adaptive-range-primary-presentation-policy`

Owned paths:

- `Packages/NembraCore/Sources/NembraCore/AdaptiveBatteryRangePrimaryPresentation.swift`
- `Packages/NembraCore/Tests/NembraCoreTests/AdaptiveBatteryRangePrimaryPresentationTests.swift`
- `docs/ADAPTIVE_RANGE_PRIMARY_PRESENTATION.md`

This branch is intentionally based on adaptive-range recovery PR #40 exact head `18051b003d8c2b48e37baa3af1dba1fbac9a2d1c` because `AdaptiveBatteryRangeEstimate` is not yet on production `main`.

It does not modify:

- PR #40 adaptive-range implementation files;
- PR #54 learning-window assembly;
- PR #38 battery/range evidence bridge;
- PR #45 battery integer-transition/readout source;
- PR #57 Dashboard/project/UI-test files;
- battery evidence-chain files;
- app bootstrap/persistence/global project memory.

After #40 is accepted, this lane must reconcile onto the accepted exact parent/fresh `main`, rerun package checks, then obtain exact-final-head Xcode 27 / iPhone 12 / iOS 27 Simulator acceptance before production merge. A green dependency head is not proof for a changed child SHA.

## Hardware boundary

Software only. This policy does not verify or assume physical ES80 battery percentage resolution, cadence, voltage/current/power semantics, charging behavior, reconnect continuity, or real-world range. It sends no Bluetooth/Tuya writes and introduces no motorized-hardware command path.
