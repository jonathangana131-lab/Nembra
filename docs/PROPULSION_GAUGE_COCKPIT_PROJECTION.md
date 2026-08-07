# Propulsion Gauge Cockpit Projection

## Purpose

The canonical propulsion gauge intentionally separates accepted power measurements from display-clock interpolation. That separation is correct but still leaves a product-integration hazard: `PropulsionGaugeFrame` contains both `displayWatts` and `latestAcceptedWatts`, so a future SwiftUI cockpit could accidentally bind its large numeric power readout to the interpolated render value.

`PropulsionGaugeCockpitProjection` closes that seam without changing telemetry authority, learned-envelope policy, BLE/Tuya behavior, or the Dashboard layout.

It is a presentation handoff above the accepted gauge model:

**accepted measurement -> typed cockpit numeric truth**

**display frame -> render-only band position / accepted-peak marker**

The projection deliberately exposes no `displayWatts` property. It also evaluates the canonical gauge frame only once per cockpit snapshot, avoiding duplicate interpolation work on a future 60 Hz render path.

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

The projection returns no live band fraction when evidence is retained/unavailable or when the observed presentation scale is incompatible with the accepted measurement.

`recentAcceptedPeakMarkerFraction` is the canonical short-lived marker derived from accepted peak observations. It is still a normalized presentation position, not a second measurement or a perfect continuous-time maximum.

## Accepted scale position

`acceptedObservedScaleFraction` is separate from the animated band. It is derived from the newest accepted measurement only after the same canonical `PropulsionGaugeFrame` has admitted the supplied presentation scale for the exact vehicle/mode identity and measurement authority.

The cockpit layer does not reimplement those identity/authority matching rules. A non-nil `frame.scaleOrigin` is the admission result from the canonical gauge model; the accepted fraction then uses the accepted watts rather than `displayWatts`.

This is the value used for near-observed-ceiling semantics. Interpolated band position and held peak position are never allowed to promote the wording state.

## Near observed max wording

`PropulsionGaugeCockpitPolicy.nearObservedCeilingFraction` is a visual/product threshold in `(0, 1]`. It does not learn a ceiling and does not define a motor/controller rating.

`PropulsionGaugeNearObservedCeilingStatus` is intentionally authority-aware:

- `.unavailable` — no compatible live accepted scale position exists;
- `.belowThreshold` — compatible accepted evidence exists but is below the chosen presentation threshold;
- `.simulatorNearObservedCeiling` — synthetic Simulator QA may exercise the visual state, but this is not production evidence;
- `.verifiedNearObservedCeiling` — a verified accepted measurement is near a compatible verified observed-envelope scale.

Only `.verifiedNearObservedCeiling` may justify user-facing **Near observed max** style wording in production.

Even then, it means near Nembra's learned observed presentation ceiling. It does **not** mean:

- full throttle;
- rated/certified motor power;
- rated/certified controller power;
- a perfect physical maximum;
- proof of a thumb-demand signal;
- proof of regenerative braking semantics.

The projection does not provide **FULL THROTTLE** or equivalent wording.

## Future SwiftUI integration

When the propulsion gauge is wired into the real cockpit:

1. drive the large numeric watts readout only from `measurement`;
2. visually qualify `.retained` as last-known/stale rather than live;
3. show no primary numeric watts for `.unavailable`;
4. animate the propulsion band only from `visualPropulsionFraction`;
5. draw the peak marker only from `recentAcceptedPeakMarkerFraction`;
6. use `verifiedNearObservedCeiling` as the only production authority for near-observed-max wording;
7. never persist a cockpit snapshot or feed its render fractions back into ride, battery, range, statistics, calibration, or protocol layers.

Actual SwiftUI layout, 60 Hz runtime behavior, VoiceOver announcement cadence, project source visibility, and physical iPhone performance remain later app/runtime acceptance work. This slice intentionally avoids contested `DashboardView.swift` and `project.pbxproj` integration surfaces.

## Hardware boundary

This is software presentation-domain work only.

It does not verify any AOVOPRO ES80 power/current/voltage data point, GATT characteristic, scale, units, signedness, cadence, stable physical identity, motor/controller maximum, throttle signal, regen signal, battery/thermal limit, or physical full-power behavior.

Simulator authority remains synthetic QA. A production verified near-observed-ceiling state can exist only after the upstream verified measurement + observed-envelope authority chain is legitimately available.
