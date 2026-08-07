# Adaptive Range Primary Presentation

Status: dependent software truth/presentation policy. Physical AOVOPRO ES80 behavior remains unverified.

## Purpose

The adaptive-range model carries more truth than the current battery instrument can visibly qualify: provisional vs learned basis, learning/low/normal/high confidence, measured vs estimated SoC provenance, raw vs smoothed range, and optional low-SoC conservatism.

The current `BatteryEstimatedRangeDisplay` intentionally has only numeric meters, learning, or unavailable. This lane prevents integration code from flattening every non-nil estimate into authoritative-looking mileage.

## Primary numeric policy

`AdaptiveBatteryRangePrimaryPresentationPolicy` allows an unqualified numeric primary range only when all of these are true:

1. canonical availability derived from the supplied `VehicleState` is live;
2. an adaptive estimate exists;
3. the estimate satisfies the parent model's policy-independent structural invariants;
4. `presentedRemainingMeters` is finite and non-negative;
5. SoC provenance is `.authoritativeMeasurement`, not `.estimate`;
6. basis is `.learned`, not `.provisionalSeed`;
7. confidence is `.normal` or `.high`;
8. final production integration can prove the estimate is bound to the current accepted authoritative SoC observation rather than retained older derived state.

The public API accepts `VehicleState`, not a caller-selected `VehicleDataAvailability`. It derives `vehicleState.dataAvailability` inside the policy. This removes a freshness role-selector seam where app code could accidentally label retained/no-data state as live.

Canonical vehicle-state behavior remains:

- no confirmed vehicle values -> `.unavailable`, even when connection says connected;
- confirmed values + connected -> `.live`;
- confirmed values + disconnected/connecting/reconnecting -> `.retained`.

### Current fail-closed mapping

| Input state | Detailed decision | Primary readout |
| --- | --- | --- |
| learned + normal/high + authoritative SoC + canonical live state | numeric candidate; still requires current-source binding before production integration | numeric |
| provisional seed | learning | learning |
| learning confidence | learning | learning |
| low confidence | learning | learning |
| estimated SoC | qualifier required | unavailable |
| retained + otherwise-valid range | qualifier required | unavailable |
| retained + no range estimate | no estimate | unavailable |
| retained + invalid presented range | invalid presented range | unavailable |
| malformed estimate structure | invalid estimate structure | unavailable |
| no confirmed vehicle data | unavailable | unavailable |

Reason precedence is deliberate. A retained qualifier only makes sense when an otherwise-usable estimate exists; missing/malformed values are classified before retained status. For a structurally valid live estimate, estimated SoC outranks provisional basis so a weak battery source cannot hide behind generic learning.

## Structural defense in depth

Parent #40 already validates decoded `AdaptiveBatteryRangeEstimate` values. #83 mirrors the policy-independent subset before numeric presentation because today's iOS target may compile these domain sources directly into the same app module, where ordinary same-module code could manually construct malformed in-memory values without crossing Codable.

The presentation boundary rejects an estimate unless:

- `rawRemainingMeters` is finite and non-negative;
- `metersPerPercentagePoint` is finite and positive;
- `metersPerPercentagePoint * 100` is finite;
- raw remaining range is at most the current full-charge-equivalent range, with the same tiny floating tolerance used by the parent decoder;
- a `.provisionalSeed` estimate has `.learning` confidence.

`presentedRemainingMeters` is **not** capped by the current full-charge-equivalent range. Valid deadband/smoothing can temporarily lag a changed learned efficiency, so presentation may legitimately exceed the new raw full-charge equivalent while converging. The policy only requires that presented range itself be finite and non-negative.

This defense does not create authority. It only ensures an already-supplied estimate is structurally representable before the UI can show it numerically.

## Derived-estimate freshness blocker

Whole-vehicle availability is necessary but not sufficient to prove the range estimate itself is current.

`BatterySOCReading` carries `receivedAtUptimeNanoseconds`, and `AdaptiveBatteryRangeModel.estimateRemainingRange(at:)` receives that exact reading. The returned `AdaptiveBatteryRangeEstimate` currently drops the source observation identity/uptime and carries only provenance/confidence/basis plus derived range values.

That creates an ambiguity #83 cannot safely resolve locally: an estimate may be genuinely authoritative in origin yet be an older estimate retained in memory across disconnect/reconnect. Meanwhile fresh speed or another confirmed field can make whole `VehicleState.dataAvailability` become `.live`. Connection state therefore does not prove that the range was recomputed from a post-reconnect battery observation.

Production numeric range requires an upstream estimate-to-source binding, for example:

- carry source SoC observation identity/uptime (and continuity generation if required) into the derived estimate and bind it to the currently accepted authoritative battery observation; or
- expose a trusted integration result that classifies the **derived estimate itself** as live/retained/unavailable from the verified battery evidence stream, without allowing UI callers to select that role.

