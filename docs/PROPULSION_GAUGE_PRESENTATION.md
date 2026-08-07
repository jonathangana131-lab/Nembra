# Propulsion Gauge Presentation

## Purpose

Nembra's live cockpit needs a propulsion/power instrument that feels continuously connected to the scooter without turning display animation into telemetry evidence. This package slice establishes that presentation boundary before production AOVOPRO ES80 power semantics are physically verified.

The gauge is **propulsion / power**, not throttle. Measured electrical output does not prove thumb-throttle position. A reverse/regen side is intentionally absent because negative current/power semantics are not physically verified for the ES80.

## Evidence and display clocks

`PropulsionPowerSample` is an accepted observation. `PropulsionGaugeFrame` is a render-only frame.

Accepted samples carry:
- exact vehicle/mode presentation identity;
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

## Scale consumption, not scale learning

This lane does **not** learn the observed full-power envelope. That capability is owned by the separate `observed-power-envelope` worker/PR and remains independent from render-clock behavior.

`PropulsionGaugeScale` is only the small presentation adapter consumed by the display model:
- Simulator can construct an explicit Simulator scale for visual/runtime QA.
- A verified observed-envelope scale can only be constructed through a package-sealed adapter entry point.
- Every scale carries exact vehicle/mode identity.
- The display refuses cross-identity normalization.
- The display refuses a Simulator scale for verified measurements and refuses a verified-envelope scale for Simulator measurements.
- The scale is presentation-only and never rewrites raw measured watts.

A verified observed-envelope scale is still **not** a certified/rated motor or controller maximum and must not be labeled as such. It is also not throttle position.

## Numeric robustness

Finite accepted observations remain finite through render interpolation, including adversarial extreme values. Normalized fractions clamp for presentation even if an intermediate raw division would overflow. Any unexpected non-finite render result fails closed to a real accepted endpoint rather than being exposed as fabricated telemetry.

## Current product integration status

This slice is currently NembraCore/package-only. It intentionally does not modify `DashboardView.swift` or `Nembra.xcodeproj/project.pbxproj` while those high-contention product surfaces are owned by other active workers.

The next production step is not to invent watts. It is to consume a verified read-only ES80 power/current source after passive physical capture establishes raw source, framing, field identity, scaling, units, signedness, cadence, provenance, and continuity. After that, the verified power observation path and the separately qualified observed-envelope calibration can feed this render model before Dashboard integration.

Simulator may use `PropulsionPowerSample.simulator` plus `PropulsionGaugeScale.simulator` for visual/runtime QA, but those values remain explicitly synthetic.

## Hardware truth boundary

No physical AOVOPRO ES80 power field, current field, voltage field, DP ID, characteristic, scaling, signedness, cadence, maximum output, throttle position, regen behavior, or controller/motor rating is established by this code. Software/Simulator acceptance is not physical scooter verification.
