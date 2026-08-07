# Propulsion Gauge Presentation

## Purpose

Nembra's live cockpit needs a propulsion/power instrument that feels continuously connected to the scooter without turning display animation into telemetry evidence. This package slice establishes that presentation boundary before production AOVOPRO ES80 power semantics are physically verified.

The gauge is **propulsion / power**, not throttle. Measured electrical output does not prove thumb-throttle position. A reverse/regen side is intentionally absent because negative current/power semantics are not physically verified for the ES80.

## Evidence and display clocks

`PropulsionPowerSample` is an accepted observation. `PropulsionGaugeFrame` is a render-only frame.

Accepted samples carry:
- exact vehicle/mode calibration identity;
- nonnegative finite watts;
- receive uptime;
- continuity generation;
- authority (`verifiedVehicleMeasurement` or explicit `simulator`).

Render frames may move at display refresh rate toward the latest accepted sample. They never become persisted telemetry, peak evidence, battery/range evidence, ride evidence, protocol claims, or calibration observations.

The display model uses a retargetable critically damped step response. Rise and fall settling windows are separately injected so release can be at least as responsive as application. Those windows are presentation tuning only; they do not assert BLE cadence or physical scooter response.

## Gaps, stale data, and disconnects

The gauge never extrapolates beyond the latest accepted target.

A new continuity generation snaps to the new accepted observation instead of drawing motion through the unknown interval. If the latest sample ages beyond the injected live window, the model preserves the exact accepted watts as **retained** data but removes the active normalized gauge. Explicit unavailability removes the live numeric display entirely while retaining the last accepted observation internally. Disconnect is never converted into measured zero.

## Peak marker

The short visual peak-hold marker is derived only from accepted samples. Render-interpolated values cannot create or raise a peak. The hold duration is a presentation readability policy, not evidence persistence.

## Learned observed power ceiling

`LearnedObservedPowerEnvelope` may eventually give the instrument a stable visual full-power region after a production adapter has verified a real positive power field.

The learned ceiling:
- accepts only package-sealed `verifiedVehicleMeasurement` observations;
- is bound to exact vehicle identity and optional confirmed mode key;
- emits a scale that carries that same vehicle/mode identity, so another scooter or mode cannot consume it accidentally;
- ignores zero when building its positive upper envelope while still advancing evidence chronology;
- uses a bounded rolling window and caller-injected upper percentile;
- requires repeated positive observations before a scale exists;
- supports restrained visual headroom;
- adapts upward when stronger repeated evidence appears;
- uses hysteresis plus deliberately slower downward adaptation;
- cannot be created from Simulator samples.

It is a **learned observed visual ceiling**, not a certified/rated motor or controller maximum. Production UI must not label it as rated power or full throttle.

A Simulator scale is a separate explicit authority and is identity-bound too. The display model refuses to combine a Simulator scale with verified vehicle observations, a learned physical scale with Simulator observations, or any scale whose vehicle/mode identity differs from the active gauge identity.

## Current product integration status

This slice is currently NembraCore/package-only. It intentionally does not modify `DashboardView.swift` or `Nembra.xcodeproj/project.pbxproj` while those high-contention product surfaces are owned by other active workers.

The next production step is not to invent watts. It is to consume a verified read-only ES80 power/current source after passive physical capture establishes raw source, framing, field identity, scaling, units, signedness, cadence, provenance, and continuity. Only then should the app wire verified power samples into this model and integrate the resulting render-only frames into the flagship Dashboard.

Simulator may use `PropulsionPowerSample.simulator` plus `PropulsionGaugeScale.simulator` for visual/runtime QA, but those values must remain explicitly synthetic and must never train `LearnedObservedPowerEnvelope`.

## Hardware truth boundary

No physical AOVOPRO ES80 power field, current field, voltage field, DP ID, characteristic, scaling, signedness, cadence, maximum output, throttle position, regen behavior, or controller/motor rating is established by this code. Software/Simulator acceptance is not physical scooter verification.
