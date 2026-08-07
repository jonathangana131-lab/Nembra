# Propulsion Gauge Cockpit Projection

## Purpose

The canonical propulsion gauge intentionally separates accepted power measurements from display-clock interpolation. That separation is correct but still leaves a product-integration hazard: `PropulsionGaugeFrame` contains both `displayWatts` and `latestAcceptedWatts`, so a future SwiftUI cockpit could accidentally bind its large numeric power readout to the interpolated render value.

`PropulsionGaugeCockpitProjection` closes only that handoff seam. It does not own learned-envelope policy, observed-scale semantic regions, BLE/Tuya behavior, or Dashboard layout.

It maps one canonical frame into two deliberately different cockpit concerns:

**accepted measurement -> typed cockpit numeric truth**

**display frame -> render-only band position / accepted-peak marker**

The projection deliberately exposes no `displayWatts` property. It evaluates the canonical gauge frame exactly once per cockpit snapshot, avoiding duplicate interpolation work inside this handoff on a future 60 Hz render path.

## Numeric truth

`PropulsionGaugeCockpitMeasurement` is one of:

- `.live(acceptedMeasurement)` — the primary numeric value is the newest accepted observation;
- `.retained(acceptedMeasurement)` — the same accepted value is explicitly last-known/stale and must not look fresh;
- `.unavailable` — the primary cockpit carries no numeric power value.

An accepted cockpit measurement retains:

- watts;
- source-owned receipt sequence;
- accepted receive uptime;
- measurement authority.

Construction is file-private. Generic UI code cannot take a 60 Hz render midpoint and relabel it as an accepted cockpit measurement.

Explicit interruption intentionally maps the primary numeric cockpit readout to `.unavailable` rather than manufacturing `0 W`. Stale-but-not-explicitly-interrupted evidence remains typed `.retained`.

## Render-only motion

`visualPropulsionFraction` is the live band position produced by the canonical gauge display model. It may move at display refresh rate between accepted samples.

It is presentation only. Never use it as:

- telemetry evidence;
- a persisted sample;
- peak-power evidence;
- acceleration evidence;
- battery/range learning evidence;
- protocol evidence;
- throttle position.

The canonical model itself admits a scale only when vehicle/mode identity and Simulator-vs-verified measurement authority are compatible. When no compatible scale is admitted, the cockpit receives no normalized band or peak marker.

`recentAcceptedPeakMarkerFraction` is the canonical short-lived marker derived from accepted peak observations. It is still a normalized presentation position, not a second measurement or a perfect continuous-time maximum.

`scaleOrigin` is presentation provenance for the compatible scale admitted by the canonical frame. It does not turn a render fraction into telemetry evidence.

## Deliberate boundary with observed-scale semantics

The cockpit projection intentionally does **not** decide whether accepted power is near an observed scale edge and does not own wording such as **Near observed max**.

That semantic responsibility belongs to the separate accepted-power `PropulsionObservedScaleRegion` recovery lane / active PR #320, which recovers the product intent of closed, unmerged PR #317. The recovered layer owns:

- accepted-power normalization against a compatible observed presentation scale;
- the explicit near-edge presentation threshold;
- accepted provenance for that semantic decision;
- retained/unavailable behavior for the region;
- protection against render interpolation entering/leaving the semantic state.

Keeping that responsibility separate prevents two workers from shipping competing near-maximum policies. A future integration may compose the accepted semantic region with this cockpit render/readout projection after both dependencies are accepted, but it must not duplicate the policy in Dashboard code.

Neither layer may relabel observed-scale proximity as full throttle, rated/certified motor/controller power, a perfect physical maximum, throttle position, or regen proof.

## Future SwiftUI integration

When the propulsion gauge is wired into the real cockpit:

1. drive the large numeric watts readout only from `measurement`;
2. visually qualify `.retained` as last-known/stale rather than live;
3. show no primary numeric watts for `.unavailable`;
4. animate the propulsion band only from `visualPropulsionFraction`;
5. draw the peak marker only from `recentAcceptedPeakMarkerFraction`;
6. use the accepted observed-scale-region layer, not render fractions, for any near-observed-max semantics;
7. never persist a cockpit snapshot or feed its render fractions back into ride, battery, range, statistics, calibration, or protocol layers.

Actual SwiftUI layout, cross-layer composition, 60 Hz runtime behavior, VoiceOver announcement cadence, project source visibility, and physical iPhone performance remain later app/runtime acceptance work. This slice intentionally avoids contested `DashboardView.swift` and `project.pbxproj` integration surfaces.

## Hardware boundary

This is software presentation-domain work only.

It does not verify any AOVOPRO ES80 power/current/voltage data point, GATT characteristic, scale, units, signedness, cadence, stable physical identity, motor/controller maximum, throttle signal, regen signal, battery/thermal limit, or physical full-power behavior.

Simulator authority remains synthetic QA. Physical ES80 power presentation stays gated on a legitimately verified upstream measurement source.