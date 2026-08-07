# Propulsion Gauge Cockpit Projection

## Purpose

The canonical propulsion gauge intentionally separates accepted power measurements from display-clock interpolation. That separation is correct but still leaves a product-integration hazard: `PropulsionGaugeFrame` contains both `displayWatts` and `latestAcceptedWatts`, so SwiftUI must never bind its large numeric power readout to the interpolated render value.

`PropulsionGaugeCockpitSnapshot` closes the numeric/render handoff seam. `PropulsionObservedScaleRegionSnapshot` separately owns accepted near-observed-scale semantics. `PropulsionGaugeCockpitCompositionSnapshot` now composes both from **one canonical frame evaluation**, which is the preferred future 60 Hz product handoff.

The layers remain deliberately different:

**accepted measurement -> typed cockpit numeric truth**

**display frame -> render-only band position / accepted-peak marker**

**accepted measurement + compatible observed scale -> near-edge semantic truth**

The combined projection never exposes `displayWatts` as a measurement and does not rebuild scale/authority policy in SwiftUI.

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

## Single-frame product composition

A future cockpit previously had to request `cockpitSnapshot(...)` and `observedScaleRegionSnapshot(...)` independently. Both calls were individually truthful, but each evaluated the canonical frame again. At display refresh rate, that duplicated interpolation work and allowed integration code to accidentally request the two projections at slightly different render clocks.

`cockpitCompositionSnapshot(atUptimeNanoseconds:scale:observedScaleRegionPolicy:)` evaluates `PropulsionGaugeFrame` exactly once and derives both product projections from that immutable frame:

- cockpit numeric truth and render-only geometry come from the same frame;
- accepted-only accessibility/scale evidence is projected from that frame without another render evaluation;
- observed-scale semantics consume that accepted-only projection, never the render fraction;
- the combined snapshot has a file-private initializer, so external callers cannot pair a cockpit frame from one tick with semantic state from another.

The standalone APIs remain source-compatible for focused consumers and tests. The combined API is the preferred future high-frequency cockpit seam.

## Observed-scale semantics remain accepted-only

The cockpit projection does **not** decide whether render motion is near an observed scale edge. That responsibility remains with `PropulsionObservedScaleRegionSnapshot`.

The semantic layer owns:

- accepted-power normalization against a compatible observed presentation scale;
- the explicit near-edge presentation threshold;
- accepted provenance for that semantic decision;
- retained/unavailable behavior for the region;
- protection against render interpolation entering/leaving the semantic state;
- verified-wording eligibility only for live verified measurement + verified observed-envelope scale authority.

The composition layer reuses this policy rather than recreating it.

Neither layer may relabel observed-scale proximity as full throttle, rated/certified motor/controller power, a perfect physical maximum, throttle position, or regen proof.

## Future SwiftUI integration

When the propulsion gauge is wired into the real cockpit:

1. request one `cockpitCompositionSnapshot(...)` per render tick rather than independently recomputing the component projections;
2. drive the large numeric watts readout only from `snapshot.cockpit.measurement`;
3. visually qualify `.retained` as last-known/stale rather than live;
4. show no primary numeric watts for `.unavailable`;
5. animate the propulsion band only from `snapshot.cockpit.visualPropulsionFraction`;
6. draw the peak marker only from `snapshot.cockpit.recentAcceptedPeakMarkerFraction`;
7. use `snapshot.observedScaleRegion`, not render fractions, for near-observed-scale semantics and verified wording eligibility;
8. never persist the composition snapshot or feed its render fractions back into ride, battery, range, statistics, calibration, or protocol layers.

Actual SwiftUI layout, source visibility/project wiring, runtime profiling, VoiceOver announcement cadence, and physical iPhone performance remain app/runtime acceptance work. This package slice intentionally avoids contested `DashboardView.swift` and `project.pbxproj` surfaces.

## Hardware boundary

This is software presentation-domain work only.

It does not verify any AOVOPRO ES80 power/current/voltage data point, GATT characteristic, scale, units, signedness, cadence, stable physical identity, motor/controller maximum, throttle signal, regen signal, battery/thermal limit, or physical full-power behavior.

Simulator authority remains synthetic QA. Physical ES80 power presentation stays gated on a legitimately verified upstream measurement source.