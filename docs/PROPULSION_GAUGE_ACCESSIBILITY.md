# Propulsion Gauge Accessibility

## Scope

This layer is a dependent accessibility projection above the propulsion presentation contract introduced by PR #215. It adds no Bluetooth acquisition, Tuya decoding, observed-envelope learning, persistence, Dashboard SwiftUI wiring, project-file wiring, ride/statistics behavior, or scooter command behavior.

Its purpose is narrow and important: assistive technologies must never announce a 60 Hz display-interpolated power value as though it were a physical measurement.

## Measurement clock stays authoritative

The visual gauge may render many presentation frames between accepted propulsion-power observations. Those frames are useful motion only.

`PropulsionGaugeAccessibilitySnapshot` therefore exposes:

- the latest accepted watts;
- the uptime of that accepted observation;
- its authority domain;
- current live / retained / unavailable state;
- optionally, the accepted observation's position within a compatible observed presentation scale.

It deliberately does **not** expose `displayWatts` or any other display-clock midpoint.

Calling the accessibility projection every display frame is safe: until a new accepted measurement arrives, the announced measurement remains unchanged even while the visual gauge continues moving.

## Retained and unavailable evidence

Stale or explicitly unavailable propulsion evidence does not become measured zero.

The projection preserves the last accepted watts and provenance for callers that need truthful retained-state wording, but it removes the live observed-scale fraction. A consumer can therefore distinguish concepts such as:

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

## Authority and identity isolation

A scale contributes an accessibility fraction only when all of the following match the latest accepted measurement:

1. exact `PropulsionGaugeIdentity` including mode scope;
2. Simulator measurement with Simulator scale, or verified vehicle measurement with verified observed-envelope scale;
3. evidence remains live rather than retained/unavailable.

Cross-vehicle, cross-mode, or cross-authority scales fail closed. The accepted watts remain readable, but no normalized percentage is manufactured.

## SwiftUI integration direction

The future Dashboard accessibility layer should derive its semantic value from `accessibilitySnapshot(...)`, never from the render frame's `displayWatts`.

Recommended product semantics once PR #215 and its dependencies are accepted and app wiring is ready:

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
