# Propulsion Gauge Accessibility

## Scope

This layer sits above the accepted propulsion presentation model now on `main` and projects that model into stable accessibility semantics. It adds no Bluetooth acquisition, Tuya decoding, observed-envelope learning, persistence, Dashboard SwiftUI wiring, project-file wiring, ride/statistics behavior, or scooter command behavior.

Its purpose is narrow and important: assistive technologies must never announce a display-interpolated propulsion value as though it were a physical measurement.

The earlier accessibility child branch was based on the superseded pre-recovery propulsion presentation lineage. This recovered slice is rebased conceptually onto the accepted mainline model, including its source-owned receipt chronology and canonical observed-envelope bridge.

## Measurement clock stays authoritative

The visual gauge may render many presentation frames between accepted propulsion-power observations. Those frames are useful motion only.

`PropulsionGaugeAccessibilitySnapshot` therefore exposes:

- the latest accepted watts;
- the source-owned receipt sequence number of that accepted observation;
- the receive uptime of that accepted observation;
- its authority domain;
- current live / retained / unavailable state;
- optionally, the accepted observation's position within a compatible observed presentation scale.

It deliberately does **not** expose `displayWatts`, `normalizedPropulsion`, or any other display-clock midpoint.

Calling the accessibility projection every display frame is safe: until a new accepted measurement arrives, the announced measurement and its receipt provenance remain unchanged even while the visual gauge continues moving.

A render request earlier than the newest accepted receive uptime fails closed. It does not expose future evidence to an earlier display clock.

## Retained and unavailable evidence

Stale or explicitly unavailable propulsion evidence does not become measured zero.

The projection preserves the last accepted watts and provenance when the underlying presentation model legitimately retains them, but it removes the live observed-scale fraction. A consumer can therefore distinguish concepts such as:

- current accepted propulsion evidence;
- last accepted propulsion evidence retained after freshness expires;
- source currently unavailable.

No stale value is silently presented as current.

## Observed-scale position is not throttle

`acceptedObservedScaleFraction` is only the accepted measurement's normalized position inside a compatible presentation scale.

It is **not**:

- throttle or thumb position;
- motor-load percentage;
- rated-power percentage;
- controller output percentage;
- a certified hardware maximum;
- a new telemetry packet.

A learned observed envelope may eventually let the gauge reach its visual edge near repeatedly observed high output, but that remains an observed presentation calibration rather than rated motor truth.

Product wording must therefore prefer concepts such as `power`, `propulsion`, or `observed scale`. It must not announce `full throttle` unless an authoritative throttle-demand signal is physically verified separately.

## Authority, vehicle, and mode isolation

A scale contributes an accessibility fraction only when all of the following match the latest accepted measurement:

1. exact `PropulsionGaugeIdentity`, including any confirmed-mode scope;
2. Simulator measurement with Simulator scale, or verified vehicle measurement with verified observed-envelope scale;
3. evidence remains live rather than retained/unavailable.

Cross-vehicle, cross-mode, or cross-authority scales fail closed. The accepted watts and provenance remain readable where the presentation model legitimately retains them, but no normalized percentage is manufactured.

The source-owned receipt sequence number is chronology/provenance evidence only. It is not power evidence and never changes the measured watts by itself.

## SwiftUI integration direction

The future Dashboard accessibility layer should derive its semantic value from `accessibilitySnapshot(...)`, never from the render frame's `displayWatts` or interpolated normalized position.

Recommended product semantics when the production Dashboard is ready to consume verified power evidence:

- use a concise label such as `Propulsion power`;
- announce authoritative accepted watts when current;
- explicitly qualify retained evidence as last accepted / unavailable rather than current;
- if an observed-scale position is useful at all, describe it as observed gauge position rather than throttle or rated power;
- do not emit accessibility announcements continuously at display refresh rate merely because the visual gauge animates;
- Reduce Motion may snap visual motion without changing the accepted measurement exposed here.

Actual SwiftUI accessibility labels, announcement cadence, Dynamic Type composition, and physical VoiceOver interaction remain app/runtime acceptance work and are intentionally not claimed by this package-only slice.

## Truth boundary

**SOFTWARE / PRESENTATION ACCESSIBILITY ONLY.**

No physical AOVOPRO ES80 power/current/voltage field, Tuya DP, GATT characteristic, units, scaling, signedness, cadence, rated maximum, throttle position, regen behavior, thermal limitation, battery limitation, or physical VoiceOver behavior is verified by this layer.

Simulator evidence remains Simulator evidence. Verified production authority remains package-sealed until an accepted physical acquisition path exists.
