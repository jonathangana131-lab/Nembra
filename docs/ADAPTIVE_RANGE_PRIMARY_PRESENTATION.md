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
4. SoC provenance is `.authoritativeMeasurement`, not `.estimate`;
5. estimate basis is `.learned`, not `.provisionalSeed`;
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

When multiple withholding conditions coexist, stronger evidence-quality qualifiers win over weaker presentation-progress qualifiers. In particular, estimated SoC now outranks provisional basis: a provisional estimate based on estimated SoC is `unavailable(.estimatedSOCRequiresQualifier)`, not merely `learning(.provisionalSeed)`. This avoids telling the user only that the model is learning while hiding the weaker battery source underneath it.

This is deliberately conservative. A future detailed battery surface may choose to present provisional, retained, estimated-SoC, or low-confidence values with explicit labels. That richer UX must not weaken the truth classification of the underlying evidence.

## Upstream authority blocker

This presentation policy does **not** itself prove that an upstream `.authoritativeMeasurement` claim is trustworthy.

Current live review of parent PR #40 found that `BatterySOCReading` still exposes a public initializer that accepts public `.authoritativeMeasurement`, while the type is also generally `Codable`. External production code can therefore manufacture/import an adaptive-range SoC reading that claims authority without passing through the sealed battery-evidence path in #34/#38.

That is an upstream parent trust-boundary bug, not a reason for this lane to duplicate battery-evidence validation. This lane therefore treats the following as a hard production dependency:

1. the accepted descendant of #40 must seal authoritative `BatterySOCReading` construction/import;
2. #38 (or its accepted successor) must remain the trusted battery-evidence → adaptive-range integration seam;
3. only then may a `.authoritativeMeasurement` carried by the accepted adaptive-range result satisfy this policy's numeric-eligibility rule;
4. until that parent seal exists, PR #83 stays draft/dependent and no Dashboard integration should interpret this policy's current numeric branch as production authority proof.

A historical/queued green for the old #40 head does not close this blocker because the reviewed source itself still contains the public-authority bypass.

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

### App-target source visibility gate

Nembra currently has two different source-discovery realities:

- the Swift package auto-discovers files under `Packages/NembraCore/Sources/NembraCore` and package tests therefore see this policy automatically;
- the `Nembra.app` Xcode target manually enumerates selected NembraCore source files in `Nembra.xcodeproj/project.pbxproj`.

This lane intentionally does **not** edit that Class-A project file while PR #57 owns it. Consequently, a green package test for this policy is not proof that a future Dashboard build can see the type. The later app integration must explicitly verify/wire every adaptive-range source it consumes into the app target (or deliberately change the app/package linkage architecture under its own accepted lane), then compile the real app on the exact final SHA.

After #40 is authority-sealed, accepted, and landed, this lane must reconcile onto the accepted exact parent/fresh `main`, rerun package checks, then obtain exact-final-head Xcode 27 / iPhone 12 / iOS 27 Simulator acceptance before production merge. A green dependency head is not proof for a changed child SHA.

## Hardware boundary

Software only. This policy does not verify or assume physical ES80 battery percentage resolution, cadence, voltage/current/power semantics, charging behavior, reconnect continuity, or real-world range. It sends no Bluetooth/Tuya writes and introduces no motorized-hardware command path.
