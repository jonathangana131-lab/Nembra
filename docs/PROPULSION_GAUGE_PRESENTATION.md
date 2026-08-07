# Propulsion Gauge Presentation

## Purpose

Nembra's live cockpit needs a propulsion/power instrument that feels continuously connected to the scooter without turning display animation into telemetry evidence. This package slice establishes that presentation boundary before production AOVOPRO ES80 power semantics are physically verified.

The gauge is **propulsion / power**, not throttle. Measured electrical output does not prove thumb-throttle position. A reverse/regen side is intentionally absent because negative current/power semantics are not physically verified for the ES80.

## Evidence and display clocks

`PropulsionPowerSample` is an accepted observation. `PropulsionGaugeFrame` is a render-only frame.

Accepted samples carry:
- exact validated vehicle/mode presentation identity;
- nonnegative finite watts;
- source-owned receipt sequence/order;
- receive uptime;
- source-owned continuity generation;
- authority (`verifiedVehicleMeasurement` or explicit `simulator`).

Verified samples require the real source-owned receipt sequence. Simulator may omit one only as an explicit synthetic-QA convenience, in which case its Simulator-owned uptime is reused as synthetic ordering metadata. Production code must never invent or subdivide nanoseconds merely to order two accepted callbacks.

Chronology is scoped to the source-owned continuity generation. Inside one generation, receipt sequence must strictly increase while uptime is nondecreasing, so equal uptime callbacks remain valid when source order advances. A newer same-generation receipt identity is consumed before secondary uptime validation, so a malformed newer callback cannot later be rewritten and a delayed lower sequence cannot re-enter.

A strictly newer continuity generation is an explicit clock/order epoch boundary. It may restart receipt sequence and uptime instead of forcing a caller to fabricate monotonic values across a process/clock restart. Older generations fail closed. This remains compatible with Nembra's passive capture model: one uninterrupted capture session keeps globally increasing sequence while its interruption markers break byte continuity; adapters with a stronger source-owned generation may also use that generation to establish a new clock/order epoch.

Render frames may move at display refresh rate toward the latest accepted sample. They never become persisted telemetry, peak evidence, battery/range evidence, ride evidence, protocol claims, or calibration observations. If a caller requests a frame before the newest accepted sample's receipt uptime, the presentation fails closed with `invalidRenderClock` instead of silently moving the requested clock forward and backdating evidence.

The display model uses a retargetable critically damped step response. Rise and fall settling windows are separately injected, and construction requires fall settling to be no slower than rise settling. Zero/zero remains an intentional Reduce Motion snap path. Those windows are presentation tuning only; they do not assert BLE cadence or physical scooter response.

## Identity boundary

`PropulsionGaugeIdentity` is a presentation key, not proof of physical scooter identity. Its public constructor rejects an empty/whitespace vehicle key and rejects a present empty/whitespace mode key. Custom `Codable` decoding routes through the same validation, so persisted/imported payloads cannot bypass the invariant. Authority-bearing sample and scale factories retain a second fail-closed structural check at their own boundary.

This prevents placeholder identities from collapsing otherwise separate vehicle/mode evidence domains while still preserving the exact opaque key bytes supplied by the verified identity owner. The code does not decide what the ES80's verified identity key should be; that remains a separate physical/session-identity responsibility.

## Gaps, stale data, and disconnects

The gauge never extrapolates beyond the latest accepted target.

A new continuity generation or authority change snaps to the new accepted observation instead of drawing motion through an unknown or cross-authority interval. The accepted peak resets on that discontinuity, so Simulator history cannot contaminate verified presentation and verified history cannot contaminate Simulator QA.

If the latest sample ages beyond the injected live window, the model preserves the exact accepted watts as **retained** data but removes the active normalized gauge.

`markUnavailable()` is stronger than visual hiding after evidence exists: it retires the latest accepted continuity generation. A delayed callback from that disconnected/interrupted generation cannot clear unavailability and resurrect `.live`; resumption requires a genuinely newer source-owned generation. The newer generation may restart its sequence and uptime epochs. This is an acceptance boundary, not a fabricated zero-power sample. If no measurement has ever been accepted, there is no known generation to retire.

## Peak marker

The short visual peak-hold marker is derived only from accepted samples. Render-interpolated values cannot create or raise a peak. The hold duration is a presentation readability policy, not evidence persistence.

## Canonical observed-envelope consumption

This lane does **not** learn a second observed full-power envelope. The canonical `ObservedPowerEnvelope` capability is now merged on main and owns repeated-evidence learning, measurement-only versus learning eligibility, upward adaptation, and the learned observed gauge scale.

`PropulsionGaugeScale` is only the presentation capability consumed by the display model:
- Simulator can construct an explicit Simulator scale for visual/runtime QA.
- `PropulsionGaugeScale.observedEnvelope(_:)` maps a canonical `ObservedPowerEnvelopeCalibration` into gauge presentation.
- Verified scope + verified measurement authority map through the sealed verified scale factory.
- Simulator scope + Simulator evidence remain Simulator authority.
- Any mixed scope/evidence authority fails closed and cannot be upgraded by presentation.
- Every scale carries the exact vehicle/mode identity from its calibration scope.
- The display refuses cross-identity normalization.
- The display refuses a Simulator scale for verified measurements and refuses a verified-envelope scale for Simulator measurements.
- The scale is presentation-only and never rewrites raw measured watts.

The raw verified-scale factory remains package-sealed under SwiftPM and file-private in Nembra's direct-source app build. The canonical calibration object is the authority token; ordinary app/UI code does not regain a module-wide factory for minting physical scale authority.

A verified observed-envelope scale is still **not** a certified/rated motor or controller maximum and must not be labeled as such. It is also not throttle position.

## Numeric robustness

Finite accepted observations remain finite through render interpolation, including adversarial extreme values. Normalized fractions clamp for presentation even if an intermediate raw division would overflow. Any unexpected non-finite render result fails closed to a real accepted endpoint rather than being exposed as fabricated telemetry.

## Current product integration status

This slice is currently NembraCore/package-only. It intentionally does not modify `DashboardView.swift` or `Nembra.xcodeproj/project.pbxproj` while those high-contention product surfaces are owned by other active workers.

The next production step is not to invent watts. It is to consume a verified read-only ES80 power/current source after passive physical capture establishes raw source, framing, field identity, scaling, units, signedness, cadence, provenance, continuity generation, and source receipt order. After that, the verified power observation path plus canonical observed-envelope calibration can feed this render model before Dashboard integration.

Simulator may use `PropulsionPowerSample.simulator` plus a Simulator envelope/scale for visual/runtime QA, but those values remain explicitly synthetic.

## Hardware truth boundary

No physical AOVOPRO ES80 power field, current field, voltage field, DP ID, characteristic, scaling, signedness, cadence, maximum output, throttle position, regen behavior, or controller/motor rating is established by this code. Software/Simulator acceptance is not physical scooter verification.