The exact owning shape belongs to #40/#38 or their accepted successors. #83 review finding `5210606651` records this dependency. Final Dashboard acceptance needs a reconnect regression: retain an old authoritative estimate, reconnect/live-update non-battery state, and prove numeric range stays withheld until a newly accepted authoritative SoC observation produces/binds a current estimate.

Until that source binding exists, #83's numeric branch is a domain-policy candidate, not production authorization.

## Upstream authority blockers

This policy does not prove that `.authoritativeMeasurement` is trustworthy. Live review of the parent/dependent chain found multiple authority-assertion paths outside #83 ownership:

1. raw/generic `BatterySOCReading` can currently claim `.authoritativeMeasurement`;
2. generic `AdaptiveBatteryRangeEstimate` import can self-assert authoritative `socProvenance`;
3. legitimate authoritative readings can be reused with a caller-constructed learning window carrying invented distance/coverage;
4. the #38/#54 evidence-to-candidate path accepts caller-classified distance, so the final app architecture must seal the whole evidence -> candidate -> model path rather than only provenance-bearing value initializers.

Generic authoritative SoC and derived-estimate Codable import/export must reject self-asserted authority unless a separately verified persistence envelope explicitly owns that restoration.

A green Xcode/Simulator run for old #40@`18051b...` is diagnostic only: that exact green source still contains these semantic blockers and is stale relative to current `main`.

## Production module-layout caveat

Plain module-`internal` constructors are not sufficient under Nembra's current iOS build graph. The app does not currently link `NembraCore` as a distinct package-product dependency; selected files under `Packages/NembraCore/Sources/NembraCore` are compiled directly into the `Nembra` app Sources build phase. Once adaptive-range/evidence files are wired the same way, app UI and those domain files share one Swift module.

Therefore production authority proof must survive the actual final app composition. The owning lanes must converge on an architecture equivalent to one of:

- link `NembraCore` as a separate module before relying on module-internal authority access;
- use a same-module file/private capability or factory ordinary app code cannot forge;
- expose authoritative conversion only through inputs whose own construction is already sealed, without raw role/window/distance selectors available to app callers.

Final integration should include an app-side negative API/compile proof after wiring, demonstrating that ordinary app code cannot manufacture authoritative SoC, learning-window authority, or authoritative derived-range provenance.

## Why `presentedRemainingMeters`

The adaptive model owns deadband/smoothing and low-SoC conservatism. This policy consumes `presentedRemainingMeters`; it does not recompute efficiency or add a second smoothing model.

It never uses advertised range x battery percentage, fabricated current/watts/Wh/Wh-mi, Dashboard interpolation frames, battery display-animation intermediates, or route geometry as a substitute for range evidence.

## Ownership / dependency boundary

Worker: `chat-n5z2k`

Lane: `adaptive-range-primary-presentation-policy`

Owned paths:

- `Packages/NembraCore/Sources/NembraCore/AdaptiveBatteryRangePrimaryPresentation.swift`
- `Packages/NembraCore/Tests/NembraCoreTests/AdaptiveBatteryRangePrimaryPresentationTests.swift`
- `docs/ADAPTIVE_RANGE_PRIMARY_PRESENTATION.md`

This branch intentionally targets PR #40 exact parent `18051b003d8c2b48e37baa3af1dba1fbac9a2d1c`. It does not modify #40, #54, #38, #45, #57, battery-evidence, app-bootstrap, workflow, project-file, or global-memory paths.

### App-target visibility gate

The Swift package auto-discovers these files, while `Nembra.app` manually enumerates selected core sources. Package success therefore proves neither app visibility nor app-side trust isolation. A future app consumer must wire the complete accepted dependency closure (or deliberately change linkage architecture), compile the exact final app, and re-prove authority construction and derived-estimate freshness under that exact module layout.

The `VehicleState`-accepting public policy API avoids introducing another app-visible freshness selector and works with both today's direct-source composition and a future separately linked core module.

After the authority- and freshness-sealed semantic parent lands, #83 must reconcile its exact three-file delta onto accepted parent/fresh `main`, run real package checks, verify app source/linkage closure, and obtain exact-final-head Xcode 27 / iPhone 12 / iOS 27 Simulator acceptance before production merge.

## Validation

Supplemental Swift 6.2.1 compatibility harness: **23/23 debug + 23/23 release**. In addition to the prior availability/provenance/confidence matrix, it covers malformed raw range, malformed efficiency, a finite efficiency whose full-charge-equivalent multiplication overflows, raw range above the full-charge equivalent, provisional basis paired with non-learning confidence, retained malformed structure, and the valid smoothed-presented-range-above-current-full-charge counterexample.

This is supplemental semantic/API evidence only, not repository package or Xcode acceptance. Freshness cannot be fully proven by this child harness until the parent/integration contract exposes a trustworthy estimate-to-source binding.

## Hardware boundary

Software only. This policy does not verify or assume physical ES80 battery percentage resolution, cadence, voltage/current/power semantics, charging behavior, reconnect continuity, or real-world range. It sends no Bluetooth/Tuya writes and introduces no motorized-hardware command path.
