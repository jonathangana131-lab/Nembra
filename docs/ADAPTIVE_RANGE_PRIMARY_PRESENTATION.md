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

The policy consumes the existing `VehicleDataAvailability` classification from `VehicleDomain.swift` directly. It deliberately does not define a second live/retained/unavailable enum. This keeps range freshness on the same canonical retained-data boundary already used by Dashboard and other vehicle presentation code and removes a mapping seam where retained data could accidentally be reclassified as live.

Future Dashboard integration should pass `vehicle.state.dataAvailability` directly to the policy. It must not recreate availability from connection state at the call site: `VehicleState.dataAvailability` already encodes the important rule that confirmed values become `.retained` whenever the vehicle is not currently connected, while a state with no confirmed vehicle values is `.unavailable`.

The output preserves a detailed withholding reason while separately projecting into the existing `BatteryEstimatedRangeDisplay` contract.

### Current fail-closed mapping

| Input state | Detailed decision | Existing primary readout |
| --- | --- | --- |
| learned + normal/high + authoritative SoC + live | numeric value | numeric value |
| provisional seed | learning | learning |
| learning confidence | learning | learning |
| low confidence | learning | learning |
| estimated SoC | unavailable until qualified | unavailable |
| retained + otherwise-valid range | unavailable until qualified | unavailable |
| retained + no range estimate | no estimate | unavailable |
| retained + invalid range | invalid range | unavailable |
| vehicle data unavailable | unavailable | unavailable |
| missing/invalid live range | unavailable | unavailable |

Reason precedence is deliberate. A retained qualifier only makes sense when an otherwise-usable range actually exists; missing or malformed range is therefore classified before `.retained`. Conversely, `.unavailable` vehicle data remains a top-level blocker because no confirmed vehicle snapshot exists to support a range at all.

When multiple range-evidence conditions coexist on a valid live estimate, stronger evidence-quality qualifiers win over weaker presentation-progress qualifiers. In particular, estimated SoC outranks provisional basis: a provisional estimate based on estimated SoC is `unavailable(.estimatedSOCRequiresQualifier)`, not merely `learning(.provisionalSeed)`. This avoids telling the user only that the model is learning while hiding the weaker battery source underneath it.

This is deliberately conservative. A future detailed battery surface may choose to present provisional, retained, estimated-SoC, or low-confidence values with explicit labels. That richer UX must not weaken the truth classification of the underlying evidence.

## Upstream authority blocker

This presentation policy does **not** itself prove that an upstream `.authoritativeMeasurement` claim is trustworthy.

Current live review of parent PR #40 found two generic authority-assertion paths:

1. `BatterySOCReading` exposes a raw constructor that accepts public `.authoritativeMeasurement`, and its generic Codable import can decode that role;
2. `AdaptiveBatteryRangeEstimate.init(from:)` likewise decodes `socProvenance` and can import an otherwise-valid learned/normal/high estimate that self-asserts `.authoritativeMeasurement`.

The second path matters directly to this lane: #83 is behaving correctly when it trusts the parent estimate's provenance field, but a forged imported parent estimate can currently make that field look authoritative. Generic encode/decode of authoritative derived estimates therefore needs the same explicit trust treatment as authoritative SoC readings.

These are upstream trust-boundary bugs, not reasons for this lane to duplicate battery-evidence validation. This lane therefore treats the following as hard production dependencies:

1. the accepted descendant of #40 must seal authoritative `BatterySOCReading` construction/import;
2. generic `AdaptiveBatteryRangeEstimate` import/export must not be able to create or carry authoritative provenance without an explicit separately verified persistence envelope;
3. #38 (or its accepted successor) must remain the trusted battery-evidence → adaptive-range integration seam;
4. only then may a `.authoritativeMeasurement` carried by the accepted adaptive-range result satisfy this policy's numeric-eligibility rule;
5. until those seals exist, PR #83 stays draft/dependent and no Dashboard integration should interpret this policy's current numeric branch as production authority proof.

A historical/queued green for the old #40 head does not close these blockers because the reviewed source itself still contains the authority-import/construction paths.

### Production module-layout caveat

A proposed #40 hardening direction is to make the raw `BatterySOCReading` role-selecting initializer module-internal and leave a public estimated-only factory. That helps Swift-package clients, but **module-internal access is not sufficient by itself under Nembra's current production iOS build graph**.

The current `Nembra` app target does not link `NembraCore` as a separate package-product dependency. Instead, `project.pbxproj` places selected files from `Packages/NembraCore/Sources/NembraCore` directly in the `Nembra` app Sources build phase. Once adaptive-range/evidence files are wired the same way for Dashboard, those declarations and ordinary app UI code compile in the same Swift module. Plain `internal` access would therefore remain callable by app code.

Production acceptance must consequently prove an authority construction boundary that remains non-forgeable in the **actual final app composition**, not only in an external package-client probe. Viable architecture belongs to the owning integration/range lanes, but the proof must be equivalent to one of these outcomes:

- the app deliberately links `NembraCore` as a distinct module before relying on module-internal authority access; or
- authoritative conversion uses a file/private capability or another construction API that ordinary same-module app code cannot forge; or
- authoritative range conversion accepts only already-sealed verified evidence through a path that never exposes a raw same-module role selector to app callers.

The final integration gate should include an app-side negative compile/API proof after the adaptive-range dependency closure is wired, demonstrating that ordinary `NembraApp` code cannot manufacture authoritative SoC or authoritative derived-range provenance.

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
- the `Nembra.app` Xcode target manually enumerates selected NembraCore source files in `Nembra.xcodeproj/project.pbxproj` and compiles them directly into the app module.

This lane intentionally does **not** edit that Class-A project file while PR #57 owns it. Consequently, a green package test for this policy is not proof that a future Dashboard build can see the type, and package-module access-control probes are not automatically proof of the production app trust boundary. The later app integration must explicitly verify/wire every adaptive-range source it consumes into the app target (or deliberately change the app/package linkage architecture under its own accepted lane), compile the real app on the exact final SHA, and re-prove authority construction under that exact module layout.

After #40 is authority-sealed, accepted, and landed, this lane must reconcile onto the accepted exact parent/fresh `main`, rerun package checks, then obtain exact-final-head Xcode 27 / iPhone 12 / iOS 27 Simulator acceptance before production merge. A green dependency head is not proof for a changed child SHA.

## Hardware boundary

Software only. This policy does not verify or assume physical ES80 battery percentage resolution, cadence, voltage/current/power semantics, charging behavior, reconnect continuity, or real-world range. It sends no Bluetooth/Tuya writes and introduces no motorized-hardware command path.
